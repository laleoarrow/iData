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
        DispatchQueue.main.async {
            self.collapseToSingleWindow()
        }
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
        openHandler(queuedURLs)
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

        DispatchQueue.main.async {
            self.collapseToSingleWindow()
        }
    }

    private func collapseToSingleWindow() {
        let visibleWindows = NSApplication.shared.windows.filter(\.isVisible)
        guard visibleWindows.count > 1 else {
            return
        }

        let windowToKeep =
            visibleWindows.max { lhs, rhs in
                (lhs.frame.width * lhs.frame.height) < (rhs.frame.width * rhs.frame.height)
            }

        guard let windowToKeep else {
            return
        }

        for window in visibleWindows where window != windowToKeep {
            window.close()
        }

        windowToKeep.makeKeyAndOrderFront(nil)
    }
}

@main
struct IDataApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear {
                    appDelegate.bind(
                        openHandler: { urls in
                            model.openExternalFiles(urls)
                        },
                        terminateHandler: {
                            model.shutdown()
                        }
                    )
                }
        }

        Settings {
            PreferencesView(model: model)
        }
    }
}
