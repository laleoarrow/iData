import Darwin
import Dispatch
import Foundation
#if canImport(iDataCore)
import iDataCore
#endif

@MainActor
protocol TerminalDisplaySink: AnyObject {
    func clearTerminalDisplay()
    func writeToTerminalDisplay(_ data: Data)
    func focusTerminalDisplay()
}

final class VisiDataSessionController: ObservableObject, @unchecked Sendable {
    @Published private(set) var currentFileURL: URL?
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let preflight = VisiDataLaunchPrereflight()
    private let ioQueue = DispatchQueue(label: "io.github.leoarrow.idata.visidata-session")
    private weak var displaySink: TerminalDisplaySink?
    private var isDisplayReady = false
    private var bufferedOutput: [Data] = []
    private var requiresDisplayReset = true
    private var masterFileDescriptor: Int32 = -1
    private var childPID: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?
    private var lastKnownSize: (cols: UInt16, rows: UInt16) = (120, 32)

    deinit {
        stopCurrentProcessIfNeeded(reapSynchronously: true)
    }

    @MainActor
    func bind(displaySink: TerminalDisplaySink?) {
        self.displaySink = displaySink
        if displaySink == nil {
            isDisplayReady = false
        }
    }

    @MainActor
    func markDisplayReady() {
        isDisplayReady = true

        if requiresDisplayReset {
            displaySink?.clearTerminalDisplay()
            requiresDisplayReset = false
        }

        flushBufferedOutput()
        displaySink?.focusTerminalDisplay()
    }

