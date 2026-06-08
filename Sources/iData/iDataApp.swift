import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let updater: AppUpdaterController

    private var pendingOpenURLs: [URL] = []
    private var openHandler: (([URL]) -> ExternalOpenPresentationDecision)?
    private var terminateHandler: (() -> Void)?
    private let appActivator: @MainActor () -> Void
    private let managesMainWindow: Bool
    private var mainWindow: NSWindow?
    private var collapseDuplicateWindowsTask: DispatchWorkItem?

    override init() {
        self.model = AppModel()
        self.updater = AppUpdaterController()
        self.managesMainWindow = true
        self.appActivator = {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.collapseDuplicateMainWindows()
        }
        super.init()
    }

    init(appActivator: @escaping @MainActor () -> Void) {
        self.model = AppModel()
        self.updater = AppUpdaterController()
        self.managesMainWindow = false
        self.appActivator = appActivator
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        if managesMainWindow {
            showMainWindow()
            updater.performStartupUpdateCheckIfNeeded()
        }
        scheduleDuplicateWindowCollapse()
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
        model.shutdown()
        terminateHandler?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if managesMainWindow && !flag {
            showMainWindow()
        }
        return true
    }

    private func routeOpen(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)

        guard !fileURLs.isEmpty else {
            return
        }

        guard managesMainWindow || openHandler != nil else {
            pendingOpenURLs.append(contentsOf: fileURLs)
            return
        }

        let presentationDecision = openHandler?(fileURLs) ?? model.handleExternalFileOpen(fileURLs)
        if presentationDecision == .activateApp {
            activateAppWindow()
        }
    }

    private func activateAppWindow() {
        guard managesMainWindow else {
            appActivator()
            scheduleDuplicateWindowCollapse()
            return
        }

        showMainWindow()
    }

    private func showMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)

        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            appActivator()
            scheduleDuplicateWindowCollapse()
            return
        }

        let hostingController = NSHostingController(rootView: ContentView(model: model, updater: updater))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "iData"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 860, height: 580)
        window.contentViewController = hostingController
        window.center()
        mainWindow = window

        window.makeKeyAndOrderFront(nil)
        appActivator()
        scheduleDuplicateWindowCollapse()
    }

    private func scheduleDuplicateWindowCollapse() {
        collapseDuplicateWindowsTask?.cancel()

        let task = DispatchWorkItem {
            NSApplication.shared.collapseDuplicateMainWindows()
        }
        collapseDuplicateWindowsTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }
}

private extension NSApplication {
    func collapseDuplicateMainWindows() {
        activate(ignoringOtherApps: true)

        let mainWindows = windows.filter { $0.title == "iData" }
        guard let primaryWindow = mainWindows.last else {
            return
        }

        for duplicateWindow in mainWindows.dropLast() {
            duplicateWindow.close()
        }
        primaryWindow.makeKeyAndOrderFront(nil)
    }
}

@main
struct IDataApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView(model: appDelegate.model, updater: appDelegate.updater)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appDelegate.updater.checkForUpdates()
                }
                .disabled(!appDelegate.updater.canCheckForUpdates)
            }

            CommandGroup(replacing: .help) {
                Button("iData Help") {
                    appDelegate.model.isHelpPresented = true
                }
                .keyboardShortcut("?", modifiers: [.command, .shift])
            }
        }
    }
}
