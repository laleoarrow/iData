import AppKit
import Combine
import SwiftUI

@MainActor
private final class AppRuntime {
    static let shared = AppRuntime()

    let model: AppModel
    let updater: AppUpdaterController

    private init() {
        model = AppModel()
        updater = AppUpdaterController()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingOpenURLs: [URL] = []
    private var openHandler: (([URL]) -> ExternalOpenPresentationDecision)?
    private var terminateHandler: (() -> Void)?
    private var shouldTerminateAfterLastWindowClosedProvider: @MainActor () -> Bool
    private let appActivator: @MainActor () -> Void
    private let mainWindowPresenterOverride: (@MainActor (AppModel, AppUpdaterController) -> Void)?
    private let statusItemController: StatusItemController?
    private weak var configuredModel: AppModel?
    private weak var configuredUpdater: AppUpdaterController?
    private var appKitWindowController: NSWindowController?

    override init() {
        self.appActivator = {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
        self.mainWindowPresenterOverride = nil
        self.statusItemController = StatusItemController()
        self.shouldTerminateAfterLastWindowClosedProvider = { true }
        super.init()
        installOpenDocumentsEventHandler()
    }

    init(
        appActivator: @escaping @MainActor () -> Void,
        mainWindowPresenter: (@MainActor (AppModel, AppUpdaterController) -> Void)? = nil,
        statusItemController: StatusItemController? = nil,
        shouldTerminateAfterLastWindowClosedProvider: @escaping @MainActor () -> Bool = { true }
    ) {
        self.appActivator = appActivator
        self.mainWindowPresenterOverride = mainWindowPresenter
        self.statusItemController = statusItemController
        self.shouldTerminateAfterLastWindowClosedProvider = shouldTerminateAfterLastWindowClosedProvider
        super.init()
        installOpenDocumentsEventHandler()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        installOpenDocumentsEventHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        let runtime = AppRuntime.shared
        configure(model: runtime.model, updater: runtime.updater)
        DockIconController.apply(hidden: runtime.model.hidesDockIcon)
        runtime.updater.performStartupUpdateCheckIfNeeded()
        installOpenDocumentsEventHandler()
        queueStartupOpenURLs(Self.fileURLs(fromCommandLineArguments: Array(CommandLine.arguments.dropFirst())))
    }

    private func installOpenDocumentsEventHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocumentsEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )
    }

    func configure(model: AppModel, updater: AppUpdaterController) {
        guard configuredModel !== model || configuredUpdater !== updater || openHandler == nil else {
            return
        }

        configuredModel = model
        configuredUpdater = updater
        statusItemController?.configure(appDelegate: self, model: model, updater: updater)
        bind(
            openHandler: { [weak self] urls in
                let decision = model.handleExternalFileOpen(urls)
                if decision == .activateApp {
                    self?.presentMainWindow(model: model, updater: updater)
                }
                return .stayBackground
            },
            terminateHandler: {
                model.shutdown()
            },
            shouldTerminateAfterLastWindowClosed: {
                model.shouldTerminateAfterLastWindowClosed
            }
        )
    }

