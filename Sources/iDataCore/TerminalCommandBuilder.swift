import Foundation

public enum TerminalCommandBuilder {
    public enum LoaderHint: Equatable {
        case csv
        case tsv
        case whitespaceSeparated
    }

    public enum GzipStreamMode: Equatable {
        case withLoader(LoaderHint)
        case raw
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
            if let loaderHint = loaderHint(for: fileURL) {
                return EmbeddedLaunchCommand(
                    executablePath: visidataExecutable.path,
                    arguments: regularArguments(for: loaderHint, filePath: fileURL.path)
                )
            }

            return EmbeddedLaunchCommand(
                executablePath: visidataExecutable.path,
                arguments: [fileURL.path]
            )
        }

        let executable = shellQuoted(visidataExecutable.path)
        let file = shellQuoted(fileURL.path)
        let loaderArgument: String
        switch gzipMode {
        case let .withLoader(loaderHint):
            loaderArgument = shellLoaderArguments(for: loaderHint)
        case .raw:
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

        guard
            lowercaseName.hasSuffix(".gz") ||
                lowercaseName.hasSuffix(".bgz") ||
                lowercaseName.hasSuffix(".bgzf")
        else {
            return nil
        }

        if let explicitHint = explicitLoaderHint(for: lowercaseName) {
            return .withLoader(explicitHint)
        }

        if let sniffedHint = sniffedLoaderHint(for: fileURL, compressed: true) {
            return .withLoader(sniffedHint)
        }

        return .raw
    }

    private static func loaderHint(for fileURL: URL) -> LoaderHint? {
        let lowercaseName = fileURL.lastPathComponent.lowercased()

        if let explicitHint = explicitLoaderHint(for: lowercaseName) {
            return explicitHint
        }

        return sniffedLoaderHint(for: fileURL, compressed: false)
    }

    private static func explicitLoaderHint(for lowercaseName: String) -> LoaderHint? {
        if
            lowercaseName.hasSuffix(".csv.gz") ||
                lowercaseName.hasSuffix(".csv") ||
                lowercaseName.hasSuffix(".csv.bgz") ||
                lowercaseName.hasSuffix(".csv.bgzf")
        {
            return .csv
        }

        if
            lowercaseName.hasSuffix(".tsv.gz") ||
                lowercaseName.hasSuffix(".tsv") ||
                lowercaseName.hasSuffix(".tsv.bgz") ||
                lowercaseName.hasSuffix(".tsv.bgzf")
        {
            return .tsv
        }

        return nil
    }

    private static func regularArguments(for loaderHint: LoaderHint, filePath: String) -> [String] {
        switch loaderHint {
        case .csv:
            return ["-f", "csv", filePath]
        case .tsv:
            return ["-f", "tsv", filePath]
        case .whitespaceSeparated:
            return ["-f", "tsv", "-d", " ", filePath]
        }
    }

    private static func shellLoaderArguments(for loaderHint: LoaderHint) -> String {
        switch loaderHint {
        case .csv:
            return "-f csv "
        case .tsv:
            return "-f tsv "
        case .whitespaceSeparated:
            return "-f tsv -d ' ' "
        }
    }

    private static func sniffedLoaderHint(for fileURL: URL, compressed: Bool) -> LoaderHint? {
        guard let sample = sampleText(for: fileURL, compressed: compressed) else {
            return nil
        }

        let lines = sample
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !lines.isEmpty else {
            return nil
        }

        let limitedLines = Array(lines.prefix(8))
        let tabMatches = limitedLines.filter { $0.contains("\t") }.count
        if tabMatches >= 2 {
            return .tsv
        }

        let commaMatches = limitedLines.filter { $0.contains(",") && !$0.contains("\t") }.count
        if commaMatches >= 2 {
            return .csv
        }

        let tokenCounts = limitedLines.map { whitespaceTokenCount(in: $0) }
        if
            limitedLines.count >= 2,
            let minCount = tokenCounts.min(),
            let maxCount = tokenCounts.max(),
            minCount >= 3,
            maxCount - minCount <= 2,
            limitedLines.allSatisfy({ $0.contains(" ") && !$0.contains(",") && !$0.contains("\t") })
        {
            return .whitespaceSeparated
        }

        return nil
    }

    private static func sampleText(for fileURL: URL, compressed: Bool) -> String? {
        let maxSampleBytes = 32 * 1024

        if compressed {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
            process.arguments = ["-dc", "--", fileURL.path]
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                let data = try pipe.fileHandleForReading.read(upToCount: maxSampleBytes) ?? Data()
                if process.isRunning {
                    process.terminate()
                }
                process.waitUntilExit()
                guard !data.isEmpty else {
                    return nil
                }
                return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            } catch {
                return nil
            }
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }

        defer {
            try? handle.close()
        }

        let data = try? handle.read(upToCount: maxSampleBytes)
        guard let data, !data.isEmpty else {
            return nil
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func whitespaceTokenCount(in line: String) -> Int {
        line.split(whereSeparator: \.isWhitespace).count
    }
}
