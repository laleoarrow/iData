import Foundation
import Testing
@testable import iData
import iDataCore

@MainActor
struct AppModelTests {
    @Test
    func supportedFormatsMatchCurrentFeatureScope() {
        #expect(AppModel.supportedFormatExtensions == ["csv", "tsv", "txt", "json", "jsonl", "xlsx", "csv.gz", "tsv.gz", "txt.gz"])
        #expect(AppModel.supportedFormatHelpText.contains("CSV (.csv)"))
        #expect(AppModel.supportedFormatHelpText.contains("JSON Lines (.jsonl)"))
        #expect(AppModel.supportedFormatHelpText.contains("Excel Workbook (.xlsx)"))
        #expect(AppModel.supportedFormatHelpText.contains("Compressed CSV (.csv.gz)"))
    }

    @Test
    func supportsRequestedFormatsByExtension() {
        #expect(AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/sample.csv")))
        #expect(AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/sample.JSONL")))
        #expect(AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/sample.xlsx")))
        #expect(AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/sample.csv.gz")))
        #expect(AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/sample.TSV.GZ")))
        #expect(AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/sample.txt.gz")))
        #expect(!AppModel.supportsTableFile(URL(fileURLWithPath: "/tmp/sample.md")))
    }

    @Test
    func firstSupportedDroppedFileWins() {
        let unsupported = URL(fileURLWithPath: "/tmp/readme.md")
        let supported = URL(fileURLWithPath: "/tmp/data.tsv")

        #expect(AppModel.firstSupportedFile(in: [unsupported, supported]) == supported)
        #expect(AppModel.firstSupportedFile(in: [unsupported]) == nil)
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
}
