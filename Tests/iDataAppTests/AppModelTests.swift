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
    func smallSupportedFileForwardsToAlternateApplication() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-small-forward-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let target = URL(fileURLWithPath: "/tmp/small.xlsx")
        let excel = try makeFakeApplicationHandler(
            in: tempRoot,
            appFolderName: "Microsoft Excel.app",
            bundleIdentifier: "com.microsoft.Excel",
            displayName: "Microsoft Excel"
        )
        let opener = RecordingExternalFileOpener()

        let model = AppModel(
            defaults: defaults,
            externalFileOpener: opener,
            alternateApplicationResolver: { _, _, _ in excel },
            fileSizeProvider: { _ in 10 }
        )

        let action = model.routeExternalFile(target)

        #expect(action == .forwardedToAlternateApp(appName: "Microsoft Excel"))
        #expect(opener.openedFileURL?.standardizedFileURL == target.standardizedFileURL)
        #expect(opener.openedApplicationURL == excel.url)
        #expect(model.activeSession == nil)
        #expect(model.errorMessage == nil)
    }

    @Test
    func preferredSmallFileApplicationOverridesResolverForSmallFiles() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-small-preferred-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let target = URL(fileURLWithPath: "/tmp/small.csv")
        let excel = try makeFakeApplicationHandler(
            in: tempRoot,
            appFolderName: "Microsoft Excel.app",
            bundleIdentifier: "com.microsoft.Excel",
            displayName: "Microsoft Excel"
        )
        let wps = try makeFakeApplicationHandler(
            in: tempRoot,
            appFolderName: "WPS Office.app",
            bundleIdentifier: "cn.wps.Office",
            displayName: "WPS Office"
        )
        let opener = RecordingExternalFileOpener()

        let model = AppModel(
            defaults: defaults,
            externalFileOpener: opener,
            alternateApplicationResolver: { _, _, _ in excel },
            fileSizeProvider: { _ in 10 }
        )
        model.setPreferredSmallFileApplication(wps)

        let action = model.routeExternalFile(target)

        #expect(action == .forwardedToAlternateApp(appName: "WPS Office"))
        #expect(opener.openedApplicationURL == wps.url)
    }

    @Test
    func stalePreferredSmallFileApplicationFallsBackToResolver() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-small-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let target = URL(fileURLWithPath: "/tmp/small.csv")
        let staleWPS = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/Missing WPS.app"),
            bundleIdentifier: "cn.wps.Office",
            displayName: "WPS Office"
        )
        let excel = try makeFakeApplicationHandler(
            in: tempRoot,
            appFolderName: "Microsoft Excel.app",
            bundleIdentifier: "com.microsoft.Excel",
            displayName: "Microsoft Excel"
        )
        let opener = RecordingExternalFileOpener(failingApplicationURLs: [staleWPS.url])

        let model = AppModel(
            defaults: defaults,
            externalFileOpener: opener,
            alternateApplicationResolver: { _, _, _ in excel },
            fileSizeProvider: { _ in 10 }
        )
        model.setPreferredSmallFileApplication(staleWPS)

        let action = model.routeExternalFile(target)

        #expect(action == .forwardedToAlternateApp(appName: "Microsoft Excel"))
        #expect(opener.openedApplicationURL == excel.url)
    }

    @Test
    func fileLargerThanThresholdStaysInsideIData() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-open-large-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let target = tempRoot.appendingPathComponent("large.xlsx")
        try Data("ok".utf8).write(to: target)

        let opener = RecordingExternalFileOpener()
        let model = AppModel(
            defaults: defaults,
            externalFileOpener: opener,
            alternateApplicationResolver: { _, _, _ in nil },
            fileSizeProvider: { _ in AppModel.largeFileOpenThresholdBytes + 1 }
        )
        model.vdExecutablePath = launcher.path
        defer {
            model.activeSession?.terminate()
        }

        let action = model.routeExternalFile(target)

        #expect(action == .openedInIData)
        #expect(opener.openedFileURL == nil)
        #expect(model.activeSession?.currentFileURL?.standardizedFileURL == target.standardizedFileURL)
        #expect(model.errorMessage == nil)
    }

    @Test
    func smallSupportedFileShowsErrorWhenNoAlternateApplicationExists() {
        let target = URL(fileURLWithPath: "/tmp/no-alt.csv")
        let model = AppModel(
            externalFileOpener: RecordingExternalFileOpener(),
            alternateApplicationResolver: { _, _, _ in nil },
            fileSizeProvider: { _ in 10 }
        )

        let action = model.routeExternalFile(target)

        #expect(action == .presentedError)
        #expect(model.errorMessage?.contains("non-iData app") == true || model.errorMessage?.contains("非 iData 应用") == true)
    }

    @Test
    func thresholdBoundaryForwardsExactlyOneHundredMiB() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-threshold-forward-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let target = URL(fileURLWithPath: "/tmp/boundary.tsv")
        let numbers = try makeFakeApplicationHandler(
            in: tempRoot,
            appFolderName: "Numbers.app",
            bundleIdentifier: "com.apple.Numbers",
            displayName: "Numbers"
        )
        let opener = RecordingExternalFileOpener()
        let expectedThreshold = Int64(100 * 1024 * 1024)
        let model = AppModel(
            externalFileOpener: opener,
            alternateApplicationResolver: { _, _, _ in numbers },
            fileSizeProvider: { _ in expectedThreshold }
        )

        let action = model.routeExternalFile(target)

        #expect(action == .forwardedToAlternateApp(appName: "Numbers"))
        #expect(opener.openedApplicationURL == numbers.url)
    }

    @Test
    func fileLargerThanOneHundredMiBStaysInsideIData() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-open-large-100m-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let target = tempRoot.appendingPathComponent("large-101m.xlsx")
        try Data("ok".utf8).write(to: target)

        let opener = RecordingExternalFileOpener()
        let expectedThreshold = Int64(100 * 1024 * 1024)
        let model = AppModel(
            defaults: defaults,
            externalFileOpener: opener,
            alternateApplicationResolver: { _, _, _ in nil },
            fileSizeProvider: { _ in expectedThreshold + 1 }
        )
        model.vdExecutablePath = launcher.path
        defer {
            model.activeSession?.terminate()
        }

        let action = model.routeExternalFile(target)

        #expect(action == .openedInIData)
        #expect(opener.openedFileURL == nil)
        #expect(model.activeSession?.currentFileURL?.standardizedFileURL == target.standardizedFileURL)
    }

    @Test
    func fileSizeUsesLogicalLengthForSparseFiles() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-sparse-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let target = tempRoot.appendingPathComponent("large.csv")
        let logicalSize = AppModel.largeFileOpenThresholdBytes + 1
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let handle = try FileHandle(forWritingTo: target)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: UInt64(logicalSize - 1))
        try handle.write(contentsOf: Data("\n".utf8))

        #expect(AppModel.fileSizeInBytes(for: target) == logicalSize)
    }

    @Test
    func compressedSmallFileAlwaysStaysInsideIData() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-open-small-gzip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let target = tempRoot.appendingPathComponent("small.tsv.gz")
        try Data("ok".utf8).write(to: target)

        let excel = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/Microsoft Excel.app"),
            bundleIdentifier: "com.microsoft.Excel",
            displayName: "Microsoft Excel"
        )
        let opener = RecordingExternalFileOpener()
        let model = AppModel(
            defaults: defaults,
            externalFileOpener: opener,
            alternateApplicationResolver: { _, _, _ in excel },
            fileSizeProvider: { _ in 1024 }
        )
        model.vdExecutablePath = launcher.path
        model.setPreferredSmallFileApplication(excel)
        defer {
            model.activeSession?.terminate()
        }

        let action = model.routeExternalFile(target)

        #expect(action == .openedInIData)
        #expect(opener.openedFileURL == nil)
        #expect(model.activeSession?.currentFileURL?.standardizedFileURL == target.standardizedFileURL)
    }

    @Test
    func forwardedExternalOpenKeepsAppInBackground() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-external-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let target = URL(fileURLWithPath: "/tmp/background.csv")
        let opener = RecordingExternalFileOpener()
        let textEdit = try makeFakeApplicationHandler(
            in: tempRoot,
            appFolderName: "TextEdit.app",
            bundleIdentifier: "com.apple.TextEdit",
            displayName: "TextEdit"
        )
        let model = AppModel(
            externalFileOpener: opener,
            alternateApplicationResolver: { _, _, _ in textEdit },
            fileSizeProvider: { _ in 1024 }
        )

        let decision = model.handleExternalFileOpen([target])

        #expect(decision == .stayBackground)
        #expect(opener.openedApplicationURL == textEdit.url)
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
    func pinningRecentFileMovesItToTop() {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = RecentFilesStore(defaults: defaults)
        let first = URL(fileURLWithPath: "/tmp/one.csv")
        let second = URL(fileURLWithPath: "/tmp/two.csv")
        let third = URL(fileURLWithPath: "/tmp/three.csv")
        store.record(third, maxCount: AppModel.recentFilesLimit)
        store.record(second, maxCount: AppModel.recentFilesLimit)
        store.record(first, maxCount: AppModel.recentFilesLimit)

        let model = AppModel(defaults: defaults, recentFilesStore: store)
        model.togglePinnedRecentFile(second)

        #expect(model.isPinnedRecentFile(second))
        #expect(model.recentFiles == [second, first, third])
    }

    @Test
    func removingPinnedRecentFileClearsPinState() {
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
        model.togglePinnedRecentFile(second)
        model.removeRecentFile(second)

        #expect(!model.isPinnedRecentFile(second))
        #expect(model.recentFiles == [first])
    }

    @Test
    func missingVisiDataMessageIncludesInstallGuidance() {
        let message = LaunchError.visiDataNotFound.errorDescription ?? ""

        #expect(message.contains("one-click"))
        #expect(message.contains("pipx install visidata"))
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
    func sessionDisplayPolicyKeepsFailedSessionVisible() {
        #expect(AppModel.shouldDisplaySessionDetail(hasCurrentFile: true, isRunning: true, hasError: false))
        #expect(AppModel.shouldDisplaySessionDetail(hasCurrentFile: true, isRunning: false, hasError: true))
        #expect(!AppModel.shouldDisplaySessionDetail(hasCurrentFile: true, isRunning: false, hasError: false))
        #expect(!AppModel.shouldDisplaySessionDetail(hasCurrentFile: false, isRunning: true, hasError: true))
    }

    @Test
    func failedSessionRemainsDisplayedSoGuidanceStaysVisible() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-appmodel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let inputFile = tempRoot.appendingPathComponent("report.xlsx")
        try Data("placeholder".utf8).write(to: inputFile)

        let launcher = tempRoot.appendingPathComponent("fake-vd.zsh")
        try makeImmediateExitLauncher(at: launcher, exitCode: 9)

        let session = VisiDataSessionController()
        try session.open(fileURL: inputFile, explicitVDPath: launcher.path)

        let model = AppModel()
        model.activeSession = session

        let didFail = await waitForSessionFailure(session, timeoutNanoseconds: 30_000_000_000)

        #expect(didFail)
        #expect(model.displayedSession === session)
        #expect(session.errorMessage?.contains("openpyxl") == true)
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
        #expect(model.visiDataDependencySummary.contains("one-click"))
        #expect(model.visiDataDependencySummary.contains("pipx install visidata"))
        #expect(model.visiDataDependencySummary.contains("brew install visidata"))
    }

    @Test
    func dependencySummaryLocalizesToChinese() {
        let checker = FakeExecutableChecker(executablePaths: [])
        let model = AppModel(
            executableChecker: checker,
            environmentPathProvider: { "/usr/bin" },
            preferredLanguagesProvider: { ["zh-Hans-CN"] }
        )

        #expect(model.visiDataDependencySummary.contains("未找到"))
        #expect(model.visiDataDependencySummary.contains("一键配置"))
        #expect(model.visiDataDependencySummary.contains("pipx install visidata"))
        #expect(model.visiDataDependencySummary.contains("偏好设置"))
    }

    @Test
    func supportedFormatLocalizedDisplayNameSwitchesToChinese() {
        let excel = AppModel.supportedFormats.first { $0.fileExtension == "xlsx" }
        let gzip = AppModel.supportedFormats.first { $0.fileExtension == "gz" }

        #expect(excel?.localizedDisplayName(for: .english) == "Excel Workbook")
        #expect(excel?.localizedDisplayName(for: .chinese) == "Excel 工作簿")
        #expect(gzip?.localizedDisplayName(for: .chinese) == "GZip 压缩文件")
    }

    @Test
    func xlsxDependencyGuidanceMentionsOpenpyxl() {
        let guidance = AppModel.visiDataFormatDependencyGuidance(
            for: URL(fileURLWithPath: "/tmp/report.xlsx"),
            language: .english
        )

        #expect(guidance?.contains(".xlsx") == true)
        #expect(guidance?.contains("openpyxl") == true)
        #expect(guidance?.contains("pipx inject visidata openpyxl") == true)
    }

    @Test
    func xlsDependencyGuidanceMentionsXlrd() {
        let guidance = AppModel.visiDataFormatDependencyGuidance(
            for: URL(fileURLWithPath: "/tmp/report.xls"),
            language: .english
        )

        #expect(guidance?.contains(".xls") == true)
        #expect(guidance?.contains("xlrd") == true)
        #expect(guidance?.contains("pipx inject visidata xlrd") == true)
    }

    @Test
    func xlsbDependencyGuidanceMentionsPyxlsb() {
        let guidance = AppModel.visiDataFormatDependencyGuidance(
            for: URL(fileURLWithPath: "/tmp/report.xlsb"),
            language: .english
        )

        #expect(guidance?.contains(".xlsb") == true)
        #expect(guidance?.contains("pyxlsb") == true)
        #expect(guidance?.contains("pipx inject visidata pyxlsb") == true)
    }

    @Test
    func parquetDependencyGuidanceMentionsOnlyPyarrow() {
        let guidance = AppModel.visiDataFormatDependencyGuidance(
            for: URL(fileURLWithPath: "/tmp/table.parquet"),
            language: .english
        )

        #expect(guidance?.contains(".parquet") == true)
        #expect(guidance?.contains("pyarrow") == true)
        #expect(guidance?.contains("pipx inject visidata pyarrow") == true)
        #expect(guidance?.contains("pandas") == false)
    }

    @Test
    func compressedWorkbookDependencyGuidanceUsesNestedSuffix() {
        let guidance = AppModel.visiDataFormatDependencyGuidance(
            for: URL(fileURLWithPath: "/tmp/report.xlsx.gz"),
            language: .english
        )

        #expect(guidance?.contains(".xlsx") == true)
        #expect(guidance?.contains("openpyxl") == true)
    }

    @Test
    func csvHasNoExtraDependencyGuidance() {
        let guidance = AppModel.visiDataFormatDependencyGuidance(
            for: URL(fileURLWithPath: "/tmp/table.csv"),
            language: .english
        )

        #expect(guidance == nil)
    }

    @Test
    func formatDependencyGuidanceRemainsStableUnderLargeFilenameSet() {
        let baseDirectory = "/tmp/idata-guidance-stress"
        let cases: [(suffix: String, shouldMatch: Bool)] = [
            ("report.xlsx", true),
            ("report.XLSX.GZ", true),
            ("report.xls", true),
            ("report.xlsb.bgz", true),
            ("dataset.parquet", true),
            ("dataset.parquet.bgzf", true),
            ("sheet.ods", true),
            ("stream.arrow", true),
            ("stream.arrows.gz", true),
            ("table.csv", false),
            ("table.tsv.gz", false),
            ("notes.txt", false),
            ("archive.zip", false),
        ]

        var matched = 0
        var unmatched = 0

        for iteration in 0..<2_000 {
            let testCase = cases[iteration % cases.count]
            let url = URL(fileURLWithPath: "\(baseDirectory)/\(iteration)-\(testCase.suffix)")
            let guidance = AppModel.visiDataFormatDependencyGuidance(for: url, language: .english)

            if testCase.shouldMatch {
                #expect(guidance != nil)
                matched += 1
            } else {
                #expect(guidance == nil)
                unmatched += 1
            }
        }

        #expect(matched > 0)
        #expect(unmatched > 0)
    }

    @Test
    func preferredRestoreApplicationReturnsNilWithoutStoredPreviousDefault() {
        let chosen = preferredRestoreApplication(
            storedPreviousDefault: nil
        )

        #expect(chosen == nil)
    }

    @Test
    func preferredRestoreApplicationFallsBackToFirstNonIDataCandidate() {
        let assumedIDataBundleIdentifier = Bundle.main.bundleIdentifier ?? "io.github.leoarrow.idata"
        let textEdit = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/TextEdit.app"),
            bundleIdentifier: "com.apple.TextEdit",
            displayName: "TextEdit"
        )
        let numbers = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/Numbers.app"),
            bundleIdentifier: "com.apple.Numbers",
            displayName: "Numbers"
        )

        let chosen = preferredRestoreApplication(
            storedPreviousDefault: nil,
            fallbackCandidates: [
                DefaultApplicationHandler(
                    url: URL(fileURLWithPath: "/Applications/iData.app"),
                    bundleIdentifier: assumedIDataBundleIdentifier,
                    displayName: "iData"
                ),
                textEdit,
                numbers,
            ]
        )

        #expect(chosen == textEdit)
    }

    @Test
    func preferredRestoreApplicationIgnoresStoredIDataHandler() {
        let assumedIDataBundleIdentifier = Bundle.main.bundleIdentifier ?? "io.github.leoarrow.idata"
        let textEdit = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/TextEdit.app"),
            bundleIdentifier: "com.apple.TextEdit",
            displayName: "TextEdit"
        )

        let chosen = preferredRestoreApplication(
            storedPreviousDefault: DefaultApplicationHandler(
                url: URL(fileURLWithPath: "/Applications/iData.app"),
                bundleIdentifier: assumedIDataBundleIdentifier,
                displayName: "iData"
            ),
            fallbackCandidates: [textEdit]
        )

        #expect(chosen == textEdit)
    }

    @Test
    func preferredRestoreApplicationPrefersStoredPreviousDefault() {
        let stored = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/Numbers.app"),
            bundleIdentifier: "com.apple.Numbers",
            displayName: "Numbers"
        )

        let chosen = preferredRestoreApplication(
            storedPreviousDefault: stored
        )

        #expect(chosen == stored)
    }

    @Test
    func preferredSmallFileOpenApplicationPrefersWPSThenExcelBeforeStoredDefault() {
        let stored = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/Numbers.app"),
            bundleIdentifier: "com.apple.Numbers",
            displayName: "Numbers"
        )
        let excel = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/Microsoft Excel.app"),
            bundleIdentifier: "com.microsoft.Excel",
            displayName: "Microsoft Excel"
        )
        let wps = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/WPS Office.app"),
            bundleIdentifier: "cn.wps.Office",
            displayName: "WPS Office"
        )

        let chosen = preferredSmallFileOpenApplication(
            storedPreviousDefault: stored,
            fallbackCandidates: [stored, excel, wps]
        )

        #expect(chosen == wps)
    }

    @Test
    func preferredSmallFileOpenApplicationFallsBackToExcelWhenWPSMissing() {
        let stored = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/Numbers.app"),
            bundleIdentifier: "com.apple.Numbers",
            displayName: "Numbers"
        )
        let excel = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/Microsoft Excel.app"),
            bundleIdentifier: "com.microsoft.Excel",
            displayName: "Microsoft Excel"
        )

        let chosen = preferredSmallFileOpenApplication(
            storedPreviousDefault: stored,
            fallbackCandidates: [stored, excel]
        )

        #expect(chosen == excel)
    }

    @Test
    func settledIDataDefaultStateWaitsForDelayedRestorePropagation() async {
        final class Probe: @unchecked Sendable {
            private var readings: [Bool]

            init(_ readings: [Bool]) {
                self.readings = readings
            }

            func current(_ fileExtension: String) -> Bool {
                _ = fileExtension
                guard !readings.isEmpty else {
                    return false
                }

                if readings.count == 1 {
                    return readings[0]
                }

                return readings.removeFirst()
            }
        }

        let probe = Probe([true, true, false])

        let settled = await settledIDataDefaultState(
            forExtension: "csv",
            expectedIsDefault: false,
            afterRequestSucceeded: true,
            checker: probe.current(_:),
            maxAttempts: 3,
            pollIntervalNanoseconds: 0
        )

        #expect(!settled)
    }

    @Test
    func settledIDataDefaultStateLeavesStatusUnchangedWhenPropagationNeverFinishes() async {
        final class Probe: @unchecked Sendable {
            private var readings: [Bool]

            init(_ readings: [Bool]) {
                self.readings = readings
            }

            func current(_ fileExtension: String) -> Bool {
                _ = fileExtension
                guard !readings.isEmpty else {
                    return false
                }

                if readings.count == 1 {
                    return readings[0]
                }

                return readings.removeFirst()
            }
        }

        let probe = Probe([true, true, true])

        let settled = await settledIDataDefaultState(
            forExtension: "tsv",
            expectedIsDefault: false,
            afterRequestSucceeded: true,
            checker: probe.current(_:),
            maxAttempts: 2,
            pollIntervalNanoseconds: 0
        )

        #expect(settled)
    }

    @Test
    func updaterStartsUnconfiguredWithoutSparkleKeys() {
        let updater = AppUpdaterController()

        #expect(!updater.isConfigured)
        #expect(updater.statusMessage.contains("Sparkle") || updater.statusMessage.contains("GitHub Releases"))
    }

    @Test
    func updaterStatusMessageLocalizesToChinesePreference() {
        let previous = UserDefaults.standard.string(forKey: AppModel.appLanguagePreferenceKey)
        UserDefaults.standard.set(AppModel.AppLanguagePreference.chinese.rawValue, forKey: AppModel.appLanguagePreferenceKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: AppModel.appLanguagePreferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppModel.appLanguagePreferenceKey)
            }
        }

        let updater = AppUpdaterController()

        #expect(updater.statusMessage.contains("自动更新") || updater.statusMessage.contains("GitHub 发布页面"))
    }

    @Test
    func appVersionSummaryOmitsBuildNumber() {
        let model = AppModel()

        #expect(model.appVersionSummary.starts(with: "v"))
        #expect(!model.appVersionSummary.localizedCaseInsensitiveContains("build"))
        #expect(!model.appVersionSummary.contains("·"))
    }

    @Test
    func versionDisplayNeverShowsBuildNumber() {
        let model = AppModel()

        #expect(model.appVersionDisplay(revealingBuild: false) == model.appVersionSummary)
        #expect(model.appVersionDisplay(revealingBuild: true) == model.appVersionSummary)
        #expect(!model.appVersionDisplay(revealingBuild: true).contains("("))
    }

    @Test
    func reduceAnimationsPreferencePersists() {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let model = AppModel(defaults: defaults)
        #expect(model.reduceAnimations == false)

        model.reduceAnimations = true

        let reloadedModel = AppModel(defaults: defaults)
        #expect(reloadedModel.reduceAnimations == true)
        #expect(reloadedModel.animationsEnabled == false)
    }

    @Test
    func sidebarCollapsePreferencePersists() {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let model = AppModel(defaults: defaults)
        #expect(model.isSidebarCollapsed == false)

        model.setSidebarCollapsed(true)

        let reloadedModel = AppModel(defaults: defaults)
        #expect(reloadedModel.isSidebarCollapsed == true)
    }

    @Test
    func collapsedRecentFileBadgeTextUsesUppercasedLeadingCharacter() {
        #expect(AppModel.collapsedRecentFileBadgeText(for: URL(fileURLWithPath: "/tmp/report.tsv")) == "R")
        #expect(AppModel.collapsedRecentFileBadgeText(for: URL(fileURLWithPath: "/tmp/αlpha.csv")) == "Α")
        #expect(AppModel.collapsedRecentFileBadgeText(for: URL(fileURLWithPath: "/tmp/.hidden")) == ".")
    }

    @Test
    func associationExtensionUsesFinalSuffixComponent() {
        #expect(AppModel.associationExtension(for: "csv") == "csv")
        #expect(AppModel.associationExtension(for: "barcodes.tsv") == "tsv")
        #expect(AppModel.associationExtension(for: ".bgz") == "bgz")
        #expect(AppModel.associationExtension(for: "  MA  ") == "ma")
        #expect(AppModel.associationExtension(for: "") == "")
    }

    @Test
    func customAssociationInputValidationRequiresNonEmptySuffix() {
        #expect(!AppModel.canSetAssociationExtensionInput(""))
        #expect(!AppModel.canSetAssociationExtensionInput("   .   "))
        #expect(AppModel.canSetAssociationExtensionInput(" .vcf "))
        #expect(AppModel.canSetAssociationExtensionInput("barcodes.tsv"))
    }

    @Test
    func previousDefaultAssociationHandlersReloadFromDefaults() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let persistedMapping = [
            "csv": [
                "url": "/Applications/Numbers.app",
                "bundleIdentifier": "com.apple.Numbers",
                "displayName": "Numbers",
            ],
        ]
        defaults.set(
            try JSONEncoder().encode(persistedMapping),
            forKey: "previousDefaultAppsByExtension"
        )

        let model = AppModel(defaults: defaults)
        let restoredMapping = Mirror(reflecting: model)
            .children
            .first(where: { $0.label == "previousDefaultAppByExtension" })?
            .value
        let restoredDescription = String(describing: restoredMapping)

        #expect(restoredDescription.contains("csv"))
        #expect(restoredDescription.contains("com.apple.Numbers"))
    }

    @Test
    func preferredSmallFileApplicationReloadsFromDefaults() {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let wps = DefaultApplicationHandler(
            url: URL(fileURLWithPath: "/Applications/WPS Office.app"),
            bundleIdentifier: "cn.wps.Office",
            displayName: "WPS Office"
        )

        let model = AppModel(defaults: defaults)
        model.setPreferredSmallFileApplication(wps)

        let reloadedModel = AppModel(defaults: defaults)
        #expect(reloadedModel.preferredSmallFileApplication == wps)
    }

    @Test
    func collapsedSidebarHeaderActionRequiresCommandForClearAll() {
        #expect(AppModel.collapsedSidebarHeaderAction(hasRecentFiles: true, isCommandPressed: false) == .expand)
        #expect(AppModel.collapsedSidebarHeaderAction(hasRecentFiles: true, isCommandPressed: true) == .clearAll)
        #expect(AppModel.collapsedSidebarHeaderAction(hasRecentFiles: false, isCommandPressed: true) == .expand)
    }

    @Test
    func tutorialStepsCoverCoreBeginnerWorkflow() {
        let model = AppModel(preferredLanguagesProvider: { ["en-US"] })
        let chapterTitles = model.tutorialChapters.map(\.title)
        let basicSteps = model.tutorialChapters.first { $0.id == AppModel.defaultTutorialChapterID }?.steps.map(\.title) ?? []

        #expect(chapterTitles.contains("Basic"))
        #expect(chapterTitles.contains("Column Types"))
        #expect(chapterTitles.contains("Editing"))
        #expect(chapterTitles.contains("Plots"))
        #expect(chapterTitles.contains("Analysis"))
        #expect(basicSteps.contains("Move Around"))
        #expect(basicSteps.contains("Search"))
        #expect(basicSteps.contains("Sort"))
        #expect(basicSteps.contains("Select Rows"))
    }

    @Test
    func tutorialCommandsExplainSelectionHelpAndPlotAxisClearly() {
        let model = AppModel(preferredLanguagesProvider: { ["en-US"] })

        let basic = model.tutorialChapters.first { $0.id == AppModel.defaultTutorialChapterID }
        let select = basic?.steps.first { $0.id == "basic-select" }
        let help = basic?.steps.first { $0.id == "basic-help" }
        let types = model.tutorialChapters.first { $0.id == "typesort" }
        let floatConvert = types?.steps.first { $0.id == "typesort-float" }
        let numericSort = types?.steps.first { $0.id == "typesort-sort" }
        let plots = model.tutorialChapters.first { $0.id == "plots" }
        let axis = plots?.steps.first { $0.id == "plot-axis" }
        let open = plots?.steps.first { $0.id == "plot-open" }

        #expect(select?.instruction.contains("`s` means select current row") == true)
        #expect(select?.instruction.contains("`t` only toggles") == true)
        #expect(help?.instruction.contains("Press `z`, then `?`") == true)
        #expect(help?.instruction.contains("No extra text input is needed") == true)
        #expect(floatConvert?.instruction.contains("`population_m`") == true)
        #expect(floatConvert?.instruction.contains("press `%`") == true)
        #expect(numericSort?.instruction.contains("press `]` for ascending and `[` for descending") == true)
        #expect(axis?.instruction.contains("`population_m`") == true)
        #expect(axis?.instruction.contains("`score`") == true)
        #expect(open?.instruction.contains("y=`score` against x=`population_m`") == true)
        #expect(open?.detail.contains("switch to English input") == true)
        #expect(open?.detail.contains("make sure `population_m` is numeric") == true)
    }

    @Test
    func inputSourceEnglishDetectionAvoidsBroadUSMatches() {
        #expect(InputSourceMonitor.looksEnglish(
            sourceID: "com.apple.keylayout.ABC",
            inputModeID: "",
            localizedName: "ABC"
        ))

        #expect(!InputSourceMonitor.looksEnglish(
            sourceID: "com.example.customsource.wechat",
            inputModeID: "",
            localizedName: "微信输入法"
        ))
    }

    @Test
    func englishInputSwitchRejectsNonEnglishCandidates() {
        #expect(InputSourceMonitor.shouldSelectEnglishCandidate(score: 320))
        #expect(!InputSourceMonitor.shouldSelectEnglishCandidate(score: 0))
        #expect(!InputSourceMonitor.shouldSelectEnglishCandidate(score: -1000))
    }

    @Test
    func statusPanelRunningTintDependsOnVisiDataStatusOnly() {
        #expect(statusPanelUsesRunningTint(for: "Running VisiData for sample.tsv."))
        #expect(statusPanelUsesRunningTint(for: "正在为 sample.tsv 运行 VisiData。"))
        #expect(!statusPanelUsesRunningTint(for: "Ready to open a file"))
    }

    @Test
    func collapsedRecentFilePrimaryActionMatchesVisibleState() {
        #expect(collapsedRecentFilePrimaryAction(isCommandHovering: true) == .remove)
        #expect(collapsedRecentFilePrimaryAction(isCommandHovering: false) == .open)
    }

    @Test
    func tutorialStepNavigationStaysWithinBounds() {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let model = AppModel(defaults: defaults)
        model.beginTutorialGuide()

        #expect(model.isTutorialActive)
        #expect(model.tutorialStepIndex == 0)

        model.rewindTutorialStep()
        #expect(model.tutorialStepIndex == 0)

        for _ in 0..<20 {
            model.advanceTutorialStep()
        }

        #expect(model.tutorialCurrentChapter != nil)
        #expect(model.tutorialStepIndex == (model.tutorialCurrentChapter?.steps.count ?? 1) - 1)
    }

    @Test
    func beginTutorialGuideAlwaysStartsFromFirstStep() {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set([AppModel.defaultTutorialChapterID: 3], forKey: AppModel.tutorialProgressByChapterKey)

        let model = AppModel(defaults: defaults)
        model.beginTutorialGuide(chapterID: AppModel.defaultTutorialChapterID)

        #expect(model.isTutorialActive)
        #expect(model.tutorialStepIndex == 0)
    }

    @Test
    func finishingTutorialResetsGuideState() {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let model = AppModel(defaults: defaults)
        model.beginTutorialGuide()
        model.advanceTutorialStep()
        model.setTutorialCoachExpanded(false)

        model.finishTutorial()

        #expect(!model.isTutorialActive)
        #expect(model.tutorialStepIndex == 0)
        #expect(model.isTutorialCoachExpanded)
        #expect(model.tutorialCurrentStep == nil)
    }

    @Test
    func tutorialSampleFileIsGeneratedWithExpectedHeader() throws {
        let model = AppModel()
        let url = try model.makeTutorialSampleFile()
        let content = try String(contentsOf: url, encoding: .utf8)

        #expect(content.contains("city\tcountry\tpopulation_m\tscore"))
        #expect(content.contains("Shanghai\tChina"))
    }

    @Test
    func tutorialLanguageDefaultsToSystemAndFollowsChineseLocale() {
        let model = AppModel(preferredLanguagesProvider: { ["zh-Hans-CN"] })
        #expect(model.appLanguagePreference == .system)
        #expect(model.effectiveLanguage == .chinese)
        #expect(model.tutorialChapters.first?.title == "基础")
    }

    @Test
    func tutorialProgressTextLocalizesToChinese() {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let model = AppModel(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-CN"] })
        model.beginTutorialGuide()

        #expect(model.tutorialProgressText.contains("第 1 步"))
        #expect(model.tutorialProgressText.contains(" / "))
    }

    @Test
    func folderDropErrorLocalizesToChinese() {
        let model = AppModel(preferredLanguagesProvider: { ["zh-Hans-CN"] })

        model.openExternalFiles([URL(fileURLWithPath: "/tmp/results", isDirectory: true)])

        #expect(model.errorMessage?.contains("请拖入文件，不要拖入文件夹。") == true)
        #expect(model.errorMessage?.contains("会直接流式读取 .gz/.bgz 压缩文件") == true)
    }

    @Test
    func largeTableOpenAndSwitchStressKeepsLatestSessionStable() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-large-switch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let largeA = tempRoot.appendingPathComponent("large-a.tsv")
        let largeB = tempRoot.appendingPathComponent("large-b.tsv")
        try writeLargeTSV(to: largeA, rows: 150_000, prefix: "A")
        try writeLargeTSV(to: largeB, rows: 150_000, prefix: "B")

        let model = AppModel(defaults: defaults)
        model.vdExecutablePath = launcher.path
        defer {
            model.activeSession?.terminate()
        }

        for _ in 0..<8 {
            model.openExternalFile(largeA)
            #expect(model.errorMessage == nil)
            #expect(model.activeSession?.isRunning == true)
            #expect(model.activeSession?.currentFileURL?.standardizedFileURL == largeA.standardizedFileURL)

            model.openExternalFile(largeB)
            #expect(model.errorMessage == nil)
            #expect(model.activeSession?.isRunning == true)
            #expect(model.activeSession?.currentFileURL?.standardizedFileURL == largeB.standardizedFileURL)
        }

        #expect(model.recentFiles.first?.standardizedFileURL == largeB.standardizedFileURL)
        #expect(model.recentFiles.contains(where: { $0.standardizedFileURL == largeA.standardizedFileURL }))
    }

    @Test
    func switchingFilesReusesSessionController() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-session-reuse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let first = tempRoot.appendingPathComponent("first.tsv")
        let second = tempRoot.appendingPathComponent("second.tsv")
        try Data("id\tvalue\n1\tA\n".utf8).write(to: first)
        try Data("id\tvalue\n1\tB\n".utf8).write(to: second)

        let model = AppModel(defaults: defaults)
        model.vdExecutablePath = launcher.path
        defer {
            model.activeSession?.terminate()
        }

        model.openExternalFile(first)
        let firstSession = try #require(model.activeSession)

        model.openExternalFile(second)

        let secondSession = try #require(model.activeSession)
        #expect(secondSession === firstSession)
        #expect(model.activeSession?.currentFileURL?.standardizedFileURL == second.standardizedFileURL)
    }

    @Test
    func reopeningActiveRecentFileDoesNotRestartSession() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-session-reopen-same-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let target = tempRoot.appendingPathComponent("same.tsv")
        try Data("id\tvalue\n1\tA\n".utf8).write(to: target)

        let model = AppModel(defaults: defaults)
        model.vdExecutablePath = launcher.path
        defer {
            model.activeSession?.terminate()
        }

        model.openExternalFile(target)
        let session = try #require(model.activeSession)
        let initialGeneration = session.outputGenerationForTesting

        model.openExternalFile(target)

        #expect(model.activeSession === session)
        #expect(session.outputGenerationForTesting == initialGeneration)
        #expect(model.statusMessage?.contains(target.lastPathComponent) == true)
    }

    @Test
    func tutorialModeEndsCleanlyWhenSwitchingToLargeTable() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-tutorial-switch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let large = tempRoot.appendingPathComponent("large-tutorial-switch.tsv")
        try writeLargeTSV(to: large, rows: 120_000, prefix: "T")

        let model = AppModel(defaults: defaults)
        model.vdExecutablePath = launcher.path
        defer {
            model.activeSession?.terminate()
        }

        model.startTutorial()
        let tutorialSample = model.tutorialSampleFileURL

        #expect(model.isTutorialActive)
        #expect(tutorialSample != nil)
        #expect(model.errorMessage == nil)
        #expect(model.activeSession?.currentFileURL?.standardizedFileURL == tutorialSample?.standardizedFileURL)

        model.openExternalFile(large)

        #expect(!model.isTutorialActive)
        #expect(model.errorMessage == nil)
        #expect(model.activeSession?.isRunning == true)
        #expect(model.activeSession?.currentFileURL?.standardizedFileURL == large.standardizedFileURL)

        let status = model.statusMessage ?? ""
        #expect(
            status.contains("Tutorial ended")
                || status.contains("教程已结束")
        )
    }

    @Test
    func repeatedTutorialAndLargeTableSwitchDoesNotLeakTutorialState() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-tutorial-loop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let largeA = tempRoot.appendingPathComponent("large-loop-a.tsv")
        let largeB = tempRoot.appendingPathComponent("large-loop-b.tsv")
        try writeLargeTSV(to: largeA, rows: 80_000, prefix: "L1")
        try writeLargeTSV(to: largeB, rows: 80_000, prefix: "L2")

        let model = AppModel(defaults: defaults)
        model.vdExecutablePath = launcher.path
        defer {
            model.activeSession?.terminate()
        }

        for index in 0..<5 {
            model.startTutorial()
            #expect(model.isTutorialActive)
            #expect(model.tutorialCurrentStep != nil)

            let target = index.isMultiple(of: 2) ? largeA : largeB
            model.openExternalFile(target)

            #expect(!model.isTutorialActive)
            #expect(model.tutorialCurrentStep == nil)
            #expect(model.activeSession?.isRunning == true)
            #expect(model.activeSession?.currentFileURL?.standardizedFileURL == target.standardizedFileURL)
        }
    }

    @Test
    func allTutorialChaptersCanTraverseAndComplete() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-tutorial-complete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let model = AppModel(defaults: defaults)
        model.vdExecutablePath = launcher.path
        defer {
            model.activeSession?.terminate()
        }

        let chapters = model.tutorialChapters
        #expect(!chapters.isEmpty)

        for chapter in chapters {
            model.startTutorial(chapterID: chapter.id)

            #expect(model.errorMessage == nil)
            #expect(model.isTutorialActive)
            #expect(model.tutorialCurrentChapter?.id == chapter.id)
            #expect(model.tutorialCurrentStep != nil)
            #expect(model.activeSession?.isRunning == true)

            let stepCount = model.tutorialCurrentChapter?.steps.count ?? 0
            #expect(stepCount > 0)

            if stepCount > 1 {
                for _ in 0..<(stepCount - 1) {
                    model.advanceTutorialStep()
                }
            }

            #expect(model.isTutorialLastStep)
            model.completeTutorial()

            #expect(!model.isTutorialActive)
            #expect(model.tutorialCurrentStep == nil)
            #expect(model.tutorialCurrentChapter == nil)
            #expect(model.tutorialChapters.first(where: { $0.id == chapter.id })?.isCompleted == true)
        }
    }

    @Test
    func allTutorialChaptersEndCleanlyWhenSwitchingToLargeTables() throws {
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("idata-tutorial-all-switch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let launcher = tempRoot.appendingPathComponent("fake-vd-long.zsh")
        try makeLongRunningLauncher(at: launcher, sleepSeconds: 120)

        let largeA = tempRoot.appendingPathComponent("large-all-a.tsv")
        let largeB = tempRoot.appendingPathComponent("large-all-b.tsv")
        try writeLargeTSV(to: largeA, rows: 100_000, prefix: "TA")
        try writeLargeTSV(to: largeB, rows: 100_000, prefix: "TB")

        let model = AppModel(defaults: defaults)
        model.vdExecutablePath = launcher.path
        defer {
            model.activeSession?.terminate()
        }

        let chapters = model.tutorialChapters
        #expect(!chapters.isEmpty)

        for (index, chapter) in chapters.enumerated() {
            model.startTutorial(chapterID: chapter.id)
            #expect(model.errorMessage == nil)
            #expect(model.isTutorialActive)
            #expect(model.tutorialCurrentChapter?.id == chapter.id)

            let target = index.isMultiple(of: 2) ? largeA : largeB
            model.openExternalFile(target)

            #expect(!model.isTutorialActive)
            #expect(model.errorMessage == nil)
            #expect(model.activeSession?.isRunning == true)
            #expect(model.activeSession?.currentFileURL?.standardizedFileURL == target.standardizedFileURL)
            #expect(model.tutorialCurrentStep == nil)
        }
    }

    @Test
    func visidataInstallerScriptUsesSharedHelperWhenAvailable() {
        let helperPath = "/Users/Shared/iData/Configure VisiData.command"
        let script = AppModel.makeVisiDataInstallerScript(helperPath: helperPath)

        #expect(script.contains(helperPath))
        #expect(script.contains("--install"))
    }

    @Test
    func visidataInstallerScriptFallsBackToBrewAndPipx() {
        let script = AppModel.makeVisiDataInstallerScript(helperPath: nil)

        #expect(script.contains("brew install pipx"))
        #expect(script.contains("pipx install visidata"))
        #expect(script.contains("pipx inject visidata openpyxl pyxlsb xlrd zstandard"))
        #expect(script.contains("if ! command -v vd >/dev/null 2>&1; then"))
        #expect(script.contains("exit 1"))
        #expect(!script.contains("brew install pipx || true"))
        #expect(!script.contains("pipx install visidata || true"))
        #expect(!script.contains("pipx inject visidata openpyxl pyxlsb xlrd zstandard || true"))
    }

    @Test
    func visidataInstallerScriptExportsPathBeforeFinalPipxCheck() {
        let script = AppModel.makeVisiDataInstallerScript(helperPath: nil)

        let exportPathRange = script.range(of: "export PATH=\"$HOME/.local/bin:")
        let finalPipxCheckRange = script.range(of: "if ! command -v pipx >/dev/null 2>&1; then\n    echo \"✗ Could not install pipx automatically. Install pipx manually, then retry.\"")

        #expect(exportPathRange != nil)
        #expect(finalPipxCheckRange != nil)
        if let exportPathRange, let finalPipxCheckRange {
            #expect(exportPathRange.lowerBound < finalPipxCheckRange.lowerBound)
        }
    }
}

