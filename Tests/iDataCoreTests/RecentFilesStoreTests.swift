import Foundation
import Testing
@testable import iDataCore

struct RecentFilesStoreTests {
    @Test
    func recordingFileMovesItToFront() {
        let first = URL(fileURLWithPath: "/tmp/one.csv")
        let second = URL(fileURLWithPath: "/tmp/two.csv")

        let updated = RecentFilesStore.updatedRecentFiles(
            recording: first,
            current: [second, first],
            maxCount: 5
        )

        #expect(updated == [first, second])
    }

    @Test
    func recordingFileRespectsMaximumCount() {
        let files = [
            URL(fileURLWithPath: "/tmp/one.csv"),
            URL(fileURLWithPath: "/tmp/two.csv"),
            URL(fileURLWithPath: "/tmp/three.csv"),
        ]

        let updated = RecentFilesStore.updatedRecentFiles(
            recording: URL(fileURLWithPath: "/tmp/four.csv"),
            current: files,
            maxCount: 3
        )

        #expect(updated.map(\.lastPathComponent) == ["four.csv", "one.csv", "two.csv"])
    }

    @Test
    func removingFileDropsItAndKeepsOrder() {
        let files = [
            URL(fileURLWithPath: "/tmp/one.csv"),
            URL(fileURLWithPath: "/tmp/two.csv"),
            URL(fileURLWithPath: "/tmp/three.csv"),
        ]

        let updated = RecentFilesStore.updatedRecentFiles(
            removing: URL(fileURLWithPath: "/tmp/two.csv"),
            current: files
        )

        #expect(updated.map(\.lastPathComponent) == ["one.csv", "three.csv"])
    }

    @Test
    func removingMissingFileLeavesListUntouched() {
        let files = [
            URL(fileURLWithPath: "/tmp/one.csv"),
            URL(fileURLWithPath: "/tmp/two.csv"),
        ]

        let updated = RecentFilesStore.updatedRecentFiles(
            removing: URL(fileURLWithPath: "/tmp/three.csv"),
            current: files
        )

        #expect(updated == files)
    }

    @Test
    func clearingFilesRemovesEverything() {
        let files = [
            URL(fileURLWithPath: "/tmp/one.csv"),
            URL(fileURLWithPath: "/tmp/two.csv"),
        ]

        let updated = RecentFilesStore.updatedRecentFilesClearingAll(current: files)

        #expect(updated.isEmpty)
    }
}
