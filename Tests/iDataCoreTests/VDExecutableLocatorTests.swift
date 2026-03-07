import Foundation
import Testing
@testable import iDataCore

struct VDExecutableLocatorTests {
    @Test
    func explicitExecutablePathWins() {
        let checker = FakeExecutableChecker(executablePaths: [
            "/custom/bin/vd",
            "/usr/local/bin/vd",
        ])

        let resolved = VDExecutableLocator.resolve(
            explicitPath: "/custom/bin/vd",
            environmentPath: "/usr/local/bin:/opt/homebrew/bin",
            checker: checker
        )

        #expect(resolved?.path == "/custom/bin/vd")
    }

    @Test
    func fallsBackToPathSearch() {
        let checker = FakeExecutableChecker(executablePaths: [
            "/opt/homebrew/bin/vd",
        ])

        let resolved = VDExecutableLocator.resolve(
            explicitPath: nil,
            environmentPath: "/usr/local/bin:/opt/homebrew/bin",
            checker: checker
        )

        #expect(resolved?.path == "/opt/homebrew/bin/vd")
    }

    @Test
    func returnsNilWhenExecutableIsMissing() {
        let checker = FakeExecutableChecker(executablePaths: [])

        let resolved = VDExecutableLocator.resolve(
            explicitPath: nil,
            environmentPath: "/usr/local/bin:/opt/homebrew/bin",
            checker: checker
        )

        #expect(resolved == nil)
    }

    @Test
    func fallsBackToCommonUserInstallLocations() {
        let expectedPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/vd"
        let checker = FakeExecutableChecker(executablePaths: [expectedPath])

        let resolved = VDExecutableLocator.resolve(
            explicitPath: nil,
            environmentPath: "/usr/bin",
            checker: checker
        )

        #expect(resolved?.path == expectedPath)
    }
}

private struct FakeExecutableChecker: ExecutableChecking {
    let executablePaths: Set<String>

    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}
