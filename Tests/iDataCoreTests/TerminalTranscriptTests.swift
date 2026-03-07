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
}
