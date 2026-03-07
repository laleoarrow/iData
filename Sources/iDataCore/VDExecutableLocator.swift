import Foundation

public enum VDExecutableLocator {
    public static func resolve<Checker: ExecutableChecking>(
        explicitPath: String?,
        environmentPath: String,
        checker: Checker
    ) -> URL? {
        if let explicitPath,
           let explicitURL = executableURL(for: explicitPath, checker: checker) {
            return explicitURL
        }

        for directory in environmentPath
            .split(separator: ":")
            .map(String.init)
            .filter({ !$0.isEmpty }) {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent("vd")
                .path

            if let resolved = executableURL(for: candidate, checker: checker) {
                return resolved
            }
        }

        for candidate in fallbackCandidates() {
            if let resolved = executableURL(for: candidate, checker: checker) {
                return resolved
            }
        }

        return nil
    }

    private static func executableURL<Checker: ExecutableChecking>(
        for path: String,
        checker: Checker
    ) -> URL? {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard checker.isExecutableFile(atPath: expandedPath) else {
            return nil
        }

        return URL(fileURLWithPath: expandedPath)
    }

    private static func fallbackCandidates() -> [String] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(homeDirectory)/.local/bin/vd",
            "\(homeDirectory)/bin/vd",
            "/opt/homebrew/bin/vd",
            "/usr/local/bin/vd",
            "/usr/bin/vd",
        ]
    }
}
