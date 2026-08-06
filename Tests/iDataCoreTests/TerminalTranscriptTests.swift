import Foundation
import Testing
@testable import iDataCore

struct TerminalTranscriptTests {
    @Test
    func resetClearsAllChunks() {
        var transcript = TerminalTranscript(maximumBytes: 32)
        transcript.append(Data("hello".utf8))
        transcript.append(Data("world".utf8))

        transcript.reset()

        #expect(transcript.chunks.isEmpty)
        #expect(transcript.totalBytes == 0)
    }

    @Test
    func trimsOldestChunksToBudget() {
        var transcript = TerminalTranscript(maximumBytes: 8)
        transcript.append(Data("1234".utf8))
        transcript.append(Data("5678".utf8))
        transcript.append(Data("90".utf8))

        let chunks = transcript.chunks.compactMap { String(data: $0, encoding: .utf8) }

        #expect(chunks == ["5678", "90"])
        #expect(transcript.totalBytes == 6)
    }

    @Test
    func largeChunkKeepsNewestSuffix() {
        var transcript = TerminalTranscript(maximumBytes: 5)
        transcript.append(Data("abcdefgh".utf8))

        #expect(String(data: transcript.chunks[0], encoding: .utf8) == "defgh")
        #expect(transcript.totalBytes == 5)
    }

    @Test
    func manySmallBinaryChunksPreserveExactOrderWithBoundedBackingStorage() {
        let chunkCount = 50_000
        let chunkSize = 3
        let maximumBytes = 1_024
        let input = (0..<chunkCount).map { index in
            Data([
                UInt8(truncatingIfNeeded: index),
                UInt8(truncatingIfNeeded: index >> 8),
                UInt8(truncatingIfNeeded: index >> 16),
            ])
        }
        var transcript = TerminalTranscript(maximumBytes: maximumBytes)

        for chunk in input {
            transcript.append(chunk)
        }

        let expectedChunkCount = maximumBytes / chunkSize
        let expectedChunks = Array(input.suffix(expectedChunkCount))
        #expect(transcript.chunks == expectedChunks)
        #expect(transcript.totalBytes == expectedChunkCount * chunkSize)
        #expect(transcript.backingChunkCountForTesting < 2_000)
    }

    @Test
    func overBudgetAppendEvictsOnlyWholeOldestChunks() {
        let first = Data([0x00, 0x01, 0x02, 0x03])
        let second = Data([0x04, 0x05, 0x06])
        let third = Data([0x07, 0x08, 0x09, 0x0a, 0xff])
        let fourth = Data([0x10, 0x11, 0x12, 0x13])
        var transcript = TerminalTranscript(maximumBytes: 10)

        transcript.append(first)
        transcript.append(second)
        transcript.append(third)

        #expect(transcript.chunks == [second, third])
        #expect(transcript.totalBytes == 8)

        transcript.append(fourth)

        #expect(transcript.chunks == [third, fourth])
        #expect(transcript.totalBytes == 9)
    }

    @Test
    func resetAfterHeavyTrimmingAllowsExactReuse() {
        var transcript = TerminalTranscript(maximumBytes: 64)
        for value in 0..<20_000 {
            transcript.append(Data([UInt8(truncatingIfNeeded: value)]))
        }

        transcript.reset()

        #expect(transcript.chunks.isEmpty)
        #expect(transcript.totalBytes == 0)
        #expect(transcript.backingChunkCountForTesting == 0)

        let reusedChunks = [
            Data([0x00, 0x80, 0xff]),
            Data([0x10, 0x20]),
        ]
        for chunk in reusedChunks {
            transcript.append(chunk)
        }

        #expect(transcript.chunks == reusedChunks)
        #expect(transcript.totalBytes == 5)
    }
}
