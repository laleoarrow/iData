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
        webView.navigationDelegate = nil
        coordinator.unbindCurrentSession()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "idata")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, TerminalDisplaySink {
        private weak var webView: WKWebView?
        private weak var session: VisiDataSessionController?
        private var bindingEpoch = 0
        private var didFinishInitialNavigation = false
        private var didReceiveTerminalReady = false
        private var didReceiveTerminalResize = false
        private var displayGeneration = 0
        private var pendingResetGeneration: Int?
        private var resetEvaluationAttempt = 0
        private var resetEvaluationSequence = 0
        private var activeResetEvaluationSequence: Int?
        private var resetEvaluationTimeoutWorkItem: DispatchWorkItem?
        private var resetRetryWorkItem: DispatchWorkItem?
        private var resetReloadAttempt = 0
        private var initialHandshakeAttempt = 0
        private var initialHandshakeSequence = 0
        private var initialHandshakeWorkItem: DispatchWorkItem?
        private var navigationRecoveryAttempt = 0
        private var navigationEpoch = 0
        private var activeNavigation: WKNavigation?
        private var navigationRecoveryWorkItem: DispatchWorkItem?

        private static let resetHandshakeTimeout: TimeInterval = 3.2
        private static let resetRetryDelay: TimeInterval = 0.12
        private static let resetAttemptsBeforeReload = 4
        private static let resetReloadLimit = 3
        private static let navigationRecoveryLimit = 5

        init(session: VisiDataSessionController) {
            self.session = session
            super.init()
        }

        func bind(session: VisiDataSessionController, webView: WKWebView) {
            let sessionDidChange = self.session !== session
            let webViewDidChange = self.webView !== webView
            let hadPendingReset = pendingResetGeneration != nil
            guard sessionDidChange || webViewDidChange else {
                return
            }

            bindingEpoch &+= 1
            cancelTerminalResetWork()
            cancelInitialHandshakeWatchdog()
            navigationRecoveryWorkItem?.cancel()
            navigationRecoveryWorkItem = nil
            activeNavigation = nil

            terminalDebugTrace("coordinator.bind session=\(ObjectIdentifier(session)) sessionDidChange=\(sessionDidChange)")
            if self.session !== session {
                self.session?.unbind(displaySink: self)
                self.session = session
                didReceiveTerminalResize = false
            }

            self.webView = webView
            session.bind(displaySink: self)
            if hadPendingReset {
                resetReloadAttempt = 0
                advanceTerminalResetGeneration(resetEvaluationBudget: true)
                _ = flushPendingTerminalResetIfPossible()
            } else if sessionDidChange {
                requestTerminalLayoutSyncIfPossible()
            }
            markSessionDisplayReadyIfPossible()
        }

        func unbindCurrentSession() {
            if let session {
                terminalDebugTrace("coordinator.unbind session=\(ObjectIdentifier(session))")
            }
            cancelTerminalResetWork()
            cancelInitialHandshakeWatchdog()
            navigationRecoveryWorkItem?.cancel()
            navigationRecoveryWorkItem = nil
            bindingEpoch &+= 1
            session?.unbind(displaySink: self)
            session = nil
            webView = nil
        }

        func loadTerminalPage(resetRecoveryBudget: Bool = true) {
            guard let webView else {
                return
            }

            if resetRecoveryBudget {
                resetReloadAttempt = 0
                initialHandshakeAttempt = 0
            }

            if didFinishInitialNavigation {
                beginTerminalNavigation()
            } else {
                // The bundled page starts at generation zero. Keep the first
                // native load on that generation so its initial ready/resize
                // handshake cannot depend on a follow-up JavaScript reset.
                didReceiveTerminalReady = false
                didReceiveTerminalResize = false
            }

            guard
                let assetsDirectory = Bundle.main.resourceURL?
                    .appendingPathComponent("TerminalAssets", isDirectory: true),
                let htmlURL = Bundle.main.resourceURL?
                    .appendingPathComponent("TerminalAssets/terminal.html", isDirectory: false)
            else {
                activeNavigation = webView.loadHTMLString(
                    """
                    <html><body style="background:#0b1020;color:#e2e8f0;font:13px Menlo,monospace;padding:24px;">Missing terminal assets.</body></html>
                    """,
                    baseURL: nil
                )
                return
            }

            activeNavigation = webView.loadFileURL(htmlURL, allowingReadAccessTo: assetsDirectory)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard self.webView === webView, session?.isBound(displaySink: self) == true else {
                return
            }
            if let navigation, navigation !== activeNavigation {
                terminalDebugTrace("webView.didFinish ignored stale navigation")
                return
            }
            activeNavigation = nil
            didFinishInitialNavigation = true
            navigationRecoveryWorkItem?.cancel()
            navigationRecoveryWorkItem = nil
            terminalDebugTrace("webView.didFinish")
            if flushPendingTerminalResetIfPossible() {
                return
            }
            markSessionDisplayReadyIfPossible()
            armInitialHandshakeWatchdogIfNeeded()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            guard self.webView === webView, session?.isBound(displaySink: self) == true else {
                return
            }
            navigationEpoch &+= 1
            activeNavigation = navigation
            cancelInitialHandshakeWatchdog()
            initialHandshakeAttempt = 0
            navigationRecoveryWorkItem?.cancel()
            navigationRecoveryWorkItem = nil
            if didFinishInitialNavigation {
                resetReloadAttempt = 0
                beginTerminalNavigation()
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard self.webView === webView, session?.isBound(displaySink: self) == true else {
                return
            }
            terminalDebugTrace("webView.webContentProcessDidTerminate")
            if didFinishInitialNavigation {
                beginTerminalNavigation()
            } else {
                didReceiveTerminalReady = false
                didReceiveTerminalResize = false
                cancelTerminalResetWork()
                session?.invalidateDisplayReadinessForTerminalReset()
            }
            scheduleNavigationRecovery(reason: "WebContent process terminated")
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            recoverFromNavigationFailure(in: webView, navigation: navigation, error: error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            recoverFromNavigationFailure(in: webView, navigation: navigation, error: error)
        }

        func handleTerminalReady(displayGeneration messageGeneration: Int? = nil) {
            guard session?.isBound(displaySink: self) == true else {
                return
            }
            guard (messageGeneration ?? displayGeneration) == displayGeneration else {
                terminalDebugTrace("terminal.ready ignored generation=\(messageGeneration ?? -1) expected=\(displayGeneration)")
                return
            }

            didReceiveTerminalReady = true
            terminalDebugTrace("terminal.ready generation=\(displayGeneration)")
            completePendingTerminalResetIfPossible()
            markSessionDisplayReadyIfPossible()
        }

        func handleTerminalResize(
            cols: Int,
            rows: Int,
            force: Bool = false,
            displayGeneration messageGeneration: Int? = nil
        ) {
            guard session?.isBound(displaySink: self) == true else {
                return
            }
            guard cols > 0, rows > 0 else {
                return
            }
            guard (messageGeneration ?? displayGeneration) == displayGeneration else {
                terminalDebugTrace("terminal.resize ignored generation=\(messageGeneration ?? -1) expected=\(displayGeneration)")
                return
            }

            didReceiveTerminalResize = true
            terminalDebugTrace("terminal.resize generation=\(displayGeneration) cols=\(cols) rows=\(rows) force=\(force)")
            session?.resize(cols: cols, rows: rows, force: force)
            completePendingTerminalResetIfPossible()
            markSessionDisplayReadyIfPossible()
        }

        func clearTerminalDisplay() {
            terminalDebugTrace("terminal.clear.soft generation=\(displayGeneration)")
            evaluate(functionCall: "window.iDataSoftClearTerminal(\(displayGeneration));")
        }

        func resetTerminalDisplay() {
            resetReloadAttempt = 0
            advanceTerminalResetGeneration(resetEvaluationBudget: true)
            terminalDebugTrace("terminal.clear.reset generation=\(displayGeneration)")
            _ = flushPendingTerminalResetIfPossible()
        }

        func writeToTerminalDisplay(_ data: Data) {
            evaluate(functionCall: Self.terminalWriteJavaScript(for: data, displayGeneration: displayGeneration))
        }

        static func terminalWriteJavaScript(for data: Data, displayGeneration: Int = 0) -> String {
            "window.iDataWriteBase64(\"\(data.base64EncodedString())\", \(displayGeneration));"
        }

        func focusTerminalDisplay() {
            terminalDebugTrace("terminal.focus")
            if let webView {
                _ = webView.window?.makeFirstResponder(webView)
            }
            evaluate(functionCall: "window.iDataFocusTerminal(\(displayGeneration));")
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
                guard let messageGeneration = body["displayGeneration"] as? Int else {
                    return
                }
                handleTerminalReady(displayGeneration: messageGeneration)
            case "input":
                if
                    session?.isBound(displaySink: self) == true,
                    body["displayGeneration"] as? Int == displayGeneration,
                    let input = body["data"] as? String
                {
                    session?.sendInput(input)
                }
            case "binary":
                if
                    session?.isBound(displaySink: self) == true,
                    body["displayGeneration"] as? Int == displayGeneration,
                    let payload = body["data"] as? String
                {
                    session?.sendBinary(base64: payload)
                }
            case "resize":
                if
                    let cols = body["cols"] as? Int,
                    let rows = body["rows"] as? Int
                {
                    let force = body["force"] as? Bool ?? false
                    guard let messageGeneration = body["displayGeneration"] as? Int else {
                        return
                    }
                    handleTerminalResize(
                        cols: cols,
                        rows: rows,
                        force: force,
                        displayGeneration: messageGeneration
                    )
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

            evaluate(
                functionCall: "window.iDataRefreshLayout ? window.iDataRefreshLayout(\(displayGeneration)) : window.iDataFocusTerminal(\(displayGeneration));"
            )
        }

        @discardableResult
        private func flushPendingTerminalResetIfPossible() -> Bool {
            guard
                didFinishInitialNavigation,
                let generation = pendingResetGeneration,
                activeResetEvaluationSequence == nil,
                let webView
            else {
                return false
            }

            resetRetryWorkItem?.cancel()
            resetRetryWorkItem = nil
            resetEvaluationAttempt += 1
            resetEvaluationSequence &+= 1
            let evaluationSequence = resetEvaluationSequence
            let evaluationBindingEpoch = bindingEpoch
            activeResetEvaluationSequence = evaluationSequence

            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                guard
                    let self,
                    self.bindingEpoch == evaluationBindingEpoch,
                    self.session?.isBound(displaySink: self) == true,
                    self.pendingResetGeneration == generation,
                    self.resetEvaluationSequence == evaluationSequence
                else {
                    return
                }
                self.activeResetEvaluationSequence = nil
                self.resetEvaluationTimeoutWorkItem = nil
                terminalDebugTrace("terminal.clear.reset handshakeTimeout generation=\(generation) attempt=\(self.resetEvaluationAttempt)")
                self.retryTerminalReset(generation: generation)
            }
            resetEvaluationTimeoutWorkItem?.cancel()
            resetEvaluationTimeoutWorkItem = timeoutWorkItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.resetHandshakeTimeout,
                execute: timeoutWorkItem
            )

            let script = "window.iDataClearTerminal ? window.iDataClearTerminal(\(generation)) : false;"
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard
                    let self,
                    self.bindingEpoch == evaluationBindingEpoch,
                    self.session?.isBound(displaySink: self) == true,
                    self.pendingResetGeneration == generation,
                    self.activeResetEvaluationSequence == evaluationSequence
                else {
                    return
                }

                self.activeResetEvaluationSequence = nil

                guard error == nil, result as? Bool == true else {
                    self.resetEvaluationTimeoutWorkItem?.cancel()
                    self.resetEvaluationTimeoutWorkItem = nil
                    let resetError = error?.localizedDescription ?? "false result"
                    terminalDebugTrace("terminal.clear.reset rejected generation=\(generation) attempt=\(self.resetEvaluationAttempt) error=\(resetError)")
                    self.retryTerminalReset(generation: generation)
                    return
                }

                // Returning true only proves that JavaScript rebuilt xterm.
                // The reset is complete after that exact generation also
                // reports both ready and its measured rows/columns.
                terminalDebugTrace("terminal.clear.reset evaluated generation=\(generation)")
            }
            return true
        }

        private func retryTerminalReset(generation: Int) {
            guard pendingResetGeneration == generation else {
                return
            }

            cancelTerminalResetWork()

            if resetEvaluationAttempt >= Self.resetAttemptsBeforeReload {
                resetReloadAttempt += 1
                guard resetReloadAttempt <= Self.resetReloadLimit else {
                    reportTerminalFailure("Terminal failed to reset after repeated reloads.")
                    return
                }
                terminalDebugTrace("terminal.clear.reset reloading generation=\(generation)")
                resetEvaluationAttempt = 0
                loadTerminalPage(resetRecoveryBudget: false)
                return
            }

            let retryBindingEpoch = bindingEpoch
            let retryWorkItem = DispatchWorkItem { [weak self] in
                guard
                    let self,
                    self.bindingEpoch == retryBindingEpoch,
                    self.session?.isBound(displaySink: self) == true,
                    self.pendingResetGeneration == generation
                else {
                    return
                }
                self.resetRetryWorkItem = nil
                self.advanceTerminalResetGeneration(resetEvaluationBudget: false)
                _ = self.flushPendingTerminalResetIfPossible()
            }
            resetRetryWorkItem?.cancel()
            resetRetryWorkItem = retryWorkItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.resetRetryDelay,
                execute: retryWorkItem
            )
        }

        private func cancelTerminalResetWork() {
            resetEvaluationTimeoutWorkItem?.cancel()
            resetEvaluationTimeoutWorkItem = nil
            resetRetryWorkItem?.cancel()
            resetRetryWorkItem = nil
            activeResetEvaluationSequence = nil
        }

        private func armInitialHandshakeWatchdogIfNeeded() {
            guard
                didFinishInitialNavigation,
                pendingResetGeneration == nil,
                !(didReceiveTerminalReady && didReceiveTerminalResize),
                initialHandshakeWorkItem == nil
            else {
                return
            }

            initialHandshakeAttempt += 1
            initialHandshakeSequence &+= 1
            let handshakeSequence = initialHandshakeSequence
            let generation = displayGeneration
            let handshakeBindingEpoch = bindingEpoch
            let watchdog = DispatchWorkItem { [weak self] in
                guard
                    let self,
                    self.bindingEpoch == handshakeBindingEpoch,
                    self.session?.isBound(displaySink: self) == true,
                    self.initialHandshakeSequence == handshakeSequence,
                    self.displayGeneration == generation,
                    self.didFinishInitialNavigation,
                    self.pendingResetGeneration == nil,
                    !(self.didReceiveTerminalReady && self.didReceiveTerminalResize)
                else {
                    return
                }

                self.initialHandshakeWorkItem = nil
                if self.initialHandshakeAttempt == 1 {
                    terminalDebugTrace("terminal.initialHandshake refresh generation=\(generation)")
                    self.evaluate(
                        functionCall: "window.iDataRefreshLayout ? window.iDataRefreshLayout(\(generation)) : false;"
                    )
                    self.armInitialHandshakeWatchdogIfNeeded()
                    return
                }

                terminalDebugTrace("terminal.initialHandshake reloading generation=\(generation)")
                self.beginTerminalNavigation()
                self.scheduleNavigationRecovery(reason: "Initial terminal handshake timed out")
            }
            initialHandshakeWorkItem = watchdog
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.resetHandshakeTimeout,
                execute: watchdog
            )
        }

        private func cancelInitialHandshakeWatchdog() {
            initialHandshakeWorkItem?.cancel()
            initialHandshakeWorkItem = nil
        }

        private func recoverFromNavigationFailure(
            in webView: WKWebView,
            navigation: WKNavigation?,
            error: Error
        ) {
            guard self.webView === webView, session?.isBound(displaySink: self) == true else {
                return
            }
            if let navigation, navigation !== activeNavigation {
                terminalDebugTrace("terminal.navigation ignored stale failure")
                return
            }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                if didFinishInitialNavigation, pendingResetGeneration == nil {
                    terminalDebugTrace("terminal.navigation ignored inactive cancellation")
                    return
                }
                terminalDebugTrace("terminal.navigation recovering current cancellation")
            }

            activeNavigation = nil
            didFinishInitialNavigation = false
            didReceiveTerminalReady = false
            didReceiveTerminalResize = false
            cancelTerminalResetWork()
            cancelInitialHandshakeWatchdog()
            session?.invalidateDisplayReadinessForTerminalReset()
            scheduleNavigationRecovery(reason: error.localizedDescription)
        }

        private func scheduleNavigationRecovery(reason: String) {
            navigationRecoveryAttempt += 1
            guard navigationRecoveryAttempt <= Self.navigationRecoveryLimit else {
                reportTerminalFailure("Terminal page failed to load after repeated attempts.")
                return
            }
            terminalDebugTrace("terminal.navigation recover attempt=\(navigationRecoveryAttempt) reason=\(reason)")

            let exponent = min(navigationRecoveryAttempt - 1, 4)
            let delay = min(0.15 * pow(2.0, Double(exponent)), 2.0)
            let scheduledEpoch = navigationEpoch
            let scheduledBindingEpoch = bindingEpoch
            let recoveryWorkItem = DispatchWorkItem { [weak self] in
                guard
                    let self,
                    self.bindingEpoch == scheduledBindingEpoch,
                    self.session?.isBound(displaySink: self) == true,
                    self.navigationEpoch == scheduledEpoch
                else {
                    return
                }
                self.navigationRecoveryWorkItem = nil
                self.loadTerminalPage(resetRecoveryBudget: false)
            }
            navigationRecoveryWorkItem?.cancel()
            navigationRecoveryWorkItem = recoveryWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: recoveryWorkItem)
        }

        private func beginTerminalNavigation() {
            cancelInitialHandshakeWatchdog()
            initialHandshakeAttempt = 0
            advanceTerminalResetGeneration(resetEvaluationBudget: true)
            didFinishInitialNavigation = false
            terminalDebugTrace("terminal.navigation generation=\(displayGeneration)")
        }

        private func advanceTerminalResetGeneration(resetEvaluationBudget: Bool) {
            cancelTerminalResetWork()
            if resetEvaluationBudget {
                resetEvaluationAttempt = 0
            }
            displayGeneration &+= 1
            didReceiveTerminalReady = false
            didReceiveTerminalResize = false
            pendingResetGeneration = displayGeneration
            if session?.isBound(displaySink: self) == true {
                session?.invalidateDisplayReadinessForTerminalReset()
            }
        }

        @discardableResult
        private func completePendingTerminalResetIfPossible() -> Bool {
            guard
                didFinishInitialNavigation,
                pendingResetGeneration == displayGeneration,
                didReceiveTerminalReady,
                didReceiveTerminalResize
            else {
                return false
            }

            pendingResetGeneration = nil
            cancelTerminalResetWork()
            resetEvaluationAttempt = 0
            resetReloadAttempt = 0
            navigationRecoveryAttempt = 0
            terminalDebugTrace("terminal.clear.reset handshake generation=\(displayGeneration)")
            return true
        }

        private func reportTerminalFailure(_ englishMessage: String) {
            guard session?.isBound(displaySink: self) == true else {
                return
            }
            pendingResetGeneration = nil
            cancelTerminalResetWork()
            cancelInitialHandshakeWatchdog()
            navigationRecoveryWorkItem?.cancel()
            navigationRecoveryWorkItem = nil
            terminalDebugTrace("terminal.failure \(englishMessage)")
            session?.reportTerminalDisplayFailure(
                english: englishMessage,
                chinese: "终端载入失败，请重新打开文件。"
            )
        }

        private func markSessionDisplayReadyIfPossible() {
            guard
                didFinishInitialNavigation,
                pendingResetGeneration == nil,
                didReceiveTerminalReady,
                didReceiveTerminalResize
            else {
                return
            }
            guard session?.isBound(displaySink: self) == true else {
                return
            }

            navigationRecoveryAttempt = 0
            resetReloadAttempt = 0
            initialHandshakeAttempt = 0
            cancelInitialHandshakeWatchdog()
            session?.markDisplayReady()
        }
    }
}
