import Foundation
import Testing
@testable import iData
import iDataCore

@MainActor
struct AppModelTests {
    @Test
    func formatExamplesDescribeCommonCases() {
        #expect(AppModel.supportedFormatHelpText.contains("CSV (.csv)"))
        #expect(AppModel.supportedFormatHelpText.contains("Excel Workbook (.xlsx)"))
        #expect(AppModel.supportedFormatHelpText.contains("JSON Lines (.jsonl)"))
        #expect(AppModel.supportedFormatHelpText.contains("MA / GWAS (.ma)"))
        #expect(AppModel.supportedFormatHelpText.contains("Compressed GZip (.gz)"))
    }

    @Test
    func acceptsArbitraryBioinformaticsSuffixes() {
        #expect(AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/sample.csv")))
        #expect(AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/study.ma")))
        #expect(AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/summary.weird_suffix")))
        #expect(AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/variants.bed.bgz")))
        #expect(!AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/folder/", isDirectory: true)))
    }

    @Test
    func firstRegularFileWinsOverFolderDuringDrop() {
        let folder = URL(fileURLWithPath: "/tmp/results/", isDirectory: true)
        let supported = URL(fileURLWithPath: "/tmp/study.ma")

        #expect(AppModel.firstSupportedFile(in: [folder, supported]) == supported)
        #expect(AppModel.firstSupportedFile(in: [folder]) == nil)
    }

    @Test
    func removingRecentFileOnlyUpdatesSidebarHistory() {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = RecentFilesStore(defaults: defaults)
        let first = URL(fileURLWithPath: "/tmp/one.csv")
        let second = URL(fileURLWithPath: "/tmp/two.csv")
        store.record(second, maxCount: AppModel.recentFilesLimit)
        store.record(first, maxCount: AppModel.recentFilesLimit)

        let model = AppModel(defaults: defaults, recentFilesStore: store)
        let session = VisiDataSessionController()
        model.activeSession = session
        model.lastOpenedFile = first

        model.removeRecentFile(first)

        #expect(model.recentFiles == [second])
        #expect(model.activeSession === session)
        #expect(model.lastOpenedFile == first)
    }

    @Test
    func clearingRecentFilesOnlyUpdatesSidebarHistory() {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = RecentFilesStore(defaults: defaults)
        let first = URL(fileURLWithPath: "/tmp/one.csv")
        let second = URL(fileURLWithPath: "/tmp/two.csv")
        store.record(second, maxCount: AppModel.recentFilesLimit)
        store.record(first, maxCount: AppModel.recentFilesLimit)

        let model = AppModel(defaults: defaults, recentFilesStore: store)
        let session = VisiDataSessionController()
        model.activeSession = session
        model.lastOpenedFile = first

        model.clearRecentFiles()

        #expect(model.recentFiles.isEmpty)
        #expect(model.activeSession === session)
        #expect(model.lastOpenedFile == first)
    }

    @Test
    func missingVisiDataMessageIncludesInstallGuidance() {
        let message = LaunchError.visiDataNotFound.errorDescription ?? ""

        #expect(message.contains("brew install visidata"))
        #expect(message.contains("Preferences"))
    }

    @Test
    func inactiveSessionDoesNotQualifyAsDisplayedSession() {
        let model = AppModel()
        model.activeSession = VisiDataSessionController()

        #expect(model.displayedSession == nil)
    }

    @Test
    func dependencyStateUsesResolvedExecutablePath() {
        let checker = FakeExecutableChecker(executablePaths: ["/opt/homebrew/bin/vd"])
        let model = AppModel(
            executableChecker: checker,
            environmentPathProvider: { "/usr/bin:/opt/homebrew/bin" }
        )

        #expect(model.visiDataDependencyState == .available(path: "/opt/homebrew/bin/vd"))
        #expect(model.visiDataDependencySummary.contains("/opt/homebrew/bin/vd"))
    }

    @Test
    func dependencyStateReportsMissingExecutable() {
        let checker = FakeExecutableChecker(executablePaths: [])
        let model = AppModel(
            executableChecker: checker,
            environmentPathProvider: { "/usr/bin" }
        )

        #expect(model.visiDataDependencyState == .missing)
        #expect(model.visiDataDependencySummary.contains("brew install visidata"))
    }

    @Test
    func updaterStartsUnconfiguredWithoutSparkleKeys() {
        let updater = AppUpdaterController()

        #expect(!updater.isConfigured)
        #expect(updater.statusMessage.contains("Sparkle") || updater.statusMessage.contains("GitHub Releases"))
    }
}

private struct FakeExecutableChecker: ExecutableChecking {
    let executablePaths: Set<String>

    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}
