import SwiftUI
import WebKit

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
        private weak var webView: WKWebView?
        private weak var session: VisiDataSessionController?
        private var isTerminalReady = false

        init(session: VisiDataSessionController) {
            self.session = session
            super.init()
        }

        func bind(session: VisiDataSessionController, webView: WKWebView) {
            if self.session !== session {
                self.session?.bind(displaySink: nil)
                self.session = session
            }

            self.webView = webView
            session.bind(displaySink: self)
            if isTerminalReady {
                session.markDisplayReady()
            }
        }

        func unbindCurrentSession() {
            session?.bind(displaySink: nil)
        }

        func loadTerminalPage() {
            guard let webView else {
                return
            }

            isTerminalReady = false

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

        func handleTerminalReady() {
            isTerminalReady = true
            session?.markDisplayReady()
        }

        func clearTerminalDisplay() {
            evaluate(functionCall: "window.iDataClearTerminal();")
        }

        func writeToTerminalDisplay(_ data: Data) {
            let payload = data.base64EncodedString()
            evaluate(functionCall: "window.iDataWriteBase64(\(quotedJavaScriptString(payload)));")
        }

        func focusTerminalDisplay() {
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
                    session?.resize(cols: cols, rows: rows)
                }
            default:
                break
            }
        }

        private func evaluate(functionCall: String) {
            webView?.evaluateJavaScript(functionCall)
        }

        private func quotedJavaScriptString(_ value: String) -> String {
            let payload = [value]
            let data = try? JSONSerialization.data(withJSONObject: payload)
            let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            return String(json.dropFirst().dropLast())
        }
    }
}
