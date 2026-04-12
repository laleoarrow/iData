import Foundation
import Testing
@testable import iData

@Suite(.serialized)
struct TerminalDebugLoggerTests {
    @Test
    func defaultDisabledModeDoesNotCreateTraceFile() throws {
        let traceURL = temporaryTraceFileURL()
        TerminalDebugLogger.resetForTesting()
        defer { cleanupTraceEnvironment(traceURL) }
        TerminalDebugLogger.setEnabledOverrideForTesting(false)
        TerminalDebugLogger.setLogFileURLForTesting(traceURL)

        TerminalDebugLogger.log("disabled-path")
        TerminalDebugLogger.flushForTesting()

        #expect(!FileManager.default.fileExists(atPath: traceURL.path))
    }

    @Test
    func enabledModeAppendsMessagesInOrder() throws {
        let traceURL = temporaryTraceFileURL()
        TerminalDebugLogger.resetForTesting()
        defer { cleanupTraceEnvironment(traceURL) }
        TerminalDebugLogger.setEnabledOverrideForTesting(true)
        TerminalDebugLogger.setLogFileURLForTesting(traceURL)

        TerminalDebugLogger.log("first-message")
        TerminalDebugLogger.log("second-message")
        TerminalDebugLogger.flushForTesting()

        let content = try String(contentsOf: traceURL, encoding: .utf8)
        #expect(content.contains("first-message"))
        #expect(content.contains("second-message"))
        #expect(content.firstRange(of: "first-message")!.lowerBound < content.firstRange(of: "second-message")!.lowerBound)
    }

    @Test
    func burstLoggingRetainsEveryEntry() throws {
        let traceURL = temporaryTraceFileURL()
        TerminalDebugLogger.resetForTesting()
        defer { cleanupTraceEnvironment(traceURL) }
        TerminalDebugLogger.setEnabledOverrideForTesting(true)
        TerminalDebugLogger.setLogFileURLForTesting(traceURL)

        let messageCount = 200
        for index in 0..<messageCount {
            TerminalDebugLogger.log("burst-\(index)")
        }
        TerminalDebugLogger.flushForTesting()

        let content = try String(contentsOf: traceURL, encoding: .utf8)
        for index in 0..<messageCount {
            #expect(content.contains("burst-\(index)"))
        }
    }

    private func temporaryTraceFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-terminal-trace-\(UUID().uuidString).log")
    }

    private func cleanupTraceEnvironment(_ traceURL: URL) {
        TerminalDebugLogger.flushForTesting()
        TerminalDebugLogger.resetForTesting()
        try? FileManager.default.removeItem(at: traceURL)
    }
}
