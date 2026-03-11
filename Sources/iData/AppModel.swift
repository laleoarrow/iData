import AppKit
import Foundation
import SwiftUI
#if canImport(iDataCore)
import iDataCore
#endif
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    enum VisiDataDependencyState: Equatable {
        case available(path: String)
        case missing
    }

    enum TutorialLanguagePreference: String, CaseIterable, Identifiable {
        case system
        case english
        case chinese

        var id: String { rawValue }
    }

    enum TutorialResolvedLanguage: Equatable {
        case english
        case chinese
    }

    enum CollapsedSidebarHeaderAction: Equatable {
        case expand
        case clearAll
    }

    struct TutorialChapter: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let steps: [TutorialStep]
        let completedStepCount: Int
        let isCompleted: Bool
    }

    struct TutorialStep: Identifiable, Equatable {
        let id: String
        let index: Int
        let title: String
        let command: String
        let instruction: String
        let detail: String
    }

    struct SupportedFormat {
        let displayName: String
        let fileExtension: String
    }

    @Published var activeSession: VisiDataSessionController?
    @Published var recentFiles: [URL]
    @Published var lastOpenedFile: URL?
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var isHelpPresented = false
    @Published var isTutorialHubPresented = false
    @Published var isTutorialActive = false
    @Published var tutorialStepIndex = 0
    @Published var isTutorialCoachExpanded = true
    @Published var activeTutorialChapterID: String?
    @Published var isSidebarCollapsed: Bool {
        didSet {
            defaults.set(isSidebarCollapsed, forKey: Self.isSidebarCollapsedKey)
        }
    }
    @Published var tutorialLanguagePreference: TutorialLanguagePreference {
        didSet {
            defaults.set(tutorialLanguagePreference.rawValue, forKey: Self.tutorialLanguagePreferenceKey)
        }
    }
    @Published var reduceAnimations: Bool {
        didSet {
            defaults.set(reduceAnimations, forKey: Self.reduceAnimationsKey)
        }
    }
    @Published var vdExecutablePath: String {
        didSet {
            defaults.set(vdExecutablePath, forKey: Self.vdExecutablePathKey)
        }
    }
    @Published var formatAssociationStatus: [String: Bool] = [:] // extension -> isDefault
    @Published var isSettingFormatDefault = false
    @Published var settingFormatExtension: String?
    private var previousDefaultAppByExtension: [String: DefaultApplicationHandler] = [:]

    private let defaults: UserDefaults
    private let recentFilesStore: RecentFilesStore
    private let executableChecker: any ExecutableChecking
    private let environmentPathProvider: () -> String
    private let preferredLanguagesProvider: () -> [String]
    private let formatAssociationRestoreStore: FormatAssociationRestoreStore

    static let vdExecutablePathKey = "vdExecutablePath"
    static let pinnedRecentFilesKey = "pinnedRecentFiles"
    static let reduceAnimationsKey = "reduceAnimations"
    static let isSidebarCollapsedKey = "isSidebarCollapsed"
    static let tutorialLanguagePreferenceKey = "tutorialLanguagePreference"
    static let previousDefaultAppsByExtensionKey = "previousDefaultAppsByExtension"
    static let tutorialProgressByChapterKey = "tutorialProgressByChapter"
    static let completedTutorialChapterIDsKey = "completedTutorialChapterIDs"
    static let defaultTutorialChapterID = "basic"
    static let recentFilesLimit = 10
    static let sharedVisiDataHelperPath = "/Users/Shared/iData/Configure VisiData.command"
    static let supportedFormats: [SupportedFormat] = [
        SupportedFormat(displayName: "CSV", fileExtension: "csv"),
        SupportedFormat(displayName: "TSV", fileExtension: "tsv"),
        SupportedFormat(displayName: "TXT / Delimited Text", fileExtension: "txt"),
        SupportedFormat(displayName: "TAB / Delimited Text", fileExtension: "tab"),
        SupportedFormat(displayName: "JSON", fileExtension: "json"),
        SupportedFormat(displayName: "JSON Lines", fileExtension: "jsonl"),
        SupportedFormat(displayName: "Excel Workbook", fileExtension: "xlsx"),
        SupportedFormat(displayName: "Excel Legacy", fileExtension: "xls"),
        SupportedFormat(displayName: "Parquet", fileExtension: "parquet"),
        SupportedFormat(displayName: "Feather", fileExtension: "feather"),
        SupportedFormat(displayName: "MA / GWAS", fileExtension: "ma"),
        SupportedFormat(displayName: "PLINK Assoc", fileExtension: "assoc"),
        SupportedFormat(displayName: "PLINK QAssoc", fileExtension: "qassoc"),
        SupportedFormat(displayName: "PLINK GLM", fileExtension: "glm"),
        SupportedFormat(displayName: "Meta Analysis", fileExtension: "meta"),
        SupportedFormat(displayName: "10x Matrix", fileExtension: "mtx"),
        SupportedFormat(displayName: "10x Barcodes", fileExtension: "barcodes.tsv"),
        SupportedFormat(displayName: "10x Features", fileExtension: "features.tsv"),
        SupportedFormat(displayName: "10x HDF5 Matrix", fileExtension: "h5"),
        SupportedFormat(displayName: "PLINK BED", fileExtension: "bed"),
        SupportedFormat(displayName: "PLINK BIM", fileExtension: "bim"),
        SupportedFormat(displayName: "PLINK FAM", fileExtension: "fam"),
        SupportedFormat(displayName: "PLINK 2 PGEN", fileExtension: "pgen"),
        SupportedFormat(displayName: "PLINK 2 PVAR", fileExtension: "pvar"),
        SupportedFormat(displayName: "PLINK 2 PSAM", fileExtension: "psam"),
        SupportedFormat(displayName: "VCF", fileExtension: "vcf"),
        SupportedFormat(displayName: "BCF", fileExtension: "bcf"),
        SupportedFormat(displayName: "BED / Interval", fileExtension: "bedgraph"),
        SupportedFormat(displayName: "GTF / GFF", fileExtension: "gtf"),
        SupportedFormat(displayName: "GFF", fileExtension: "gff"),
        SupportedFormat(displayName: "GFF3", fileExtension: "gff3"),
        SupportedFormat(displayName: "AnnData", fileExtension: "h5ad"),
        SupportedFormat(displayName: "Loom", fileExtension: "loom"),
        SupportedFormat(displayName: "Compressed GZip", fileExtension: "gz"),
        SupportedFormat(displayName: "Compressed BGZip", fileExtension: "bgz"),
    ]
    static var supportedFormatHelpText: String {
        supportedFormats
            .map { "\($0.displayName) (.\($0.fileExtension))" }
            .joined(separator: ", ")
    }

    private struct TutorialLocalizedText {
        let english: String
        let chinese: String

        func localized(for language: TutorialResolvedLanguage) -> String {
            switch language {
            case .english:
                english
            case .chinese:
                chinese
            }
        }
    }

    private struct TutorialStepDefinition {
        let id: String
        let title: TutorialLocalizedText
        let command: String
        let instruction: TutorialLocalizedText
        let detail: TutorialLocalizedText
    }

    private struct TutorialChapterDefinition {
        let id: String
        let title: TutorialLocalizedText
        let subtitle: TutorialLocalizedText
        let icon: String
        let steps: [TutorialStepDefinition]
    }

    private static let tutorialChapterDefinitions: [TutorialChapterDefinition] = [
        TutorialChapterDefinition(
            id: "basic",
            title: TutorialLocalizedText(english: "Basic", chinese: "基础"),
            subtitle: TutorialLocalizedText(english: "Move, search, sort, and select in a real VisiData session.", chinese: "在真实 VisiData 会话里完成移动、搜索、排序和选择。"),
            icon: "sparkles",
            steps: [
                TutorialStepDefinition(
                    id: "basic-move",
                    title: TutorialLocalizedText(english: "Move Around", chinese: "移动光标"),
                    command: "← ↑ → ↓  /  h j k l",
                    instruction: TutorialLocalizedText(english: "Use arrow keys or `h j k l` to move around rows and columns.", chinese: "用方向键或 `h j k l` 在行列间移动。"),
                    detail: TutorialLocalizedText(english: "Arrow keys are fully supported. `h j k l` is just faster for power users.", chinese: "方向键完全可用；`h j k l` 只是熟练用户更高效。")
                ),
                TutorialStepDefinition(
                    id: "basic-search",
                    title: TutorialLocalizedText(english: "Search", chinese: "搜索"),
                    command: "/  Tokyo  Enter",
                    instruction: TutorialLocalizedText(english: "Press `/`, type `Tokyo`, then press Enter once to submit the search.", chinese: "按 `/`，输入 `Tokyo`，然后只按一次 Enter 提交搜索。"),
                    detail: TutorialLocalizedText(english: "After the first Enter, use `n` / `N` for next/previous match. Don't press Enter twice.", chinese: "第一次 Enter 后，用 `n` / `N` 跳转下一条/上一条；不要连续按两次 Enter。")
                ),
                TutorialStepDefinition(
                    id: "basic-sort",
                    title: TutorialLocalizedText(english: "Sort", chinese: "排序"),
                    command: "]  [",
                    instruction: TutorialLocalizedText(english: "Move to `score`, then sort ascending with `]` and descending with `[`.", chinese: "先移动到 `score` 列，再按 `]` 升序、`[` 降序。"),
                    detail: TutorialLocalizedText(english: "Sorting is column-scoped, so cursor location matters.", chinese: "排序作用在当前列，所以光标位置很关键。")
                ),
                TutorialStepDefinition(
                    id: "basic-select",
                    title: TutorialLocalizedText(english: "Select Rows", chinese: "行选择"),
                    command: "s  t  u",
                    instruction: TutorialLocalizedText(english: "`s` means select current row. `t` only toggles: selected -> unselected, unselected -> selected. `u` always unselects current row.", chinese: "`s` 是把当前行设为已选；`t` 只是切换（已选变未选，未选变已选）；`u` 永远是取消当前行选择。"),
                    detail: TutorialLocalizedText(english: "If `t` feels confusing, use `s` for selecting and `u` for clearing until you are comfortable.", chinese: "如果 `t` 容易混淆，先只用 `s` 选择、`u` 取消，熟悉后再用切换。")
                ),
                TutorialStepDefinition(
                    id: "basic-help",
                    title: TutorialLocalizedText(english: "Discover Commands", chinese: "命令发现"),
                    command: "z  then  ?",
                    instruction: TutorialLocalizedText(english: "Press `z`, then `?` (not together). No extra text input is needed; a command-help sheet opens directly.", chinese: "先按 `z` 再按 `?`（不是同时按）。不需要再输入文字，会直接打开命令帮助页。"),
                    detail: TutorialLocalizedText(english: "If nothing appears, check that keyboard focus is inside the terminal and input method is English.", chinese: "如果没有反应，先确认焦点在终端内部，且输入法是英文。")
                ),
            ]
        ),
        TutorialChapterDefinition(
            id: "typesort",
            title: TutorialLocalizedText(english: "Column Types", chinese: "列类型"),
            subtitle: TutorialLocalizedText(english: "Convert columns to numeric types, then sort correctly.", chinese: "先切换为数值类型，再进行正确排序。"),
            icon: "arrow.up.arrow.down.square",
            steps: [
                TutorialStepDefinition(
                    id: "typesort-float",
                    title: TutorialLocalizedText(english: "Convert To Float", chinese: "转为浮点数"),
                    command: "% on population_m",
                    instruction: TutorialLocalizedText(english: "Move to `population_m`, then press `%` to set the column type to float.", chinese: "把光标移到 `population_m`，按 `%` 将列类型设为浮点数。"),
                    detail: TutorialLocalizedText(english: "Use this when numeric values include decimals such as `24.9`.", chinese: "当数值包含小数（如 `24.9`）时，优先用这个类型。")
                ),
                TutorialStepDefinition(
                    id: "typesort-int",
                    title: TutorialLocalizedText(english: "Convert To Integer", chinese: "转为整数"),
                    command: "# on score",
                    instruction: TutorialLocalizedText(english: "Move to `score`, then press `#` to set the column type to integer.", chinese: "把光标移到 `score`，按 `#` 将列类型设为整数。"),
                    detail: TutorialLocalizedText(english: "Integer typing keeps numeric comparisons stable for rank-like columns.", chinese: "对分数或排名类列，用整数类型可避免文本比较导致的错序。")
                ),
                TutorialStepDefinition(
                    id: "typesort-sort",
                    title: TutorialLocalizedText(english: "Sort Numeric Column", chinese: "按数值排序"),
                    command: "]  [",
                    instruction: TutorialLocalizedText(english: "On the converted numeric column, press `]` for ascending and `[` for descending.", chinese: "在已转换的数值列上，按 `]` 升序，按 `[` 降序。"),
                    detail: TutorialLocalizedText(english: "If order looks wrong, check whether the column is still text and convert again.", chinese: "如果顺序看起来不对，先检查列是否仍是文本类型，再重新转换。")
                ),
            ]
        ),
        TutorialChapterDefinition(
            id: "editing",
            title: TutorialLocalizedText(english: "Editing", chinese: "编辑"),
            subtitle: TutorialLocalizedText(english: "Practice cell edits and bulk updates on selected rows.", chinese: "练习单元格编辑与选中行批量更新。"),
            icon: "pencil.and.scribble",
            steps: [
                TutorialStepDefinition(
                    id: "editing-cell",
                    title: TutorialLocalizedText(english: "Edit One Cell", chinese: "编辑单元格"),
                    command: "e",
                    instruction: TutorialLocalizedText(english: "On any cell, press `e`, edit the value, then press Enter once to accept.", chinese: "在任意单元格按 `e`，修改值后按一次 Enter 确认。"),
                    detail: TutorialLocalizedText(english: "If an editor prompt opens, Enter confirms the current input.", chinese: "若出现输入提示，Enter 表示确认当前输入。")
                ),
                TutorialStepDefinition(
                    id: "editing-select",
                    title: TutorialLocalizedText(english: "Mark Rows For Update", chinese: "标记待更新行"),
                    command: "s  /  n",
                    instruction: TutorialLocalizedText(english: "Select several rows (for example by searching and using `s`).", chinese: "先选择几行（例如搜索后用 `s` 逐条标记）。"),
                    detail: TutorialLocalizedText(english: "Keep the selection active before running bulk edit commands.", chinese: "执行批量编辑命令前，保持这些行处于已选状态。")
                ),
                TutorialStepDefinition(
                    id: "editing-bulk",
                    title: TutorialLocalizedText(english: "Bulk Edit Selected", chinese: "批量编辑已选行"),
                    command: "g e",
                    instruction: TutorialLocalizedText(english: "Use `g e` to set values on selected rows in the current column.", chinese: "用 `g e` 对当前列中的已选行统一赋值。"),
                    detail: TutorialLocalizedText(english: "This is safer than repeating single-cell edits row by row.", chinese: "比逐行单独编辑更稳定、更高效。")
                ),
            ]
        ),
        TutorialChapterDefinition(
            id: "plots",
            title: TutorialLocalizedText(english: "Plots", chinese: "绘图"),
            subtitle: TutorialLocalizedText(english: "Create quick visual checks directly from your table.", chinese: "直接从表格快速做可视化检查。"),
            icon: "chart.xyaxis.line",
            steps: [
                TutorialStepDefinition(
                    id: "plot-axis",
                    title: TutorialLocalizedText(english: "Prepare Axes", chinese: "准备坐标轴"),
                    command: "on population_m: !  -> move to score",
                    instruction: TutorialLocalizedText(english: "In this sample, move to numeric column `population_m` and press `!` to set x key, then move cursor to numeric column `score` as y.", chinese: "在当前示例里，先移动到数值列 `population_m` 并按 `!` 设为 x 键，再把光标移到数值列 `score` 作为 y。"),
                    detail: TutorialLocalizedText(english: "If `population_m` is not treated as numeric, convert it first, then press `!` again so VisiData can use it as the x key column.", chinese: "如果 `population_m` 没被当成数值列，先把它转成 numeric，再按一次 `!`，这样 VisiData 才能把它当作 x 轴 key 列。")
                ),
                TutorialStepDefinition(
                    id: "plot-open",
                    title: TutorialLocalizedText(english: "Open Plot", chinese: "打开图表"),
                    command: "on score: .",
                    instruction: TutorialLocalizedText(english: "With cursor on `score`, press `.` to plot y=`score` against x=`population_m`.", chinese: "把光标停在 `score` 列后按 `.`，会画出 y=`score` 对 x=`population_m`。"),
                    detail: TutorialLocalizedText(english: "If you see `at least one numeric key col necessary for x-axis`: go back to `population_m`, press `!` again, then return to `score` and press `.`. If the warning still stays, make sure `population_m` is numeric instead of text. Only if the shortcut itself does not register should you switch to English input and retry.", chinese: "如果看到 `at least one numeric key col necessary for x-axis`：先回到 `population_m` 再按一次 `!`，然后回到 `score` 按 `.`。如果警告还在，说明 `population_m` 可能还是文本列，需要先转成 numeric。只有当快捷键本身没有被正确输入时，才需要切到英文输入法后再重试。")
                ),
                TutorialStepDefinition(
                    id: "plot-drill",
                    title: TutorialLocalizedText(english: "Drill Back To Rows", chinese: "回钻到原始行"),
                    command: "Enter",
                    instruction: TutorialLocalizedText(english: "In graph view, move to a point and press Enter to open source rows.", chinese: "在图表视图移动到某个点后，按 Enter 打开对应原始行。"),
                    detail: TutorialLocalizedText(english: "This is useful for tracing outliers from chart to data.", chinese: "可快速把图中异常点追溯回原始数据。")
                ),
            ]
        ),
        TutorialChapterDefinition(
            id: "analysis",
            title: TutorialLocalizedText(english: "Analysis", chinese: "分析"),
            subtitle: TutorialLocalizedText(english: "Build quick profiling sheets to summarize your data.", chinese: "快速构建统计摘要表。"),
            icon: "waveform.path.ecg.text",
            steps: [
                TutorialStepDefinition(
                    id: "analysis-freq",
                    title: TutorialLocalizedText(english: "Frequency Table", chinese: "频率表"),
                    command: "Shift+F",
                    instruction: TutorialLocalizedText(english: "On a categorical column, press `Shift+F` to open frequencies.", chinese: "在分类列按 `Shift+F` 打开频率统计表。"),
                    detail: TutorialLocalizedText(english: "Great for quick distribution checks before deeper modeling.", chinese: "适合在深入建模前先看分布。")
                ),
                TutorialStepDefinition(
                    id: "analysis-describe",
                    title: TutorialLocalizedText(english: "Describe Numeric Columns", chinese: "数值列描述统计"),
                    command: "Shift+I",
                    instruction: TutorialLocalizedText(english: "Press `Shift+I` to generate a describe sheet for numeric columns.", chinese: "按 `Shift+I` 生成数值列描述统计表。"),
                    detail: TutorialLocalizedText(english: "Review min/max/mean and spread to catch suspicious values.", chinese: "查看最值、均值和离散度，快速发现异常值。")
                ),
            ]
        ),
    ]

    private static let tutorialSampleDirectoryName = "io.github.leoarrow.idata.tutorial"
    private static let tutorialSampleFilename = "idata_tutorial_sample.tsv"
    private static let tutorialSampleContents = """
    city\tcountry\tpopulation_m\tscore\tgroup
    Shanghai\tChina\t24.9\t91\tA
    Tokyo\tJapan\t14.0\t87\tA
    Mumbai\tIndia\t12.5\t82\tB
    Sao Paulo\tBrazil\t12.3\t78\tB
    Cairo\tEgypt\t10.2\t74\tC
    Berlin\tGermany\t3.6\t89\tA
    Seattle\tUSA\t0.8\t93\tA
    """

    private(set) var tutorialSampleFileURL: URL?

    init(
        defaults: UserDefaults = .standard,
        recentFilesStore: RecentFilesStore? = nil,
        executableChecker: any ExecutableChecking = LocalExecutableChecker(),
        environmentPathProvider: @escaping () -> String = { ProcessInfo.processInfo.environment["PATH"] ?? "" },
        preferredLanguagesProvider: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.defaults = defaults
        self.recentFilesStore = recentFilesStore ?? RecentFilesStore(defaults: defaults)
        self.executableChecker = executableChecker
        self.environmentPathProvider = environmentPathProvider
        self.preferredLanguagesProvider = preferredLanguagesProvider
        self.formatAssociationRestoreStore = FormatAssociationRestoreStore(defaults: defaults)
        let initialRecentFiles = (recentFilesStore ?? RecentFilesStore(defaults: defaults)).load()
        self.recentFiles = Self.orderedRecentFiles(
            initialRecentFiles,
            pinned: Self.loadPinnedRecentFiles(defaults: defaults)
        )
        self.reduceAnimations = defaults.object(forKey: Self.reduceAnimationsKey) as? Bool ?? false
        self.vdExecutablePath = defaults.string(forKey: Self.vdExecutablePathKey) ?? ""
        self.isSidebarCollapsed = defaults.object(forKey: Self.isSidebarCollapsedKey) as? Bool ?? false
        self.tutorialLanguagePreference = TutorialLanguagePreference(
            rawValue: defaults.string(forKey: Self.tutorialLanguagePreferenceKey) ?? ""
        ) ?? .system
        self.previousDefaultAppByExtension = formatAssociationRestoreStore.loadAll()
    }

    var displayedSession: VisiDataSessionController? {
        guard let activeSession, activeSession.isRunning, activeSession.currentFileURL != nil else {
            return nil
        }

        return activeSession
    }

    var appVersionSummary: String {
        appVersionDisplay(revealingBuild: false)
    }

    var animationsEnabled: Bool {
        !reduceAnimations
    }

    var effectiveTutorialLanguage: TutorialResolvedLanguage {
        switch tutorialLanguagePreference {
        case .english:
            return .english
        case .chinese:
            return .chinese
        case .system:
            let preferredLanguage = preferredLanguagesProvider().first?.lowercased() ?? "en"
            return preferredLanguage.hasPrefix("zh") ? .chinese : .english
        }
    }

    var tutorialChapters: [TutorialChapter] {
        Self.tutorialChapterDefinitions.map { definition in
            let completedStepCount = min(
                tutorialProgressByChapter()[definition.id] ?? 0,
                definition.steps.count
            )
            let steps = definition.steps.enumerated().map { index, stepDefinition in
                TutorialStep(
                    id: stepDefinition.id,
                    index: index,
                    title: stepDefinition.title.localized(for: effectiveTutorialLanguage),
                    command: stepDefinition.command,
                    instruction: stepDefinition.instruction.localized(for: effectiveTutorialLanguage),
                    detail: stepDefinition.detail.localized(for: effectiveTutorialLanguage)
                )
            }
            return TutorialChapter(
                id: definition.id,
                title: definition.title.localized(for: effectiveTutorialLanguage),
                subtitle: definition.subtitle.localized(for: effectiveTutorialLanguage),
                icon: definition.icon,
                steps: steps,
                completedStepCount: completedStepCount,
                isCompleted: completedTutorialChapterIDs().contains(definition.id)
            )
        }
    }

    var tutorialCurrentChapter: TutorialChapter? {
        guard let activeTutorialChapterID else {
            return nil
        }
        return tutorialChapters.first { $0.id == activeTutorialChapterID }
    }

    var tutorialCurrentStep: TutorialStep? {
        guard
            isTutorialActive,
            let chapter = tutorialCurrentChapter,
            chapter.steps.indices.contains(tutorialStepIndex)
        else {
            return nil
        }
        return chapter.steps[tutorialStepIndex]
    }

    var tutorialProgressText: String {
        guard
            isTutorialActive,
            let chapter = tutorialCurrentChapter
        else {
            return "Tutorial"
        }
        return "\(chapter.title) · Step \(tutorialStepIndex + 1) of \(chapter.steps.count)"
    }

    var isTutorialLastStep: Bool {
        guard isTutorialActive, let chapter = tutorialCurrentChapter else {
            return false
        }
        return tutorialStepIndex >= chapter.steps.count - 1
    }

    var tutorialLanguageSummary: String {
        switch effectiveTutorialLanguage {
        case .english:
            return "Tutorial currently shown in English."
        case .chinese:
            return "教程当前显示为中文。"
        }
    }

    var tutorialLanguageBadgeText: String {
        switch effectiveTutorialLanguage {
        case .english:
            return "Language: English"
        case .chinese:
            return "语言：中文"
        }
    }

    func tutorialLanguageOptionTitle(_ preference: TutorialLanguagePreference) -> String {
        switch preference {
        case .system:
            return "System"
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }

    func appVersionDisplay(revealingBuild _: Bool) -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        return "v\(shortVersion)"
    }

    var visiDataDependencyState: VisiDataDependencyState {
        guard let resolvedURL = VDExecutableLocator.resolve(
            explicitPath: normalizedVDExecutablePath(),
            environmentPath: environmentPathProvider(),
            checker: executableChecker
        ) else {
            return .missing
        }

        return .available(path: resolvedURL.path)
    }

    var visiDataDependencySummary: String {
        switch visiDataDependencyState {
        case let .available(path):
            return "VisiData detected at \(path)"
        case .missing:
            return "VisiData not found. Install with `brew install visidata` or set the executable path in Preferences."
        }
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            openExternalFile(url)
        }
    }

    func presentTutorialHub() {
        isTutorialHubPresented = true
    }

    func startTutorial(chapterID: String = AppModel.defaultTutorialChapterID) {
        do {
            guard let chapter = tutorialChapters.first(where: { $0.id == chapterID }) else {
                throw NSError(
                    domain: "io.github.leoarrow.idata.tutorial",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Requested tutorial chapter was not found."]
                )
            }

            let sampleURL = try makeTutorialSampleFile()
            tutorialSampleFileURL = sampleURL
            openExternalFile(sampleURL)

            guard activeSession?.currentFileURL?.standardizedFileURL == sampleURL.standardizedFileURL else {
                finishTutorial()
                if errorMessage == nil {
                    errorMessage = "Could not start tutorial because the sample table failed to open. Check VisiData path in Preferences."
                }
                return
            }

            beginTutorialGuide(chapterID: chapter.id)
            isTutorialHubPresented = false
            statusMessage = "Tutorial started with \(sampleURL.lastPathComponent). Follow the floating coach in the session."
            errorMessage = nil
        } catch {
            finishTutorial()
            statusMessage = nil
            errorMessage = "Could not prepare tutorial sample data: \(error.localizedDescription)"
        }
    }

    func beginTutorialGuide(chapterID: String = AppModel.defaultTutorialChapterID) {
        guard let chapter = tutorialChapters.first(where: { $0.id == chapterID }) else {
            return
        }
        isTutorialActive = true
        activeTutorialChapterID = chapter.id
        let completedCount = tutorialProgressByChapter()[chapter.id] ?? 0
        if completedCount >= chapter.steps.count {
            tutorialStepIndex = 0
        } else {
            tutorialStepIndex = min(completedCount, max(chapter.steps.count - 1, 0))
        }
        isTutorialCoachExpanded = true
        markTutorialProgress(chapterID: chapter.id, completedStepCount: max(completedCount, 0))
    }

    func advanceTutorialStep() {
        guard isTutorialActive, let chapter = tutorialCurrentChapter else {
            return
        }
        let newIndex = min(tutorialStepIndex + 1, chapter.steps.count - 1)
        tutorialStepIndex = newIndex
        markTutorialProgress(chapterID: chapter.id, completedStepCount: newIndex)
    }

    func rewindTutorialStep() {
        guard isTutorialActive else {
            return
        }
        tutorialStepIndex = max(tutorialStepIndex - 1, 0)
    }

    func jumpToTutorialStep(_ index: Int) {
        guard isTutorialActive, let chapter = tutorialCurrentChapter else {
            return
        }
        tutorialStepIndex = min(max(index, 0), chapter.steps.count - 1)
    }

    func setTutorialCoachExpanded(_ expanded: Bool) {
        guard isTutorialActive else {
            return
        }
        isTutorialCoachExpanded = expanded
    }

    func finishTutorial() {
        isTutorialActive = false
        tutorialStepIndex = 0
        isTutorialCoachExpanded = true
        tutorialSampleFileURL = nil
        activeTutorialChapterID = nil
    }

    func completeTutorial() {
        if let chapterID = activeTutorialChapterID, let chapter = tutorialCurrentChapter {
            markTutorialProgress(chapterID: chapterID, completedStepCount: chapter.steps.count)
            markTutorialChapterCompleted(chapterID)
        }
        finishTutorial()
        statusMessage = "Tutorial completed. Open any file to continue exploring with VisiData."
        errorMessage = nil
    }

    func makeTutorialSampleFile() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.tutorialSampleDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent(Self.tutorialSampleFilename)
        try Self.tutorialSampleContents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func openExternalFiles(_ urls: [URL]) {
        guard let url = Self.firstSupportedFile(in: urls) else {
            guard !urls.isEmpty else {
                return
            }

            statusMessage = nil
            errorMessage = "Drop a regular file, not a folder. iData streams compressed .gz/.bgz files without extracting."
            return
        }

        openExternalFile(url)
    }

    func openExternalFile(_ url: URL) {
        guard Self.supportsTableFile(url) else {
            statusMessage = nil
            errorMessage = "The selected item is not a regular file. iData opens most file suffixes directly and streams .gz/.bgz files without extracting."
            return
        }

        do {
            let explicitPath = normalizedVDExecutablePath()
            let session = VisiDataSessionController()
            try session.open(fileURL: url, explicitVDPath: explicitPath)
            let previousSession = activeSession
            activeSession = session
            previousSession?.terminate()
            lastOpenedFile = url
            performAnimatedMutation(.spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.15)) {
                recentFilesStore.record(url, maxCount: Self.recentFilesLimit)
                refreshRecentFiles()
            }
            if isTutorialActive, let tutorialSampleFileURL, tutorialSampleFileURL.standardizedFileURL != url.standardizedFileURL {
                finishTutorial()
                statusMessage = "Opened \(url.lastPathComponent) inside iData. Tutorial ended because a different file is active."
                errorMessage = nil
                return
            }
            statusMessage = "Opened \(url.lastPathComponent) inside iData."
            errorMessage = nil
        } catch {
            if isTutorialActive {
                finishTutorial()
            }
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    func reopenLastFile() {
        guard let lastOpenedFile else {
            return
        }

        openExternalFile(lastOpenedFile)
    }

    func copyPathToPasteboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        statusMessage = "Copied file path."
        errorMessage = nil
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func removeRecentFile(_ url: URL) {
        performAnimatedMutation(.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.12)) {
            recentFilesStore.remove(url)
            unpinRecentFileIfNeeded(url)
            refreshRecentFiles()
        }
        statusMessage = "Removed \(url.lastPathComponent) from recent files."
        errorMessage = nil
    }

    func clearRecentFiles() {
        performAnimatedMutation(.spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.1)) {
            recentFilesStore.clear()
            defaults.removeObject(forKey: Self.pinnedRecentFilesKey)
            recentFiles = []
        }
        statusMessage = "Cleared recent files."
        errorMessage = nil
    }

    func isPinnedRecentFile(_ url: URL) -> Bool {
        Self.loadPinnedRecentFiles(defaults: defaults).contains {
            $0.standardizedFileURL == url.standardizedFileURL
        }
    }

    func togglePinnedRecentFile(_ url: URL) {
        performAnimatedMutation(.spring(response: 0.32, dampingFraction: 0.84, blendDuration: 0.12)) {
            var pinnedFiles = Self.loadPinnedRecentFiles(defaults: defaults)

            if let existingIndex = pinnedFiles.firstIndex(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                pinnedFiles.remove(at: existingIndex)
                statusMessage = "Unpinned \(url.lastPathComponent)."
            } else {
                pinnedFiles.insert(url, at: 0)
                statusMessage = "Pinned \(url.lastPathComponent) to the top."
            }

            savePinnedRecentFiles(pinnedFiles)
            refreshRecentFiles()
        }
        errorMessage = nil
    }

    func setSidebarCollapsed(_ collapsed: Bool) {
        guard isSidebarCollapsed != collapsed else {
            return
        }
        isSidebarCollapsed = collapsed
    }

    func toggleSidebarCollapsed() {
        setSidebarCollapsed(!isSidebarCollapsed)
    }

    func chooseVDExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.unixExecutable, .shellScript]

        if panel.runModal() == .OK, let url = panel.url {
            vdExecutablePath = url.path
        }
    }

    func runVisiDataOneClickSetup() {
        if case let .available(path) = visiDataDependencyState {
            statusMessage = "VisiData is already available at \(path)."
            errorMessage = nil
            return
        }

        let helperPath = sharedVisiDataHelperPathIfExecutable()
        let scriptContents = Self.makeVisiDataInstallerScript(helperPath: helperPath)

        do {
            let tempScriptURL = try Self.writeTemporaryExecutableScript(contents: scriptContents)
            try Self.openScriptInTerminal(tempScriptURL)
            statusMessage = "Opened Terminal for one-click VisiData setup."
            errorMessage = nil
        } catch {
            statusMessage = nil
            errorMessage = "Could not start one-click VisiData setup: \(error.localizedDescription)"
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func shutdown() {
        activeSession?.terminate()
        activeSession = nil
    }

    func checkFormatAssociation(forExtension fileExtension: String) -> Bool {
        let lookupExtension = Self.associationExtension(for: fileExtension)
        guard !lookupExtension.isEmpty else {
            formatAssociationStatus[fileExtension] = false
            return false
        }

        let isDefault = FileTypeAssociation.isIDataDefaultApp(forExtension: lookupExtension)
        updateAssociationStatus(forLookupExtension: lookupExtension, isDefault: isDefault)
        return isDefault
    }

    func setFormatAsDefault(forExtension fileExtension: String) {
        guard !isSettingFormatDefault else { return }
        let lookupExtension = Self.associationExtension(for: fileExtension)
        guard !lookupExtension.isEmpty else {
            errorMessage = "无法识别 .\(fileExtension) 的后缀。"
            statusMessage = nil
            return
        }

        let wasIDataDefault = FileTypeAssociation.isIDataDefaultApp(forExtension: lookupExtension)
        updateAssociationStatus(forLookupExtension: lookupExtension, isDefault: wasIDataDefault)

        isSettingFormatDefault = true
        settingFormatExtension = fileExtension

        Task {
            if wasIDataDefault {
                let previousDefaultApp = await MainActor.run { [lookupExtension] in
                    previousDefaultAppByExtension[lookupExtension]
                }
                let restoreResult: FileTypeAssociationSetResult
                if let previousDefaultApp {
                    restoreResult = await FileTypeAssociation.setDefaultApp(
                        at: previousDefaultApp.url,
                        forExtension: lookupExtension
                    )
                } else {
                    restoreResult = .missingPreviousDefault
                }

                await MainActor.run {
                    let isNowDefault = FileTypeAssociation.isIDataDefaultApp(forExtension: lookupExtension)
                    updateAssociationStatus(forLookupExtension: lookupExtension, isDefault: isNowDefault)
                    let shownExtension = lookupExtension

                    if !isNowDefault {
                        forgetPreviousDefaultApp(forLookupExtension: lookupExtension)
                        if let previousDefaultApp {
                            statusMessage = "已恢复 .\(shownExtension) 默认应用为 \(previousDefaultApp.displayName)"
                            errorMessage = nil
                        } else {
                            statusMessage = "已取消 .\(shownExtension) 默认用 iData 打开"
                            errorMessage = nil
                        }
                    } else if restoreResult == .success {
                        statusMessage = "系统已收到恢复请求，但 .\(shownExtension) 仍默认 iData。请再试一次并确认系统提示。"
                        errorMessage = nil
                    } else {
                        errorMessage = "无法恢复 .\(shownExtension) 的默认应用：\(restoreResult.userMessage)"
                        statusMessage = nil
                    }

                    isSettingFormatDefault = false
                    settingFormatExtension = nil
                }
                return
            }

            let previousDefaultApp = FileTypeAssociation.currentDefaultApp(forExtension: lookupExtension)
            let setResult = await FileTypeAssociation.setIDataAsDefaultApp(forExtension: lookupExtension)

            await MainActor.run {
                let isNowDefault = FileTypeAssociation.isIDataDefaultApp(forExtension: lookupExtension)
                updateAssociationStatus(forLookupExtension: lookupExtension, isDefault: isNowDefault)
                let shownExtension = lookupExtension

                if isNowDefault {
                    if
                        let previousDefaultApp,
                        !FileTypeAssociation.isIDataBundleIdentifier(previousDefaultApp.bundleIdentifier)
                    {
                        rememberPreviousDefaultApp(previousDefaultApp, forLookupExtension: lookupExtension)
                    }
                    statusMessage = "已设置 .\(shownExtension) 默认用 iData 打开"
                    errorMessage = nil
                } else if setResult == .success {
                    statusMessage = "系统已收到设置请求，但 .\(shownExtension) 还未切换到 iData。请再试一次并确认系统提示。"
                    errorMessage = nil
                } else {
                    errorMessage = "无法设置 .\(shownExtension) 默认应用：\(setResult.userMessage)"
                    statusMessage = nil
                }

                isSettingFormatDefault = false
                settingFormatExtension = nil
            }
        }
    }

    @discardableResult
    func handleDroppedFiles(_ urls: [URL]) -> Bool {
        guard let fileURL = Self.firstSupportedFile(in: urls) else {
            guard !urls.isEmpty else {
                return false
            }

            statusMessage = nil
            errorMessage = "Drop a regular file, not a folder. iData opens most file suffixes directly and streams .gz/.bgz files without extracting."
            return false
        }

        openExternalFile(fileURL)
        return true
    }

    private func normalizedVDExecutablePath() -> String? {
        let trimmed = vdExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func tutorialProgressByChapter() -> [String: Int] {
        defaults.dictionary(forKey: Self.tutorialProgressByChapterKey)?
            .reduce(into: [String: Int]()) { partialResult, pair in
                if let value = pair.value as? Int {
                    partialResult[pair.key] = value
                } else if let number = pair.value as? NSNumber {
                    partialResult[pair.key] = number.intValue
                }
            } ?? [:]
    }

    private func markTutorialProgress(chapterID: String, completedStepCount: Int) {
        var progress = tutorialProgressByChapter()
        let current = progress[chapterID] ?? 0
        progress[chapterID] = max(current, completedStepCount)
        defaults.set(progress, forKey: Self.tutorialProgressByChapterKey)
    }

    private func completedTutorialChapterIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.completedTutorialChapterIDsKey) ?? [])
    }

    private func markTutorialChapterCompleted(_ chapterID: String) {
        var completed = completedTutorialChapterIDs()
        completed.insert(chapterID)
        defaults.set(Array(completed), forKey: Self.completedTutorialChapterIDsKey)
    }

    private func performAnimatedMutation(
        _ animation: Animation,
        changes: () -> Void
    ) {
        if animationsEnabled {
            withAnimation(animation, changes)
        } else {
            changes()
        }
    }

    static func supportsTableFile(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        if
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
            let isDirectory = resourceValues.isDirectory
        {
            return !isDirectory
        }

        return !url.hasDirectoryPath
    }

    static func firstSupportedFile(in urls: [URL]) -> URL? {
        urls.first(where: supportsTableFile)
    }

    static func collapsedRecentFileBadgeText(for url: URL) -> String {
        let title = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstCharacter = title.first else {
            return "?"
        }
        return String(firstCharacter).uppercased()
    }

    static func makeVisiDataInstallerScript(helperPath: String?) -> String {
        if let helperPath {
            return """
            #!/bin/zsh
            set -euo pipefail

            \(shellSingleQuoted(helperPath)) --install
            """
        }

        return """
        #!/bin/zsh
        set -euo pipefail

        echo "iData one-click VisiData setup"
        echo "--------------------------------"

        if command -v vd >/dev/null 2>&1; then
          echo "vd already detected at: $(command -v vd)"
        fi

        if command -v brew >/dev/null 2>&1; then
          echo "Installing or upgrading VisiData with Homebrew..."
          brew install visidata || brew upgrade visidata || true
        else
          if ! command -v pipx >/dev/null 2>&1; then
            if command -v python3 >/dev/null 2>&1; then
              echo "pipx not found. Installing pipx with python3 --user..."
              python3 -m pip install --user pipx
              python3 -m pipx ensurepath || true
              export PATH="$HOME/.local/bin:$PATH"
            else
              echo "python3 is missing. Install Homebrew or python3, then retry."
              exit 1
            fi
          fi

          echo "Installing or upgrading VisiData with pipx..."
          pipx install visidata || pipx upgrade visidata || true
        fi

        if command -v pipx >/dev/null 2>&1; then
          echo "Injecting openpyxl for Excel loaders..."
          pipx inject visidata openpyxl || true
        fi

        echo ""
        echo "Verification"
        command -v vd || true
        vd --version || true

        echo ""
        echo "Return to iData and use Auto Detect in Preferences if needed."
        read '?Press Return to close this installer...'
        """
    }

    static func collapsedSidebarHeaderAction(
        hasRecentFiles: Bool,
        isCommandPressed: Bool
    ) -> CollapsedSidebarHeaderAction {
        if hasRecentFiles && isCommandPressed {
            return .clearAll
        }
        return .expand
    }

    static func associationExtension(for fileExtension: String) -> String {
        fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
            .last
            .map { String($0).lowercased() } ?? ""
    }

    static func canSetAssociationExtensionInput(_ rawInput: String) -> Bool {
        !associationExtension(for: rawInput).isEmpty
    }

    private func updateAssociationStatus(forLookupExtension lookupExtension: String, isDefault: Bool) {
        formatAssociationStatus[lookupExtension] = isDefault
        for format in Self.supportedFormats where Self.associationExtension(for: format.fileExtension) == lookupExtension {
            formatAssociationStatus[format.fileExtension] = isDefault
        }
    }

    private func rememberPreviousDefaultApp(_ handler: DefaultApplicationHandler, forLookupExtension lookupExtension: String) {
        previousDefaultAppByExtension[lookupExtension] = handler
        formatAssociationRestoreStore.save(handler, forLookupExtension: lookupExtension)
    }

    private func forgetPreviousDefaultApp(forLookupExtension lookupExtension: String) {
        previousDefaultAppByExtension.removeValue(forKey: lookupExtension)
        formatAssociationRestoreStore.remove(forLookupExtension: lookupExtension)
    }

    private func refreshRecentFiles() {
        recentFiles = Self.orderedRecentFiles(
            recentFilesStore.load(),
            pinned: Self.loadPinnedRecentFiles(defaults: defaults)
        )
    }

    private func unpinRecentFileIfNeeded(_ url: URL) {
        let remainingPinned = Self.loadPinnedRecentFiles(defaults: defaults).filter {
            $0.standardizedFileURL != url.standardizedFileURL
        }
        savePinnedRecentFiles(remainingPinned)
    }

    private func savePinnedRecentFiles(_ urls: [URL]) {
        defaults.set(urls.map(\.path), forKey: Self.pinnedRecentFilesKey)
    }

    private func sharedVisiDataHelperPathIfExecutable() -> String? {
        let helperPath = Self.sharedVisiDataHelperPath
        return FileManager.default.isExecutableFile(atPath: helperPath) ? helperPath : nil
    }

    private static func writeTemporaryExecutableScript(contents: String) throws -> URL {
        let filename = "idata-visidata-setup-\(UUID().uuidString).command"
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private static func openScriptInTerminal(_ scriptURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", scriptURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "io.github.leoarrow.idata.visidata-setup",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "open returned exit code \(process.terminationStatus)."]
            )
        }
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func loadPinnedRecentFiles(defaults: UserDefaults) -> [URL] {
        let storedPaths = defaults.stringArray(forKey: Self.pinnedRecentFilesKey) ?? []
        return storedPaths.map { URL(fileURLWithPath: $0) }
    }

    private static func orderedRecentFiles(_ recentFiles: [URL], pinned: [URL]) -> [URL] {
        let standardizedRecentFiles = recentFiles.map(\.standardizedFileURL)
        let pinnedFiles = pinned.filter { pinnedURL in
            standardizedRecentFiles.contains(pinnedURL.standardizedFileURL)
        }
        let pinnedSet = Set(pinnedFiles.map(\.standardizedFileURL))
        let unpinnedFiles = recentFiles.filter { !pinnedSet.contains($0.standardizedFileURL) }
        return pinnedFiles + unpinnedFiles
    }
}

