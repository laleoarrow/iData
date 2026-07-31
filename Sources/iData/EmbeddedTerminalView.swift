import SwiftUI
import WebKit

/// WKWebView subclass that prevents the terminal from eating the first mouse
/// click when focus needs to move to a sibling SwiftUI control (e.g. sidebar).
///
/// On macOS, when a WKWebView holds first-responder status, clicking outside
/// it (e.g. on a sidebar Button) normally just transfers focus without
/// triggering the button action.  Overriding `acceptsFirstMouse` and properly
/// resigning first-responder fixes this.
final class TerminalWebView: WKWebView {
    /// Allow clicks on the window to pass through even when the window is
    /// becoming key, so sidebar buttons respond on the very first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// When another view claims first-responder (e.g. the user clicks the
    /// sidebar), blur the embedded xterm so key events stop going to it.
    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            evaluateJavaScript("window.iDataBlurTerminal && window.iDataBlurTerminal();")
        }
        return didResign
    }
}

struct EmbeddedTerminalView: NSViewRepresentable {
    @ObservedObject var session: VisiDataSessionController

    static func terminalDebugConfigurationJavaScript(isEnabled: Bool) -> String {
        "window.iDataDebugEnabled = \(isEnabled ? "true" : "false");"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "idata")
        contentController.addUserScript(
            WKUserScript(
                source: Self.terminalDebugConfigurationJavaScript(isEnabled: TerminalDebugLogger.isEnabled),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController = contentController

        let webView = TerminalWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 0
        webView.layer?.masksToBounds = false
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
            let webViewDidChange = self.webView !== webView
            guard sessionDidChange || webViewDidChange else {
                return
            }

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

        func handleTerminalResize(cols: Int, rows: Int, force: Bool = false) {
            guard cols > 0, rows > 0 else {
                return
            }

            didReceiveTerminalResize = true
            terminalDebugTrace("terminal.resize cols=\(cols) rows=\(rows) force=\(force)")
            session?.resize(cols: cols, rows: rows, force: force)
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
            evaluate(functionCall: Self.terminalWriteJavaScript(for: data))
        }

        static func terminalWriteJavaScript(for data: Data) -> String {
            "window.iDataWriteBase64(\"\(data.base64EncodedString())\");"
        }

        func focusTerminalDisplay() {
            terminalDebugTrace("terminal.focus")
            if let webView {
                _ = webView.window?.makeFirstResponder(webView)
            }
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
                    let force = body["force"] as? Bool ?? false
                    handleTerminalResize(cols: cols, rows: rows, force: force)
                }
            case "debug":
                if let message = body["message"] as? String {
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
    }
}
