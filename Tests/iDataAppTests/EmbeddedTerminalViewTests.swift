import Testing
import Foundation
import WebKit
@testable import iData

@MainActor
struct EmbeddedTerminalViewTests {
    @Test
    func sessionOnlyBecomesReadyAfterNavigationTerminalReadyAndFirstResize() {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = WKWebView(frame: .zero)

        coordinator.bind(session: session, webView: webView)
        coordinator.handleTerminalReady()

        #expect(!displayReadyFlag(for: session))

        coordinator.webView(webView, didFinish: nil)

        #expect(!displayReadyFlag(for: session))

        coordinator.handleTerminalResize(cols: 120, rows: 32)

        #expect(displayReadyFlag(for: session))
    }

    @Test
    func rebindingToNewSessionWaitsForFreshResizeBeforeMarkingDisplayReady() {
        let firstSession = VisiDataSessionController()
        let secondSession = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: firstSession)
        let webView = WKWebView(frame: .zero)

        coordinator.bind(session: firstSession, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady()
        coordinator.handleTerminalResize(cols: 120, rows: 32)

        #expect(displayReadyFlag(for: firstSession))

        coordinator.bind(session: secondSession, webView: webView)

        #expect(!displayReadyFlag(for: firstSession))
        #expect(!displayReadyFlag(for: secondSession))

        coordinator.handleTerminalResize(cols: 120, rows: 32)

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

    @Test
    func terminalHTMLUsesDedicatedMountElementForXterm() throws {
        let html = try terminalHTML()

        #expect(html.contains("id=\"terminal-mount\""))
        #expect(html.contains("const terminalMount = document.getElementById('terminal-mount');"))
        #expect(html.contains("term.open(terminalMount);"))
    }

    @Test
    func terminalHTMLForcesResizeWhenFocusReenters() throws {
        let html = try terminalHTML()

        #expect(html.contains("window.iDataFocusTerminal = function()"))
        #expect(html.contains("term?.focus();"))
        #expect(html.contains("scheduleTerminalLayoutPasses({ forceResize: true });"))
        #expect(html.contains("terminalRoot.addEventListener('focusin', () => {\n      scheduleTerminalLayoutPasses({ forceResize: true });\n    });"))
        #expect(html.contains("document.addEventListener('visibilitychange'"))
        #expect(html.contains("if (!document.hidden) {\n        scheduleTerminalLayoutPasses({ forceResize: true });\n      }"))
        #expect(html.contains("window.addEventListener('pageshow'"))
        #expect(html.contains("window.addEventListener('focus', () => {\n      scheduleTerminalLayoutPasses({ forceResize: true });\n    });"))
    }

    @Test
    func terminalHTMLResetsViewportStateWhenClearingTerminal() throws {
        let html = try terminalHTML()

        #expect(html.contains("term.clearSelection();"))
        #expect(html.contains("term.scrollToTop();"))
    }

    @Test
    func terminalHTMLRecreatesTerminalInstanceWhenClearingDisplay() throws {
        let html = try terminalHTML()

        #expect(html.contains("function createTerminal("))
        #expect(html.contains("term.dispose();"))
        #expect(html.contains("createTerminal();"))
    }

    @Test
    func terminalHTMLAvoidsHotPathForcedRefreshCalls() throws {
        let html = try terminalHTML()

        #expect(!html.contains("currentTerm.refresh(0, Math.max(currentTerm.rows - 1, 0));"))
        #expect(!html.contains("term.refresh(0, Math.max(term.rows - 1, 0));"))
    }

    @Test
    func terminalHTMLDoesNotSendForcedResizeWhenSizeUnchanged() throws {
        let html = try terminalHTML()

        #expect(!html.contains("if (force || sizeChanged) {"))
        #expect(html.contains("if (sizeChanged || terminalNeedsResize) {"))
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

private func terminalHTML(filePath: StaticString = #filePath) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let htmlURL = repositoryRoot.appendingPathComponent("iDataApp/Resources/TerminalAssets/terminal.html")
    return try String(contentsOf: htmlURL, encoding: .utf8)
}
