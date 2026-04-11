import Testing
import Foundation
import AppKit
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
    func runningSessionDoesNotTriggerDeferredFocusStormAfterDisplayReady() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-focus-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let target = tempRoot.appendingPathComponent("large.tsv")
        try Data("col\nvalue\n".utf8).write(to: target)

        let session = VisiDataSessionController()
        let sink = TerminalDisplaySinkSpy()

        session.bind(displaySink: sink)
        try session.open(fileURL: target, explicitVDPath: launcher.path)
        defer {
            session.terminate()
        }

        session.markDisplayReady()

        #expect(sink.focusCallCount == 1)

        try await Task.sleep(for: .milliseconds(900))

        #expect(sink.focusCallCount == 1)
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
    func embeddedTerminalViewDoesNotObserveInputSourceChanges() throws {
        let source = try embeddedTerminalViewSource()

        #expect(!source.contains("Carbon.HIToolbox"))
        #expect(!source.contains("kTISNotifySelectedKeyboardInputSourceChanged"))
        #expect(!source.contains("handleInputSourceDidChange"))
    }

    @Test
    func terminalHTMLAvoidsViewportAndIMEForcedResizeStorms() throws {
        let html = try terminalHTML()

        #expect(!html.contains("window.visualViewport.addEventListener"))
        #expect(!html.contains("terminalRoot.addEventListener('compositionstart'"))
        #expect(!html.contains("terminalRoot.addEventListener('compositionend'"))
        #expect(!html.contains("resizeObserver.observe(terminalMount);"))
    }

    @Test
    func terminalHTMLUsesBoundedLayoutPassBudget() throws {
        let html = try terminalHTML()

        #expect(html.contains("let layoutPassBudgetRemaining = 0;"))
        #expect(html.contains("let deferredMeasureBudgetRemaining = 0;"))
        #expect(!html.contains("layoutRetryDeadline"))
        #expect(!html.contains("layoutStablePassesRemaining"))
        #expect(!html.contains("readyRetryHandle"))
        #expect(!html.contains("readyProbeFrameBudget"))
        #expect(!html.contains("notifyReadyWhenSized"))
        #expect(!html.contains("layoutPassBudgetRemaining < 2"))
        #expect(html.contains("deferredMeasureHandle = setTimeout(retryDeferredMeasurement, 250);"))
        #expect(html.contains("deferredMeasureBudgetRemaining = Math.max(deferredMeasureBudgetRemaining, 8);"))
        #expect(html.contains("window.iDataRefreshLayout = function() {\n      lastSentSize = null;"))
    }

    @Test
    func terminalHTMLRecoversFromDelayedTerminalMetrics() async throws {
        let harness = try TerminalHTMLHarness(initialCellWidth: 0, initialCellHeight: 0)
        try await harness.load()
        try await harness.clearMessages()

        try await Task.sleep(for: .milliseconds(950))
        try await harness.setCellMetrics(width: 8, height: 18)
        try await Task.sleep(for: .milliseconds(450))

        let messages = try await harness.messages()
        let sawResize = messages.contains { message in
            message.type == "resize" && message.cols != nil && message.rows != nil
        }
        let sawReady = messages.contains { $0.type == "ready" }
        #expect(sawResize)
        #expect(sawReady)
    }

    @Test
    func terminalHTMLRefreshLayoutRepostsResizeForSameGeometry() async throws {
        let harness = try TerminalHTMLHarness()
        try await harness.load()
        try await Task.sleep(for: .milliseconds(300))
        try await harness.clearMessages()

        _ = try await harness.evaluate("window.iDataRefreshLayout();")
        try await Task.sleep(for: .milliseconds(250))

        let messages = try await harness.messages()
        let resizeMessages = messages.filter { $0.type == "resize" }
        #expect(resizeMessages.count == 1)
        #expect(resizeMessages.first?.cols != nil)
        #expect(resizeMessages.first?.rows != nil)
    }

    @Test
    func manualActualFixtureSnapshot() async throws {
        guard
            let fixturePath = ProcessInfo.processInfo.environment["IDATA_ACTUAL_FIXTURE_PATH"],
            !fixturePath.isEmpty
        else {
            return
        }

        let fixtureURL = URL(fileURLWithPath: fixturePath)
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            Issue.record("Fixture path does not exist: \(fixtureURL.path)")
            return
        }

        let harness = ActualTerminalSnapshotHarness()
        let snapshotURL = try await harness.renderSnapshot(
            fixtureURL: fixtureURL,
            outputName: "actual-fixture-snapshot"
        )

        print("ACTUAL_FIXTURE_SNAPSHOT=\(snapshotURL.path)")

        let image = NSImage(contentsOf: snapshotURL)
        #expect(image != nil)
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
    private(set) var focusCallCount = 0

    func clearTerminalDisplay() {
        clearCallCount += 1
    }

    func writeToTerminalDisplay(_ data: Data) {
        writeCallCount += 1
    }

    func focusTerminalDisplay() {
        focusCallCount += 1
    }
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

