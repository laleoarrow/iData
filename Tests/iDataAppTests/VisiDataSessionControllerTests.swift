import Darwin
import Foundation
import Testing
@testable import iData

@MainActor
struct VisiDataSessionControllerTests {
    @Test
    func terminateAlsoStopsDescendantProcesses() throws {
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

        let childPID = try waitForChildPID(in: childPIDFile, timeout: 8.0)
        #expect(processExists(childPID))

        session.terminate()

        let childExited = waitForProcessExit(childPID, timeout: 5.0)
        #expect(childExited)
        if !childExited {
            _ = kill(childPID, SIGKILL)
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
        let session = VisiDataSessionController(signalSender: signalSpy.send)
        try session.open(fileURL: inputFile, explicitVDPath: launcher.path)
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

    private func makeFakeVDLauncher(at url: URL, childPIDFile: URL) throws {
        let escapedPIDPath = childPIDFile.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        #!/usr/bin/env python3
        import pathlib
        import subprocess
        import time

        child = subprocess.Popen(["/bin/sleep", "120"])
        pathlib.Path("\(escapedPIDPath)").write_text(str(child.pid))
        time.sleep(120)
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

    private func waitForChildPID(in fileURL: URL, timeout: TimeInterval) throws -> pid_t {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if
                let content = try? String(contentsOf: fileURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                let pid = pid_t(content)
            {
                return pid
            }
            usleep(50_000)
        }

        throw TestError.missingChildPIDFile(fileURL.path)
    }

    private func processExists(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
    }

    private func waitForProcessExit(_ pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !processExists(pid) {
                return true
            }
            usleep(50_000)
        }

        return !processExists(pid)
    }
}

private enum TestError: Error {
    case missingChildPIDFile(String)
}

@MainActor
private final class TerminalDisplaySinkBuffer: TerminalDisplaySink {
    private(set) var writes: [String] = []

    func clearTerminalDisplay() {
        writes.removeAll()
    }

    func writeToTerminalDisplay(_ data: Data) {
        writes.append(String(decoding: data, as: UTF8.self))
    }

    func focusTerminalDisplay() {}

    func reset() {
        writes.removeAll()
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
