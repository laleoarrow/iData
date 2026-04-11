import SwiftUI
import WebKit
import OSLog

private func terminalDebugTrace(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) \(message)\n"
    guard let data = line.data(using: .utf8) else {
        return
    }

    let fileURL = URL(fileURLWithPath: "/tmp/idata-terminal-trace.log")
    if !FileManager.default.fileExists(atPath: fileURL.path) {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }

    guard let handle = try? FileHandle(forWritingTo: fileURL) else {
        return
    }

    defer { try? handle.close() }

    do {
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    } catch {
        return
    }
}

struct EmbeddedTerminalView: NSViewRepresentable {
    @ObservedObject var session: VisiDataSessionController

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "idata")
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 24
        webView.layer?.masksToBounds = true
        context.coordinator.bind(session: session, webView: webView)
        context.coordinator.loadTerminalPage()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.bind(session: session, webView: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.unbindCurrentSession()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "idata")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, TerminalDisplaySink {
        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "io.github.leoarrow.idata",
            category: "TerminalLayout"
        )
        private weak var webView: WKWebView?
        private weak var session: VisiDataSessionController?
        private var didFinishInitialNavigation = false
        private var didReceiveTerminalReady = false
        private var didReceiveTerminalResize = false

        init(session: VisiDataSessionController) {
            self.session = session
            super.init()
        }

        func bind(session: VisiDataSessionController, webView: WKWebView) {
            let sessionDidChange = self.session !== session
            logger.info("coordinator bind session=\(String(describing: ObjectIdentifier(session)), privacy: .public) sessionDidChange=\(sessionDidChange, privacy: .public)")
            terminalDebugTrace("coordinator.bind session=\(ObjectIdentifier(session)) sessionDidChange=\(sessionDidChange)")
            if self.session !== session {
                self.session?.bind(displaySink: nil)
                self.session = session
                didReceiveTerminalResize = false
            }

            self.webView = webView
            session.bind(displaySink: self)
            if sessionDidChange {
                requestTerminalLayoutSyncIfPossible()
            }
            markSessionDisplayReadyIfPossible()
        }

        func unbindCurrentSession() {
            if let session {
                logger.info("coordinator unbind session=\(String(describing: ObjectIdentifier(session)), privacy: .public)")
                terminalDebugTrace("coordinator.unbind session=\(ObjectIdentifier(session))")
            }
            session?.bind(displaySink: nil)
        }

        func loadTerminalPage() {
            guard let webView else {
                return
            }

            didFinishInitialNavigation = false
            didReceiveTerminalReady = false
            didReceiveTerminalResize = false

            guard
                let assetsDirectory = Bundle.main.resourceURL?
                    .appendingPathComponent("TerminalAssets", isDirectory: true),
                let htmlURL = Bundle.main.resourceURL?
                    .appendingPathComponent("TerminalAssets/terminal.html", isDirectory: false)
            else {
                webView.loadHTMLString(
                    """
                    <html><body style="background:#0b1020;color:#e2e8f0;font:13px Menlo,monospace;padding:24px;">Missing terminal assets.</body></html>
                    """,
                    baseURL: nil
                )
                return
            }

            webView.loadFileURL(htmlURL, allowingReadAccessTo: assetsDirectory)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishInitialNavigation = true
            terminalDebugTrace("webView.didFinish")
            markSessionDisplayReadyIfPossible()
        }

        func handleTerminalReady() {
            didReceiveTerminalReady = true
            terminalDebugTrace("terminal.ready")
            markSessionDisplayReadyIfPossible()
        }

        func handleTerminalResize(cols: Int, rows: Int) {
            guard cols > 0, rows > 0 else {
                return
            }

            didReceiveTerminalResize = true
            terminalDebugTrace("terminal.resize cols=\(cols) rows=\(rows)")
            session?.resize(cols: cols, rows: rows)
            markSessionDisplayReadyIfPossible()
        }

        func clearTerminalDisplay() {
            terminalDebugTrace("terminal.clear.soft")
            evaluate(functionCall: "window.iDataSoftClearTerminal();")
        }

        func resetTerminalDisplay() {
            didReceiveTerminalReady = false
            didReceiveTerminalResize = false
            session?.invalidateDisplayReadinessForTerminalReset()
            terminalDebugTrace("terminal.clear.reset")
            evaluate(functionCall: "window.iDataClearTerminal();")
        }

        func writeToTerminalDisplay(_ data: Data) {
            let payload = data.base64EncodedString()
            evaluate(functionCall: "window.iDataWriteBase64(\(quotedJavaScriptString(payload)));")
        }

        func focusTerminalDisplay() {
            terminalDebugTrace("terminal.focus")
            evaluate(functionCall: "window.iDataFocusTerminal();")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "idata" else {
                return
            }

            guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
                return
            }

            switch type {
            case "ready":
                handleTerminalReady()
            case "input":
                if let input = body["data"] as? String {
                    session?.sendInput(input)
                }
            case "binary":
                if let payload = body["data"] as? String {
                    session?.sendBinary(base64: payload)
                }
            case "resize":
                if
                    let cols = body["cols"] as? Int,
                    let rows = body["rows"] as? Int
                {
                    handleTerminalResize(cols: cols, rows: rows)
                }
            case "debug":
                if let message = body["message"] as? String {
                    logger.info("\(message, privacy: .public)")
                    terminalDebugTrace("js.debug \(message)")
                }
            default:
                break
            }
        }

        private func evaluate(functionCall: String) {
            webView?.evaluateJavaScript(functionCall)
        }

        private func requestTerminalLayoutSyncIfPossible() {
            guard didFinishInitialNavigation, didReceiveTerminalReady else {
                return
            }

            evaluate(functionCall: "window.iDataRefreshLayout ? window.iDataRefreshLayout() : window.iDataFocusTerminal();")
        }

        private func markSessionDisplayReadyIfPossible() {
            guard didFinishInitialNavigation, didReceiveTerminalReady, didReceiveTerminalResize else {
                return
            }

            session?.markDisplayReady()
        }

        private func quotedJavaScriptString(_ value: String) -> String {
            let payload = [value]
            let data = try? JSONSerialization.data(withJSONObject: payload)
            let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            return String(json.dropFirst().dropLast())
        }
    }
}