private struct FakeExecutableChecker: ExecutableChecking {
    let executablePaths: Set<String>

    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}

@MainActor
private final class RecordingExternalFileOpener: ExternalFileOpening {
    private(set) var openedFileURL: URL?
    private(set) var openedApplicationURL: URL?
    var shouldSucceed = true
    private let failingApplicationURLs: Set<URL>

    init(failingApplicationURLs: Set<URL> = []) {
        self.failingApplicationURLs = failingApplicationURLs
    }

    func open(_ fileURL: URL, withApplicationAt applicationURL: URL) -> Bool {
        openedFileURL = fileURL
        openedApplicationURL = applicationURL
        if failingApplicationURLs.contains(applicationURL) {
            return false
        }
        return shouldSucceed
    }
}

private func makeImmediateExitLauncher(at url: URL, exitCode: Int) throws {
    let script = """
    #!/bin/zsh
    exit \(exitCode)
    """

    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func makeLongRunningLauncher(at url: URL, sleepSeconds: Int) throws {
    let script = """
    #!/bin/zsh
    if [[ -n "$1" && -f "$1" ]]; then
      /usr/bin/head -n 3 "$1" >/dev/null 2>&1
    fi
    /bin/sleep \(sleepSeconds)
    """

    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func makeFakeApplicationHandler(
    in directory: URL,
    appFolderName: String,
    bundleIdentifier: String,
    displayName: String
) throws -> DefaultApplicationHandler {
    let appURL = directory.appendingPathComponent(appFolderName, isDirectory: true)
    try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
    return DefaultApplicationHandler(
        url: appURL,
        bundleIdentifier: bundleIdentifier,
        displayName: displayName
    )
}

private func writeLargeTSV(to url: URL, rows: Int, prefix: String) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer {
        try? handle.close()
    }

    try handle.write(contentsOf: Data("id\tvalue\tgroup\tpayload\n".utf8))

    for row in 1...rows {
        let line = "\(row)\t\(row % 97)\t\(prefix)\t\(prefix)-\(row)-\(row % 13)-\(row % 19)\n"
        try handle.write(contentsOf: Data(line.utf8))
    }
}

@MainActor
private func waitForSessionFailure(
    _ session: VisiDataSessionController,
    timeoutNanoseconds: UInt64,
    pollNanoseconds: UInt64 = 25_000_000
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if !session.isRunning, session.errorMessage != nil {
            return true
        }

        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }

    return !session.isRunning && session.errorMessage != nil
}
