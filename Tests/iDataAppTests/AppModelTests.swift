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
        #expect(statusPanelUsesRunningTint(for: "正在运行 VisiData：sample.tsv"))
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
        #expect(model.tutorialLanguagePreference == .system)
        #expect(model.effectiveTutorialLanguage == .chinese)
        #expect(model.tutorialChapters.first?.title == "基础")
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
        #expect(script.contains("pipx inject visidata openpyxl xlrd zstandard"))
    }
}

private struct FakeExecutableChecker: ExecutableChecking {
    let executablePaths: Set<String>

    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}
