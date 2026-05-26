import AppKit
import Foundation
import SwiftUI
#if canImport(iDataCore)
import iDataCore
#endif
import UniformTypeIdentifiers

@MainActor
protocol ExternalFileOpening {
    func open(_ fileURL: URL, withApplicationAt applicationURL: URL) -> Bool
}

struct WorkspaceExternalFileOpener: ExternalFileOpening {
    @MainActor
    func open(_ fileURL: URL, withApplicationAt applicationURL: URL) -> Bool {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", applicationURL.path, fileURL.path]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

enum ExternalOpenAction: Equatable {
    case openedInIData
    case forwardedToAlternateApp(appName: String)
    case presentedError
}

enum ExternalOpenPresentationDecision: Equatable {
    case activateApp
    case stayBackground
}

@MainActor
final class AppModel: ObservableObject {
    enum VisiDataDependencyState: Equatable {
        case available(path: String)
        case missing
    }

    enum AppLanguagePreference: String, CaseIterable, Identifiable {
        case system
        case english
        case chinese

        var id: String { rawValue }
    }

    enum AppResolvedLanguage: Equatable {
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
        let chineseDisplayName: String
        let fileExtension: String

        func localizedDisplayName(for language: AppResolvedLanguage) -> String {
            switch language {
            case .english:
                displayName
            case .chinese:
                chineseDisplayName
            }
        }
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
    @Published var appLanguagePreference: AppLanguagePreference {
        didSet {
            defaults.set(appLanguagePreference.rawValue, forKey: Self.appLanguagePreferenceKey)
        }
    }
    @Published var preferredSmallFileApplication: DefaultApplicationHandler? {
        didSet {
            preferredSmallFileApplicationStore.store(preferredSmallFileApplication)
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
    private let preferredSmallFileApplicationStore: PreferredSmallFileApplicationStore
    private let externalFileOpener: any ExternalFileOpening
    private let alternateApplicationResolver: @MainActor (URL, String, [String: DefaultApplicationHandler]) -> DefaultApplicationHandler?
    private let fileSizeProvider: @MainActor (URL) -> Int64?

    nonisolated static let vdExecutablePathKey = "vdExecutablePath"
    nonisolated static let pinnedRecentFilesKey = "pinnedRecentFiles"
    nonisolated static let reduceAnimationsKey = "reduceAnimations"
    nonisolated static let isSidebarCollapsedKey = "isSidebarCollapsed"
    nonisolated static let appLanguagePreferenceKey = "appLanguagePreference"
    nonisolated static let previousDefaultAppsByExtensionKey = "previousDefaultAppsByExtension"
    nonisolated static let preferredSmallFileApplicationKey = "preferredSmallFileApplication"
    nonisolated static let tutorialProgressByChapterKey = "tutorialProgressByChapter"
    nonisolated static let completedTutorialChapterIDsKey = "completedTutorialChapterIDs"
    nonisolated static let defaultTutorialChapterID = "basic"
    nonisolated static let recentFilesLimit = 10
    static let largeFileOpenThresholdBytes: Int64 = 100 * 1024 * 1024
    static let sharedVisiDataHelperPath = "/Users/Shared/iData/Configure VisiData.command"
    static let supportedFormats: [SupportedFormat] = [
        SupportedFormat(displayName: "CSV", chineseDisplayName: "CSV", fileExtension: "csv"),
        SupportedFormat(displayName: "TSV", chineseDisplayName: "TSV", fileExtension: "tsv"),
        SupportedFormat(displayName: "TXT / Delimited Text", chineseDisplayName: "TXT / 分隔文本", fileExtension: "txt"),
        SupportedFormat(displayName: "TAB / Delimited Text", chineseDisplayName: "TAB / 分隔文本", fileExtension: "tab"),
        SupportedFormat(displayName: "JSON", chineseDisplayName: "JSON", fileExtension: "json"),
        SupportedFormat(displayName: "JSON Lines", chineseDisplayName: "JSON 行", fileExtension: "jsonl"),
        SupportedFormat(displayName: "Excel Workbook", chineseDisplayName: "Excel 工作簿", fileExtension: "xlsx"),
        SupportedFormat(displayName: "Excel Legacy", chineseDisplayName: "Excel 旧版", fileExtension: "xls"),
        SupportedFormat(displayName: "Parquet", chineseDisplayName: "Parquet", fileExtension: "parquet"),
        SupportedFormat(displayName: "Feather", chineseDisplayName: "Feather", fileExtension: "feather"),
        SupportedFormat(displayName: "MA / GWAS", chineseDisplayName: "MA / GWAS", fileExtension: "ma"),
        SupportedFormat(displayName: "PLINK Assoc", chineseDisplayName: "PLINK Assoc", fileExtension: "assoc"),
        SupportedFormat(displayName: "PLINK QAssoc", chineseDisplayName: "PLINK QAssoc", fileExtension: "qassoc"),
        SupportedFormat(displayName: "PLINK GLM", chineseDisplayName: "PLINK GLM", fileExtension: "glm"),
        SupportedFormat(displayName: "Meta Analysis", chineseDisplayName: "Meta 分析", fileExtension: "meta"),
        SupportedFormat(displayName: "10x Matrix", chineseDisplayName: "10x 矩阵", fileExtension: "mtx"),
        SupportedFormat(displayName: "10x Barcodes", chineseDisplayName: "10x 条形码", fileExtension: "barcodes.tsv"),
        SupportedFormat(displayName: "10x Features", chineseDisplayName: "10x 特征", fileExtension: "features.tsv"),
        SupportedFormat(displayName: "10x HDF5 Matrix", chineseDisplayName: "10x HDF5 矩阵", fileExtension: "h5"),
        SupportedFormat(displayName: "PLINK BED", chineseDisplayName: "PLINK BED", fileExtension: "bed"),
        SupportedFormat(displayName: "PLINK BIM", chineseDisplayName: "PLINK BIM", fileExtension: "bim"),
        SupportedFormat(displayName: "PLINK FAM", chineseDisplayName: "PLINK FAM", fileExtension: "fam"),
        SupportedFormat(displayName: "PLINK 2 PGEN", chineseDisplayName: "PLINK 2 PGEN", fileExtension: "pgen"),
        SupportedFormat(displayName: "PLINK 2 PVAR", chineseDisplayName: "PLINK 2 PVAR", fileExtension: "pvar"),
        SupportedFormat(displayName: "PLINK 2 PSAM", chineseDisplayName: "PLINK 2 PSAM", fileExtension: "psam"),
        SupportedFormat(displayName: "VCF", chineseDisplayName: "VCF", fileExtension: "vcf"),
        SupportedFormat(displayName: "BCF", chineseDisplayName: "BCF", fileExtension: "bcf"),
        SupportedFormat(displayName: "BED / Interval", chineseDisplayName: "BED / 区间", fileExtension: "bedgraph"),
        SupportedFormat(displayName: "GTF / GFF", chineseDisplayName: "GTF / GFF", fileExtension: "gtf"),
        SupportedFormat(displayName: "GFF", chineseDisplayName: "GFF", fileExtension: "gff"),
        SupportedFormat(displayName: "GFF3", chineseDisplayName: "GFF3", fileExtension: "gff3"),
        SupportedFormat(displayName: "AnnData", chineseDisplayName: "AnnData", fileExtension: "h5ad"),
        SupportedFormat(displayName: "Loom", chineseDisplayName: "Loom", fileExtension: "loom"),
        SupportedFormat(displayName: "Compressed GZip", chineseDisplayName: "GZip 压缩文件", fileExtension: "gz"),
        SupportedFormat(displayName: "Compressed BGZip", chineseDisplayName: "BGZip 压缩文件", fileExtension: "bgz"),
    ]
    static let formatPanelFormats: [SupportedFormat] = {
        let conciseExamples = [
            "csv",
            "tsv",
            "txt",
            "tab",
            "json",
            "jsonl",
            "xlsx",
            "xls",
            "parquet",
            "feather",
            "ma",
            "vcf",
            "h5ad",
            "gz",
            "bgz",
        ]

        return conciseExamples.compactMap { target in
            supportedFormats.first { associationExtension(for: $0.fileExtension) == target }
        }
    }()
    static var supportedFormatHelpText: String {
        supportedFormats
            .map { "\($0.displayName) (.\($0.fileExtension))" }
            .joined(separator: ", ")
    }

    private struct TutorialLocalizedText {
        let english: String
        let chinese: String

        func localized(for language: AppResolvedLanguage) -> String {
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
        preferredLanguagesProvider: @escaping () -> [String] = { Locale.preferredLanguages },
        externalFileOpener: any ExternalFileOpening = WorkspaceExternalFileOpener(),
        alternateApplicationResolver: @escaping @MainActor (URL, String, [String: DefaultApplicationHandler]) -> DefaultApplicationHandler? = AppModel.resolveAlternateApplication(for:lookupExtension:storedPreviousDefaults:),
        fileSizeProvider: @escaping @MainActor (URL) -> Int64? = AppModel.fileSizeInBytes(for:)
    ) {
        self.defaults = defaults
        self.recentFilesStore = recentFilesStore ?? RecentFilesStore(defaults: defaults)
        self.executableChecker = executableChecker
        self.environmentPathProvider = environmentPathProvider
        self.preferredLanguagesProvider = preferredLanguagesProvider
        self.formatAssociationRestoreStore = FormatAssociationRestoreStore(defaults: defaults)
        self.preferredSmallFileApplicationStore = PreferredSmallFileApplicationStore(defaults: defaults)
        self.externalFileOpener = externalFileOpener
        self.alternateApplicationResolver = alternateApplicationResolver
        self.fileSizeProvider = fileSizeProvider
        let initialRecentFiles = (recentFilesStore ?? RecentFilesStore(defaults: defaults)).load()
        self.recentFiles = Self.orderedRecentFiles(
            initialRecentFiles,
            pinned: Self.loadPinnedRecentFiles(defaults: defaults)
        )
        self.reduceAnimations = defaults.object(forKey: Self.reduceAnimationsKey) as? Bool ?? false
        self.vdExecutablePath = defaults.string(forKey: Self.vdExecutablePathKey) ?? ""
        self.isSidebarCollapsed = defaults.object(forKey: Self.isSidebarCollapsedKey) as? Bool ?? false
        self.appLanguagePreference = AppLanguagePreference(
            rawValue: defaults.string(forKey: Self.appLanguagePreferenceKey) ?? ""
        ) ?? .system
        self.preferredSmallFileApplication = preferredSmallFileApplicationStore.load()
        self.previousDefaultAppByExtension = formatAssociationRestoreStore.loadAll()
    }

    var displayedSession: VisiDataSessionController? {
        guard let activeSession, activeSession.currentFileURL != nil else {
            return nil
        }

        guard Self.shouldDisplaySessionDetail(
            hasCurrentFile: activeSession.currentFileURL != nil,
            isRunning: activeSession.isRunning,
            hasError: activeSession.errorMessage != nil
        ) else {
            return nil
        }

        return activeSession
    }

    nonisolated static func shouldDisplaySessionDetail(
        hasCurrentFile: Bool,
        isRunning: Bool,
        hasError: Bool
    ) -> Bool {
        // Keep a failed session visible so its launch/loader guidance remains actionable.
        hasCurrentFile && (isRunning || hasError)
    }

    var appVersionSummary: String {
        appVersionDisplay(revealingBuild: false)
    }

    var animationsEnabled: Bool {
        !reduceAnimations
    }

    var effectiveLanguage: AppResolvedLanguage {
        Self.resolvedLanguage(preference: appLanguagePreference, preferredLanguages: preferredLanguagesProvider())
    }

    var isChinese: Bool {
        effectiveLanguage == .chinese
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
                    title: stepDefinition.title.localized(for: effectiveLanguage),
                    command: stepDefinition.command,
                    instruction: stepDefinition.instruction.localized(for: effectiveLanguage),
                    detail: stepDefinition.detail.localized(for: effectiveLanguage)
                )
            }
            return TutorialChapter(
                id: definition.id,
                title: definition.title.localized(for: effectiveLanguage),
                subtitle: definition.subtitle.localized(for: effectiveLanguage),
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
            return localized(english: "Tutorial", chinese: "教程")
        }
        return localized(
            english: "\(chapter.title) · Step \(tutorialStepIndex + 1) of \(chapter.steps.count)",
            chinese: "\(chapter.title) · 第 \(tutorialStepIndex + 1) 步 / 共 \(chapter.steps.count) 步"
        )
    }

    var isTutorialLastStep: Bool {
        guard isTutorialActive, let chapter = tutorialCurrentChapter else {
            return false
        }
        return tutorialStepIndex >= chapter.steps.count - 1
    }

    var appLanguageSummary: String {
        switch effectiveLanguage {
        case .english:
            return "App interface currently shown in English."
        case .chinese:
            return "当前界面语言：中文。"
        }
    }

    var appLanguageBadgeText: String {
        switch effectiveLanguage {
        case .english:
            return "Language: English"
        case .chinese:
            return "语言：中文"
        }
    }

    func appLanguageOptionTitle(_ preference: AppLanguagePreference) -> String {
        switch preference {
        case .system:
            return localized(english: "System", chinese: "系统")
        case .english:
            return localized(english: "English", chinese: "英文")
        case .chinese:
            return "中文"
        }
    }

    nonisolated static func resolvedLanguage(
        preference: AppLanguagePreference,
        preferredLanguages: [String]
    ) -> AppResolvedLanguage {
        switch preference {
        case .english:
            return .english
        case .chinese:
            return .chinese
        case .system:
            let preferredLanguage = preferredLanguages.first?.lowercased() ?? "en"
            return preferredLanguage.hasPrefix("zh") ? .chinese : .english
        }
    }

    nonisolated static func resolvedLanguage(
        defaults: UserDefaults = .standard,
        preferredLanguagesProvider: () -> [String] = { Locale.preferredLanguages }
    ) -> AppResolvedLanguage {
        let preference = AppLanguagePreference(
            rawValue: defaults.string(forKey: Self.appLanguagePreferenceKey) ?? ""
        ) ?? .system
        return resolvedLanguage(preference: preference, preferredLanguages: preferredLanguagesProvider())
    }

    nonisolated static func localized(
        _ language: AppResolvedLanguage,
        english: String,
        chinese: String
    ) -> String {
        switch language {
        case .english:
            return english
        case .chinese:
            return chinese
        }
    }

    nonisolated static func localized(
        defaults: UserDefaults = .standard,
        preferredLanguagesProvider: () -> [String] = { Locale.preferredLanguages },
        english: String,
        chinese: String
    ) -> String {
        localized(
            resolvedLanguage(defaults: defaults, preferredLanguagesProvider: preferredLanguagesProvider),
            english: english,
            chinese: chinese
        )
    }

    nonisolated static func visiDataInstallGuidance(_ language: AppResolvedLanguage) -> String {
        switch language {
        case .english:
            return "Use iData's one-click setup, or install with `pipx install visidata` and `pipx inject visidata openpyxl`. `brew install visidata` also works. You can set the executable path in Preferences."
        case .chinese:
            return "可先使用 iData 的一键配置，或执行 `pipx install visidata` 和 `pipx inject visidata openpyxl`。`brew install visidata` 也可用；你也可以在偏好设置中指定可执行文件路径。"
        }
    }

    private struct VisiDataFormatDependencyAdvice {
        let extensions: Set<String>
        let english: String
        let chinese: String
    }

    private nonisolated static let compressionSuffixes = ["gz", "bgz", "bgzf"]
    private nonisolated static let visidataFormatDependencyAdvice: [VisiDataFormatDependencyAdvice] = [
        VisiDataFormatDependencyAdvice(
            extensions: ["xlsx"],
            english: "For `.xlsx` files, VisiData uses `openpyxl`. Install it with `pipx inject visidata openpyxl` if loader support is missing.",
            chinese: "`.xlsx` 文件通常依赖 `openpyxl`。如果缺少对应 loader，可执行 `pipx inject visidata openpyxl`。"
        ),
        VisiDataFormatDependencyAdvice(
            extensions: ["xls"],
            english: "For `.xls` files, VisiData uses `xlrd`. Install it with `pipx inject visidata xlrd` if loader support is missing.",
            chinese: "`.xls` 文件通常依赖 `xlrd`。如果缺少对应 loader，可执行 `pipx inject visidata xlrd`。"
        ),
        // VisiData 3.3 ships a dedicated xlsb loader which imports `pyxlsb`.
        VisiDataFormatDependencyAdvice(
            extensions: ["xlsb"],
            english: "For `.xlsb` files, VisiData uses `pyxlsb`. Install it with `pipx inject visidata pyxlsb` if loader support is missing.",
            chinese: "`.xlsb` 文件通常依赖 `pyxlsb`。如果缺少对应 loader，可执行 `pipx inject visidata pyxlsb`。"
        ),
        VisiDataFormatDependencyAdvice(
            extensions: ["parquet"],
            english: "For `.parquet` files, VisiData uses `pyarrow`. Install it with `pipx inject visidata pyarrow` if loader support is missing.",
            chinese: "`.parquet` 文件通常依赖 `pyarrow`。如果缺少对应 loader，可执行 `pipx inject visidata pyarrow`。"
        ),
        VisiDataFormatDependencyAdvice(
            extensions: ["ods"],
            english: "For `.ods` files, VisiData uses `odfpy`. Install it with `pipx inject visidata odfpy` if loader support is missing.",
            chinese: "`.ods` 文件通常依赖 `odfpy`。如果缺少对应 loader，可执行 `pipx inject visidata odfpy`。"
        ),
        VisiDataFormatDependencyAdvice(
            extensions: ["arrow", "arrows"],
            english: "For Arrow IPC files, VisiData uses `pyarrow`. Install it with `pipx inject visidata pyarrow` if loader support is missing.",
            chinese: "Arrow IPC 文件通常依赖 `pyarrow`。如果缺少对应 loader，可执行 `pipx inject visidata pyarrow`。"
        ),
    ]

    nonisolated static func visiDataFormatDependencyGuidance(
        for url: URL,
        language: AppResolvedLanguage
    ) -> String? {
        let normalizedExtension = normalizedDataExtension(for: url)
        guard
            let advice = visidataFormatDependencyAdvice.first(where: { $0.extensions.contains(normalizedExtension) })
        else {
            return nil
        }

        switch language {
        case .english:
            return advice.english
        case .chinese:
            return advice.chinese
        }
    }

    private nonisolated static func normalizedDataExtension(for url: URL) -> String {
        var components = url.lastPathComponent.lowercased().split(separator: ".").map(String.init)
        while let last = components.last, compressionSuffixes.contains(last) {
            components.removeLast()
        }
        return components.last ?? ""
    }

    func localized(english: String, chinese: String) -> String {
        Self.localized(effectiveLanguage, english: english, chinese: chinese)
    }

    func appVersionDisplay(revealingBuild _: Bool) -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.1"
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
            return localized(
                english: "VisiData detected at \(path)",
                chinese: "已检测到 VisiData：\(path)"
            )
        case .missing:
            return localized(
                english: "VisiData not found. \(Self.visiDataInstallGuidance(.english))",
                chinese: "未找到 VisiData。\(Self.visiDataInstallGuidance(.chinese))"
            )
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

    func setPreferredSmallFileApplication(_ handler: DefaultApplicationHandler?) {
        if let handler, FileTypeAssociation.isIDataBundleIdentifier(handler.bundleIdentifier) {
            errorMessage = localized(
                english: "Please choose a non-iData app for small-file handoff.",
                chinese: "请为小文件转交选择一个非 iData 应用。"
            )
            return
        }

        preferredSmallFileApplication = handler
        errorMessage = nil
        statusMessage = handler.map {
            localized(
                english: "Small files at or below 100 MiB will be handed off to \($0.displayName). Compressed .gz/.bgz files always stay in iData.",
                chinese: "小于等于 100 MiB 的文件将转交给 \($0.displayName)。压缩 .gz/.bgz 文件始终留在 iData 中打开。"
            )
        }
    }

    func clearPreferredSmallFileApplication() {
        preferredSmallFileApplication = nil
        errorMessage = nil
        statusMessage = localized(
            english: "Small files at or below 100 MiB will fall back to the previous default app when possible. Compressed .gz/.bgz files always stay in iData.",
            chinese: "小于等于 100 MiB 的文件会尽量回退到此前的默认应用。压缩 .gz/.bgz 文件始终留在 iData 中打开。"
        )
    }

    func choosePreferredSmallFileApplication() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let appURL = panel.url else {
            return
        }

        guard let handler = FileTypeAssociation.applicationHandler(for: appURL) else {
            errorMessage = localized(
                english: "Could not read the selected application.",
                chinese: "无法读取所选应用。"
            )
            return
        }

        setPreferredSmallFileApplication(handler)
    }

    var preferredSmallFileApplicationDisplayName: String {
        preferredSmallFileApplication?.displayName ?? localized(
            english: "Prefer WPS Office, then Microsoft Excel",
            chinese: "默认优先 WPS Office，其次 Microsoft Excel"
        )
    }

    var smallFileRoutingSummary: String {
        localized(
            english: "Finder-opened files at or below 100 MiB prefer WPS Office, then Microsoft Excel, unless you choose a different global app here. Compressed .gz/.bgz files always stay in iData.",
            chinese: "通过 Finder 交给 iData 且小于等于 100 MiB 的文件，默认优先交给 WPS Office，其次 Microsoft Excel；也可在此改为其他统一应用。.gz/.bgz 压缩文件始终在 iData 中打开。"
        )
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
                    userInfo: [NSLocalizedDescriptionKey: localized(
                        english: "Requested tutorial chapter was not found.",
                        chinese: "未找到所请求的教程章节。"
                    )]
                )
            }

            let sampleURL = try makeTutorialSampleFile()
            tutorialSampleFileURL = sampleURL
            openExternalFile(sampleURL)

            guard activeSession?.currentFileURL?.standardizedFileURL == sampleURL.standardizedFileURL else {
                finishTutorial()
                if errorMessage == nil {
                    errorMessage = localized(
                        english: "Could not start tutorial because the sample table failed to open. Check VisiData path in Preferences.",
                        chinese: "无法启动教程，因为示例表格未能打开。请在偏好设置中检查 VisiData 路径。"
                    )
                }
                return
            }

            beginTutorialGuide(chapterID: chapter.id)
            isTutorialHubPresented = false
            statusMessage = localized(
                english: "Tutorial started with \(sampleURL.lastPathComponent). Follow the floating coach in the session.",
                chinese: "已用 \(sampleURL.lastPathComponent) 启动教程。请跟随会话中的浮动引导继续操作。"
            )
            errorMessage = nil
        } catch {
            finishTutorial()
            statusMessage = nil
            errorMessage = localized(
                english: "Could not prepare tutorial sample data: \(error.localizedDescription)",
                chinese: "无法准备教程示例数据：\(error.localizedDescription)"
            )
        }
    }

