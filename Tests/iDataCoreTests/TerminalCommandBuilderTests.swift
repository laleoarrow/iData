import Foundation
import Testing
@testable import iDataCore

struct TerminalCommandBuilderTests {
    private let temporaryDirectory = TerminalCommandBuilderTestDirectory()

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
    func sniffingPreservesDelimitedAndRawBehavior() throws {
        let cases: [(filename: String, contents: String, expectedPrefix: [String])] = [
            (
                "comma-delimited.data",
                """
                name,value
                first,1
                """,
                ["-f", "csv"]
            ),
            (
                "tab-delimited.data",
                """
                name	value
                first	1
                """,
                ["-f", "tsv"]
            ),
            (
                "space-delimited.data",
                """
                marker allele effect stderr
                rs1 A 0.10 0.02
                """,
                ["-f", "tsv", "-d", " "]
            ),
            (
                "unstructured.data",
                """
                first
                second
                """,
                []
            ),
        ]

        for testCase in cases {
            let fileURL = try makeTemporaryFile(
                named: testCase.filename,
                contents: testCase.contents
            )
            let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
                visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
                fileURL: fileURL
            )

            #expect(command.executablePath == "/Users/test/bin/vd")
            #expect(command.arguments == testCase.expectedPrefix + [fileURL.path])
        }
    }

    @Test
    func sniffingSkipsBlankAndCommentLines() throws {
        let fileURL = try makeTemporaryFile(
            named: "commented.data",
            contents: """

                  # generated table

                name	value
                first	1
                """
        )

        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: fileURL
        )

        #expect(command.arguments == ["-f", "tsv", fileURL.path])
    }

    @Test
    func sniffingOnlyUsesFirstEightSignificantLines() throws {
        let firstEight = (1...8).map { "plain\($0)" }.joined(separator: "\n")
        let laterDelimitedLines = (1...20).map { "column\($0)\tvalue\($0)" }.joined(separator: "\n")
        let fileURL = try makeTemporaryFile(
            named: "late-delimiter.data",
            contents: firstEight + "\n" + laterDelimitedLines
        )

        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: fileURL
        )

        #expect(command.arguments == [fileURL.path])
    }

    @Test
    func sniffingPreservesLossyUTF8Fallback() throws {
        var data = Data("name\tvalue\nfirst\t".utf8)
        data.append(0xFF)
        data.append(contentsOf: Data("\n".utf8))
        let fileURL = try makeTemporaryFile(named: "invalid-utf8.data", data: data)

        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: fileURL
        )

        #expect(command.arguments == ["-f", "tsv", fileURL.path])
    }

    @Test
    func sniffingPreservesEmptyFileBehavior() throws {
        let fileURL = try makeTemporaryFile(named: "empty.data", data: Data())

        let command = TerminalCommandBuilder.makeEmbeddedLaunchCommand(
            visidataExecutable: URL(fileURLWithPath: "/Users/test/bin/vd"),
            fileURL: fileURL
        )

        #expect(command.arguments == [fileURL.path])
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
        try makeTemporaryFile(named: filename, data: Data(contents.utf8))
    }

    private func makeTemporaryFile(named filename: String, data: Data) throws -> URL {
        let directory = temporaryDirectory.url
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL)
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

private final class TerminalCommandBuilderTestDirectory: @unchecked Sendable {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("idata-terminal-command-builder-tests-\(UUID().uuidString)", isDirectory: true)

    init() {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
