import Foundation
import Testing
@testable import TankfulCore

private extension Freshness {
    var staleAge: TimeInterval? { if case .stale(let age) = self { age } else { nil } }
    var unavailableReason: String? { if case .unavailable(let reason) = self { reason } else { nil } }
}

@Suite struct ClaudeBridgeReaderTests {

    private let capturedAt = TestSupport.date("2026-08-03T12:00:00Z")

    private func env(now: Date, home: URL = URL(fileURLWithPath: "/nonexistent")) -> Env {
        Env(now: { now }, homeDirectory: home)
    }

    @discardableResult
    private func writeSnapshot(_ json: String, in base: URL) throws -> URL {
        let url = base.appendingPathComponent("claude-rate-limits.json")
        try TestSupport.write(json, to: url)
        return url
    }

    private func snapshotJSON(
        version: Int = 1,
        capturedAt: String = "2026-08-03T12:00:00Z",
        windows: String = #"{"id":"five_hour","usedPercent":42,"resetsAt":"2026-08-03T15:00:00Z"}"#,
        extras: String = ""
    ) -> String {
        """
        {"version":\(version),"capturedAt":"\(capturedAt)","source":"statusline","sourceHash":"h",\
        "windows":[\(windows)],"extraWindows":[\(extras)]}
        """
    }

    @Test func missingFileTellsTheUserToInstallTheBridge() throws {
        try TestSupport.withTemporaryDirectory { base in
            let (snapshot, freshness) = ClaudeBridgeReader.read(
                snapshotURL: base.appendingPathComponent("absent.json"), env: env(now: capturedAt)
            )
            #expect(snapshot == nil)
            #expect(freshness.unavailableReason?.contains("bridge not installed") == true)
        }
    }

    @Test func unreadableFileTellsTheUserToReinstall() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = try writeSnapshot("{ this is not json", in: base)
            let (snapshot, freshness) = ClaudeBridgeReader.read(snapshotURL: url, env: env(now: capturedAt))
            #expect(snapshot == nil)
            #expect(freshness.unavailableReason?.contains("snapshot unreadable") == true)
        }
    }

    @Test func newerVersionTellsTheUserToUpdate() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = try writeSnapshot(snapshotJSON(version: 2), in: base)
            let (snapshot, freshness) = ClaudeBridgeReader.read(snapshotURL: url, env: env(now: capturedAt))
            #expect(snapshot == nil)
            #expect(freshness.unavailableReason?.contains("newer bridge") == true)
        }
    }

    @Test func futureTimestampIsRejected() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = try writeSnapshot(snapshotJSON(capturedAt: "2026-08-03T12:10:00Z"), in: base)
            let (snapshot, freshness) = ClaudeBridgeReader.read(snapshotURL: url, env: env(now: capturedAt))
            #expect(snapshot == nil)
            #expect(freshness.unavailableReason == "snapshot has a future timestamp")
        }
    }

    @Test func smallClockSkewIsTolerated() throws {
        try TestSupport.withTemporaryDirectory { base in
            // Four minutes ahead is inside the 300 s allowance.
            let url = try writeSnapshot(snapshotJSON(capturedAt: "2026-08-03T12:04:00Z"), in: base)
            let (snapshot, freshness) = ClaudeBridgeReader.read(snapshotURL: url, env: env(now: capturedAt))
            #expect(snapshot != nil)
            #expect(freshness == .fresh)
        }
    }

    @Test func emptySnapshotAsksTheUserToSendAMessage() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = try writeSnapshot(snapshotJSON(windows: ""), in: base)
            let (snapshot, freshness) = ClaudeBridgeReader.read(snapshotURL: url, env: env(now: capturedAt))
            #expect(snapshot == nil)
            #expect(freshness.unavailableReason?.contains("no rate-limit data yet") == true)
        }
    }

    @Test func recentSnapshotIsFresh() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = try writeSnapshot(snapshotJSON(), in: base)
            let now = capturedAt.addingTimeInterval(9 * 60)
            let (snapshot, freshness) = ClaudeBridgeReader.read(snapshotURL: url, env: env(now: now))
            #expect(snapshot?.fiveHour?.usedPercent == 42)
            #expect(freshness == .fresh)
        }
    }

    @Test func oldSnapshotIsStaleWithItsAge() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = try writeSnapshot(snapshotJSON(), in: base)
            let now = capturedAt.addingTimeInterval(11 * 60)
            let (snapshot, freshness) = ClaudeBridgeReader.read(snapshotURL: url, env: env(now: now))
            #expect(snapshot != nil)
            let age = try #require(freshness.staleAge)
            #expect(abs(age - 660) < 0.001)
        }
    }

    @Test func windowsAreSortedWithFiveHourFirst() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = try writeSnapshot(snapshotJSON(windows: """
            {"id":"seven_day","usedPercent":10,"resetsAt":null},\
            {"id":"five_hour","usedPercent":42,"resetsAt":null}
            """), in: base)
            let snapshot = try #require(ClaudeBridgeReader.read(snapshotURL: url, env: env(now: capturedAt)).0)
            #expect(snapshot.windows.map(\.kind) == [.fiveHour, .weekly])
            #expect(snapshot.weekly?.usedPercent == 10)
        }
    }

    @Test func extrasReachTheSnapshot() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = try writeSnapshot(snapshotJSON(extras: """
            {"id":"seven_day_opus","usedPercent":12,"resetsAt":null},\
            {"id":"seven_day_sonnet","usedPercent":13,"resetsAt":null}
            """), in: base)
            let snapshot = try #require(ClaudeBridgeReader.read(snapshotURL: url, env: env(now: capturedAt)).0)
            #expect(snapshot.extraWindows.map(\.id) == ["seven_day_opus", "seven_day_sonnet"])
            #expect(snapshot.extraWindows.map(\.usedPercent) == [12, 13])
        }
    }

    @Test func outOfRangePercentsAreClampedEndToEnd() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = try writeSnapshot(snapshotJSON(
                windows: #"{"id":"five_hour","usedPercent":150,"resetsAt":null}"#,
                extras: #"{"id":"seven_day_opus","usedPercent":-4,"resetsAt":null}"#
            ), in: base)
            let snapshot = try #require(ClaudeBridgeReader.read(snapshotURL: url, env: env(now: capturedAt)).0)
            #expect(snapshot.fiveHour?.usedPercent == 100)
            #expect(snapshot.extraWindows[0].usedPercent == 0)
        }
    }

    @Test func envOverloadResolvesTheApplicationSupportPath() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let environment = env(now: capturedAt, home: base)
            try FileManager.default.createDirectory(
                at: environment.claudeSnapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try TestSupport.write(snapshotJSON(), to: environment.claudeSnapshotURL)

            let (snapshot, freshness) = await ClaudeBridgeReader().read(env: environment)
            #expect(snapshot?.fiveHour?.usedPercent == 42)
            #expect(freshness == .fresh)
        }
    }
}