private enum FileTypeAssociationSetResult: Equatable {
    case success
    case missingAppBundle
    case missingTargetApplication
    case unresolvedContentType
    case permissionDenied
    case missingPreviousDefault
    case launchServicesError(String)
    case unexpected(String)

    var userMessage: String {
        switch self {
        case .success:
            return "成功"
        case .missingAppBundle:
            return "未找到 iData 应用标识"
        case .missingTargetApplication:
            return "未找到要恢复的默认应用"
        case .unresolvedContentType:
            return "系统无法解析该后缀对应的文件类型"
        case .permissionDenied:
            return "系统拒绝了修改默认应用的请求"
        case .missingPreviousDefault:
            return "没有记录此前的默认应用"
        case let .launchServicesError(reason):
            return reason
        case let .unexpected(reason):
            return reason
        }
    }
}

private struct DefaultApplicationHandler: Equatable, Sendable {
    let url: URL
    let bundleIdentifier: String
    let displayName: String
}

private struct PersistedDefaultApplicationHandler: Codable {
    let url: URL
    let bundleIdentifier: String
    let displayName: String

    init(_ handler: DefaultApplicationHandler) {
        url = handler.url
        bundleIdentifier = handler.bundleIdentifier
        displayName = handler.displayName
    }

    var handler: DefaultApplicationHandler {
        DefaultApplicationHandler(
            url: url,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
    }
}

@MainActor
private struct FormatAssociationRestoreStore {
    let defaults: UserDefaults