    @MainActor
    func open(fileURL: URL, explicitVDPath: String?) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LaunchError.fileMissing(fileURL.path)
        }

        let vdURL = try preflight.resolveExecutable(explicitVDPath: explicitVDPath)
        stopCurrentProcessIfNeeded(reapSynchronously: true)

        currentFileURL = fileURL
        errorMessage = nil
        statusMessage = "Opening \(fileURL.lastPathComponent)…"
        bufferedOutput.removeAll(keepingCapacity: true)
        requiresDisplayReset = true

        if isDisplayReady {
            displaySink?.clearTerminalDisplay()
            requiresDisplayReset = false
        }

        try startProcess(
            visidataExecutable: vdURL,
            fileURL: fileURL,
            cols: lastKnownSize.cols,
            rows: lastKnownSize.rows
        )

        isRunning = true
        statusMessage = "Running VisiData for \(fileURL.lastPathComponent)."
    }

    @MainActor
    func sendInput(_ input: String) {
        guard let data = input.data(using: .utf8) else {
            return
        }

        writeToPTY(data)
    }

    @MainActor
    func sendBinary(base64: String) {
        guard let data = Data(base64Encoded: base64) else {
            return
        }

        writeToPTY(data)
    }

    @MainActor
    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else {
            return
        }

        let normalizedCols = UInt16(min(cols, Int(UInt16.max)))
        let normalizedRows = UInt16(min(rows, Int(UInt16.max)))
        lastKnownSize = (normalizedCols, normalizedRows)

        guard masterFileDescriptor >= 0 else {
            return
        }

        var windowSize = winsize(
            ws_row: normalizedRows,
            ws_col: normalizedCols,
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        _ = ioctl(masterFileDescriptor, TIOCSWINSZ, &windowSize)

        if childPID > 0 {
            kill(childPID, SIGWINCH)
        }
    }

    @MainActor
    func terminate() {
        stopCurrentProcessIfNeeded(reapSynchronously: true)
        isRunning = false
        statusMessage = "Session ended."
    }

    private func startProcess(
        visidataExecutable: URL,
        fileURL: URL,
        cols: UInt16,
        rows: UInt16
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
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, master)
        if slave > STDERR_FILENO {
            posix_spawn_file_actions_addclose(&fileActions, slave)
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
                        nil,
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
        posix_spawn_file_actions_destroy(&fileActions)

        guard spawnResult == 0 else {
            close(master)
            close(slave)
            throw LaunchError.processLaunchFailed(systemErrorDescription(Int32(spawnResult)))
        }

        close(slave)
        masterFileDescriptor = master
        childPID = pid
        configureReadSource(for: master)
        configureProcessSource(for: pid)
    }

    private func configureReadSource(for fileDescriptor: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: ioQueue)
        source.setEventHandler { [weak self] in
            self?.drainOutput()
        }
        source.resume()
        readSource = source
    }

    private func configureProcessSource(for pid: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: ioQueue)
        source.setEventHandler { [weak self] in
            self?.handleProcessExit()
        }
        source.resume()
        processSource = source
    }

    private func drainOutput() {
        guard masterFileDescriptor >= 0 else {
            return
        }

        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = Darwin.read(masterFileDescriptor, &buffer, buffer.count)

            if bytesRead > 0 {
                let data = Data(buffer.prefix(bytesRead))
                Task { @MainActor [weak self] in
                    self?.enqueueOutput(data)
                }
                continue
            }

            if bytesRead == 0 {
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }

            return
        }
    }

    @MainActor
    private func enqueueOutput(_ data: Data) {
        if isDisplayReady {
            if requiresDisplayReset {
                displaySink?.clearTerminalDisplay()
                requiresDisplayReset = false
            }
            displaySink?.writeToTerminalDisplay(data)
        } else {
            bufferedOutput.append(data)
        }
    }

    @MainActor
    private func flushBufferedOutput() {
        guard isDisplayReady else {
            return
        }

        for chunk in bufferedOutput {
            displaySink?.writeToTerminalDisplay(chunk)
        }
        bufferedOutput.removeAll(keepingCapacity: true)
    }

    private func writeToPTY(_ data: Data) {
        guard masterFileDescriptor >= 0 else {
            return
        }

        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }

            var totalWritten = 0
            while totalWritten < data.count {
                let bytesWritten = Darwin.write(
                    masterFileDescriptor,
                    baseAddress.advanced(by: totalWritten),
                    data.count - totalWritten
                )

                if bytesWritten <= 0 {
                    return
                }

                totalWritten += bytesWritten
            }
        }
    }

    private func handleProcessExit() {
        guard childPID > 0 else {
            return
        }

        var exitStatus: Int32 = 0
        let exitedPID = waitpid(childPID, &exitStatus, 0)
        guard exitedPID == childPID else {
            return
        }

        childPID = 0
        cleanupDescriptorsAndSources()

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.isRunning = false

            if didExitNormally(exitStatus) {
                let code = exitCode(from: exitStatus)
                if code == 0 {
                    self.statusMessage = "VisiData exited."
                    self.errorMessage = nil
                } else {
                    self.statusMessage = "VisiData exited with code \(code)."
                    self.errorMessage = "VisiData exited with code \(code)."
                }
            } else if didTerminateBySignal(exitStatus) {
                let signal = terminatingSignal(from: exitStatus)
                self.statusMessage = "VisiData terminated."
                self.errorMessage = "VisiData was interrupted by signal \(signal)."
            } else {
                self.statusMessage = "VisiData ended."
            }
        }
    }

    private func stopCurrentProcessIfNeeded(reapSynchronously: Bool) {
        let pid = childPID

        if pid > 0 {
            processSource?.cancel()
            processSource = nil
            childPID = 0
            kill(pid, SIGTERM)

            if reapSynchronously {
                var exitStatus: Int32 = 0
                let deadline = Date().addingTimeInterval(0.5)

                while true {
                    let waitResult = waitpid(pid, &exitStatus, WNOHANG)
                    if waitResult == pid || waitResult == -1 {
                        break
                    }

                    if Date() >= deadline {
                        kill(pid, SIGKILL)
                        _ = waitpid(pid, &exitStatus, 0)
                        break
                    }

                    usleep(20_000)
                }
            }
        }

        cleanupDescriptorsAndSources()
    }

    private func cleanupDescriptorsAndSources() {
        readSource?.cancel()
        readSource = nil

        if masterFileDescriptor >= 0 {
            close(masterFileDescriptor)
            masterFileDescriptor = -1
        }
    }

    private func childEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "iData"
        return environment
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
