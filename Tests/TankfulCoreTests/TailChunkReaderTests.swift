import Foundation
import Testing
@testable import TankfulCore

@Suite struct TailChunkReaderTests {
    private static let marker = "\"rate_limits\""

    private func matches(_ line: Substring) -> Bool { line.contains(Self.marker) }

    @Test func findsMatchOnLastLine() throws {
        try TestSupport.withTemporaryDirectory { dir in
            let file = try TestSupport.write(
                "{\"type\":\"noise\"}\n{\"id\":1,\(Self.marker):{}}\n",
                to: dir.appendingPathComponent("a.jsonl")
            )
            let lines = try TailChunkReader.lines(at: file, matching: matches)
            #expect(lines.count == 1)
            #expect(lines[0] == "{\"id\":1,\(Self.marker):{}}")
        }
    }

    @Test func findsMatchBuriedUnderTrailingNoise() throws {
        let file = try TestSupport.fixtureURL("codex-normal.jsonl")
        let lines = try TailChunkReader.lines(at: file, matching: matches)
        #expect(lines.count == 1)
        #expect(lines[0].contains("\"used_percent\":59.0"))
    }

    @Test func newestMatchComesFirst() throws {
        try TestSupport.withTemporaryDirectory { dir in
            let file = try TestSupport.write(
                "{\"id\":1,\(Self.marker):{}}\n{\"id\":2,\(Self.marker):{}}\n",
                to: dir.appendingPathComponent("a.jsonl")
            )
            let lines = try TailChunkReader.lines(at: file, matching: matches)
            #expect(lines.map(String.init) == ["{\"id\":2,\(Self.marker):{}}", "{\"id\":1,\(Self.marker):{}}"])
        }
    }

    @Test func doublesChunkWhenMatchLiesBeyondTheFirstChunk() throws {
        try TestSupport.withTemporaryDirectory { dir in
            var text = "{\"id\":1,\(Self.marker):{}}\n"
            let noise = "{\"type\":\"noise\",\"pad\":\"" + String(repeating: "n", count: 200) + "\"}\n"
            while text.utf8.count < 80 * 1024 { text += noise }
            let file = try TestSupport.write(text, to: dir.appendingPathComponent("big.jsonl"))

            #expect(text.utf8.count > 64 * 1024)
            let lines = try TailChunkReader.lines(at: file, matching: matches)
            #expect(lines.count == 1)
            #expect(lines[0] == "{\"id\":1,\(Self.marker):{}}")
        }
    }

    @Test func discardsPartialFirstLineAndRetriesWithABiggerChunk() throws {
        try TestSupport.withTemporaryDirectory { dir in
            let initialChunk = 256
            let targetLine = "{\"pad\":\"" + String(repeating: "p", count: 120)
                + "\",\"x\":1,\(Self.marker):{\"primary\":null}}"
            let noiseLine = "{\"type\":\"noise\"}\n"
            let text = targetLine + "\n" + String(repeating: noiseLine, count: 11)
            let file = try TestSupport.write(text, to: dir.appendingPathComponent("split.jsonl"))

            // The chunk boundary must bisect the target line ahead of the marker, so the
            // discarded fragment still looks like a match.
            let markerOffset = try #require(targetLine.range(of: Self.marker)).lowerBound
            let markerByteOffset = targetLine.utf8.distance(
                from: targetLine.utf8.startIndex,
                to: markerOffset.samePosition(in: targetLine.utf8)!
            )
            let cut = text.utf8.count - initialChunk
            #expect(cut > 0)
            #expect(cut < markerByteOffset)

            let withoutRetry = try TailChunkReader.lines(
                at: file, initialChunk: initialChunk, maxChunk: initialChunk, matching: matches
            )
            #expect(withoutRetry.isEmpty)

            let withRetry = try TailChunkReader.lines(
                at: file, initialChunk: initialChunk, maxChunk: 4096, matching: matches
            )
            #expect(withRetry.map(String.init) == [targetLine])
        }
    }

    @Test func emptyFileYieldsNoLines() throws {
        let file = try TestSupport.fixtureURL("codex-empty.jsonl")
        #expect(try TailChunkReader.lines(at: file, matching: matches).isEmpty)
    }

    @Test func truncatedLastLineIsStillReturnedButDoesNotParse() throws {
        let file = try TestSupport.fixtureURL("codex-truncated-lastline.jsonl")
        let lines = try TailChunkReader.lines(at: file, matching: matches)
        #expect(lines.count == 2)
        #expect(CodexRateLimitParser.snapshot(fromLine: lines[0]) == nil)
        #expect(CodexRateLimitParser.snapshot(fromLine: lines[1]) != nil)
    }
}
