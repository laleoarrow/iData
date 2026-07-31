import Darwin
import Foundation
import Testing
@testable import iData

@Suite(.serialized)
@MainActor
struct VisiDataSessionControllerTests {
    @Test
    func processExitMonitoringUsesOneKernelWaitWithoutPolling() throws {
        let source = try visiDataSessionControllerSource()

        #expect(source.contains("private let processWaitQueue"))
        #expect(source.contains("private func waitForProcessExit"))
        #expect(!source.contains("DispatchSourceProcess"))
        #expect(!source.contains("makeProcessSource"))
        #expect(!source.contains("scheduleEarlyExitSafetyCheck"))
    }

    @Test
    func delayedLaunchFailuresArePublishedAndStaleFallbacksCannotLaunchNewRequests() throws {
        let source = try visiDataSessionControllerSource()

        #expect(!source.contains("try? self.launchPendingOpenIfPossible()"))
        #expect(!source.contains("try? launchPendingOpenIfPossible()"))
        #expect(source.contains("launchPendingOpenReportingFailure()"))
        #expect(source.contains("pendingOpenRequest?.generation == scheduledGeneration"))
        #expect(source.contains("errorMessage = error.localizedDescription"))
    }

    @Test
    func fallbackLaunchFailurePublishesErrorAndStopsPendingSession() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-session-fallback-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let inputFile = tempRoot.appendingPathComponent("input.tsv")
        try "id\tvalue\n1\t2\n".write(to: inputFile, atomically: true, encoding: .utf8)

        let launcher = tempRoot.appendingPathComponent("fake-vd-failure.zsh")
        try makeSleepLauncher(at: launcher, sleepSeconds: 120)

        let session = VisiDataSessionController(
            launchAttemptValidator: {
                throw NSError(
                    domain: "io.github.leoarrow.idata.tests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "forced launch failure"]
                )
            },
            displayMeasurementFallbackDelay: .milliseconds(10)
        )
        try session.open(fileURL: inputFile, explicitVDPath: launcher.path)
        defer {
            session.terminate()
        }

        try await waitForCondition(timeout: 1.0) {
            !session.isRunning && session.errorMessage == "forced launch failure"
        }

