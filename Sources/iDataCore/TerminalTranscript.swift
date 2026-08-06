import Foundation

public struct TerminalTranscript {
    private static let compactionThreshold = 1_024

    private var storedChunks: [Data] = []
    private var firstLiveChunkIndex = 0

    public var chunks: [Data] {
        guard firstLiveChunkIndex > 0 else {
            return storedChunks
        }
        return Array(storedChunks[firstLiveChunkIndex...])
    }

    public private(set) var totalBytes = 0
    public let maximumBytes: Int

    var backingChunkCountForTesting: Int {
        storedChunks.count
    }

    public init(maximumBytes: Int = 8 * 1024 * 1024) {
        self.maximumBytes = max(1, maximumBytes)
    }

    public mutating func reset() {
        storedChunks.removeAll(keepingCapacity: true)
        firstLiveChunkIndex = 0
        totalBytes = 0
    }

    public mutating func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        if data.count >= maximumBytes {
            let suffix = Data(data.suffix(maximumBytes))
            storedChunks = [suffix]
            firstLiveChunkIndex = 0
            totalBytes = suffix.count
            return
        }

        storedChunks.append(data)
        totalBytes += data.count
        trimIfNeeded()
    }

    private mutating func trimIfNeeded() {
        while totalBytes > maximumBytes {
            let discardedByteCount = storedChunks[firstLiveChunkIndex].count
            storedChunks[firstLiveChunkIndex] = Data()
            firstLiveChunkIndex += 1
            totalBytes -= discardedByteCount
        }

        guard
            firstLiveChunkIndex >= Self.compactionThreshold,
            firstLiveChunkIndex >= storedChunks.count - firstLiveChunkIndex
        else {
            return
        }

        storedChunks = Array(storedChunks[firstLiveChunkIndex...])
        firstLiveChunkIndex = 0
    }
}