    func loadAll() -> [String: DefaultApplicationHandler] {
        loadPersistedMappings().reduce(into: [:]) { result, entry in
            let lookupExtension = AppModel.associationExtension(for: entry.key)
            guard !lookupExtension.isEmpty else {
                return
            }
            result[lookupExtension] = entry.value.handler
        }
    }

    func save(_ handler: DefaultApplicationHandler, forLookupExtension lookupExtension: String) {
        var mappings = loadPersistedMappings()
        mappings[lookupExtension] = PersistedDefaultApplicationHandler(handler)
        store(mappings)
    }

    func remove(forLookupExtension lookupExtension: String) {
        var mappings = loadPersistedMappings()
        mappings.removeValue(forKey: lookupExtension)
        store(mappings)
    }

    private func loadPersistedMappings() -> [String: PersistedDefaultApplicationHandler] {
        guard
            let data = defaults.data(forKey: AppModel.previousDefaultAppsByExtensionKey),
            let mappings = try? JSONDecoder().decode([String: PersistedDefaultApplicationHandler].self, from: data)
        else {
            return [:]
        }

        return mappings
    }

    private func store(_ mappings: [String: PersistedDefaultApplicationHandler]) {
        if mappings.isEmpty {
            defaults.removeObject(forKey: AppModel.previousDefaultAppsByExtensionKey)
            return
        }

        if let data = try? JSONEncoder().encode(mappings) {
            defaults.set(data, forKey: AppModel.previousDefaultAppsByExtensionKey)
        }
    }
}

@MainActor
private enum FileTypeAssociation {
    static var iDataBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "io.github.leoarrow.idata"
    }