    private func queueStartupOpenURLs(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        if openHandler == nil {
            pendingOpenURLs.append(contentsOf: urls)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.routeOpen(urls)
            }
        }
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

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        routeOpen([URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        routeOpen(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )
        terminateHandler?()
        statusItemController?.invalidate()
        appKitWindowController = nil
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

    @objc private func handleOpenDocumentsEvent(
        _ event: NSAppleEventDescriptor,
        replyEvent _: NSAppleEventDescriptor
    ) {
        routeOpen(Self.fileURLs(fromOpenDocumentsEvent: event))
    }

    static func fileURLs(fromOpenDocumentsEvent event: NSAppleEventDescriptor) -> [URL] {
        fileURLs(fromOpenDocumentsDirectObject: event.paramDescriptor(forKeyword: keyDirectObject))
    }

    static func fileURLs(fromOpenDocumentsDirectObject descriptor: NSAppleEventDescriptor?) -> [URL] {
        guard let descriptor else {
            return []
        }

        let itemCount = descriptor.numberOfItems
        if itemCount > 0 {
            return (1...itemCount).compactMap { index in
                fileURL(fromOpenDocumentsDescriptor: descriptor.atIndex(index))
            }
        }

        return fileURL(fromOpenDocumentsDescriptor: descriptor).map { [$0] } ?? []
    }

    static func fileURLs(fromCommandLineArguments arguments: [String]) -> [URL] {
        arguments
            .filter { !$0.hasPrefix("-") }
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func fileURL(fromOpenDocumentsDescriptor descriptor: NSAppleEventDescriptor?) -> URL? {
        if let fileURL = descriptor?.fileURLValue {
            return fileURL
        }

        guard let path = descriptor?.stringValue, !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func activateAppWindow() {
        appActivator()
    }

    func presentMainWindow(model: AppModel, updater: AppUpdaterController) {
        if let mainWindowPresenterOverride {
            mainWindowPresenterOverride(model, updater)
            return
        }

        if let appKitWindow = appKitWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            appKitWindow.makeKeyAndOrderFront(nil)
            return
        }

        if let existingWindow = NSApp.windows.first(where: { $0.isVisible && $0.title == "iData" }) {
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "iData"
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.minSize = NSSize(width: 960, height: 620)
        window.setFrameAutosaveName("main")
        window.contentView = NSHostingView(rootView: ContentView(model: model, updater: updater))

        let controller = NSWindowController(window: window)
        appKitWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }
}

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private weak var appDelegate: AppDelegate?
    private weak var model: AppModel?
    private weak var updater: AppUpdaterController?
    private var cancellables: Set<AnyCancellable> = []

    func configure(appDelegate: AppDelegate, model: AppModel, updater: AppUpdaterController) {
        guard self.appDelegate !== appDelegate || self.model !== model || self.updater !== updater else {
            updateInsertionState()
            rebuildMenu()
            return
        }

        self.appDelegate = appDelegate
        self.model = model
        self.updater = updater
        cancellables.removeAll()

        model.$showsMenuBarItem
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateInsertionState()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        model.$hidesDockIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] hidesDockIcon in
                DockIconController.apply(hidden: hidesDockIcon)
                self?.updateInsertionState()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        model.$appLanguagePreference
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        updater.$canCheckForUpdates
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        updateInsertionState()
        rebuildMenu()
    }

    func invalidate() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        cancellables.removeAll()
    }

    private func updateInsertionState() {
        guard let model else {
            invalidate()
            return
        }

        if model.showsMenuBarItem {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.title = "iData"
                item.button?.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: "iData")
                item.button?.imagePosition = .imageLeading
                statusItem = item
            }
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func rebuildMenu() {
        guard let model, let updater, let statusItem else {
            return
        }

        let isChinese = model.effectiveLanguage == .chinese
        let menu = NSMenu()

        menu.addItem(item(
            title: isChinese ? "显示 iData" : "Show iData",
            action: #selector(showMainWindow)
        ))
        menu.addItem(item(
            title: isChinese ? "打开文件…" : "Open File…",
            action: #selector(openFile)
        ))
        menu.addItem(.separator())

        let menuBarItem = item(
            title: isChinese ? "在菜单栏显示 iData" : "Show iData in Menu Bar",
            action: #selector(toggleMenuBarItem)
        )
        menuBarItem.state = model.showsMenuBarItem ? .on : .off
        menuBarItem.isEnabled = !model.hidesDockIcon
        menu.addItem(menuBarItem)

        let dockItem = item(
            title: isChinese ? "隐藏 Dock 图标" : "Hide Dock Icon",
            action: #selector(toggleDockIcon)
        )
        dockItem.state = model.hidesDockIcon ? .on : .off
        menu.addItem(dockItem)
        menu.addItem(.separator())

        menu.addItem(item(
            title: isChinese ? "偏好设置…" : "Preferences…",
            action: #selector(showSettingsWindow)
        ))

        let updateItem = item(
            title: isChinese ? "检查更新…" : "Check for Updates…",
            action: #selector(checkForUpdates)
        )
        updateItem.isEnabled = updater.canCheckForUpdates
        menu.addItem(updateItem)
        menu.addItem(.separator())

        menu.addItem(item(
            title: isChinese ? "退出 iData" : "Quit iData",
            action: #selector(quit)
        ))

        statusItem.menu = menu
    }

    private func item(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showMainWindow() {
        guard let appDelegate, let model, let updater else {
            return
        }
        appDelegate.presentMainWindow(model: model, updater: updater)
    }

    @objc private func openFile() {
        showMainWindow()
        DispatchQueue.main.async { [weak self] in
            self?.model?.openDocument()
        }
    }

    @objc private func toggleMenuBarItem() {
        guard let model else {
            return
        }
        model.showsMenuBarItem.toggle()
    }

    @objc private func toggleDockIcon() {
        guard let model else {
            return
        }
        model.hidesDockIcon.toggle()
        DockIconController.apply(hidden: model.hidesDockIcon)
    }

    @objc private func showSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func checkForUpdates() {
        updater?.checkForUpdates()
    }

    @objc private func quit() {
        model?.shutdown()
        NSApp.terminate(nil)
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
    @ObservedObject private var model: AppModel
    @ObservedObject private var updater: AppUpdaterController

    init() {
        let runtime = AppRuntime.shared
        model = runtime.model
        updater = runtime.updater
    }

    @SceneBuilder var body: some Scene {
        Settings {
            PreferencesView(model: model, updater: updater)
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
    }
}
