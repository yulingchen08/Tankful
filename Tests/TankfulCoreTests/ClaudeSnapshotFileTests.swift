import Foundation
import Testing
@testable import TankfulCore

@Suite struct ClaudeSnapshotFileTests {

    private let capturedAt = TestSupport.date("2026-08-03T12:34:56Z")
    private let resetsAt = TestSupport.date("2026-08-03T15:00:00Z")

    private func parsed(
        windows: [RateWindow],
        extras: [ExtraWindow] = [],
        hash: String = "abc123"
    ) -> StatusLineRateLimitParser.ParsedRateLimits {
        .init(windows: windows, extras: extras, canonicalHash: hash)
    }

    @Test func roundTripsWindowsAndExtras() throws {
        let source = parsed(
            windows: [
                RateWindow(kind: .fiveHour, usedPercent: 42, resetsAt: resetsAt),
                RateWindow(kind: .weekly, usedPercent: 10, resetsAt: nil)
            ],
            extras: [ExtraWindow(id: "seven_day_opus", usedPercent: 12, resetsAt: resetsAt)]
        )

        let decoded = try ClaudeSnapshotFile.decode(ClaudeSnapshotFile.encode(source, capturedAt: capturedAt))
        #expect(decoded.version == 1)
        #expect(decoded.capturedAt == capturedAt)
        #expect(decoded.sourceHash == "abc123")
        #expect(decoded.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(decoded.windows.map(\.usedPercent) == [42, 10])
        #expect(decoded.windows[0].resetsAt == resetsAt)
        #expect(decoded.extraWindows == [ExtraWindow(id: "seven_day_opus", usedPercent: 12, resetsAt: resetsAt)])
    }

    @Test func encodesDeterministicBytes() throws {
        let source = parsed(windows: [RateWindow(kind: .fiveHour, usedPercent: 42, resetsAt: resetsAt)])
        let first = try ClaudeSnapshotFile.encode(source, capturedAt: capturedAt)
        let second = try ClaudeSnapshotFile.encode(source, capturedAt: capturedAt)
        #expect(first == second)

        let text = String(decoding: first, as: UTF8.self)
        // Sorted keys are what makes the bytes comparable, so the first key must be the
        // alphabetically first one.
        #expect(text.hasPrefix(#"{"capturedAt":"2026-08-03T12:34:56Z""#))
        #expect(text.contains(#""source":"statusline""#))
    }

    @Test func nullResetTimeSurvivesTheRoundTrip() throws {
        let source = parsed(
            windows: [RateWindow(kind: .fiveHour, usedPercent: 5, resetsAt: nil)],
            extras: [ExtraWindow(id: "seven_day_opus", usedPercent: 1, resetsAt: nil)]
        )
        let data = try ClaudeSnapshotFile.encode(source, capturedAt: capturedAt)
        #expect(String(decoding: data, as: UTF8.self).contains(#""resetsAt":null"#))

        let decoded = try ClaudeSnapshotFile.decode(data)
        #expect(decoded.windows[0].resetsAt == nil)
        #expect(decoded.extraWindows[0].resetsAt == nil)
    }

    @Test func unknownTopLevelKeyIsTolerated() throws {
        let decoded = try ClaudeSnapshotFile.decode(Data("""
        {"version":1,"capturedAt":"2026-08-03T12:34:56Z","source":"statusline","sourceHash":"h",\
        "futureField":{"a":1},"windows":[{"id":"five_hour","usedPercent":42,"resetsAt":null}],"extraWindows":[]}
        """.utf8))
        #expect(decoded.windows.map(\.kind) == [.fiveHour])
    }

    @Test func unknownWindowIdBecomesAnExtra() throws {
        let decoded = try ClaudeSnapshotFile.decode(Data("""
        {"version":1,"capturedAt":"2026-08-03T12:34:56Z","sourceHash":"h","extraWindows":[],"windows":[\
        {"id":"five_hour","usedPercent":42,"resetsAt":null},\
        {"id":"thirty_day","usedPercent":9,"resetsAt":"2026-08-03T15:00:00Z"}]}
        """.utf8))
        #expect(decoded.windows.map(\.kind) == [.fiveHour])
        #expect(decoded.extraWindows == [ExtraWindow(id: "thirty_day", usedPercent: 9, resetsAt: resetsAt)])
    }

