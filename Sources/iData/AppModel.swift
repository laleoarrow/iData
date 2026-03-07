import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(iDataCore)
import iDataCore
#endif

@MainActor
final class AppModel: ObservableObject {
    struct SupportedFormat {
        let displayName: String
        let fileExtension: String
        let contentType: UTType
    }

    @Published var activeSession: VisiDataSessionController?
    @Published var recentFiles: [URL]
    @Published var lastOpenedFile: URL?
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var vdExecutablePath: String {
        didSet {
            defaults.set(vdExecutablePath, forKey: Self.vdExecutablePathKey)
        }
    }

    private let defaults: UserDefaults
    private let recentFilesStore: RecentFilesStore

    static let vdExecutablePathKey = "vdExecutablePath"
    static let recentFilesLimit = 10
    static let supportedFormats: [SupportedFormat] = [
        SupportedFormat(displayName: "CSV", fileExtension: "csv", contentType: UTType(filenameExtension: "csv") ?? .data),
        SupportedFormat(displayName: "TSV", fileExtension: "tsv", contentType: UTType(filenameExtension: "tsv") ?? .data),
        SupportedFormat(displayName: "Plain Text", fileExtension: "txt", contentType: UTType(filenameExtension: "txt") ?? .plainText),
        SupportedFormat(displayName: "JSON", fileExtension: "json", contentType: UTType.json),
        SupportedFormat(displayName: "JSON Lines", fileExtension: "jsonl", contentType: UTType(filenameExtension: "jsonl") ?? .data),
        SupportedFormat(displayName: "Excel Workbook", fileExtension: "xlsx", contentType: UTType(filenameExtension: "xlsx") ?? .data),
        SupportedFormat(displayName: "Compressed CSV", fileExtension: "csv.gz", contentType: UTType(filenameExtension: "gz") ?? .data),
        SupportedFormat(displayName: "Compressed TSV", fileExtension: "tsv.gz", contentType: UTType(filenameExtension: "gz") ?? .data),
        SupportedFormat(displayName: "Compressed Text", fileExtension: "txt.gz", contentType: UTType(filenameExtension: "gz") ?? .data),
    ]
    static var supportedFormatExtensions: [String] {
        supportedFormats.map(\.fileExtension)
    }
    static var supportedFormatHelpText: String {
        supportedFormats
            .map { "\($0.displayName) (.\($0.fileExtension))" }
            .joined(separator: ", ")
    }

    init(
        defaults: UserDefaults = .standard,
        recentFilesStore: RecentFilesStore? = nil
    ) {
        self.defaults = defaults
        self.recentFilesStore = recentFilesStore ?? RecentFilesStore(defaults: defaults)
        self.recentFiles = (recentFilesStore ?? RecentFilesStore(defaults: defaults)).load()
        self.vdExecutablePath = defaults.string(forKey: Self.vdExecutablePathKey) ?? ""
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.supportedContentTypes

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
            errorMessage = "Unsupported format. Supported formats: \(Self.supportedFormatHelpText)."
            return
        }

        openExternalFile(url)
    }

    func openExternalFile(_ url: URL) {
        guard Self.supportsTableFile(url) else {
            statusMessage = nil
            errorMessage = "Unsupported format. Supported formats: \(Self.supportedFormatHelpText)."
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
            recentFilesStore.record(url, maxCount: Self.recentFilesLimit)
            recentFiles = recentFilesStore.load()
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
        recentFilesStore.remove(url)
        recentFiles = recentFilesStore.load()
        statusMessage = "Removed \(url.lastPathComponent) from recent files."
        errorMessage = nil
    }

    func clearRecentFiles() {
        recentFilesStore.clear()
        recentFiles = []
        statusMessage = "Cleared recent files."
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
    }

    @discardableResult
    func handleDroppedFiles(_ urls: [URL]) -> Bool {
        guard let fileURL = Self.firstSupportedFile(in: urls) else {
            guard !urls.isEmpty else {
                return false
            }

            statusMessage = nil
            errorMessage = "Unsupported format. Supported formats: \(Self.supportedFormatHelpText)."
            return false
        }

        openExternalFile(fileURL)
        return true
    }

    private func normalizedVDExecutablePath() -> String? {
        let trimmed = vdExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func supportsTableFile(_ url: URL) -> Bool {
        let lowercaseName = url.lastPathComponent.lowercased()
        return supportedFormatExtensions.contains { lowercaseName.hasSuffix(".\($0)") || lowercaseName == $0 }
    }

    static func firstSupportedFile(in urls: [URL]) -> URL? {
        urls.first(where: supportsTableFile)
    }

    private static var supportedContentTypes: [UTType] {
        var contentTypes: [UTType] = []
        for contentType in supportedFormats.map(\.contentType) where !contentTypes.contains(contentType) {
            contentTypes.append(contentType)
        }
        return contentTypes
    }
}
