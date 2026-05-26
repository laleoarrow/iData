import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingOpenURLs: [URL] = []
    private var openHandler: (([URL]) -> ExternalOpenPresentationDecision)?
    private var terminateHandler: (() -> Void)?
    private var shouldTerminateAfterLastWindowClosedProvider: @MainActor () -> Bool
    private let appActivator: @MainActor () -> Void

    override init() {
        self.appActivator = {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
        self.shouldTerminateAfterLastWindowClosedProvider = { true }
        super.init()
    }

    init(
        appActivator: @escaping @MainActor () -> Void,
        shouldTerminateAfterLastWindowClosedProvider: @escaping @MainActor () -> Bool = { true }
    ) {
        self.appActivator = appActivator
        self.shouldTerminateAfterLastWindowClosedProvider = shouldTerminateAfterLastWindowClosedProvider
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        DockIconController.applyStoredPreference()
    }

    func bind(
        openHandler: @escaping ([URL]) -> ExternalOpenPresentationDecision,
        terminateHandler: @escaping () -> Void,
        shouldTerminateAfterLastWindowClosed: @escaping @MainActor () -> Bool = { true }
    ) {
        self.openHandler = openHandler
        self.terminateHandler = terminateHandler
        self.shouldTerminateAfterLastWindowClosedProvider = shouldTerminateAfterLastWindowClosed

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
        shouldTerminateAfterLastWindowClosedProvider()
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

@MainActor
enum DockIconController {
    static func apply(hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
    }

    static func applyStoredPreference(defaults: UserDefaults = .standard) {
        apply(hidden: defaults.object(forKey: AppModel.hidesDockIconKey) as? Bool ?? false)
    }
}

@main
struct IDataApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var updater = AppUpdaterController()

    @SceneBuilder var body: some Scene {
        Window("iData", id: "main") {
            ContentView(model: model, updater: updater)
                .onAppear {
                    appDelegate.bind(
                        openHandler: { urls in
                            model.handleExternalFileOpen(urls)
                        },
                        terminateHandler: {
                            model.shutdown()
                        },
                        shouldTerminateAfterLastWindowClosed: {
                            model.shouldTerminateAfterLastWindowClosed
                        }
                    )
                    DockIconController.apply(hidden: model.hidesDockIcon)
                    updater.performStartupUpdateCheckIfNeeded()
                }
                .onChange(of: model.hidesDockIcon) { _, hidesDockIcon in
                    DockIconController.apply(hidden: hidesDockIcon)
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

        MenuBarExtra("iData", systemImage: "tablecells", isInserted: $model.showsMenuBarItem) {
            IDataMenuBarContent(model: model, updater: updater)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct IDataMenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdaterController
    @Environment(\.openWindow) private var openWindow

    private var isChinese: Bool {
        model.effectiveLanguage == .chinese
    }

    var body: some View {
        Button(isChinese ? "显示 iData" : "Show iData") {
            showMainWindow()
        }

        Button(isChinese ? "打开文件…" : "Open File…") {
            showMainWindow()
            DispatchQueue.main.async {
                model.openDocument()
            }
        }

        Divider()

        Toggle(isChinese ? "在菜单栏显示 iData" : "Show iData in Menu Bar", isOn: $model.showsMenuBarItem)
            .disabled(model.hidesDockIcon)
        Toggle(isChinese ? "隐藏 Dock 图标" : "Hide Dock Icon", isOn: $model.hidesDockIcon)

        Divider()

        Button(isChinese ? "偏好设置…" : "Preferences…") {
            showSettingsWindow()
        }

        Button(isChinese ? "检查更新…" : "Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)

        Divider()

        Button(isChinese ? "退出 iData" : "Quit iData") {
            model.shutdown()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow() {
        openWindow(id: "main")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let mainWindow = NSApp.windows.first { $0.title == "iData" } ?? NSApp.windows.first
            mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func showSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
