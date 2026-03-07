import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingOpenURLs: [URL] = []
    private var openHandler: (([URL]) -> Void)?
    private var terminateHandler: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
    }

    func bind(
        openHandler: @escaping ([URL]) -> Void,
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
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
            openHandler(queuedURLs)
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

    private func routeOpen(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)

        guard !fileURLs.isEmpty else {
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        if let openHandler {
            openHandler(fileURLs)
        } else {
            pendingOpenURLs.append(contentsOf: fileURLs)
        }
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
                            model.openExternalFiles(urls)
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
                .disabled(!updater.isConfigured && !updater.canCheckForUpdates)
            }
        }

        Settings {
            PreferencesView(model: model, updater: updater)
        }
    }
}
