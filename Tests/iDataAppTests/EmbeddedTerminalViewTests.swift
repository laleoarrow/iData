import Testing
import Foundation
import AppKit
import JavaScriptCore
import WebKit
@testable import iData

@Suite(.serialized)
@MainActor
struct EmbeddedTerminalViewTests {
    @Test
    func focusingTerminalClaimsTheNativeFirstResponder() {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = TerminalWebView(frame: .init(x: 0, y: 0, width: 640, height: 420))
        let tutorialButton = NSButton(title: "Next", target: nil, action: nil)
        let container = NSView(frame: webView.frame)
        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        container.addSubview(webView)
        container.addSubview(tutorialButton)
        window.contentView = container
        coordinator.bind(session: session, webView: webView)

        #expect(window.makeFirstResponder(tutorialButton))
        #expect(window.firstResponder === tutorialButton)

        coordinator.focusTerminalDisplay()

        #expect(window.firstResponder === webView)
    }

    @Test
    func deferredTerminalFocusWinsAfterAButtonAction() async {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = TerminalWebView(frame: .init(x: 0, y: 0, width: 640, height: 420))
        let tutorialButton = NSButton(title: "Next", target: nil, action: nil)
        let container = NSView(frame: webView.frame)
        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        container.addSubview(webView)
        container.addSubview(tutorialButton)
        window.contentView = container
        coordinator.bind(session: session, webView: webView)

        DispatchQueue.main.async {
            coordinator.focusTerminalDisplay()
        }
        #expect(window.makeFirstResponder(tutorialButton))

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        #expect(window.firstResponder === webView)
    }

    @Test
    func sessionOnlyBecomesReadyAfterNavigationTerminalReadyAndFirstResize() {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView()

        coordinator.bind(session: session, webView: webView)
        coordinator.handleTerminalReady()

        #expect(!displayReadyFlag(for: session))

        coordinator.webView(webView, didFinish: nil)

        #expect(!displayReadyFlag(for: session))

        coordinator.handleTerminalResize(cols: 120, rows: 32)

        #expect(displayReadyFlag(for: session))
    }

    @Test
    func initialTerminalPageAcceptsTheHTMLGenerationZeroHandshake() {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView()

        coordinator.bind(session: session, webView: webView)
        coordinator.loadTerminalPage()
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        coordinator.webView(webView, didFinish: nil)

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

        #expect(sink.clearCallCount == 0)
        #expect(sink.resetCallCount == 0)
        #expect(sink.writeCallCount == 1)

        try await Task.sleep(for: .milliseconds(650))

        #expect(sink.clearCallCount == 0)
        #expect(sink.resetCallCount == 0)
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

        #expect(sink.clearCallCount == 0)
        #expect(sink.resetCallCount == 0)
        #expect(sink.writeCallCount == 1)
        #expect(sink.focusCallCount == 1)

        session.markDisplayReady()
        session.markDisplayReady()

        #expect(sink.clearCallCount == 0)
        #expect(sink.resetCallCount == 0)
        #expect(sink.writeCallCount == 1)
        #expect(sink.focusCallCount == 1)
    }

    @Test
    func rebindingExistingSessionReplaysTranscriptIntoReplacementDisplay() {
        let session = VisiDataSessionController()
        let firstSink = TerminalDisplaySinkSpy()
        let secondSink = TerminalDisplaySinkSpy()

        session.bind(displaySink: firstSink)
        session.appendOutputForTesting(Data("hello".utf8))
        session.markDisplayReady()

        #expect(firstSink.clearCallCount == 0)
        #expect(firstSink.writeCallCount == 1)

        session.bind(displaySink: nil)
        session.bind(displaySink: secondSink)
        session.markDisplayReady()

        #expect(secondSink.clearCallCount == 1)
        #expect(secondSink.resetCallCount == 0)
        #expect(secondSink.writeCallCount == 1)
        #expect(secondSink.focusCallCount == 1)
    }

