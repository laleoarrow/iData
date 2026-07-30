import AppKit
import Foundation
import Testing
@testable import iData

@MainActor
struct AppDelegateTests {
    @Test
    func appTerminatesWhenLastWindowCloses() {
        let delegate = AppDelegate()
        let shouldTerminate = (delegate as NSApplicationDelegate)
            .applicationShouldTerminateAfterLastWindowClosed?(NSApplication.shared)

        #expect(shouldTerminate == true)
    }

    @Test
    func queuedOpenFilesAreDeliveredAfterBinding() async {
        let fileURL = URL(fileURLWithPath: "/tmp/queued.csv")
        let delegate = AppDelegate(appActivator: {})
        var receivedURLs: [URL] = []

        delegate.application(NSApplication.shared, open: [fileURL])
        delegate.bind(
            openHandler: { urls in
                receivedURLs = urls
                return .stayBackground
            },
            terminateHandler: {}
        )

        try? await Task.sleep(nanoseconds: 600_000_000)

        #expect(receivedURLs == [fileURL])
    }

    @Test
    func immediateOpenActivatesWhenHandlerRequestsForeground() {
        let fileURL = URL(fileURLWithPath: "/tmp/large.csv")
        var activationCount = 0
        var receivedURLs: [URL] = []
        let delegate = AppDelegate(appActivator: {
            activationCount += 1
        })

        delegate.bind(
            openHandler: { urls in
                receivedURLs = urls
                return .activateApp
            },
            terminateHandler: {}
        )

        delegate.application(NSApplication.shared, open: [fileURL])

        #expect(receivedURLs == [fileURL])
        #expect(activationCount == 1)
    }

    @Test
    func queuedOpenActivatesWhenBoundHandlerRequestsForeground() async {
        let fileURL = URL(fileURLWithPath: "/tmp/queued-large.csv")
        var activationCount = 0
        var receivedURLs: [URL] = []
        let delegate = AppDelegate(appActivator: {
            activationCount += 1
        })

        delegate.application(NSApplication.shared, open: [fileURL])
        delegate.bind(
            openHandler: { urls in
                receivedURLs = urls
                return .activateApp
            },
            terminateHandler: {}
        )

        try? await Task.sleep(nanoseconds: 600_000_000)

        #expect(receivedURLs == [fileURL])
        #expect(activationCount == 1)
    }

    @Test
    func mainSceneCreatesStartupWindowWithoutOfferingNewWindowCommand() throws {
        let source = normalizeWhitespace(try iDataAppSource())

        #expect(!source.contains("WindowGroup(\"iData\")"))
        #expect(source.contains("Settings { PreferencesView(model: appDelegate.model, updater: appDelegate.updater) }"))
        #expect(!source.contains("Window(\"iData\", id: \"main\")"))
        #expect(source.contains("IDataAppCommands(model: appDelegate.model, updater: appDelegate.updater)"))
        #expect(source.contains("private var mainWindow: NSWindow?"))
        #expect(source.contains("func applicationShouldHandleReopen("))
        #expect(source.contains("private func showMainWindow()"))
        #expect(source.contains("NSHostingController(rootView: ContentView(model: model, updater: updater))"))
        #expect(source.contains("window.makeKeyAndOrderFront(nil)"))
        #expect(source.contains("private var collapseDuplicateWindowsTask: DispatchWorkItem?"))
        #expect(source.contains("scheduleDuplicateWindowCollapse()"))
        #expect(source.contains("private extension NSApplication"))
        #expect(source.contains("func collapseDuplicateMainWindows()"))
        #expect(source.contains("guard let primaryWindow = mainWindows.last"))
        #expect(source.contains("for duplicateWindow in mainWindows.dropLast()"))
    }

    @Test
    func commandMenuExposesHighFrequencyActions() throws {
        let source = normalizeWhitespace(try iDataAppSource())

        #expect(source.contains("struct IDataAppCommands: Commands"))
        #expect(source.contains("CommandGroup(replacing: .newItem)"))
        #expect(source.contains("model.openDocument()"))
        #expect(source.contains("model.reopenLastFile()"))
        #expect(source.contains(".keyboardShortcut(\"o\")"))
        #expect(source.contains(".keyboardShortcut(\"r\", modifiers: [.command, .shift])"))
        #expect(source.contains("CommandMenu(model.localized(english: \"Session\", chinese: \"会话\"))"))
        #expect(source.contains("model.toggleSidebarCollapsed()"))
        #expect(source.contains("model.revealCurrentFileInFinder()"))
        #expect(source.contains("model.copyCurrentFilePathToPasteboard()"))
        #expect(source.contains("model.presentTutorialHub()"))
        #expect(source.contains("model.returnExternalHandoffToIData()"))
        #expect(source.contains(".disabled(model.externalHandoffNotice == nil)"))
    }
}

private func iDataAppSource(filePath: StaticString = #filePath) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try [
        "Sources/iData/iDataApp.swift",
        "Sources/iData/AppCommands.swift",
    ]
    .map { relativePath in
        let sourceURL = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
    .joined(separator: "\n")
}

private func normalizeWhitespace(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
