import Darwin
import Dispatch
import Foundation
#if canImport(iDataCore)
import iDataCore
#endif

enum TerminalDebugLogger {
    private final class Storage: @unchecked Sendable {
        let stateLock = NSLock()
        let writeQueue = DispatchQueue(label: "io.github.leoarrow.idata.terminal-debug-log")
        var enabledOverride: Bool?
        var logFileURLOverride: URL?
    }

    private static let storage = Storage()
    private static let environmentEnabled: Bool = {
        let environment = ProcessInfo.processInfo.environment
        let value = environment["IDATA_TERMINAL_TRACE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }()

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else {
            return
        }

        let resolvedMessage = message()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(resolvedMessage)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        let logFileURL = resolvedLogFileURL()
        storage.writeQueue.async {
            append(data: data, to: logFileURL)
        }
    }

    static var isEnabled: Bool {
        storage.stateLock.withLock {
            if let enabledOverride = storage.enabledOverride {
                return enabledOverride
            }

            return environmentEnabled
        }
    }

    private static func resolvedLogFileURL() -> URL {
        storage.stateLock.withLock {
            storage.logFileURLOverride ?? URL(fileURLWithPath: "/tmp/idata-terminal-trace.log")
        }
    }

    private static func append(data: Data, to fileURL: URL) {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    static func setEnabledOverrideForTesting(_ value: Bool?) {
        storage.stateLock.withLock {
            storage.enabledOverride = value
        }
    }

    static func setLogFileURLForTesting(_ value: URL?) {
        storage.stateLock.withLock {
            storage.logFileURLOverride = value
        }
    }

    static func flushForTesting() {
        storage.writeQueue.sync {}
    }

    static func resetForTesting() {
        storage.stateLock.withLock {
            storage.enabledOverride = nil
            storage.logFileURLOverride = nil
        }
    }
}

func terminalDebugTrace(_ message: @autoclosure () -> String) {
    TerminalDebugLogger.log(message())
}

@MainActor
protocol TerminalDisplaySink: AnyObject {
    func clearTerminalDisplay()
    func resetTerminalDisplay()
    func writeToTerminalDisplay(_ data: Data)
    func focusTerminalDisplay()
}

enum PTYWriteOutcome: Equatable {
    case completed
    case descriptorUnavailable
    case retryBudgetExceeded
    case failed(errno: Int32)
}

struct PTYWriteDriver {
    typealias WriteCall = (_ fileDescriptor: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int
    typealias SleepCall = (_ microseconds: useconds_t) -> Void

    let maxBackoffRetries: Int
    let backoffMicros: useconds_t
    let writeCall: WriteCall
    let sleepCall: SleepCall

    init(
        maxBackoffRetries: Int = 200,
        backoffMicros: useconds_t = 2_000,
        writeCall: @escaping WriteCall = { fileDescriptor, buffer, count in
            Darwin.write(fileDescriptor, buffer, count)
        },
        sleepCall: @escaping SleepCall = { microseconds in
            Darwin.usleep(microseconds)
        }
    ) {
        self.maxBackoffRetries = maxBackoffRetries
        self.backoffMicros = backoffMicros
        self.writeCall = writeCall
        self.sleepCall = sleepCall
    }

    func writeAll(
        data: Data,
        fileDescriptorProvider: () -> Int32
    ) -> PTYWriteOutcome {
        guard !data.isEmpty else {
            return .completed
        }

        var totalWritten = 0
        var transientRetryCount = 0

        return data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return .completed
            }

            while totalWritten < data.count {
                let fileDescriptor = fileDescriptorProvider()
                guard fileDescriptor >= 0 else {
                    return .descriptorUnavailable
                }

                let writeResult = writeCall(
                    fileDescriptor,
                    baseAddress.advanced(by: totalWritten),
                    data.count - totalWritten
                )

                if writeResult > 0 {
                    totalWritten += writeResult
                    transientRetryCount = 0
                    continue
                }

                if writeResult == 0 {
                    return .failed(errno: 0)
                }

                let writeErrno = errno

                if writeErrno == EINTR {
                    continue
                }

                if writeErrno == EAGAIN || writeErrno == EWOULDBLOCK {
                    transientRetryCount += 1
                    if transientRetryCount > maxBackoffRetries {
                        return .retryBudgetExceeded
                    }
                    sleepCall(backoffMicros)
                    continue
                }

                return .failed(errno: writeErrno)
            }

            return .completed
        }
    }
}

final class VisiDataSessionController: ObservableObject, @unchecked Sendable {
    @Published private(set) var currentFileURL: URL?
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let preflight = VisiDataLaunchPrereflight()
    private let ioQueue = DispatchQueue(label: "io.github.leoarrow.idata.visidata-session")
    private let processWaitQueue = DispatchQueue(label: "io.github.leoarrow.idata.visidata-session.wait")
    private let writeQueue = DispatchQueue(label: "io.github.leoarrow.idata.visidata-session.write")
    private let ptyWriteDriver: PTYWriteDriver
    private let signalSender: (_ pid: pid_t, _ signal: Int32) -> Int32
    private let launchObserver: ((_ cols: UInt16, _ rows: UInt16) -> Void)?
    private let launchAttemptValidator: () throws -> Void
    private let fallbackReadyObserver: ((UInt64) -> Void)?
    private let fallbackEvaluationObserver: ((UInt64) -> Void)?
    private let displayMeasurementFallbackDelay: Duration
    private weak var displaySink: TerminalDisplaySink?
    private var isDisplayReady = false
    private var hasPresentedDisplay = false
    private var transcript = TerminalTranscript()
    private var requiresDisplayReset = true
    private var needsRedrawAfterDisplayReady = false
    private var pendingOpenRequest: PendingOpenRequest?
    private var pendingLaunchTask: Task<Void, Never>?
    private var hasMeasuredDisplaySize = false
    private var launchedBeforeMeasuredDisplaySize = false
    private let ptyLock = NSLock()
    private var _masterFileDescriptor: Int32 = -1
    private var masterFileDescriptor: Int32 {
        get { ptyLock.withLock { _masterFileDescriptor } }
        set { ptyLock.withLock { _masterFileDescriptor = newValue } }
    }
    private var childPID: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var outputDeliveryTail: Task<Void, Never>?
    private var outputDeliveryGeneration: UInt64?
    private var lastKnownSize: (cols: UInt16, rows: UInt16) = (120, 32)
    private var outputGeneration: UInt64 = 0