    @Test
    func resetTerminalDisplayRequiresFreshReadyAndResizeBeforeSessionBecomesReadyAgain() {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView()

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady()
        coordinator.handleTerminalResize(cols: 120, rows: 32)

        #expect(displayReadyFlag(for: session))

        coordinator.resetTerminalDisplay()

        #expect(!displayReadyFlag(for: session))

        coordinator.handleTerminalResize(cols: 120, rows: 32)
        #expect(!displayReadyFlag(for: session))

        coordinator.handleTerminalReady()
        #expect(displayReadyFlag(for: session))
    }

    @Test
    func hardResetReadinessDoesNotSoftClearTheFreshTerminalBeforeReplay() {
        let session = VisiDataSessionController()
        let sink = TerminalDisplaySinkSpy()

        session.bind(displaySink: sink)
        session.appendOutputForTesting(Data("VISIBLE".utf8))
        session.markDisplayReady()

        #expect(sink.clearCallCount == 0)
        #expect(sink.writeCallCount == 1)

        session.invalidateDisplayReadinessForTerminalReset()
        session.markDisplayReady()

        #expect(sink.clearCallCount == 0)
        #expect(sink.writeCallCount == 2)
    }

    @Test
    func staleTerminalGenerationCannotMakeLatestResetReady() {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView(resetOutcomes: [.success, .success])

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        #expect(displayReadyFlag(for: session))

        coordinator.resetTerminalDisplay()
        coordinator.resetTerminalDisplay()

        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 1)
        coordinator.handleTerminalReady(displayGeneration: 1)
        #expect(!displayReadyFlag(for: session))

        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 2)
        #expect(!displayReadyFlag(for: session))

        coordinator.handleTerminalReady(displayGeneration: 2)
        #expect(displayReadyFlag(for: session))
    }

    @Test
    func resetBeforeNavigationFinishesRejectsInitialTerminalMessages() {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView()

        coordinator.bind(session: session, webView: webView)
        for _ in 0..<50 {
            coordinator.resetTerminalDisplay()
        }
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        coordinator.handleTerminalReady(displayGeneration: 49)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 49)
        coordinator.webView(webView, didFinish: nil)

        #expect(!displayReadyFlag(for: session))

        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 50)
        coordinator.handleTerminalReady(displayGeneration: 50)

        #expect(displayReadyFlag(for: session))
    }

    @Test
    func failedTerminalResetEvaluationRetriesBeforeAcceptingTheNewGeneration() async throws {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView(resetOutcomes: [.failure, .success])

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        #expect(displayReadyFlag(for: session))

        coordinator.resetTerminalDisplay()
        #expect(!displayReadyFlag(for: session))

        let didRetry = try await waitUntil {
            webView.resetEvaluationCallCount >= 2
        }

        #expect(didRetry)
        try await Task.sleep(for: .milliseconds(300))
        #expect(webView.resetEvaluationCallCount == 2)
        #expect(!displayReadyFlag(for: session))

        coordinator.handleTerminalReady(displayGeneration: 2)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 2)

        #expect(displayReadyFlag(for: session))
    }

    @Test
    func timedOutTerminalResetEvaluationRetriesInsteadOfStalling() async throws {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView(resetOutcomes: [.noCompletion, .success])

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)

        coordinator.resetTerminalDisplay()

        let didRetry = try await waitUntil {
            webView.resetEvaluationCallCount >= 2
        }

        #expect(didRetry)
        try await Task.sleep(for: .milliseconds(300))
        #expect(webView.resetEvaluationCallCount == 2)
        #expect(!displayReadyFlag(for: session))

        coordinator.handleTerminalReady(displayGeneration: 2)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 2)

        #expect(displayReadyFlag(for: session))
    }

    @Test
    func matchingHandshakeCompletesWhenJavaScriptCompletionIsLost() async throws {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView(resetOutcomes: [.noCompletion])

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)

        coordinator.resetTerminalDisplay()
        coordinator.handleTerminalReady(displayGeneration: 1)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 1)

        #expect(displayReadyFlag(for: session))

        try await Task.sleep(for: .milliseconds(3_500))

        #expect(webView.resetEvaluationCallCount == 1)
        #expect(displayReadyFlag(for: session))
    }

    @Test
    func repeatedTerminalResetEvaluationFailureReloadsTheBundledPage() async throws {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView(
            resetOutcomes: [.failure, .failure, .failure, .failure]
        )

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)

        coordinator.resetTerminalDisplay()
        let didReload = try await waitUntil {
            webView.pageLoadCallCount >= 1
        }

        #expect(didReload)
        #expect(webView.resetEvaluationCallCount == 4)
        #expect(webView.pageLoadCallCount == 1)
        #expect(!displayReadyFlag(for: session))
    }

    @Test
    func persistentTerminalResetFailureStopsAfterTheReloadBudget() async throws {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView(
            resetOutcomes: Array(repeating: .failure, count: 16)
        )

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)

        coordinator.resetTerminalDisplay()
        for expectedPageLoadCount in 1...3 {
            let didReload = try await waitUntil {
                webView.pageLoadCallCount >= expectedPageLoadCount
            }
            #expect(didReload)
            guard didReload else {
                return
            }
            #expect(webView.pageLoadCallCount == expectedPageLoadCount)
            coordinator.webView(webView, didFinish: nil)
        }
        let didExhaustReloadBudget = try await waitUntil {
            webView.resetEvaluationCallCount >= 16 && session.errorMessage != nil
        }

        #expect(didExhaustReloadBudget)
        #expect(webView.resetEvaluationCallCount == 16)
        #expect(webView.pageLoadCallCount == 3)
        #expect(session.errorMessage != nil)
        #expect(!displayReadyFlag(for: session))
    }

    @Test
    func provisionalNavigationFailureSchedulesARecoveryLoad() async throws {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView()

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        #expect(displayReadyFlag(for: session))

        coordinator.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: SimulatedTerminalJavaScriptError()
        )

        #expect(!displayReadyFlag(for: session))

        let didScheduleRecovery = try await waitUntil {
            webView.pageLoadCallCount >= 1
        }

        #expect(didScheduleRecovery)
        #expect(webView.pageLoadCallCount == 1)
    }

    @Test
    func cancelledNavigationDoesNotStartARecoveryLoop() async throws {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView()

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)

        coordinator.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        )
        try await Task.sleep(for: .milliseconds(400))

        #expect(webView.pageLoadCallCount == 0)
        #expect(displayReadyFlag(for: session))
    }

    @Test
    func cancelledCurrentNavigationRecoversWhenNoReplacementStarts() async throws {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView()

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)

        coordinator.webView(webView, didStartProvisionalNavigation: nil)
        coordinator.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        )
        let didScheduleRecovery = try await waitUntil {
            webView.pageLoadCallCount >= 1
        }

        #expect(didScheduleRecovery)
        #expect(webView.pageLoadCallCount == 1)
        #expect(!displayReadyFlag(for: session))
    }

    @Test
    func initialGenerationReloadsWhenReadyAndResizeNeverArrive() async throws {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView()

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)

        let didReload = try await waitUntil(timeout: .seconds(10)) {
            webView.refreshEvaluationCallCount >= 1 && webView.pageLoadCallCount >= 1
        }

        #expect(didReload)
        #expect(webView.refreshEvaluationCallCount == 1)
        #expect(webView.pageLoadCallCount == 1)
        #expect(!displayReadyFlag(for: session))
    }

    @Test
    func staleCoordinatorCannotUnbindReplacementDisplaySink() {
        let session = VisiDataSessionController()
        let staleSink = TerminalDisplaySinkSpy()
        let replacementSink = TerminalDisplaySinkSpy()

        session.bind(displaySink: staleSink)
        session.appendOutputForTesting(Data("FIRST".utf8))
        session.markDisplayReady()
        session.bind(displaySink: replacementSink)
        session.unbind(displaySink: staleSink)
        session.appendOutputForTesting(Data("LATEST".utf8))
        session.markDisplayReady()

        #expect(staleSink.writeCallCount == 1)
        #expect(replacementSink.clearCallCount == 1)
        #expect(replacementSink.writeCallCount == 2)
    }

    @Test
    func staleCoordinatorMessagesCannotReadyReplacementDisplay() {
        let session = VisiDataSessionController()
        let staleCoordinator = EmbeddedTerminalView.Coordinator(session: session)
        let replacementCoordinator = EmbeddedTerminalView.Coordinator(session: session)
        let staleWebView = WKWebView(frame: .zero)
        let replacementWebView = WKWebView(frame: .zero)

        staleCoordinator.bind(session: session, webView: staleWebView)
        staleCoordinator.webView(staleWebView, didFinish: nil)
        staleCoordinator.handleTerminalReady(displayGeneration: 0)
        staleCoordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        #expect(displayReadyFlag(for: session))

        replacementCoordinator.bind(session: session, webView: replacementWebView)
        #expect(!displayReadyFlag(for: session))

        staleCoordinator.handleTerminalReady(displayGeneration: 0)
        staleCoordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        #expect(!displayReadyFlag(for: session))

        replacementCoordinator.webView(replacementWebView, didFinish: nil)
        replacementCoordinator.handleTerminalReady(displayGeneration: 0)
        replacementCoordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        #expect(displayReadyFlag(for: session))
    }

    @Test
    func staleCoordinatorRecoveryCannotFailTheReplacementDisplay() async throws {
        let session = VisiDataSessionController()
        let staleCoordinator = EmbeddedTerminalView.Coordinator(session: session)
        let replacementCoordinator = EmbeddedTerminalView.Coordinator(session: session)
        let staleWebView = ScriptedTerminalWebView()
        let replacementWebView = ScriptedTerminalWebView()

        staleCoordinator.bind(session: session, webView: staleWebView)
        staleCoordinator.webView(staleWebView, didFinish: nil)
        staleCoordinator.handleTerminalReady(displayGeneration: 0)
        staleCoordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)

        replacementCoordinator.bind(session: session, webView: replacementWebView)
        replacementCoordinator.webView(replacementWebView, didFinish: nil)
        replacementCoordinator.handleTerminalReady(displayGeneration: 0)
        replacementCoordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        #expect(displayReadyFlag(for: session))

        staleCoordinator.webViewWebContentProcessDidTerminate(staleWebView)
        staleCoordinator.webView(
            staleWebView,
            didFailProvisionalNavigation: nil,
            withError: SimulatedTerminalJavaScriptError()
        )
        try await Task.sleep(for: .milliseconds(400))

        #expect(staleWebView.pageLoadCallCount == 0)
        #expect(session.errorMessage == nil)
        #expect(displayReadyFlag(for: session))
    }

    @Test
    func queuedStaleRecoveryCannotRunAfterReplacementDisplayBinds() async throws {
        let session = VisiDataSessionController()
        let staleCoordinator = EmbeddedTerminalView.Coordinator(session: session)
        let replacementCoordinator = EmbeddedTerminalView.Coordinator(session: session)
        let staleWebView = ScriptedTerminalWebView()
        let replacementWebView = ScriptedTerminalWebView()

        staleCoordinator.bind(session: session, webView: staleWebView)
        staleCoordinator.webView(staleWebView, didFinish: nil)
        staleCoordinator.handleTerminalReady(displayGeneration: 0)
        staleCoordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        staleCoordinator.webView(
            staleWebView,
            didFailProvisionalNavigation: nil,
            withError: SimulatedTerminalJavaScriptError()
        )

        replacementCoordinator.bind(session: session, webView: replacementWebView)
        replacementCoordinator.webView(replacementWebView, didFinish: nil)
        replacementCoordinator.handleTerminalReady(displayGeneration: 0)
        replacementCoordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)

        try await Task.sleep(for: .milliseconds(400))

        #expect(staleWebView.pageLoadCallCount == 0)
        #expect(session.errorMessage == nil)
        #expect(displayReadyFlag(for: session))
    }

    @Test
    func pendingResetResumesWhenTheCoordinatorRebindsToANewSession() {
        let firstSession = VisiDataSessionController()
        let secondSession = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: firstSession)
        let webView = ScriptedTerminalWebView(resetOutcomes: [.noCompletion, .success])

        coordinator.bind(session: firstSession, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        coordinator.resetTerminalDisplay()
        #expect(!displayReadyFlag(for: firstSession))

        coordinator.bind(session: secondSession, webView: webView)
        coordinator.handleTerminalReady(displayGeneration: 2)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 2)

        #expect(webView.resetEvaluationCallCount == 2)
        #expect(!displayReadyFlag(for: firstSession))
        #expect(displayReadyFlag(for: secondSession))
    }

    @Test
    func navigationReloadRequiresFreshGenerationBeforeReplay() {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView()

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        #expect(displayReadyFlag(for: session))

        coordinator.webView(webView, didStartProvisionalNavigation: nil)
        #expect(!displayReadyFlag(for: session))

        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        #expect(!displayReadyFlag(for: session))

        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 1)
        coordinator.handleTerminalReady(displayGeneration: 1)
        #expect(displayReadyFlag(for: session))
    }

    @Test
    func webContentTerminationReloadsAndRequiresFreshGeneration() async throws {
        let session = VisiDataSessionController()
        let coordinator = EmbeddedTerminalView.Coordinator(session: session)
        let webView = ScriptedTerminalWebView()

        coordinator.bind(session: session, webView: webView)
        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalReady(displayGeneration: 0)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 0)
        #expect(displayReadyFlag(for: session))

        coordinator.webViewWebContentProcessDidTerminate(webView)
        #expect(!displayReadyFlag(for: session))

        let didReload = try await waitUntil {
            webView.pageLoadCallCount >= 1
        }

        #expect(didReload)
        #expect(webView.pageLoadCallCount == 1)

        coordinator.webView(webView, didFinish: nil)
        coordinator.handleTerminalResize(cols: 120, rows: 32, displayGeneration: 1)
        coordinator.handleTerminalReady(displayGeneration: 1)
        #expect(displayReadyFlag(for: session))
    }

    @Test
    func terminalHTMLUsesDedicatedMountElementForXterm() throws {
        let html = try terminalHTML()

        #expect(html.contains("id=\"terminal-mount\""))
        #expect(html.contains("const terminalMount = document.getElementById('terminal-mount');"))
        #expect(html.contains("term.open(terminalMount);"))
    }

    @Test
    func terminalHTMLOuterCornersMatchSwiftUIContainer() throws {
        let html = try terminalHTML()

        #expect(html.components(separatedBy: "border-radius: 10px;").count - 1 == 2)
        #expect(!html.contains("border-radius: 24px;"))
    }

    @Test
    func terminalHTMLDisablesBrowserScrollbackForVisiData() throws {
        let html = try terminalHTML()

        #expect(html.contains("scrollback: 0,"))
        #expect(html.contains("scrollbar: {\n          showScrollbar: false\n        },"))
    }

    @Test
    func terminalHTMLForcesResizeWhenFocusReenters() throws {
        let html = try terminalHTML()

        #expect(html.contains("window.iDataFocusTerminal = function(displayGeneration = activeDisplayGeneration)"))
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
    func embeddedTerminalViewSkipsRedundantSwiftUIRebinding() throws {
        let source = try embeddedTerminalViewSource()

        #expect(source.contains("let webViewDidChange = self.webView !== webView"))
        #expect(source.contains("guard sessionDidChange || webViewDidChange else"))
        #expect(!source.contains("Logger("))
    }

    @Test
    func embeddedTerminalViewLeavesCornerMaskingToSwiftUIContainer() throws {
        let source = try embeddedTerminalViewSource()

        #expect(source.contains("webView.layer?.cornerRadius = 0"))
        #expect(source.contains("webView.layer?.masksToBounds = false"))
        #expect(!source.contains("webView.layer?.cornerRadius = 24"))
        #expect(!source.contains("webView.layer?.masksToBounds = true"))
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
        #expect(html.contains("window.iDataRefreshLayout = function(displayGeneration = activeDisplayGeneration) {"))
        #expect(html.contains("lastSentSize = null;"))
    }

    @Test
    func terminalHTMLPostsDebugMessagesOnlyWhenTraceIsEnabled() async throws {
        let harness = try TerminalHTMLHarness()
        try await harness.load()
        try await harness.clearMessages()

        _ = try await harness.evaluate("window.iDataRefreshLayout();")
        try await Task.sleep(for: .milliseconds(100))
        #expect(!(try await harness.messages()).contains { $0.type == "debug" })

        try await harness.clearMessages()
        _ = try await harness.evaluate("window.iDataDebugEnabled = true; window.iDataRefreshLayout();")
        try await Task.sleep(for: .milliseconds(100))
        #expect((try await harness.messages()).contains { $0.type == "debug" })
    }

    @Test
    func terminalHTMLAvoidsDebugOnlyWorkOnHotInteractionPaths() throws {
        let html = try terminalHTML()

        #expect(!html.contains("addEventListener('wheel'"))
        #expect(html.contains("if (window.iDataDebugEnabled === true)"))
    }

    @Test
    func embeddedTerminalInjectsTraceFlagAtDocumentStart() {
        #expect(
            EmbeddedTerminalView.terminalDebugConfigurationJavaScript(isEnabled: true)
                == "window.iDataDebugEnabled = true;"
        )
        #expect(
            EmbeddedTerminalView.terminalDebugConfigurationJavaScript(isEnabled: false)
                == "window.iDataDebugEnabled = false;"
        )
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
    func terminalHTMLRepostsResizeWhenCellMetricsSettleAfterInitialMeasurement() async throws {
        let harness = try TerminalHTMLHarness(initialCellWidth: 8, initialCellHeight: 20)
        try await harness.load()
        try await Task.sleep(for: .milliseconds(300))

        let initialMessages = try await harness.messages()
        let initialResize = try #require(initialMessages.last { $0.type == "resize" })
        #expect(initialResize.rows == 32)

        try await harness.clearMessages()
        try await harness.setCellMetrics(width: 8, height: 18)
        try await Task.sleep(for: .milliseconds(1200))

        let settledMessages = try await harness.messages()
        let settledResize = settledMessages.last { $0.type == "resize" }
        #expect(settledResize?.rows == 35)
    }

    @Test
    func terminalHTMLDoesNotRestartMetricPollingAfterInitialMeasurement() async throws {
        let harness = try TerminalHTMLHarness()
        try await harness.load()
        try await Task.sleep(for: .milliseconds(100))

        _ = try await harness.evaluate("stopMetricSettlingChecks();")
        #expect(try await harness.evaluate("String(metricSettleBudgetRemaining);") == "0")

        _ = try await harness.evaluate("window.iDataRefreshLayout();")
        try await Task.sleep(for: .milliseconds(50))

        #expect(try await harness.evaluate("String(metricSettleBudgetRemaining);") == "0")
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
        #expect(resizeMessages.first?.force == true)
    }

    @Test
    func terminalHTMLRejectsStaleResetWriteAndClearGenerations() async throws {
        let harness = try TerminalHTMLHarness()
        try await harness.load()
        try await Task.sleep(for: .milliseconds(100))

        let result = try await harness.evaluate(
            """
            window.iDataClearTerminal(1);
            window.iDataWriteBase64(btoa('OLD'), 1);
            window.iDataClearTerminal(2);
            window.iDataWriteBase64(btoa('LATEST'), 2);
            window.iDataWriteBase64(btoa('STALE'), 1);
            window.iDataSoftClearTerminal(1);
            window.iDataClearTerminal(1);
            JSON.stringify({
              generation: activeDisplayGeneration,
              bytes: term.__writtenBytes,
              terminalCount: window.__terminalHarness.terminalCount
            });
            """
        )

        #expect(result == "{\"generation\":2,\"bytes\":[76,65,84,69,83,84],\"terminalCount\":3}")
    }

    @Test
    func terminalHTMLRefreshesTheCanvasOnlyAfterTheFirstWritePerTerminal() async throws {
        let harness = try TerminalHTMLHarness()
        try await harness.load()

        _ = try await harness.evaluate(
            """
            window.iDataWriteBase64(btoa('FIRST'), 0);
            window.iDataWriteBase64(btoa('SECOND'), 0);
            """
        )
        try await Task.sleep(for: .milliseconds(300))
        let firstTerminalResult = try await harness.evaluate("String(term.__refreshCount);")
        #expect(firstTerminalResult == "1")

        _ = try await harness.evaluate(
            """
            window.iDataClearTerminal(1);
            window.iDataWriteBase64(btoa('THIRD'), 1);
            window.iDataWriteBase64(btoa('FOURTH'), 1);
            """
        )
        try await Task.sleep(for: .milliseconds(300))
        let replacementTerminalResult = try await harness.evaluate(
            """
            JSON.stringify({
              refreshCount: term.__refreshCount,
              terminalCount: window.__terminalHarness.terminalCount
            });
            """
        )
        #expect(replacementTerminalResult == "{\"refreshCount\":1,\"terminalCount\":2}")
    }

    @Test
    func staleInitialPaintTimerCannotRefreshAReplacementTerminal() async throws {
        let harness = try TerminalHTMLHarness()
        try await harness.load()

        _ = try await harness.evaluate(
            """
            window.iDataWriteBase64(btoa('OLD'), 0);
            window.iDataClearTerminal(1);
            window.iDataWriteBase64(btoa('LATEST'), 1);
            """
        )
        try await Task.sleep(for: .milliseconds(300))

        let result = try await harness.evaluate(
            """
            JSON.stringify({
              staleRefreshCount: window.__terminalHarness.terminals[0].__refreshCount,
              currentRefreshCount: window.__terminalHarness.terminals[1].__refreshCount,
              currentBytes: term.__writtenBytes
            });
            """
        )

        #expect(result == "{\"staleRefreshCount\":0,\"currentRefreshCount\":1,\"currentBytes\":[76,65,84,69,83,84]}")
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
        #expect(html.contains("window.iDataSoftClearTerminal = function(displayGeneration = activeDisplayGeneration)"))
        #expect(html.contains("term?.clear();"))
    }

    @Test
    func terminalHTMLRecreatesTerminalInstanceWhenClearingDisplay() throws {
        let html = try terminalHTML()

        #expect(html.contains("function createTerminal("))
        #expect(html.contains("term.dispose();"))
        #expect(html.contains("createTerminal(true);"))
    }

    @Test
    func terminalHTMLUsesProperLineHeightToAvoidLayoutGaps() throws {
        let html = try terminalHTML()

        #expect(!html.contains("customGlyphs: false,"))
        #expect(html.contains("lineHeight: 1.22,"))
    }

    @Test
    func terminalHTMLUsesOneInitialPaintRefreshInsteadOfHotPathRefreshes() throws {
        let html = try terminalHTML()

        #expect(html.contains("let initialPaintRefreshScheduled = false;"))
        #expect(html.contains("if (!initialPaintRefreshScheduled) {"))
        #expect(html.contains("initialPaintRefreshScheduled = true;"))
        #expect(html.components(separatedBy: "currentTerm.refresh(0, Math.max(currentTerm.rows - 1, 0));").count - 1 == 1)
        #expect(!html.contains("term.refresh(0, Math.max(term.rows - 1, 0));"))
    }

    @Test
    func terminalHTMLDoesNotSendForcedResizeWhenSizeUnchanged() throws {
        let html = try terminalHTML()

        #expect(!html.contains("if (force || sizeChanged) {"))
        #expect(html.contains("if (sizeChanged || terminalNeedsResize) {"))
    }

    @Test(arguments: [
        Data(),
        Data((0...UInt8.max).map { $0 }),
        Data([0x00, 0x22, 0x27, 0x5c, 0x7f, 0xff])
    ])
    func terminalWriteJavaScriptPreservesEveryInputByte(_ expected: Data) throws {
        let context = try #require(JSContext())
        context.evaluateScript(
            """
            var capturedPayload = null;
            var window = {
                iDataWriteBase64: function(payload) {
                    capturedPayload = payload;
                }
            };
            """
        )

        let functionCall = EmbeddedTerminalView.Coordinator.terminalWriteJavaScript(for: expected)
        context.evaluateScript(functionCall)

        let payload = try #require(context.objectForKeyedSubscript("capturedPayload")?.toString())
        let decoded = try #require(Data(base64Encoded: payload))
        #expect(decoded == expected)
    }

    @Test
    func terminalWriteHotPathAvoidsJSONSerialization() throws {
        let source = try embeddedTerminalViewSource()

        #expect(!source.contains("JSONSerialization"))
        #expect(!source.contains("quotedJavaScriptString"))
    }

    private func displayReadyFlag(for session: VisiDataSessionController) -> Bool {
        Mirror(reflecting: session)
            .children
            .first { $0.label == "isDisplayReady" }?
            .value as? Bool ?? false
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(20),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return true
            }
            try await Task.sleep(for: pollInterval)
        }

        return condition()
    }
}

