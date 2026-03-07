import Foundation

public struct RecentFilesStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "recentFiles") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [URL] {
        let paths = defaults.stringArray(forKey: key) ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }

    public func record(_ url: URL, maxCount: Int) {
        let updated = Self.updatedRecentFiles(recording: url, current: load(), maxCount: maxCount)
        let paths = updated.map(\.path)
        defaults.set(paths, forKey: key)
    }

    public func remove(_ url: URL) {
        let updated = Self.updatedRecentFiles(removing: url, current: load())
        let paths = updated.map(\.path)
        defaults.set(paths, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }

    public static func updatedRecentFiles(
        recording url: URL,
        current: [URL],
        maxCount: Int
    ) -> [URL] {
        let filtered = current.filter { $0.standardizedFileURL != url.standardizedFileURL }
        return Array(([url] + filtered).prefix(maxCount))
    }

    public static func updatedRecentFiles(
        removing url: URL,
        current: [URL]
    ) -> [URL] {
        current.filter { $0.standardizedFileURL != url.standardizedFileURL }
    }

    public static func updatedRecentFilesClearingAll(current: [URL]) -> [URL] {
        []
    }
}
