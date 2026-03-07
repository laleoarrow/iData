import Foundation
import Testing
@testable import iDataCore

struct TerminalCommandBuilderTests {
    @Test
    func buildsDirectEmbeddedLaunchCommandForRegularFiles() {
        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: URL(fileURLWithPath: "/Users/test/data.csv")
        )

        #expect(command.executablePath == "/Users/test/bin/vd")
        #expect(command.arguments == ["-f", "csv", "/Users/test/data.csv"])
    }

    @Test
    func buildsCSVGzipStreamLaunchCommandWithoutExtracting() {
        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: URL(fileURLWithPath: "/Users/test/data.csv.gz")
        )

        #expect(command.executablePath == "/bin/zsh")
        #expect(command.arguments.count == 2)
        #expect(command.arguments[0] == "-lc")
        #expect(command.arguments[1].contains("gzip -dc -- '/Users/test/data.csv.gz'"))
        #expect(command.arguments[1].contains("'/Users/test/bin/vd' -f csv <("))
    }

    @Test
    func buildsTSVGzipStreamLaunchCommandWithoutExtracting() {
        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: URL(fileURLWithPath: "/Users/test/data.tsv.gz")
        )

        #expect(command.executablePath == "/bin/zsh")
        #expect(command.arguments[1].contains("'/Users/test/bin/vd' -f tsv <("))
    }

    @Test
    func buildsTextGzipStreamLaunchCommandWithoutForcedLoader() {
        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: URL(fileURLWithPath: "/Users/test/data.txt.gz")
        )

        #expect(command.executablePath == "/bin/zsh")
        #expect(command.arguments[1].contains("gzip -dc -- '/Users/test/data.txt.gz'"))
        #expect(command.arguments[1].contains("'/Users/test/bin/vd' <("))
        #expect(!command.arguments[1].contains("-f txt"))
    }

    @Test
    func buildsRawGzipStreamLaunchCommandForUnknownBioinfoSuffix() {
        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: URL(fileURLWithPath: "/Users/test/study.ma.gz")
        )

        #expect(command.executablePath == "/bin/zsh")
        #expect(command.arguments[1].contains("gzip -dc -- '/Users/test/study.ma.gz'"))
        #expect(command.arguments[1].contains("'/Users/test/bin/vd' <("))
        #expect(!command.arguments[1].contains("-f"))
    }

    @Test
    func buildsRawBgzipStreamLaunchCommandForUnknownBioinfoSuffix() {
        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: URL(fileURLWithPath: "/Users/test/variants.bed.bgz")
        )

        #expect(command.executablePath == "/bin/zsh")
        #expect(command.arguments[1].contains("gzip -dc -- '/Users/test/variants.bed.bgz'"))
        #expect(!command.arguments[1].contains("-f"))
    }

    @Test
    func forcesWhitespaceDelimitedTSVForSpaceSeparatedBioinfoFile() throws {
        let fileURL = try makeTemporaryFile(
            named: "study.ma",
            contents: """
            SNP A1 A2 BETA SE P
            rs1 A G 0.10 0.02 1e-4
            rs2 C T -0.04 0.03 0.15
            """
        )

        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: fileURL
        )

        #expect(command.executablePath == "/Users/test/bin/vd")
        #expect(command.arguments == ["-f", "tsv", "-d", " ", fileURL.path])
    }

    @Test
    func forcesWhitespaceDelimitedTSVForCompressedSpaceSeparatedBioinfoFile() throws {
        let fileURL = try makeTemporaryGzipFile(
            named: "study.ma.gz",
            contents: """
            SNP A1 A2 BETA SE P
            rs1 A G 0.10 0.02 1e-4
            rs2 C T -0.04 0.03 0.15
            """
        )

        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: fileURL
        )

        #expect(command.executablePath == "/bin/zsh")
        #expect(command.arguments[1].contains("gzip -dc -- '\(fileURL.path)'"))
        #expect(command.arguments[1].contains("'/Users/test/bin/vd' -f tsv -d ' ' <("))
    }

    @Test
    func buildsQuotedLaunchScript() {
        let script = TerminalCommandBuilder.makeLaunchScript(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: URL(fileURLWithPath: "/Users/test/Data Files/big table.csv")
        )

        #expect(script.contains("'/Users/test/bin/vd'"))
        #expect(script.contains("'/Users/test/Data Files/big table.csv'"))
        #expect(script.contains("exec "))
    }

    @Test
    func escapesSingleQuotesForShell() {
        let escaped = TerminalCommandBuilder.shellQuoted("/tmp/it's.csv")

        #expect(escaped == "'/tmp/it'\"'\"'s.csv'")
    }

    private func makeTemporaryFile(named filename: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(filename)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func makeTemporaryGzipFile(named filename: String, contents: String) throws -> URL {
        let sourceURL = try makeTemporaryFile(named: filename.replacingOccurrences(of: ".gz", with: ""), contents: contents)
        let gzipURL = sourceURL.deletingLastPathComponent().appendingPathComponent(filename)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-c", "--", sourceURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try data.write(to: gzipURL)
        return gzipURL
    }
}
