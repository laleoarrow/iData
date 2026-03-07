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
        #expect(command.arguments == ["/Users/test/data.csv"])
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
}