        try session.launchPendingOpenImmediatelyIfNeeded()
        #expect(session.statusMessage == nil)
        #expect(session.processIdentifierForTesting == 0)
    }

    @Test
    func staleFallbackCannotLaunchAReplacementRequest() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-session-stale-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let firstFile = tempRoot.appendingPathComponent("first.tsv")
        let secondFile = tempRoot.appendingPathComponent("second.tsv")
        try "id\tvalue\n1\tA\n".write(to: firstFile, atomically: true, encoding: .utf8)
        try "id\tvalue\n1\tB\n".write(to: secondFile, atomically: true, encoding: .utf8)

        let launcher = tempRoot.appendingPathComponent("fake-vd-stale-fallback.zsh")
        try makeSleepLauncher(at: launcher, sleepSeconds: 120)

        let firstFallbackIsWaitingForMainActor = DispatchSemaphore(value: 0)
        let fallbackEvaluationObserver = GenerationObserver()
        let launchObserver = LaunchObserver()
        let session = VisiDataSessionController(
            launchObserver: launchObserver.record(cols:rows:),
            fallbackReadyObserver: { _ in
                firstFallbackIsWaitingForMainActor.signal()
            },
            fallbackEvaluationObserver: fallbackEvaluationObserver.record,
            displayMeasurementFallbackDelay: .milliseconds(500)
        )
        defer {
            session.terminate()
        }

        try session.open(fileURL: firstFile, explicitVDPath: launcher.path)
        let firstGeneration = session.outputGenerationForTesting
        #expect(waitSynchronously(for: firstFallbackIsWaitingForMainActor, timeout: 2.0))

        try session.open(fileURL: secondFile, explicitVDPath: launcher.path)
        try await waitForCondition(timeout: 1.0) {
            fallbackEvaluationObserver.contains(firstGeneration)
        }

        #expect(launchObserver.isEmpty())
        #expect(session.processIdentifierForTesting == 0)

        try session.launchPendingOpenImmediatelyIfNeeded()
        let launchedSize = try #require(launchObserver.firstRecord())

        #expect(launchedSize.0 == 120)
        #expect(launchedSize.1 == 32)
        #expect(session.processIdentifierForTesting > 0)
        #expect(session.currentFileURL?.standardizedFileURL == secondFile.standardizedFileURL)
    }

    @Test
    func terminateAlsoStopsDescendantProcesses() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let inputFile = tempRoot.appendingPathComponent("input.tsv")
        try "id\tvalue\n1\t2\n".write(to: inputFile, atomically: true, encoding: .utf8)

        let childPIDFile = tempRoot.appendingPathComponent("child.pid")
        let launcher = tempRoot.appendingPathComponent("fake-vd.py")
        try makeFakeVDLauncher(at: launcher, childPIDFile: childPIDFile)

        let session = VisiDataSessionController()
        try session.open(fileURL: inputFile, explicitVDPath: launcher.path)

        let childPID = try await waitForChildPID(in: childPIDFile, timeout: 8.0)
        #expect(processExists(childPID))

        session.terminate()

        let childExited = await waitForProcessExit(childPID, timeout: 5.0)
        #expect(childExited)
        if !childExited {
            _ = kill(childPID, SIGKILL)
        }
    }

    @Test
    func rapidShortLivedProcessesAlwaysPublishTheirExit() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-session-short-exit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let inputFile = tempRoot.appendingPathComponent("input.tsv")
        try "id\tvalue\n1\t2\n".write(to: inputFile, atomically: true, encoding: .utf8)

        let launcher = tempRoot.appendingPathComponent("fake-vd-short-exit.zsh")
        try makeDelayedExitLauncher(at: launcher, delaySeconds: 0.01, exitCode: 7)

        for _ in 0..<32 {
            let session = VisiDataSessionController()
            session.resize(cols: 120, rows: 32)
            try session.open(fileURL: inputFile, explicitVDPath: launcher.path)

            try await waitForCondition(timeout: 8.0) {
                !session.isRunning
            }

            #expect(session.statusMessage?.contains("7") == true)
            #expect(session.errorMessage?.contains("7") == true)
        }
    }

    @Test
    func staleOutputFromPreviousSessionGenerationIsIgnoredAfterTableSwitch() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-session-generation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let firstFile = tempRoot.appendingPathComponent("first.tsv")
        let secondFile = tempRoot.appendingPathComponent("second.tsv")
        try "id\tvalue\n1\tA\n".write(to: firstFile, atomically: true, encoding: .utf8)
        try "id\tvalue\n1\tB\n".write(to: secondFile, atomically: true, encoding: .utf8)

        let launcher = tempRoot.appendingPathComponent("fake-vd-sleep.zsh")
        try makeSleepLauncher(at: launcher, sleepSeconds: 120)

        let sink = TerminalDisplaySinkBuffer()
        let session = VisiDataSessionController()
        session.bind(displaySink: sink)
        session.markDisplayReady()
        defer {
            session.terminate()
        }

        try session.open(fileURL: firstFile, explicitVDPath: launcher.path)
        let firstGeneration = session.outputGenerationForTesting

        try session.open(fileURL: secondFile, explicitVDPath: launcher.path)
        let secondGeneration = session.outputGenerationForTesting

        sink.reset()
        session.appendOutputForTesting(Data("OLD".utf8), generation: firstGeneration)
        session.appendOutputForTesting(Data("NEW".utf8), generation: secondGeneration)

        #expect(sink.writes == ["NEW"])
    }

    @Test
    func unboundSessionCannotWriteLateOutputIntoSharedTerminalSink() {
        let sink = TerminalDisplaySinkBuffer()
        let session = VisiDataSessionController()

        session.bind(displaySink: sink)
        session.markDisplayReady()
        session.appendOutputForTesting(Data("FIRST".utf8))
        #expect(sink.writes == ["FIRST"])

        session.bind(displaySink: nil)
        session.appendOutputForTesting(Data("LATE".utf8))

        #expect(sink.writes == ["FIRST"])
    }

    @Test
    func sameSizeResizeDoesNotSpamSIGWINCHDuringLargeTableRefresh() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-session-resize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let inputFile = tempRoot.appendingPathComponent("input.tsv")
        try "id\tvalue\n1\t2\n".write(to: inputFile, atomically: true, encoding: .utf8)

        let launcher = tempRoot.appendingPathComponent("fake-vd-resize.zsh")
        try makeSleepLauncher(at: launcher, sleepSeconds: 120)

        let signalSpy = SignalSenderSpy()
        let sink = TerminalDisplaySinkBuffer()
        let session = VisiDataSessionController(signalSender: signalSpy.send)
        session.bind(displaySink: sink)
        try session.open(fileURL: inputFile, explicitVDPath: launcher.path)
        session.resize(cols: 120, rows: 32)
        session.markDisplayReady()
        defer {
            session.terminate()
        }

        session.resize(cols: 120, rows: 32)
        session.resize(cols: 120, rows: 32)
        session.resize(cols: 120, rows: 32)

        #expect(signalSpy.signalCount == 0)

        session.resize(cols: 140, rows: 40)
        #expect(signalSpy.signalCount == 1)
    }

    @Test
    func openUsesMeasuredDisplaySizeWhenFirstResizeArrivesBeforeFallback() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-session-launch-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let inputFile = tempRoot.appendingPathComponent("input.tsv")
        try "id\tvalue\n1\t2\n".write(to: inputFile, atomically: true, encoding: .utf8)

        let observer = LaunchObserver()
        let launcher = tempRoot.appendingPathComponent("fake-vd-size.zsh")
        try makeSleepLauncher(at: launcher, sleepSeconds: 5)

        let sink = TerminalDisplaySinkBuffer()
        let session = VisiDataSessionController(launchObserver: observer.record(cols:rows:))
        session.bind(displaySink: sink)
        try session.open(fileURL: inputFile, explicitVDPath: launcher.path)
        #expect(observer.isEmpty())
        #expect(sink.resetCount == 1)
        session.resize(cols: 195, rows: 41)
        session.markDisplayReady()
        defer {
            session.terminate()
        }

        let launchedSize = try await waitForLaunchRecord(observer, timeout: 1.0)
        #expect(launchedSize == (195, 41))
    }

    @Test
    func openUsesDefaultSizeAfterFallbackDelayWhenNoDisplayIsBound() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-session-launch-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let inputFile = tempRoot.appendingPathComponent("input.tsv")
        try "id\tvalue\n1\t2\n".write(to: inputFile, atomically: true, encoding: .utf8)

        let observer = LaunchObserver()
        let launcher = tempRoot.appendingPathComponent("fake-vd-size-fallback.zsh")
        try makeSleepLauncher(at: launcher, sleepSeconds: 5)

        let session = VisiDataSessionController(
            launchObserver: observer.record(cols:rows:),
            displayMeasurementFallbackDelay: .milliseconds(20)
        )
        try session.open(fileURL: inputFile, explicitVDPath: launcher.path)
        #expect(observer.isEmpty())
        defer {
            session.terminate()
        }

        let launchedSize = try await waitForLaunchRecord(observer, timeout: 5.0)
        #expect(launchedSize == (120, 32))
    }

    @Test
    func firstMeasuredResizeAfterFallbackLaunchDiscardsStaleTranscript() {
        let sink = TerminalDisplaySinkBuffer()
        let signalSpy = SignalSenderSpy()
        let session = VisiDataSessionController(signalSender: signalSpy.send)
        session.bind(displaySink: sink)
        session.simulateFallbackLaunchBeforeMeasurementForTesting(fileDescriptor: open("/dev/null", O_RDONLY))

        // Simulate stale output painted for the wrong default size.
        session.appendOutputForTesting(Data("STALE\n".utf8))

        #expect(sink.resetCount == 0)

        session.resize(cols: 180, rows: 40)

        // Terminal surface is NOT rebuilt (avoids dropping full-screen paint),
        // but the stale transcript is discarded.
        #expect(sink.resetCount == 0)
        #expect(signalSpy.signalCount == 1)

        // markDisplayReady replays the transcript — it should be empty now.
        session.markDisplayReady()
        #expect(sink.writes.isEmpty)

        session.resize(cols: 180, rows: 40)

        #expect(sink.resetCount == 0)
    }

    @Test
    func sameSizeFirstMeasuredResizeAfterFallbackStillForcesRedraw() async throws {
        let sink = TerminalDisplaySinkBuffer()
        let recorder = PTYWriteRecorder()
        let driver = PTYWriteDriver(
            writeCall: recorder.write(fileDescriptor:buffer:count:),
            sleepCall: { _ in }
        )
        let session = VisiDataSessionController(ptyWriteDriver: driver)
        session.bind(displaySink: sink)

        // Establish a previously measured size, matching a normal in-place
        // switch where the next xterm measurement reports the same geometry.
        session.resize(cols: 180, rows: 40)
        session.simulateFallbackLaunchBeforeMeasurementForTesting(fileDescriptor: open("/dev/null", O_RDONLY))
        defer {
            session.terminate()
        }

        session.appendOutputForTesting(Data("STALE\n".utf8))
        session.resize(cols: 180, rows: 40)

        session.markDisplayReady()
        session.resize(cols: 180, rows: 40, force: true)

        try await waitForCondition(timeout: 2.0) {
            recorder.recordedData.contains(Data("\u{0C}".utf8))
        }

        #expect(sink.writes.isEmpty)
    }

    @Test
    func fallbackRedrawRunsAfterMeasuredResizeSignal() async throws {
        let eventRecorder = TerminalResizeEventRecorder()
        let driver = PTYWriteDriver(
            writeCall: eventRecorder.write(fileDescriptor:buffer:count:),
            sleepCall: { _ in }
        )
        let session = VisiDataSessionController(
            ptyWriteDriver: driver,
            signalSender: eventRecorder.send(pid:signal:)
        )
        session.bind(displaySink: TerminalDisplaySinkBuffer())
        session.simulateFallbackLaunchBeforeMeasurementForTesting(fileDescriptor: open("/dev/null", O_RDONLY))
        defer {
            session.terminate()
        }

        session.resize(cols: 180, rows: 40)

        #expect(eventRecorder.events == [
            .signal(SIGWINCH)
        ])

        session.markDisplayReady()
        session.resize(cols: 180, rows: 40, force: true)

        try await waitForCondition(timeout: 2.0) {
            eventRecorder.events.contains(.write(Data("\u{0C}".utf8)))
        }

        #expect(eventRecorder.events == [
            .signal(SIGWINCH),
            .signal(SIGWINCH),
            .write(Data("\u{0C}".utf8))
        ])
    }

    @Test
    func firstMeasuredResizeAfterSessionBindsPostLaunchDiscardsStaleOutput() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-session-post-bind-resize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let inputFile = tempRoot.appendingPathComponent("input.tsv")
        try "id\tvalue\n1\t2\n".write(to: inputFile, atomically: true, encoding: .utf8)

        let launcher = tempRoot.appendingPathComponent("fake-vd-post-bind.zsh")
        try makeSleepLauncher(at: launcher, sleepSeconds: 120)

        let sink = TerminalDisplaySinkBuffer()
        let session = VisiDataSessionController()
        try session.open(fileURL: inputFile, explicitVDPath: launcher.path)
        defer {
            session.terminate()
        }

        session.bind(displaySink: sink)

        #expect(sink.resetCount == 0)

        session.resize(cols: 180, rows: 40)

        // No xterm rebuild, but transcript cleared.
        #expect(sink.resetCount == 0)

        session.markDisplayReady()
        #expect(sink.writes.isEmpty)
    }

    @Test
    func invalidatingDisplayReadinessBuffersOutputUntilFreshReplay() {
        let session = VisiDataSessionController()
        let sink = TerminalDisplaySinkBuffer()

        session.bind(displaySink: sink)
        session.appendOutputForTesting(Data("FIRST\n".utf8))
        session.markDisplayReady()
        #expect(sink.writes == ["FIRST\n"])

        session.invalidateDisplayReadinessForTerminalReset()
        session.appendOutputForTesting(Data("SECOND\n".utf8))

        #expect(sink.writes == ["FIRST\n"])

        session.markDisplayReady()

        #expect(sink.writes == ["FIRST\n", "SECOND\n"])
    }

    @Test
    func drainingOutputCoalescesBytesIntoOrderedBoundedDrains() async throws {
        let byteCount = (64 * 1024) + 17
        let expected = Data((0..<byteCount).map { UInt8(truncatingIfNeeded: $0) })
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-output-drain-\(UUID().uuidString)")
        try expected.write(to: temporaryURL)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let fileDescriptor = open(temporaryURL.path, O_RDONLY)
        #expect(fileDescriptor >= 0)
        defer {
            if fileDescriptor >= 0 {
                close(fileDescriptor)
            }
        }

        let session = VisiDataSessionController()
        let sink = TerminalDisplaySinkBuffer()
        session.bind(displaySink: sink)
        session.markDisplayReady()

        session.drainOutputForTesting(
            from: fileDescriptor,
            generation: session.outputGenerationForTesting
        )
        #expect(lseek(fileDescriptor, 0, SEEK_CUR) == 64 * 1024)

        session.drainOutputForTesting(
            from: fileDescriptor,
            generation: session.outputGenerationForTesting
        )
        #expect(lseek(fileDescriptor, 0, SEEK_CUR) == byteCount)
        try await waitForSinkWrites(sink, count: 2)

        #expect(sink.dataWrites.map(\.count) == [64 * 1024, 17])
        #expect(sink.dataWrites.reduce(into: Data()) { $0.append($1) } == expected)
    }

    @Test
    func drainingOutputDeliversSmallNonblockingReadImmediatelyAtEAGAIN() async throws {
        var descriptors: [Int32] = [-1, -1]
        #expect(pipe(&descriptors) == 0)
        let readDescriptor = descriptors[0]
        let writeDescriptor = descriptors[1]
        defer {
            if readDescriptor >= 0 {
                close(readDescriptor)
            }
            if writeDescriptor >= 0 {
                close(writeDescriptor)
            }
        }

        let currentFlags = fcntl(readDescriptor, F_GETFL)
        #expect(currentFlags >= 0)
        #expect(fcntl(readDescriptor, F_SETFL, currentFlags | O_NONBLOCK) == 0)

        let expected = Data([0x00, 0x7f, 0xff])
        let bytesWritten = expected.withUnsafeBytes { buffer in
            Darwin.write(writeDescriptor, buffer.baseAddress, buffer.count)
        }
        #expect(bytesWritten == expected.count)

        let session = VisiDataSessionController()
        let sink = TerminalDisplaySinkBuffer()
        session.bind(displaySink: sink)
        session.markDisplayReady()

        session.drainOutputForTesting(
            from: readDescriptor,
            generation: session.outputGenerationForTesting
        )
        try await waitForSinkWrites(sink, count: 1)

        #expect(sink.dataWrites == [expected])
    }

    @Test
    func currentGenerationOutputDoesNotWaitForAnOlderDeliveryTail() async throws {
        var descriptors: [Int32] = [-1, -1]
        #expect(pipe(&descriptors) == 0)
        let readDescriptor = descriptors[0]
        let writeDescriptor = descriptors[1]
        defer {
            if readDescriptor >= 0 {
                close(readDescriptor)
            }
            if writeDescriptor >= 0 {
                close(writeDescriptor)
            }
        }

        let currentFlags = fcntl(readDescriptor, F_GETFL)
        #expect(currentFlags >= 0)
        #expect(fcntl(readDescriptor, F_SETFL, currentFlags | O_NONBLOCK) == 0)

        let session = VisiDataSessionController()
        let sink = TerminalDisplaySinkBuffer()
        session.bind(displaySink: sink)
        session.markDisplayReady()

        let blockedOldDelivery = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(10))
        }
        defer {
            blockedOldDelivery.cancel()
        }
        session.installOutputDeliveryTailForTesting(
            blockedOldDelivery,
            generation: session.outputGenerationForTesting &+ 1
        )

        let expected = Data("NEW".utf8)
        let bytesWritten = expected.withUnsafeBytes { buffer in
            Darwin.write(writeDescriptor, buffer.baseAddress, buffer.count)
        }
        #expect(bytesWritten == expected.count)

        session.drainOutputForTesting(
            from: readDescriptor,
            generation: session.outputGenerationForTesting
        )
        try await waitForSinkWrites(sink, count: 1, timeout: .milliseconds(250))

        #expect(sink.dataWrites == [expected])
    }

    private func makeFakeVDLauncher(at url: URL, childPIDFile: URL) throws {
        let escapedPIDPath = childPIDFile.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        #!/bin/zsh
        trap 'exit 0' TERM INT HUP
        /bin/sleep 120 &
        child_pid=$!
        print -r -- "$child_pid" > "\(escapedPIDPath)"
        wait "$child_pid"
        """

        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeSleepLauncher(at url: URL, sleepSeconds: Int) throws {
        let script = """
        #!/bin/zsh
        trap 'exit 0' TERM INT HUP
        sleep \(sleepSeconds)
        """

        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeDelayedExitLauncher(at url: URL, delaySeconds: Double, exitCode: Int32) throws {
        let script = """
        #!/bin/zsh
        sleep \(delaySeconds)
        exit \(exitCode)
        """

        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

}

private enum TestError: Error {
    case missingChildPIDFile(String)
    case missingLaunchObservation
}

@MainActor
private final class TerminalDisplaySinkBuffer: TerminalDisplaySink {
    private(set) var writes: [String] = []
    private(set) var dataWrites: [Data] = []
    private(set) var clearCount = 0
    private(set) var resetCount = 0

    func clearTerminalDisplay() {
        clearCount += 1
        writes.removeAll()
        dataWrites.removeAll()
    }

    func resetTerminalDisplay() {
        resetCount += 1
        writes.removeAll()
        dataWrites.removeAll()
    }

    func writeToTerminalDisplay(_ data: Data) {
        dataWrites.append(data)
        writes.append(String(decoding: data, as: UTF8.self))
    }

    func focusTerminalDisplay() {}

    func reset() {
        writes.removeAll()
        dataWrites.removeAll()
        clearCount = 0
        resetCount = 0
    }
}

@MainActor
private final class SignalSenderSpy {
    private(set) var signals: [(pid: pid_t, signal: Int32)] = []

    var signalCount: Int {
        signals.count
    }

    func send(pid: pid_t, signal: Int32) -> Int32 {
        signals.append((pid: pid, signal: signal))
        return 0
    }
}

private final class LaunchObserver {
    private let lock = NSLock()
    private var records: [(Int, Int)] = []

    func record(cols: UInt16, rows: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        records.append((Int(cols), Int(rows)))
    }

    func firstRecord() -> (Int, Int)? {
        lock.lock()
        defer { lock.unlock() }
        return records.first
    }

    func isEmpty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return records.isEmpty
    }
}

private final class GenerationObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var generations: Set<UInt64> = []

    func record(_ generation: UInt64) {
        lock.lock()
        generations.insert(generation)
        lock.unlock()
    }

    func contains(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generations.contains(generation)
    }
}

private final class PTYWriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [Data] = []

    var recordedData: Data {
        lock.lock()
        defer { lock.unlock() }
        return chunks.reduce(into: Data()) { result, chunk in
            result.append(chunk)
        }
    }

    func write(fileDescriptor _: Int32, buffer: UnsafeRawPointer, count: Int) -> Int {
        let data = Data(bytes: buffer, count: count)
        lock.lock()
        chunks.append(data)
        lock.unlock()
        return count
    }
}

private enum TerminalResizeEvent: Equatable {
    case signal(Int32)
    case write(Data)
}

private final class TerminalResizeEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [TerminalResizeEvent] = []

    var events: [TerminalResizeEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    func send(pid _: pid_t, signal: Int32) -> Int32 {
        append(.signal(signal))
        return 0
    }

    func write(fileDescriptor _: Int32, buffer: UnsafeRawPointer, count: Int) -> Int {
        append(.write(Data(bytes: buffer, count: count)))
        return count
    }

    private func append(_ event: TerminalResizeEvent) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }
}

private func waitForChildPID(in fileURL: URL, timeout: TimeInterval) async throws -> pid_t {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if
            let content = try? String(contentsOf: fileURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = pid_t(content)
        {
            return pid
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    throw TestError.missingChildPIDFile(fileURL.path)
}

private func waitForCondition(timeout: TimeInterval, predicate: @escaping @Sendable () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if predicate() {
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(predicate())
}

private func waitSynchronously(
    for semaphore: DispatchSemaphore,
    timeout: TimeInterval
) -> Bool {
    semaphore.wait(timeout: .now() + timeout) == .success
}

@MainActor
private func waitForSinkWrites(
    _ sink: TerminalDisplaySinkBuffer,
    count: Int,
    timeout: Duration = .seconds(1)
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while sink.dataWrites.count < count {
        guard clock.now < deadline else {
            Issue.record("Timed out waiting for \(count) terminal writes; received \(sink.dataWrites.count).")
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private func waitForLaunchRecord(_ observer: LaunchObserver, timeout: TimeInterval) async throws -> (Int, Int) {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if let record = observer.firstRecord() {
            return record
        }

        try await Task.sleep(for: .milliseconds(50))
    }

    throw TestError.missingLaunchObservation
}

private func processExists(_ pid: pid_t) -> Bool {
    if kill(pid, 0) == 0 {
        return true
    }

    return errno == EPERM
}

private func waitForProcessExit(_ pid: pid_t, timeout: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if !processExists(pid) {
            return true
        }
        try? await Task.sleep(for: .milliseconds(50))
    }

    return !processExists(pid)
}

private func visiDataSessionControllerSource(filePath: StaticString = #filePath) throws -> String {
    let testFileURL = URL(fileURLWithPath: "\(filePath)")
    let repositoryRoot = testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot.appendingPathComponent("Sources/iData/VisiDataSessionController.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
}
