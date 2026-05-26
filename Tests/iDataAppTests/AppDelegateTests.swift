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
    func boundAppCanStayRunningAfterLastWindowCloses() {
        let delegate = AppDelegate(appActivator: {})
        delegate.bind(
            openHandler: { _ in .stayBackground },
            terminateHandler: {},
            shouldTerminateAfterLastWindowClosed: { false }
        )

        let shouldTerminate = (delegate as NSApplicationDelegate)
            .applicationShouldTerminateAfterLastWindowClosed?(NSApplication.shared)

        #expect(shouldTerminate == false)
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
    func openDocumentsAppleEventExtractsFileURLs() {
        let first = URL(fileURLWithPath: "/tmp/first.csv")
        let second = URL(fileURLWithPath: "/tmp/second.tsv")
        let directObject = NSAppleEventDescriptor.list()
        directObject.insert(NSAppleEventDescriptor(fileURL: first), at: 1)
        directObject.insert(NSAppleEventDescriptor(fileURL: second), at: 2)

        #expect(AppDelegate.fileURLs(fromOpenDocumentsDirectObject: directObject) == [first, second])
    }

    @Test
    func commandLineArgumentsExtractExistingFilesOnly() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-command-line-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let fileURL = tempRoot.appendingPathComponent("sample.csv")
        try Data("a,b\n1,2\n".utf8).write(to: fileURL)

        #expect(AppDelegate.fileURLs(fromCommandLineArguments: [
            "--ignored-flag",
            fileURL.path,
            tempRoot.appendingPathComponent("missing.csv").path,
        ]) == [fileURL.standardizedFileURL])
    }
}
