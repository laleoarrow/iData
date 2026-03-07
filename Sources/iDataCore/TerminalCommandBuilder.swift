import Foundation

public enum TerminalCommandBuilder {
    public enum GzipStreamMode: Equatable {
        case withLoader(String)
        case text
    }

    public struct EmbeddedLaunchCommand: Equatable {
        public let executablePath: String
        public let arguments: [String]

        public init(executablePath: String, arguments: [String]) {
            self.executablePath = executablePath
            self.arguments = arguments
        }
    }

    public static func shellQuoted(_ rawValue: String) -> String {
        let escaped = rawValue.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    public static func makeEmbeddedLaunchCommand(
        visidataExecutable: URL,
        fileURL: URL
    ) -> EmbeddedLaunchCommand {
        guard let gzipMode = gzipStreamMode(for: fileURL) else {
            return EmbeddedLaunchCommand(
                executablePath: visidataExecutable.path,
                arguments: [fileURL.path]
            )
        }

        let executable = shellQuoted(visidataExecutable.path)
        let file = shellQuoted(fileURL.path)
        let loaderArgument: String
        switch gzipMode {
        case let .withLoader(loader):
            loaderArgument = "-f \(loader) "
        case .text:
            loaderArgument = ""
        }
        let script = "exec \(executable) \(loaderArgument)<(gzip -dc -- \(file))"

        return EmbeddedLaunchCommand(
            executablePath: "/bin/zsh",
            arguments: ["-lc", script]
        )
    }

    public static func makeLaunchScript(
        visidataExecutable: URL,
        fileURL: URL
    ) -> String {
        let executable = shellQuoted(visidataExecutable.path)
        let file = shellQuoted(fileURL.path)

        return """
        #!/bin/zsh
        exec \(executable) \(file)
        """
    }

    private static func gzipStreamMode(for fileURL: URL) -> GzipStreamMode? {
        let lowercaseName = fileURL.lastPathComponent.lowercased()

        if lowercaseName.hasSuffix(".csv.gz") {
            return .withLoader("csv")
        }

        if lowercaseName.hasSuffix(".tsv.gz") {
            return .withLoader("tsv")
        }

        if lowercaseName.hasSuffix(".txt.gz") {
            return .text
        }

        return nil
    }
}
