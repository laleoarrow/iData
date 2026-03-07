import Foundation

public struct TerminalTranscript {
    public private(set) var chunks: [Data] = []
    public private(set) var totalBytes = 0
    public let maximumBytes: Int

    public init(maximumBytes: Int = 8 * 1024 * 1024) {
        self.maximumBytes = max(1, maximumBytes)
    }

    public mutating func reset() {
        chunks.removeAll(keepingCapacity: true)
        totalBytes = 0
    }

    public mutating func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        if data.count >= maximumBytes {
            let suffix = Data(data.suffix(maximumBytes))
            chunks = [suffix]
            totalBytes = suffix.count
            return
        }

        chunks.append(data)
        totalBytes += data.count
        trimIfNeeded()
    }

    private mutating func trimIfNeeded() {
        while totalBytes > maximumBytes, let first = chunks.first {
            chunks.removeFirst()
            totalBytes -= first.count
        }
    }
}