    private static func appURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: iDataBundleIdentifier)
    }

    static func isIDataBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier == iDataBundleIdentifier
    }

    private static func contentType(forExtension fileExtension: String) -> UTType? {
        let trimmed = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let probeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("idata-content-type-probe", isDirectory: true)
        try? FileManager.default.createDirectory(at: probeDirectory, withIntermediateDirectories: true)
        let probeURL = probeDirectory.appendingPathComponent("probe-\(UUID().uuidString).\(trimmed)")

        do {
            try Data("idata".utf8).write(to: probeURL, options: [.atomic])
            defer {
                try? FileManager.default.removeItem(at: probeURL)
            }
            let values = try probeURL.resourceValues(forKeys: [.contentTypeKey])
            guard let contentType = values.contentType else {
                return nil
            }
            return contentType
        } catch {
            return nil
        }
    }

    static func isIDataDefaultApp(forExtension fileExtension: String) -> Bool {
        guard let currentDefaultApp = currentDefaultApp(forExtension: fileExtension) else {
            return false
        }
        return currentDefaultApp.bundleIdentifier == iDataBundleIdentifier
    }

    static func currentDefaultApp(forExtension fileExtension: String) -> DefaultApplicationHandler? {
        guard
            let contentType = contentType(forExtension: fileExtension),
            let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: contentType),
            let defaultBundle = Bundle(url: defaultAppURL),
            let defaultBundleIdentifier = defaultBundle.bundleIdentifier
        else {
            return nil
        }

        let displayName =
            (defaultBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (defaultBundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
                ?? FileManager.default.displayName(atPath: defaultAppURL.path)

        return DefaultApplicationHandler(
            url: defaultAppURL,
            bundleIdentifier: defaultBundleIdentifier,
            displayName: displayName
        )
    }

    static func setIDataAsDefaultApp(forExtension fileExtension: String) async -> FileTypeAssociationSetResult {
        guard let appURL = appURL() else {
            return .missingAppBundle
        }
        return await setDefaultApp(at: appURL, forExtension: fileExtension)
    }

    static func setDefaultApp(at appURL: URL, forExtension fileExtension: String) async -> FileTypeAssociationSetResult {
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            return .missingTargetApplication
        }
        guard let contentType = contentType(forExtension: fileExtension) else {
            return .unresolvedContentType
        }
        return await setDefaultApplication(at: appURL, toOpen: contentType)
    }

    private static func setDefaultApplication(at appURL: URL, toOpen contentType: UTType) async -> FileTypeAssociationSetResult {
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: contentType) { error in
                guard let nsError = error as NSError? else {
                    continuation.resume(returning: .success)
                    return
                }

                if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                    continuation.resume(returning: .permissionDenied)
                    return
                }

                if nsError.domain == NSOSStatusErrorDomain {
                    continuation.resume(returning: .launchServicesError(nsError.localizedDescription))
                    return
                }

                continuation.resume(returning: .unexpected(nsError.localizedDescription))
            }
        }
    }
}