    private struct PendingOpenRequest {
        let fileURL: URL
        let vdURL: URL
        let generation: UInt64
    }

    init(
        ptyWriteDriver: PTYWriteDriver = PTYWriteDriver(),
        signalSender: @escaping (_ pid: pid_t, _ signal: Int32) -> Int32 = { pid, signal in
            Darwin.kill(pid, signal)
        },
        launchObserver: ((_ cols: UInt16, _ rows: UInt16) -> Void)? = nil,
        launchAttemptValidator: @escaping () throws -> Void = {},
        fallbackReadyObserver: ((UInt64) -> Void)? = nil,
        fallbackEvaluationObserver: ((UInt64) -> Void)? = nil,
        displayMeasurementFallbackDelay: Duration = .milliseconds(900)
    ) {
        self.ptyWriteDriver = ptyWriteDriver
        self.signalSender = signalSender
        self.launchObserver = launchObserver
        self.launchAttemptValidator = launchAttemptValidator
        self.fallbackReadyObserver = fallbackReadyObserver
        self.fallbackEvaluationObserver = fallbackEvaluationObserver
        self.displayMeasurementFallbackDelay = displayMeasurementFallbackDelay
    }

    deinit {
        stopCurrentProcessIfNeeded(reapSynchronously: true)
    }