    @Test func versionIsSurfacedVerbatim() throws {
        let decoded = try ClaudeSnapshotFile.decode(Data("""
        {"version":7,"capturedAt":"2026-08-03T12:34:56Z","windows":[],"extraWindows":[]}
        """.utf8))
        #expect(decoded.version == 7)
        #expect(decoded.sourceHash == nil)
        #expect(decoded.windows.isEmpty)
    }

    @Test func corruptedDataThrows() {
        let malformed = #expect(throws: DecodingError.self) {
            try ClaudeSnapshotFile.decode(Data("{not json".utf8))
        }
        guard case .dataCorrupted = malformed else {
            Issue.record("expected dataCorrupted, got \(String(describing: malformed))")
            return
        }
        // `capturedAt` is load-bearing, so a file without it is not a snapshot.
        let missingKey = #expect(throws: DecodingError.self) {
            try ClaudeSnapshotFile.decode(Data(#"{"version":1}"#.utf8))
        }
        guard case .keyNotFound(let key, _) = missingKey else {
            Issue.record("expected keyNotFound, got \(String(describing: missingKey))")
            return
        }
        #expect(key.stringValue == "capturedAt")
    }

    // MARK: - Hostile files

    /// Nothing stops someone writing the snapshot file by hand, so the decoder bounds it the same
    /// way the parser bounds the payload rather than trusting a file the bridge may not have made.
    @Test func aFileRepeatingOneWindowDecodesToASingleRow() throws {
        let windows = (0..<20_000).map { #"{"id":"five_hour","usedPercent":\#($0 % 100),"resetsAt":null}"# }
        let decoded = try ClaudeSnapshotFile.decode(Data("""
        {"version":1,"capturedAt":"2026-08-03T12:34:56Z",\
        "windows":[\(windows.joined(separator: ","))],"extraWindows":[]}
        """.utf8))
        #expect(decoded.windows.count == 1)
        #expect(decoded.windows[0].usedPercent == 99)
        #expect(decoded.extraWindows.isEmpty)
    }

    @Test func aFileWithThousandsOfExtrasDecodesToTheCap() throws {
        let extras = (0..<20_000).map { #"{"id":"w\#($0)","usedPercent":\#($0 % 100),"resetsAt":null}"# }
        let decoded = try ClaudeSnapshotFile.decode(Data("""
        {"version":1,"capturedAt":"2026-08-03T12:34:56Z",\
        "windows":[],"extraWindows":[\(extras.joined(separator: ","))]}
        """.utf8))
        #expect(decoded.extraWindows.count == 16)
        #expect(Set(decoded.extraWindows.map(\.id)).count == 16)
    }

    @Test func anAbsurdlyLongIdInTheFileIsTruncated() throws {
        let id = String(repeating: "a", count: 5_000)
        let decoded = try ClaudeSnapshotFile.decode(Data("""
        {"version":1,"capturedAt":"2026-08-03T12:34:56Z",\
        "windows":[],"extraWindows":[{"id":"\(id)","usedPercent":50,"resetsAt":null}]}
        """.utf8))
        #expect(decoded.extraWindows.count == 1)
        #expect(decoded.extraWindows[0].id.count == 64)
    }

    @Test func capturedAtIsStoredToWholeSeconds() throws {
        let fractional = Date(timeIntervalSince1970: 1_785_000_000.25)
        let source = parsed(windows: [RateWindow(kind: .fiveHour, usedPercent: 1, resetsAt: nil)])
        let decoded = try ClaudeSnapshotFile.decode(ClaudeSnapshotFile.encode(source, capturedAt: fractional))
        #expect(decoded.capturedAt.timeIntervalSince1970 == 1_785_000_000)
    }
}
