import AppKit
import Foundation
import SwiftUI
#if canImport(iDataCore)
import iDataCore
#endif

@MainActor
final class AppModel: ObservableObject {
    enum VisiDataDependencyState: Equatable {
        case available(path: String)
        case missing
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

    private let defaults: UserDefaults
    private let recentFilesStore: RecentFilesStore
    private let executableChecker: any ExecutableChecking
    private let environmentPathProvider: () -> String

    static let vdExecutablePathKey = "vdExecutablePath"
    static let pinnedRecentFilesKey = "pinnedRecentFiles"
    static let reduceAnimationsKey = "reduceAnimations"
    static let recentFilesLimit = 10
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

    init(
        defaults: UserDefaults = .standard,
        recentFilesStore: RecentFilesStore? = nil,
        executableChecker: any ExecutableChecking = LocalExecutableChecker(),
        environmentPathProvider: @escaping () -> String = { ProcessInfo.processInfo.environment["PATH"] ?? "" }
    ) {
        self.defaults = defaults
        self.recentFilesStore = recentFilesStore ?? RecentFilesStore(defaults: defaults)
        self.executableChecker = executableChecker
        self.environmentPathProvider = environmentPathProvider
        let initialRecentFiles = (recentFilesStore ?? RecentFilesStore(defaults: defaults)).load()
        self.recentFiles = Self.orderedRecentFiles(
            initialRecentFiles,
            pinned: Self.loadPinnedRecentFiles(defaults: defaults)
        )
        self.reduceAnimations = defaults.object(forKey: Self.reduceAnimationsKey) as? Bool ?? false
        self.vdExecutablePath = defaults.string(forKey: Self.vdExecutablePathKey) ?? ""
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

    var appBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var animationsEnabled: Bool {
        !reduceAnimations
    }

    func appVersionDisplay(revealingBuild: Bool) -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        if revealingBuild {
            return "v\(shortVersion) (\(appBuildNumber))"
        }
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
            statusMessage = "Opened \(url.lastPathComponent) inside iData."
            errorMessage = nil
        } catch {
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

    func clearError() {
        errorMessage = nil
    }

    func shutdown() {
        activeSession?.terminate()
        activeSession = nil
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
