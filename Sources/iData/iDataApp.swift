import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingOpenURLs: [URL] = []
    private var openHandler: (([URL]) -> ExternalOpenPresentationDecision)?
    private var terminateHandler: (() -> Void)?
    private let appActivator: @MainActor () -> Void

    override init() {
        self.appActivator = {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
        super.init()
    }

    init(appActivator: @escaping @MainActor () -> Void) {
        self.appActivator = appActivator
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func bind(
        openHandler: @escaping ([URL]) -> ExternalOpenPresentationDecision,
        terminateHandler: @escaping () -> Void
    ) {
        self.openHandler = openHandler
        self.terminateHandler = terminateHandler

        guard !pendingOpenURLs.isEmpty else {
            return
        }

        let queuedURLs = pendingOpenURLs
        pendingOpenURLs.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let presentationDecision = openHandler(queuedURLs)
            if presentationDecision == .activateApp {
                self.activateAppWindow()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        routeOpen(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        routeOpen(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminateHandler?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func routeOpen(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)

        guard !fileURLs.isEmpty else {
            return
        }

        if let openHandler {
            let presentationDecision = openHandler(fileURLs)
            if presentationDecision == .activateApp {
                activateAppWindow()
            }
        } else {
            pendingOpenURLs.append(contentsOf: fileURLs)
        }
    }

    private func activateAppWindow() {
        appActivator()
    }
}

@main
struct IDataApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var updater = AppUpdaterController()

    var body: some Scene {
        Window("iData", id: "main") {
            ContentView(model: model, updater: updater)
                .onAppear {
                    appDelegate.bind(
                        openHandler: { urls in
                            model.handleExternalFileOpen(urls)
                        },
                        terminateHandler: {
                            model.shutdown()
                        }
                    )
                    updater.performStartupUpdateCheckIfNeeded()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }

            CommandGroup(replacing: .help) {
                Button("iData Help") {
                    model.isHelpPresented = true
                }
                .keyboardShortcut("?", modifiers: [.command, .shift])
            }
        }

        Settings {
            PreferencesView(model: model, updater: updater)
        }
    }
}