private func embeddedTerminalViewSource(filePath: StaticString = #filePath) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot.appendingPathComponent("Sources/iData/EmbeddedTerminalView.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
}

private struct TerminalMessage: Decodable {
    let type: String
    let cols: Int?
    let rows: Int?
}

@MainActor
private final class TerminalHTMLHarness: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let html: String
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    init(
        initialCellWidth: Int = 8,
        initialCellHeight: Int = 18,
        filePath: StaticString = #filePath
    ) throws {
        let baseHTML = try terminalHTML(filePath: filePath)
        let stub = """
        <script>
          window.__terminalHarness = {
            cellWidth: \(initialCellWidth),
            cellHeight: \(initialCellHeight),
            rectWidth: 960,
            rectHeight: 640,
            messages: [],
            observers: []
          };
          window.webkit = {
            messageHandlers: {
              idata: {
                postMessage(message) {
                  window.__terminalHarness.messages.push(message);
                }
              }
            }
          };
          window.ResizeObserver = class {
            constructor(callback) {
              this.callback = callback;
              this.disconnected = false;
              window.__terminalHarness.observers.push(this);
            }
            observe(element) {
              this.element = element;
            }
            disconnect() {
              this.disconnected = true;
            }
            __fire() {
              if (!this.disconnected) {
                this.callback([{ target: this.element }]);
              }
            }
          };
          const originalGetBoundingClientRect = HTMLElement.prototype.getBoundingClientRect;
          HTMLElement.prototype.getBoundingClientRect = function() {
            if (this.id === 'terminal' || this.id === 'terminal-mount' || this.classList.contains('xterm')) {
              const width = window.__terminalHarness.rectWidth;
              const height = window.__terminalHarness.rectHeight;
              return { x: 0, y: 0, top: 0, left: 0, right: width, bottom: height, width, height, toJSON() { return this; } };
            }
            return originalGetBoundingClientRect.call(this);
          };
          window.Terminal = class {
            constructor(options) {
              this.options = {
                ...options,
                scrollbar: { showScrollbar: true, width: 14 }
              };
              this.cols = 0;
              this.rows = 0;
              this._disposables = [];
            }
            get dimensions() {
              const width = window.__terminalHarness.cellWidth;
              const height = window.__terminalHarness.cellHeight;
              if (!width || !height) {
                return null;
              }
              return { css: { cell: { width, height } } };
            }
            open(element) {
              const xtermElement = document.createElement('div');
              xtermElement.className = 'xterm';
              xtermElement.style.padding = '0px';
              element.appendChild(xtermElement);
              this.element = xtermElement;
            }
            onData() {
              return { dispose() {} };
            }
            onBinary() {
              return { dispose() {} };
            }
            focus() {}
            clearSelection() {}
            scrollToTop() {}
            dispose() {}
            resize(cols, rows) {
              this.cols = cols;
              this.rows = rows;
            }
            write() {}
          };
          window.__setCellMetrics = function(width, height) {
            window.__terminalHarness.cellWidth = width;
            window.__terminalHarness.cellHeight = height;
          };
          window.__clearMessages = function() {
            window.__terminalHarness.messages = [];
          };
          window.__messagesJSON = function() {
            return JSON.stringify(window.__terminalHarness.messages);
          };
        </script>
        """
        self.html = baseHTML.replacingOccurrences(of: "<script src=\"xterm.js\"></script>", with: stub)

        let configuration = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .init(x: 0, y: 0, width: 960, height: 640), configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
    }

    func load() async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume(returning: ())
        navigationContinuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func setCellMetrics(width: Int, height: Int) async throws {
        _ = try await evaluate("window.__setCellMetrics(\(width), \(height));")
    }

    func clearMessages() async throws {
        _ = try await evaluate("window.__clearMessages();")
    }

    func messages() async throws -> [TerminalMessage] {
        let json = try await evaluate("window.__messagesJSON();")
        let data = Data(json.utf8)
        return try JSONDecoder().decode([TerminalMessage].self, from: data)
    }

    func evaluate(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }
}