    @MainActor
    func bind(displaySink: TerminalDisplaySink?) {
        let displaySinkDidChange = self.displaySink !== displaySink
        self.displaySink = displaySink
        if displaySink == nil {
            terminalDebugTrace("session.bind nil session=\(ObjectIdentifier(self))")
            isDisplayReady = false
        } else {
            terminalDebugTrace("session.bind sink session=\(ObjectIdentifier(self))")
            if displaySinkDidChange {
                isDisplayReady = false
                if childPID > 0 {
                    needsRedrawAfterDisplayReady = true
                }
            }
        }
    }

    @MainActor
    func unbind(displaySink expectedDisplaySink: TerminalDisplaySink) {
        guard displaySink === expectedDisplaySink else {
            return
        }

        terminalDebugTrace("session.unbind sink session=\(ObjectIdentifier(self))")
        displaySink = nil
        isDisplayReady = false
    }

    @MainActor
    func isBound(displaySink expectedDisplaySink: TerminalDisplaySink) -> Bool {
        displaySink === expectedDisplaySink
    }

    @MainActor
    func markDisplayReady() {
        guard !isDisplayReady else {
            return
        }

        terminalDebugTrace("session.markDisplayReady session=\(ObjectIdentifier(self)) chunks=\(self.transcript.chunks.count)")
        isDisplayReady = true
        if hasPresentedDisplay {
            replayTranscript()
        } else {
            presentInitialTranscript()
        }
        hasPresentedDisplay = true
        displaySink?.focusTerminalDisplay()
        sendPendingMeasuredDisplayRedrawIfReady()
        launchPendingOpenAfterDisplayReadyIfPossible()
    }

    @MainActor
    func invalidateDisplayReadinessForTerminalReset() {
        guard isDisplayReady else {
            return
        }

        terminalDebugTrace("session.invalidateDisplayReadinessForTerminalReset session=\(ObjectIdentifier(self))")
        isDisplayReady = false
        requiresDisplayReset = true
        if childPID > 0 {
            needsRedrawAfterDisplayReady = true
        }
    }

    @MainActor
    func focusTerminalDisplay() {
        displaySink?.focusTerminalDisplay()
    }

    @MainActor
    func open(fileURL: URL, explicitVDPath: String?) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LaunchError.fileMissing(fileURL.path)
        }

        let vdURL = try preflight.resolveExecutable(explicitVDPath: explicitVDPath)
        stopCurrentProcessIfNeeded(reapSynchronously: true)
        pendingLaunchTask?.cancel()
        pendingLaunchTask = nil

        currentFileURL = fileURL
        errorMessage = nil
        isRunning = true
        statusMessage = AppModel.localized(
            english: "Opening \(fileURL.lastPathComponent)…",
            chinese: "正在打开 \(fileURL.lastPathComponent)…"
        )
        transcript.reset()
        requiresDisplayReset = true
        needsRedrawAfterDisplayReady = false
        outputGeneration &+= 1
        terminalDebugTrace("session.open session=\(ObjectIdentifier(self)) file=\(fileURL.lastPathComponent) generation=\(self.outputGeneration) displayReady=\(self.isDisplayReady)")
        pendingOpenRequest = PendingOpenRequest(fileURL: fileURL, vdURL: vdURL, generation: outputGeneration)

        let hasBoundDisplaySink = displaySink != nil
        if hasBoundDisplaySink {
            // Recreate and remeasure the terminal on every in-place file switch.
            // This avoids stale viewport state carrying over between sessions.
            displaySink?.resetTerminalDisplay()
            hasMeasuredDisplaySize = false
        }
        let canLaunchWithExistingMeasurement = hasMeasuredDisplaySize

