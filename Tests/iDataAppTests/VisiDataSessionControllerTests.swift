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

        let childPID = try waitForChildPID(in: childPIDFile, timeout: 3.0)
        #expect(processExists(childPID))

        session.terminate()

        let childExited = waitForProcessExit(childPID, timeout: 2.0)
        #expect(childExited)
        if !childExited {
            _ = kill(childPID, SIGKILL)
        }
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