@MainActor
private final class ActualTerminalSnapshotHarness: NSObject, WKNavigationDelegate {
    private let session = VisiDataSessionController()
    private let configuration = WKWebViewConfiguration()
    private lazy var coordinator = EmbeddedTerminalView.Coordinator(session: session)
    private lazy var webView: WKWebView = {
        let contentController = WKUserContentController()
        contentController.add(coordinator, name: "idata")
        configuration.userContentController = contentController

        let webView = WKWebView(
            frame: .init(x: 0, y: 0, width: 1700, height: 980),
            configuration: configuration
        )
        webView.navigationDelegate = self
        return webView
    }()
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    func renderSnapshot(
        fixtureURL: URL,
        outputName: String,
        filePath: StaticString = #filePath
    ) async throws -> URL {
        let htmlURL = try terminalHTMLURL(filePath: filePath)
        let assetsDirectory = htmlURL.deletingLastPathComponent()

        coordinator.bind(session: session, webView: webView)

        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            webView.loadFileURL(htmlURL, allowingReadAccessTo: assetsDirectory)
        }

        try session.open(fileURL: fixtureURL, explicitVDPath: nil)
        try await Task.sleep(for: .seconds(6))

        let outputURL = try artifactURL(named: outputName, filePath: filePath)
        try await snapshotWebView(to: outputURL)
        session.terminate()
        return outputURL
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        coordinator.webView(webView, didFinish: navigation)
        navigationContinuation?.resume(returning: ())
        navigationContinuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    private func snapshotWebView(to outputURL: URL) async throws {
        let pngData: Data = try await withCheckedThrowingContinuation { continuation in
            let configuration = WKSnapshotConfiguration()
            configuration.rect = webView.bounds
            webView.takeSnapshot(with: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image else {
                    continuation.resume(throwing: SnapshotError.missingImage)
                    return
                }
                guard
                    let tiff = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiff),
                    let pngData = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
                else {
                    continuation.resume(throwing: SnapshotError.missingImageData)
                    return
                }
                continuation.resume(returning: pngData)
            }
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL)
    }
}

private enum SnapshotError: Error {
    case missingImage
    case missingImageData
}

private func terminalHTMLURL(filePath: StaticString = #filePath) throws -> URL {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return repositoryRoot.appendingPathComponent("iDataApp/Resources/TerminalAssets/terminal.html")
}

private func artifactURL(named name: String, filePath: StaticString = #filePath) throws -> URL {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return repositoryRoot
        .appendingPathComponent(".artifacts", isDirectory: true)
        .appendingPathComponent("\(name).png")
}

private func makeLongRunningLauncher(at url: URL, sleepSeconds: Int) throws {
    let script = """
    #!/bin/zsh
    trap 'exit 0' TERM INT HUP
    sleep \(sleepSeconds)
    """
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}
