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
}
