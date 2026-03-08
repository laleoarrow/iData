import Testing
import WebKit
@testable import iData

@MainActor
struct EmbeddedTerminalViewTests {
    @Test
    func sessionOnlyBecomesReadyAfterNavigationAndTerminalReady() {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = WKWebView(frame: .zero)

        coordinator.bind(session: session, webView: webView)
        coordinator.handleTerminalReady()

        #expect(!displayReadyFlag(for: session))

        coordinator.webView(webView, didFinish: nil)

        #expect(displayReadyFlag(for: session))
    }

    @Test
    func rebindingToFullyReadyTerminalMarksNewSessionDisplayReady() {
        let firstSession = VisiDataSessionController()
        let secondSession = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: firstSession)
        let webView = WKWebView(frame: .zero)

        coordinator.bind(session: firstSession, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady()

        #expect(displayReadyFlag(for: firstSession))

        coordinator.bind(session: secondSession, webView: webView)

        #expect(!displayReadyFlag(for: firstSession))
        #expect(displayReadyFlag(for: secondSession))
    }

    @Test
    func markDisplayReadyDoesNotReplayTranscriptAgainDuringDelayedRefreshes() async throws {
        let session = VisiDataSessionController()
        let sink = TerminalDisplaySinkSpy()

        session.bind(displaySink: sink)
        session.appendOutputForTesting(Data("hello".utf8))
        session.markDisplayReady()

        #expect(sink.clearCallCount == 1)
        #expect(sink.writeCallCount == 1)

        try await Task.sleep(for: .milliseconds(650))

        #expect(sink.clearCallCount == 1)
        #expect(sink.writeCallCount == 1)
    }

    @Test
    func markDisplayReadyIsIdempotentAcrossRepeatedBindings() {
        let session = VisiDataSessionController()
        let sink = TerminalDisplaySinkSpy()

        session.bind(displaySink: sink)
        session.appendOutputForTesting(Data("hello".utf8))
        session.markDisplayReady()

        #expect(sink.clearCallCount == 1)
        #expect(sink.writeCallCount == 1)

        session.markDisplayReady()
        session.markDisplayReady()

        #expect(sink.clearCallCount == 1)
        #expect(sink.writeCallCount == 1)
    }

    private func displayReadyFlag(for session: VisiDataSessionController) -> Bool {
        Mirror(reflecting: session)
            .children
            .first { $0.label == "isDisplayReady" }?
            .value as? Bool ?? false
    }
}

@MainActor
private final class TerminalDisplaySinkSpy: TerminalDisplaySink {
    private(set) var clearCallCount = 0
    private(set) var writeCallCount = 0

    func clearTerminalDisplay() {
        clearCallCount += 1
    }

    func writeToTerminalDisplay(_ data: Data) {
        writeCallCount += 1
    }

    func focusTerminalDisplay() {}
}
