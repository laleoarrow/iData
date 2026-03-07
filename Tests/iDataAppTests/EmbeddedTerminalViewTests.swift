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

    private func displayReadyFlag(for session: VisiDataSessionController) -> Bool {
        Mirror(reflecting: session)
            .children
            .first { $0.label == "isDisplayReady" }?
            .value as? Bool ?? false
    }
}