        do {
            if canLaunchWithExistingMeasurement {
                try launchPendingOpenIfPossible()
            } else {
                let scheduledGeneration = outputGeneration
                pendingLaunchTask = Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self else {
                        return
                    }
                    do {
                        try await Task.sleep(for: self.displayMeasurementFallbackDelay)
                        try Task.checkCancellation()
                        self.fallbackReadyObserver?(scheduledGeneration)
                        await MainActor.run {
                            defer {
                                self.fallbackEvaluationObserver?(scheduledGeneration)
                            }
                            guard self.pendingOpenRequest?.generation == scheduledGeneration else {
                                return
                            }
                            terminalDebugTrace("session.open fallbackFire session=\(ObjectIdentifier(self))")
                            self.launchPendingOpenReportingFailure()
                        }
                    } catch {
                        return
                    }
                }
                terminalDebugTrace("session.open fallbackSchedule session=\(ObjectIdentifier(self))")
            }
        } catch {
            recordPendingLaunchFailure(error)
            throw error
        }
    }

    @MainActor
    func launchPendingOpenImmediatelyIfNeeded() throws {
        do {
            try launchPendingOpenIfPossible()
        } catch {
            recordPendingLaunchFailure(error)
            throw error
        }
    }

    @MainActor
    func sendInput(_ input: String) {
        guard let data = input.data(using: .utf8) else {
            return
        }

        enqueuePTYWrite(data)
    }

    @MainActor
    func sendBinary(base64: String) {
        guard let data = Data(base64Encoded: base64) else {
            return
        }

        enqueuePTYWrite(data)
    }

    @MainActor
    func resize(cols: Int, rows: Int, force: Bool = false) {
        guard cols > 0, rows > 0 else {
            return
        }

        hasMeasuredDisplaySize = true
        let normalizedCols = UInt16(min(cols, Int(UInt16.max)))
        let normalizedRows = UInt16(min(rows, Int(UInt16.max)))
        let requestedSize = (normalizedCols, normalizedRows)
        let sizeChanged = requestedSize != lastKnownSize
        lastKnownSize = (normalizedCols, normalizedRows)
        terminalDebugTrace("session.resize session=\(ObjectIdentifier(self)) cols=\(normalizedCols) rows=\(normalizedRows) sizeChanged=\(sizeChanged) force=\(force)")

        guard masterFileDescriptor >= 0 else {
            return
        }

        let shouldForceRedrawAfterMeasuredResize = childPID > 0 && launchedBeforeMeasuredDisplaySize
        if shouldForceRedrawAfterMeasuredResize {
            // The process was launched with a default size before the real
            // terminal measurement arrived. Discard any output that VisiData
            // painted for the stale default dimensions so that
            // presentInitialTranscript() does not replay misaligned frames.
            launchedBeforeMeasuredDisplaySize = false
            transcript.reset()
            needsRedrawAfterDisplayReady = true
        }

        let shouldApplyWindowSize = sizeChanged || (force && needsRedrawAfterDisplayReady)

        if shouldApplyWindowSize {
            var windowSize = winsize(
                ws_row: normalizedRows,
                ws_col: normalizedCols,
                ws_xpixel: 0,
                ws_ypixel: 0
            )

            _ = ioctl(masterFileDescriptor, TIOCSWINSZ, &windowSize)

            if childPID > 0 {
                _ = signalSender(childPID, SIGWINCH)
            }
        }

        if shouldForceRedrawAfterMeasuredResize {
            terminalDebugTrace("session.resize settleAfterFallbackLaunch session=\(ObjectIdentifier(self)) cols=\(normalizedCols) rows=\(normalizedRows)")
        }

        if shouldApplyWindowSize {
            sendPendingMeasuredDisplayRedrawIfReady()
        }
    }

    @MainActor
    func terminate() {
        pendingLaunchTask?.cancel()
        pendingLaunchTask = nil
        pendingOpenRequest = nil
        stopCurrentProcessIfNeeded(reapSynchronously: true)
        isRunning = false
        statusMessage = AppModel.localized(
            english: "Session ended.",
            chinese: "会话已结束。"
        )
    }

    @MainActor
    func reportTerminalDisplayFailure(english: String, chinese: String) {
        pendingLaunchTask?.cancel()
        pendingLaunchTask = nil
        pendingOpenRequest = nil
        stopCurrentProcessIfNeeded(reapSynchronously: true)
        isRunning = false
        statusMessage = nil
        errorMessage = AppModel.localized(english: english, chinese: chinese)
    }

    private func startProcess(
        visidataExecutable: URL,
        fileURL: URL,
        cols: UInt16,
        rows: UInt16,
        generation: UInt64
    ) throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var windowSize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)

        guard openpty(&master, &slave, nil, nil, &windowSize) == 0 else {
            throw LaunchError.pseudoTerminalUnavailable(systemErrorDescription(errno))
        }

        let currentFlags = fcntl(master, F_GETFL)
        if currentFlags >= 0 {
            _ = fcntl(master, F_SETFL, currentFlags | O_NONBLOCK)
        }

        var fileActions: posix_spawn_file_actions_t? = nil
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            close(master)
            close(slave)
            throw LaunchError.processLaunchFailed(systemErrorDescription(errno))
        }
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
        }
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, master)
        if slave > STDERR_FILENO {
            posix_spawn_file_actions_addclose(&fileActions, slave)
        }

        var spawnAttributes: posix_spawnattr_t? = nil
        guard posix_spawnattr_init(&spawnAttributes) == 0 else {
            close(master)
            close(slave)
            throw LaunchError.processLaunchFailed(systemErrorDescription(errno))
        }
        defer {
            posix_spawnattr_destroy(&spawnAttributes)
        }

        let spawnFlags = Int16(POSIX_SPAWN_SETPGROUP)
        guard posix_spawnattr_setflags(&spawnAttributes, spawnFlags) == 0 else {
            close(master)
            close(slave)
            throw LaunchError.processLaunchFailed(systemErrorDescription(errno))
        }

        // Put the child in its own process group so we can terminate descendants as a unit.
        guard posix_spawnattr_setpgroup(&spawnAttributes, 0) == 0 else {
            close(master)
            close(slave)
            throw LaunchError.processLaunchFailed(systemErrorDescription(errno))
        }

        let launchCommand = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: visidataExecutable,
            fileURL: fileURL
        )
        let environment = childEnvironment()
        let argumentPointers = ([launchCommand.executablePath] + launchCommand.arguments).map { strdup($0) }
        let environmentPointers = environment.map { strdup("\($0.key)=\($0.value)") }
        var arguments = argumentPointers + [nil]
        var environmentVariables = environmentPointers + [nil]
        var pid = pid_t()

        let spawnResult = arguments.withUnsafeMutableBufferPointer { argumentBuffer in
            environmentVariables.withUnsafeMutableBufferPointer { environmentBuffer in
                launchCommand.executablePath.withCString { executablePathPointer in
                    posix_spawn(
                        &pid,
                        executablePathPointer,
                        &fileActions,
                        &spawnAttributes,
                        argumentBuffer.baseAddress,
                        environmentBuffer.baseAddress
                    )
                }
            }
        }

        for pointer in argumentPointers {
            free(pointer)
        }
        for pointer in environmentPointers {
            free(pointer)
        }
        guard spawnResult == 0 else {
            close(master)
            close(slave)
            throw LaunchError.processLaunchFailed(systemErrorDescription(Int32(spawnResult)))
        }

        close(slave)
        masterFileDescriptor = master
        childPID = pid
        configureReadSource(for: master, generation: generation)
        waitForProcessExit(pid: pid, generation: generation)
    }

    private func configureReadSource(for fileDescriptor: Int32, generation: UInt64) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: ioQueue)
        let writeQueue = self.writeQueue
        source.setEventHandler { [weak self] in
            self?.drainOutput(from: fileDescriptor, generation: generation)
        }
        source.setCancelHandler {
            writeQueue.async {
                close(fileDescriptor)
            }
        }
        source.resume()
        readSource = source
    }

    private func drainOutput(from fileDescriptor: Int32, generation: UInt64) {
        guard fileDescriptor >= 0 else {
            return
        }

        let maximumBatchSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        var batch = Data()
        batch.reserveCapacity(buffer.count)

        while batch.count < maximumBatchSize {
            let remainingBatchCapacity = maximumBatchSize - batch.count
            let bytesRead = Darwin.read(
                fileDescriptor,
                &buffer,
                min(buffer.count, remainingBatchCapacity)
            )

            if bytesRead > 0 {
                batch.append(buffer, count: bytesRead)
                continue
            }

            if bytesRead < 0, errno == EINTR {
                continue
            }

            break
        }

        guard !batch.isEmpty else {
            return
        }

        let precedingDelivery = outputDeliveryGeneration == generation ? outputDeliveryTail : nil
        let delivery = Task { @MainActor [weak self, batch, precedingDelivery] in
            await precedingDelivery?.value

            guard let self else {
                return
            }

            enqueueOutput(batch, generation: generation)
        }
        outputDeliveryGeneration = generation
        outputDeliveryTail = delivery
    }

    @MainActor
    private func enqueueOutput(_ data: Data, generation: UInt64) {
        guard generation == outputGeneration else {
            return
        }

        transcript.append(data)

        if isDisplayReady {
            if requiresDisplayReset {
                terminalDebugTrace("session.enqueueOutput deferredClear session=\(ObjectIdentifier(self)) generation=\(generation)")
                displaySink?.clearTerminalDisplay()
                requiresDisplayReset = false
            }
            displaySink?.writeToTerminalDisplay(data)
        }
    }

    @MainActor
    func appendOutputForTesting(_ data: Data) {
        enqueueOutput(data, generation: outputGeneration)
    }

    @MainActor
    func appendOutputForTesting(_ data: Data, generation: UInt64) {
        enqueueOutput(data, generation: generation)
    }

    func drainOutputForTesting(from fileDescriptor: Int32, generation: UInt64) {
        drainOutput(from: fileDescriptor, generation: generation)
    }

    @MainActor
    private func replayTranscript() {
        guard isDisplayReady else {
            return
        }

        terminalDebugTrace("session.replayTranscript session=\(ObjectIdentifier(self)) chunks=\(self.transcript.chunks.count)")
        if !requiresDisplayReset {
            displaySink?.clearTerminalDisplay()
        }
        requiresDisplayReset = false

        for chunk in transcript.chunks {
            displaySink?.writeToTerminalDisplay(chunk)
        }
    }

    @MainActor
    private func presentInitialTranscript() {
        guard isDisplayReady else {
            return
        }

        requiresDisplayReset = false

        for chunk in transcript.chunks {
            displaySink?.writeToTerminalDisplay(chunk)
        }
    }

    @MainActor
    private func launchPendingOpenIfPossible() throws {
        guard let pendingOpenRequest else {
            return
        }
        pendingLaunchTask?.cancel()
        pendingLaunchTask = nil

        // Rebuild the terminal on the first measured resize whenever the PTY
        // launched before we had a real container measurement, even if the
        // display sink was attached later during the welcome -> session switch.
        launchedBeforeMeasuredDisplaySize = !hasMeasuredDisplaySize
        terminalDebugTrace("session.open launch session=\(ObjectIdentifier(self)) generation=\(pendingOpenRequest.generation) launchedBeforeMeasuredDisplaySize=\(launchedBeforeMeasuredDisplaySize)")

        try launchAttemptValidator()
        try startProcess(
            visidataExecutable: pendingOpenRequest.vdURL,
            fileURL: pendingOpenRequest.fileURL,
            cols: lastKnownSize.cols,
            rows: lastKnownSize.rows,
            generation: pendingOpenRequest.generation
        )

        launchObserver?(lastKnownSize.cols, lastKnownSize.rows)
        self.pendingOpenRequest = nil
        isRunning = true
        statusMessage = AppModel.localized(
            english: "Running VisiData for \(pendingOpenRequest.fileURL.lastPathComponent).",
            chinese: "正在用 VisiData 查看 \(pendingOpenRequest.fileURL.lastPathComponent)。"
        )
    }

    @MainActor
    private func enqueuePTYWrite(_ data: Data) {
        let fileDescriptor = masterFileDescriptor
        guard fileDescriptor >= 0 else {
            return
        }
        writeQueue.async { [weak self] in
            guard let self else {
                return
            }
            _ = self.ptyWriteDriver.writeAll(data: data) {
                fileDescriptor
            }
        }
    }

    @MainActor
    private func launchPendingOpenAfterDisplayReadyIfPossible() {
        guard pendingOpenRequest != nil, childPID == 0, hasMeasuredDisplaySize, isDisplayReady else {
            return
        }

        pendingLaunchTask?.cancel()
        pendingLaunchTask = nil
        launchPendingOpenReportingFailure()
    }

    @MainActor
    private func launchPendingOpenReportingFailure() {
        do {
            try launchPendingOpenIfPossible()
        } catch {
            recordPendingLaunchFailure(error)
        }
    }

    @MainActor
    private func recordPendingLaunchFailure(_ error: Error) {
        pendingLaunchTask?.cancel()
        pendingLaunchTask = nil
        pendingOpenRequest = nil
        isRunning = false
        statusMessage = nil
        errorMessage = error.localizedDescription
    }

    @MainActor
    private func sendPendingMeasuredDisplayRedrawIfReady() {
        guard isDisplayReady, needsRedrawAfterDisplayReady, childPID > 0, masterFileDescriptor >= 0 else {
            return
        }

        needsRedrawAfterDisplayReady = false
        enqueuePTYWrite(Data("\u{0C}".utf8))
        terminalDebugTrace("session.redrawAfterDisplayReady session=\(ObjectIdentifier(self))")
    }

    private func waitForProcessExit(pid: pid_t, generation: UInt64) {
        // A single kernel wait avoids timer polling and cannot miss a short-lived process.
        // It runs outside both the main actor and the PTY I/O queue.
        processWaitQueue.async { [weak self] in
            var exitStatus: Int32 = 0
            var exitedPID: pid_t

            repeat {
                exitedPID = waitpid(pid, &exitStatus, 0)
            } while exitedPID == -1 && errno == EINTR

            guard exitedPID == pid else {
                return
            }

            let capturedExitStatus = exitStatus
            self?.ioQueue.async { [weak self] in
                Task { @MainActor [weak self] in
                    self?.finalizeProcessExit(pid: pid, generation: generation, exitStatus: capturedExitStatus)
                }
            }
        }
    }

    @MainActor
    private func finalizeProcessExit(pid: pid_t, generation: UInt64, exitStatus: Int32) {
        guard generation == outputGeneration, childPID == pid else {
            return
        }

        childPID = 0
        cleanupDescriptorsAndSources()

        if didExitNormally(exitStatus) {
            let code = exitCode(from: exitStatus)
            if code == 0 {
                statusMessage = AppModel.localized(
                    english: "VisiData exited.",
                    chinese: "VisiData 已退出。"
                )
                errorMessage = nil
            } else {
                statusMessage = AppModel.localized(
                    english: "VisiData exited with code \(code).",
                    chinese: "VisiData 已退出，代码为 \(code)。"
                )
                let baseErrorMessage = AppModel.localized(
                    english: "VisiData exited with code \(code).",
                    chinese: "VisiData 已退出，代码为 \(code)。"
                )
                if let currentFileURL, let dependencyGuidance = AppModel.visiDataFormatDependencyGuidance(for: currentFileURL, language: AppModel.resolvedLanguage()) {
                    errorMessage = "\(baseErrorMessage) \(dependencyGuidance)"
                } else {
                    errorMessage = baseErrorMessage
                }
            }
        } else if didTerminateBySignal(exitStatus) {
            let signal = terminatingSignal(from: exitStatus)
            statusMessage = AppModel.localized(
                english: "VisiData terminated.",
                chinese: "VisiData 已终止。"
            )
            errorMessage = AppModel.localized(
                english: "VisiData was interrupted by signal \(signal).",
                chinese: "VisiData 被信号 \(signal) 中断。"
            )
        } else {
            statusMessage = AppModel.localized(
                english: "VisiData ended.",
                chinese: "VisiData 已结束。"
            )
        }

        isRunning = false
    }

    private func stopCurrentProcessIfNeeded(reapSynchronously: Bool) {
        let pid = childPID
        outputGeneration &+= 1
        launchedBeforeMeasuredDisplaySize = false
        needsRedrawAfterDisplayReady = false

        if pid > 0 {
            childPID = 0
            signalProcessTree(rootPID: pid, signal: SIGTERM)

            if reapSynchronously {
                var exitStatus: Int32 = 0
                let deadline = Date().addingTimeInterval(0.5)

                while true {
                    let waitResult = waitpid(pid, &exitStatus, WNOHANG)
                    if waitResult == pid || waitResult == -1 {
                        break
                    }

                    if Date() >= deadline {
                        signalProcessTree(rootPID: pid, signal: SIGKILL)
                        _ = waitpid(pid, &exitStatus, 0)
                        break
                    }

                    usleep(20_000)
                }
            }
        }

        cleanupDescriptorsAndSources()
    }

    private func signalProcessTree(rootPID: pid_t, signal: Int32) {
        guard rootPID > 0 else {
            return
        }

        let descendantPIDs = descendantProcessIDs(of: rootPID)

        if kill(-rootPID, signal) == 0 {
            for descendantPID in descendantPIDs {
                _ = kill(descendantPID, signal)
            }
            return
        }

        for descendantPID in descendantPIDs {
            _ = kill(descendantPID, signal)
        }
        _ = kill(rootPID, signal)
    }

    private func descendantProcessIDs(of rootPID: pid_t) -> [pid_t] {
        var visited = Set<pid_t>()
        var queue: [pid_t] = [rootPID]
        var descendants: [pid_t] = []

        while let parentPID = queue.popLast() {
            for childPID in childProcessIDs(of: parentPID) where !visited.contains(childPID) {
                visited.insert(childPID)
                descendants.append(childPID)
                queue.append(childPID)
            }
        }

        return descendants
    }

    private func childProcessIDs(of parentPID: pid_t) -> [pid_t] {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", String(parentPID)]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return []
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return []
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return output
            .split(whereSeparator: \.isWhitespace)
            .compactMap { pid_t($0) }
    }

    private func cleanupDescriptorsAndSources() {
        let source = readSource
        readSource = nil
        let fileDescriptor = masterFileDescriptor
        masterFileDescriptor = -1

        if let source {
            source.cancel()
        } else if fileDescriptor >= 0 {
            writeQueue.async {
                close(fileDescriptor)
            }
        }
    }

    private func childEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "iData"
        return environment
    }

    @MainActor
    var outputGenerationForTesting: UInt64 {
        outputGeneration
    }

    @MainActor
    var processIdentifierForTesting: pid_t {
        childPID
    }

    @MainActor
    var masterFileDescriptorForTesting: Int32 {
        masterFileDescriptor
    }

    @MainActor
    func finalizeProcessExitForTesting(pid: pid_t, generation: UInt64, exitStatus: Int32 = 0) {
        finalizeProcessExit(pid: pid, generation: generation, exitStatus: exitStatus)
    }

    func installOutputDeliveryTailForTesting(
        _ task: Task<Void, Never>,
        generation: UInt64
    ) {
        outputDeliveryGeneration = generation
        outputDeliveryTail = task
    }

    @MainActor
    func simulateFallbackLaunchBeforeMeasurementForTesting(fileDescriptor: Int32) {
        masterFileDescriptor = fileDescriptor
        childPID = 999_999
        launchedBeforeMeasuredDisplaySize = true
    }
}

private func didExitNormally(_ status: Int32) -> Bool {
    (status & 0x7f) == 0
}

private func exitCode(from status: Int32) -> Int32 {
    (status >> 8) & 0xff
}

private func didTerminateBySignal(_ status: Int32) -> Bool {
    let signal = status & 0x7f
    return signal != 0 && signal != 0x7f
}

private func terminatingSignal(from status: Int32) -> Int32 {
    status & 0x7f
}