@MainActor
private final class TerminalDisplaySinkSpy: TerminalDisplaySink {
    private(set) var clearCallCount = 0
    private(set) var resetCallCount = 0
    private(set) var writeCallCount = 0
    private(set) var focusCallCount = 0

    func clearTerminalDisplay() {
        clearCallCount += 1
    }

    func resetTerminalDisplay() {
        resetCallCount += 1
    }

    func writeToTerminalDisplay(_ data: Data) {
        writeCallCount += 1
    }

    func focusTerminalDisplay() {
        focusCallCount += 1
    }
}

@MainActor
private final class ScriptedTerminalWebView: WKWebView {
    enum ResetOutcome {
        case success
        case failure
        case noCompletion
    }

    private var resetOutcomes: [ResetOutcome]
    private(set) var resetEvaluationCallCount = 0
    private(set) var refreshEvaluationCallCount = 0
    private(set) var pageLoadCallCount = 0

    init(resetOutcomes: [ResetOutcome] = []) {
        self.resetOutcomes = resetOutcomes
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: (@MainActor @Sendable (Any?, (any Error)?) -> Void)? = nil
    ) {
        guard javaScriptString.contains("iDataClearTerminal") else {
            if javaScriptString.contains("iDataRefreshLayout") {
                refreshEvaluationCallCount += 1
            }
            completionHandler?(true, nil)
            return
        }

        resetEvaluationCallCount += 1
        let outcome = resetOutcomes.isEmpty ? .success : resetOutcomes.removeFirst()
        switch outcome {
        case .success:
            completionHandler?(true, nil)
        case .failure:
            completionHandler?(nil, SimulatedTerminalJavaScriptError())
        case .noCompletion:
            break
        }
    }

    override func loadFileURL(_ URL: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation? {
        pageLoadCallCount += 1
        return nil
    }

    override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        pageLoadCallCount += 1
        return nil
    }
}

private struct SimulatedTerminalJavaScriptError: LocalizedError {
    var errorDescription: String? {
        "Simulated JavaScript failure"
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
    let force: Bool?
    let displayGeneration: Int?
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
            observers: [],
            terminalCount: 0,
            terminals: []
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
              window.__terminalHarness.terminalCount += 1;
              window.__terminalHarness.terminals.push(this);
              this.options = {
                ...options,
                scrollbar: { showScrollbar: true, width: 14 }
              };
              this.cols = 0;
              this.rows = 0;
              this.__writtenBytes = [];
              this.__refreshCount = 0;
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
            clear() {
              this.__writtenBytes = [];
            }
            dispose() {}
            resize(cols, rows) {
              this.cols = cols;
              this.rows = rows;
            }
            write(bytes, callback) {
              this.__writtenBytes.push(...bytes);
              callback?.();
            }
            refresh() {
              this.__refreshCount += 1;
            }
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