    func beginTutorialGuide(chapterID: String = AppModel.defaultTutorialChapterID) {
        guard let chapter = tutorialChapters.first(where: { $0.id == chapterID }) else {
            return
        }
        isTutorialActive = true
        activeTutorialChapterID = chapter.id
        tutorialStepIndex = 0
        isTutorialCoachExpanded = true
        markTutorialProgress(chapterID: chapter.id, completedStepCount: 0)
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
        statusMessage = localized(
            english: "Tutorial completed. Open any file to continue exploring with VisiData.",
            chinese: "教程已完成。打开任意文件即可继续探索 VisiData。"
        )
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
            errorMessage = localized(
                english: "Drop a regular file, not a folder. iData streams compressed .gz/.bgz files without extracting.",
                chinese: "请拖入文件，不要拖入文件夹。iData 会直接流式读取 .gz/.bgz 压缩文件。"
            )
            return
        }

        openExternalFile(url)
    }

    func handleExternalFileOpen(_ urls: [URL]) -> ExternalOpenPresentationDecision {
        guard let url = Self.firstSupportedFile(in: urls) else {
            guard !urls.isEmpty else {
                return .stayBackground
            }

            statusMessage = nil
            errorMessage = localized(
                english: "Drop a regular file, not a folder. iData streams compressed .gz/.bgz files without extracting.",
                chinese: "请拖入文件，不要拖入文件夹。iData 会直接流式读取 .gz/.bgz 压缩文件。"
            )
            return .activateApp
        }

        switch routeExternalFile(url) {
        case .openedInIData, .presentedError:
            return .activateApp
        case .forwardedToAlternateApp:
            return .stayBackground
        }
    }

    func routeExternalFile(_ url: URL) -> ExternalOpenAction {
        guard Self.supportsTableFile(url) else {
            statusMessage = nil
            errorMessage = localized(
                english: "The selected item is not a regular file. iData opens most file suffixes directly and streams .gz/.bgz files without extracting.",
                chinese: "所选内容不是普通文件。iData 会直接打开大多数文件后缀，并对 .gz/.bgz 文件进行流式读取而不解压。"
            )
            return .presentedError
        }

        let lookupExtension = Self.lookupExtension(for: url)
        if
            let fileSize = fileSizeProvider(url),
            fileSize <= Self.largeFileOpenThresholdBytes,
            !Self.compressionSuffixes.contains(lookupExtension)
        {
            let candidateApplications = preferredSmallFileApplicationCandidates(
                for: url,
                lookupExtension: lookupExtension
            )

            guard !candidateApplications.isEmpty else {
                statusMessage = nil
                errorMessage = localized(
                    english: "Could not find a non-iData app to open \(url.lastPathComponent).",
                    chinese: "找不到可用于打开 \(url.lastPathComponent) 的非 iData 应用。"
                )
                return .presentedError
            }

            for alternateApp in candidateApplications {
                guard FileManager.default.fileExists(atPath: alternateApp.url.path) else {
                    if preferredSmallFileApplication == alternateApp {
                        preferredSmallFileApplication = nil
                    }
                    continue
                }

                if externalFileOpener.open(url, withApplicationAt: alternateApp.url) {
                    statusMessage = nil
                    errorMessage = nil
                    return .forwardedToAlternateApp(appName: alternateApp.displayName)
                }
            }

            statusMessage = nil
            errorMessage = localized(
                english: "Could not open \(url.lastPathComponent) with any configured non-iData app.",
                chinese: "无法使用任何已配置的非 iData 应用打开 \(url.lastPathComponent)。"
            )
            return .presentedError
        }

        openExternalFile(url)
        if activeSession?.currentFileURL?.standardizedFileURL == url.standardizedFileURL {
            return .openedInIData
        }
        return .presentedError
    }

    func openExternalFile(_ url: URL) {
        guard Self.supportsTableFile(url) else {
            statusMessage = nil
            errorMessage = localized(
                english: "The selected item is not a regular file. iData opens most file suffixes directly and streams .gz/.bgz files without extracting.",
                chinese: "所选内容不是普通文件。iData 会直接打开大多数文件后缀，并对 .gz/.bgz 文件进行流式读取而不解压。"
            )
            return
        }

        if
            let session = activeSession,
            session.currentFileURL?.standardizedFileURL == url.standardizedFileURL,
            session.isRunning,
            session.errorMessage == nil
        {
            session.focusTerminalDisplay()
            statusMessage = localized(
                english: "Already showing \(url.lastPathComponent).",
                chinese: "当前已在显示 \(url.lastPathComponent)。"
            )
            errorMessage = nil
            return
        }

        do {
            let explicitPath = normalizedVDExecutablePath()
            let session = activeSession ?? VisiDataSessionController()
            
            try session.open(fileURL: url, explicitVDPath: explicitPath)
            
            if activeSession !== session {
                activeSession = session
            }
            
            lastOpenedFile = url
            performAnimatedMutation(.spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.15)) {
                recentFilesStore.record(url, maxCount: Self.recentFilesLimit)
                refreshRecentFiles()
            }
            if isTutorialActive, let tutorialSampleFileURL, tutorialSampleFileURL.standardizedFileURL != url.standardizedFileURL {
                finishTutorial()
                statusMessage = localized(
                    english: "Opened \(url.lastPathComponent) inside iData. Tutorial ended because a different file is active.",
                    chinese: "已在 iData 中打开 \(url.lastPathComponent)。由于当前激活的是其他文件，教程已结束。"
                )
                errorMessage = nil
                return
            }
            statusMessage = localized(
                english: "Opened \(url.lastPathComponent) inside iData.",
                chinese: "已在 iData 中打开 \(url.lastPathComponent)。"
            )
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
        statusMessage = localized(english: "Copied file path.", chinese: "已复制文件路径。")
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
        statusMessage = localized(
            english: "Removed \(url.lastPathComponent) from recent files.",
            chinese: "已将 \(url.lastPathComponent) 从最近文件中移除。"
        )
        errorMessage = nil
    }

    func clearRecentFiles() {
        performAnimatedMutation(.spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.1)) {
            recentFilesStore.clear()
            defaults.removeObject(forKey: Self.pinnedRecentFilesKey)
            recentFiles = []
        }
        statusMessage = localized(english: "Cleared recent files.", chinese: "已清空最近文件。")
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
                statusMessage = localized(
                    english: "Unpinned \(url.lastPathComponent).",
                    chinese: "已取消置顶 \(url.lastPathComponent)。"
                )
            } else {
                pinnedFiles.insert(url, at: 0)
                statusMessage = localized(
                    english: "Pinned \(url.lastPathComponent) to the top.",
                    chinese: "已将 \(url.lastPathComponent) 置顶。"
                )
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
            statusMessage = localized(
                english: "VisiData is already available at \(path).",
                chinese: "VisiData 已可用：\(path)。"
            )
            errorMessage = nil
            return
        }

        let helperPath = sharedVisiDataHelperPathIfExecutable()
        let scriptContents = Self.makeVisiDataInstallerScript(helperPath: helperPath)

        do {
            let tempScriptURL = try Self.writeTemporaryExecutableScript(contents: scriptContents)
            try Self.openScriptInTerminal(tempScriptURL)
            statusMessage = localized(
                english: "Opened Terminal for one-click VisiData setup.",
                chinese: "已打开终端，开始一键配置 VisiData。"
            )
            errorMessage = nil
        } catch {
            statusMessage = nil
            errorMessage = localized(
                english: "Could not start one-click VisiData setup: \(error.localizedDescription)",
                chinese: "无法启动一键配置 VisiData：\(error.localizedDescription)"
            )
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
            errorMessage = localized(
                english: "Could not recognize the .\(fileExtension) suffix.",
                chinese: "无法识别 .\(fileExtension) 的后缀。"
            )
            statusMessage = nil
            return
        }

        let wasIDataDefault = FileTypeAssociation.isIDataDefaultApp(forExtension: lookupExtension)
        updateAssociationStatus(forLookupExtension: lookupExtension, isDefault: wasIDataDefault)

        isSettingFormatDefault = true
        settingFormatExtension = fileExtension

        Task {
            if wasIDataDefault {
                let storedPreviousDefaultApp = await MainActor.run { [lookupExtension] in
                    previousDefaultAppByExtension[lookupExtension]
                }
                let fallbackCandidates = FileTypeAssociation.alternativeApplicationCandidates(forExtension: lookupExtension)
                let restoreCandidates = restoreApplicationCandidates(
                    storedPreviousDefault: storedPreviousDefaultApp,
                    fallbackCandidates: fallbackCandidates
                )
                var restoreTarget: DefaultApplicationHandler?
                var restoreResult: FileTypeAssociationSetResult = .missingPreviousDefault
                for candidate in restoreCandidates {
                    let candidateResult = await FileTypeAssociation.setDefaultApp(
                        at: candidate.url,
                        forExtension: lookupExtension
                    )
                    if candidateResult == .success {
                        restoreTarget = candidate
                        restoreResult = .success
                        break
                    }
                    restoreResult = candidateResult
                }
                let isNowDefault = await settledIDataDefaultState(
                    forExtension: lookupExtension,
                    expectedIsDefault: false,
                    afterRequestSucceeded: restoreResult == .success
                )

                await MainActor.run {
                    updateAssociationStatus(forLookupExtension: lookupExtension, isDefault: isNowDefault)
                    let shownExtension = lookupExtension

                    if !isNowDefault {
                        forgetPreviousDefaultApp(forLookupExtension: lookupExtension)
                        if let restoreTarget {
                            statusMessage = localized(
                                english: "Restored the default app for .\(shownExtension) to \(restoreTarget.displayName).",
                                chinese: "已恢复 .\(shownExtension) 默认应用为 \(restoreTarget.displayName)。"
                            )
                            errorMessage = nil
                        } else {
                            statusMessage = localized(
                                english: "Removed iData as the default app for .\(shownExtension).",
                                chinese: "已取消 .\(shownExtension) 默认用 iData 打开。"
                            )
                            errorMessage = nil
                        }
                    } else if restoreResult == .success {
                        statusMessage = localized(
                            english: "macOS accepted the restore request, but .\(shownExtension) is still set to iData. Try again and confirm the system prompt.",
                            chinese: "系统已收到恢复请求，但 .\(shownExtension) 仍默认 iData。请再试一次并确认系统提示。"
                        )
                        errorMessage = nil
                    } else if restoreResult == .missingPreviousDefault {
                        errorMessage = localized(
                            english: "Could not find a non-iData app to restore .\(shownExtension). Open this format once with another app in Finder, then try again.",
                            chinese: "找不到可用于恢复 .\(shownExtension) 的非 iData 应用。请先在 Finder 里用其他应用打开一次该格式，再重试。"
                        )
                        statusMessage = nil
                    } else {
                        errorMessage = localized(
                            english: "Could not restore the default app for .\(shownExtension): \(restoreResult.userMessage)",
                            chinese: "无法恢复 .\(shownExtension) 的默认应用：\(restoreResult.userMessage)"
                        )
                        statusMessage = nil
                    }

                    isSettingFormatDefault = false
                    settingFormatExtension = nil
                }
                return
            }

            let previousDefaultApp = FileTypeAssociation.currentDefaultApp(forExtension: lookupExtension)

            // Remember the previous default app BEFORE we attempt to change it.
            // macOS may apply the change asynchronously, so if we wait until after
            // checking isNowDefault, we risk never saving the old default.
            if
                let previousDefaultApp,
                !FileTypeAssociation.isIDataBundleIdentifier(previousDefaultApp.bundleIdentifier)
            {
                await MainActor.run {
                    rememberPreviousDefaultApp(previousDefaultApp, forLookupExtension: lookupExtension)
                }
            }

            let setResult = await FileTypeAssociation.setIDataAsDefaultApp(forExtension: lookupExtension)
            let isNowDefault = await settledIDataDefaultState(
                forExtension: lookupExtension,
                expectedIsDefault: true,
                afterRequestSucceeded: setResult == .success
            )

            await MainActor.run {
                updateAssociationStatus(forLookupExtension: lookupExtension, isDefault: isNowDefault)
                let shownExtension = lookupExtension

                if isNowDefault {
                    statusMessage = localized(
                        english: "Set iData as the default app for .\(shownExtension).",
                        chinese: "已设置 .\(shownExtension) 默认用 iData 打开。"
                    )
                    errorMessage = nil
                } else if setResult == .success {
                    statusMessage = localized(
                        english: "macOS accepted the request, but .\(shownExtension) has not switched to iData yet. Try again and confirm the system prompt.",
                        chinese: "系统已收到设置请求，但 .\(shownExtension) 还未切换到 iData。请再试一次并确认系统提示。"
                    )
                    errorMessage = nil
                } else {
                    // Setting failed, forget the saved previous default since no change was made
                    forgetPreviousDefaultApp(forLookupExtension: lookupExtension)
                    errorMessage = localized(
                        english: "Could not set the default app for .\(shownExtension): \(setResult.userMessage)",
                        chinese: "无法设置 .\(shownExtension) 默认应用：\(setResult.userMessage)"
                    )
                    statusMessage = nil
                }

                isSettingFormatDefault = false
                settingFormatExtension = nil
            }
        }
    }

    func refreshFormatAssociationStatuses(forExtensions fileExtensions: [String]) {
        let lookupExtensions = Set(
            fileExtensions
                .map(Self.associationExtension(for:))
                .filter { !$0.isEmpty }
        )

        for lookupExtension in lookupExtensions {
            let isDefault = FileTypeAssociation.isIDataDefaultApp(forExtension: lookupExtension)
            updateAssociationStatus(forLookupExtension: lookupExtension, isDefault: isDefault)
        }
    }

    @discardableResult
    func handleDroppedFiles(_ urls: [URL]) -> Bool {
        guard let fileURL = Self.firstSupportedFile(in: urls) else {
            guard !urls.isEmpty else {
                return false
            }

            statusMessage = nil
            errorMessage = localized(
                english: "Drop a regular file, not a folder. iData opens most file suffixes directly and streams .gz/.bgz files without extracting.",
                chinese: "请拖入文件，不要拖入文件夹。iData 可直接打开大多数文件类型，并会流式读取 .gz/.bgz 压缩文件。"
            )
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
        echo "================================"
        echo ""

        if command -v vd >/dev/null 2>&1; then
          echo "✓ vd already detected at: $(command -v vd)"
          echo ""
        fi

        # ── Step 1: Ensure pipx is available ──
        if ! command -v pipx >/dev/null 2>&1; then
          if command -v brew >/dev/null 2>&1; then
            echo "▸ Installing pipx via Homebrew..."
            if ! brew install pipx; then
              echo "▸ Homebrew pipx install failed, trying python3 fallback..."
            fi
          fi

          if ! command -v pipx >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
            echo "▸ Installing pipx via python3..."
            python3 -m pip install --user pipx
            python3 -m pipx ensurepath || true
          fi

          export PATH="$HOME/.local/bin:$(brew --prefix 2>/dev/null || echo /opt/homebrew)/bin:$PATH"

          if ! command -v pipx >/dev/null 2>&1; then
            echo "✗ Could not install pipx automatically. Install pipx manually, then retry."
            read '?Press Return to close...'
            exit 1
          fi
        fi

        echo "✓ pipx is available at: $(command -v pipx)"
        echo ""

        # ── Step 2: Install or upgrade VisiData via pipx ──
        if pipx list 2>/dev/null | grep -q visidata; then
          echo "▸ Upgrading VisiData..."
          if ! pipx upgrade visidata; then
            echo "✗ Failed to upgrade VisiData with pipx."
            read '?Press Return to close this installer...'
            exit 1
          fi
        else
          echo "▸ Installing VisiData via pipx..."
          if ! pipx install visidata; then
            echo "✗ Failed to install VisiData with pipx."
            read '?Press Return to close this installer...'
            exit 1
          fi
        fi
        echo ""

        # ── Step 3: Inject Excel & common format plugins ──
        echo "▸ Injecting Excel and compression plugins (openpyxl, pyxlsb, xlrd, zstandard)..."
        if ! pipx inject visidata openpyxl pyxlsb xlrd zstandard; then
          echo "✗ Failed to inject plugin dependencies into pipx visidata."
          read '?Press Return to close this installer...'
          exit 1
        fi
        echo ""

        # ── Verification ──
        if ! command -v vd >/dev/null 2>&1; then
          echo "✗ Setup finished but vd is still not on PATH."
          echo "  Run 'pipx ensurepath', reopen Terminal, then retry."
          read '?Press Return to close this installer...'
          exit 1
        fi

        if ! vd --version >/dev/null 2>&1; then
          echo "✗ Found vd, but version check failed."
          read '?Press Return to close this installer...'
          exit 1
        fi

        echo "================================"
        echo "Verification:"
        echo "  vd path:    $(command -v vd)"
        echo "  vd version: $(vd --version 2>/dev/null)"
        echo ""
        echo "✓ Setup complete. Return to iData and reopen your file."
        echo "  If iData does not detect vd, use Auto Detect in Preferences."
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

    static func fileSizeInBytes(for url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        if let size = values?.fileSize {
            return Int64(size)
        }
        if let size = values?.totalFileAllocatedSize {
            return Int64(size)
        }
        if let size = values?.fileAllocatedSize {
            return Int64(size)
        }
        return nil
    }

    static func canSetAssociationExtensionInput(_ rawInput: String) -> Bool {
        !associationExtension(for: rawInput).isEmpty
    }

    static func lookupExtension(for url: URL) -> String {
        let fileName = url.lastPathComponent.lowercased()
        guard !fileName.isEmpty else {
            return associationExtension(for: url.pathExtension)
        }

        let formatsBySpecificity = supportedFormats.sorted { lhs, rhs in
            lhs.fileExtension.count > rhs.fileExtension.count
        }

        for format in formatsBySpecificity {
            let suffix = ".\(format.fileExtension.lowercased())"
            if fileName.hasSuffix(suffix) {
                return associationExtension(for: format.fileExtension)
            }
        }

        return associationExtension(for: url.pathExtension)
    }

    @MainActor
    static func resolveAlternateApplication(
        for _: URL,
        lookupExtension: String,
        storedPreviousDefaults: [String: DefaultApplicationHandler]
    ) -> DefaultApplicationHandler? {
        guard !lookupExtension.isEmpty else {
            return nil
        }

        return preferredSmallFileOpenApplication(
            storedPreviousDefault: storedPreviousDefaults[lookupExtension],
            fallbackCandidates: FileTypeAssociation.alternativeApplicationCandidates(forExtension: lookupExtension)
        )
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

    private func preferredSmallFileApplicationCandidates(for url: URL, lookupExtension: String) -> [DefaultApplicationHandler] {
        var candidates: [DefaultApplicationHandler] = []
        var seenBundleIdentifiers: Set<String> = []

        if
            let preferredSmallFileApplication,
            !FileTypeAssociation.isIDataBundleIdentifier(preferredSmallFileApplication.bundleIdentifier),
            seenBundleIdentifiers.insert(preferredSmallFileApplication.bundleIdentifier).inserted
        {
            candidates.append(preferredSmallFileApplication)
        }

        if
            let fallback = alternateApplicationResolver(url, lookupExtension, previousDefaultAppByExtension),
            !FileTypeAssociation.isIDataBundleIdentifier(fallback.bundleIdentifier),
            seenBundleIdentifiers.insert(fallback.bundleIdentifier).inserted
        {
            candidates.append(fallback)
        }

        return candidates
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

struct DefaultApplicationHandler: Equatable, Sendable {
    let url: URL
    let bundleIdentifier: String
    let displayName: String
}

@MainActor
func restoreApplicationCandidates(
    storedPreviousDefault: DefaultApplicationHandler?,
    fallbackCandidates: [DefaultApplicationHandler] = []
) -> [DefaultApplicationHandler] {
    var candidates: [DefaultApplicationHandler] = []
    var seenBundleIdentifiers: Set<String> = []

    if
        let storedPreviousDefault,
        !FileTypeAssociation.isIDataBundleIdentifier(storedPreviousDefault.bundleIdentifier)
    {
        candidates.append(storedPreviousDefault)
        seenBundleIdentifiers.insert(storedPreviousDefault.bundleIdentifier)
    }

    for fallback in fallbackCandidates where !FileTypeAssociation.isIDataBundleIdentifier(fallback.bundleIdentifier) {
        guard seenBundleIdentifiers.insert(fallback.bundleIdentifier).inserted else {
            continue
        }
        candidates.append(fallback)
    }

    return candidates
}

@MainActor
func preferredRestoreApplication(
    storedPreviousDefault: DefaultApplicationHandler?,
    fallbackCandidates: [DefaultApplicationHandler] = []
) -> DefaultApplicationHandler? {
    restoreApplicationCandidates(
        storedPreviousDefault: storedPreviousDefault,
        fallbackCandidates: fallbackCandidates
    ).first
}

@MainActor
func preferredSmallFileOpenApplication(
    storedPreviousDefault: DefaultApplicationHandler?,
    fallbackCandidates: [DefaultApplicationHandler] = []
) -> DefaultApplicationHandler? {
    preferredSmallFileOpenCandidates(
        storedPreviousDefault: storedPreviousDefault,
        fallbackCandidates: fallbackCandidates
    ).first
}

@MainActor
func preferredSmallFileOpenCandidates(
    storedPreviousDefault: DefaultApplicationHandler?,
    fallbackCandidates: [DefaultApplicationHandler] = []
) -> [DefaultApplicationHandler] {
    var candidates: [DefaultApplicationHandler] = []
    var seenBundleIdentifiers: Set<String> = []

    let orderedFallbacks = fallbackCandidates.sorted { lhs, rhs in
        let lhsRank = smallFileOpenPriorityRank(for: lhs)
        let rhsRank = smallFileOpenPriorityRank(for: rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    for fallback in orderedFallbacks where !FileTypeAssociation.isIDataBundleIdentifier(fallback.bundleIdentifier) {
        guard seenBundleIdentifiers.insert(fallback.bundleIdentifier).inserted else {
            continue
        }
        candidates.append(fallback)
    }

    if
        let storedPreviousDefault,
        !FileTypeAssociation.isIDataBundleIdentifier(storedPreviousDefault.bundleIdentifier),
        seenBundleIdentifiers.insert(storedPreviousDefault.bundleIdentifier).inserted
    {
        candidates.append(storedPreviousDefault)
    }

    return candidates
}

private func smallFileOpenPriorityRank(for handler: DefaultApplicationHandler) -> Int {
    let displayName = handler.displayName.lowercased()

    switch handler.bundleIdentifier {
    case "cn.wps.Office":
        return 0
    case "com.microsoft.Excel":
        return 1
    default:
        if displayName.contains("wps") {
            return 0
        }
        if displayName.contains("excel") {
            return 1
        }
        return 2
    }
}

@MainActor
func settledIDataDefaultState(
    forExtension fileExtension: String,
    expectedIsDefault: Bool,
    afterRequestSucceeded requestSucceeded: Bool,
    checker: @MainActor (String) -> Bool = FileTypeAssociation.isIDataDefaultApp(forExtension:),
    maxAttempts: Int = 10,
    pollIntervalNanoseconds: UInt64 = 200_000_000
) async -> Bool {
    var latest = checker(fileExtension)
    guard requestSucceeded, latest != expectedIsDefault else {
        return latest
    }

    for _ in 0..<maxAttempts {
        if pollIntervalNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        latest = checker(fileExtension)
        if latest == expectedIsDefault {
            return latest
        }
    }

    return latest
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
private struct PreferredSmallFileApplicationStore {
    let defaults: UserDefaults

    func load() -> DefaultApplicationHandler? {
        guard
            let data = defaults.data(forKey: AppModel.preferredSmallFileApplicationKey),
            let handler = try? JSONDecoder().decode(PersistedDefaultApplicationHandler.self, from: data)
        else {
            return nil
        }

        return handler.handler
    }

    func store(_ handler: DefaultApplicationHandler?) {
        guard let handler else {
            defaults.removeObject(forKey: AppModel.preferredSmallFileApplicationKey)
            return
        }

        if let data = try? JSONEncoder().encode(PersistedDefaultApplicationHandler(handler)) {
            defaults.set(data, forKey: AppModel.preferredSmallFileApplicationKey)
        }
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
        bundleIdentifier == iDataBundleIdentifier || bundleIdentifier.starts(with: "io.github.leoarrow.idata")
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
        return isIDataBundleIdentifier(currentDefaultApp.bundleIdentifier)
    }

    static func currentDefaultApp(forExtension fileExtension: String) -> DefaultApplicationHandler? {
        guard
            let contentType = contentType(forExtension: fileExtension),
            let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: contentType)
        else {
            return nil
        }

        return applicationHandler(for: defaultAppURL)
    }

    static func alternativeApplicationCandidates(forExtension fileExtension: String) -> [DefaultApplicationHandler] {
        guard let contentType = contentType(forExtension: fileExtension) else {
            return []
        }

        var candidates: [DefaultApplicationHandler] = []
        var seenBundleIdentifiers: Set<String> = []

        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: contentType) {
            guard let handler = applicationHandler(for: appURL) else {
                continue
            }
            guard !isIDataBundleIdentifier(handler.bundleIdentifier) else {
                continue
            }
            guard seenBundleIdentifiers.insert(handler.bundleIdentifier).inserted else {
                continue
            }
            candidates.append(handler)
        }

        if
            candidates.isEmpty,
            contentType.conforms(to: .plainText),
            let textEditURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit"),
            let textEdit = applicationHandler(for: textEditURL),
            !isIDataBundleIdentifier(textEdit.bundleIdentifier)
        {
            candidates.append(textEdit)
        }

        return candidates
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

    private static func withProbeURL<T>(forExtension fileExtension: String, _ body: (URL) -> T?) -> T? {
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
            return body(probeURL)
        } catch {
            return nil
        }
    }

    static func applicationHandler(for appURL: URL) -> DefaultApplicationHandler? {
        guard
            let bundle = Bundle(url: appURL),
            let bundleIdentifier = bundle.bundleIdentifier
        else {
            return nil
        }

        let displayName =
            (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
                ?? FileManager.default.displayName(atPath: appURL.path)

        return DefaultApplicationHandler(
            url: appURL,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
    }
}
