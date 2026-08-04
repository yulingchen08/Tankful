import Foundation
import Testing
@testable import TankfulCore

private extension Freshness {
    var staleAge: TimeInterval? { if case .stale(let age) = self { age } else { nil } }
    var unavailableReason: String? { if case .unavailable(let reason) = self { reason } else { nil } }
}

@Suite struct CodexReaderTests {

    /// Lays fixtures out the way Codex does: `<root>/YYYY/MM/DD/rollout-<timestamp>.jsonl`.
    private func makeSessionsRoot(in base: URL, sessions: [(name: String, fixture: String)]) throws -> URL {
        let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
        let day = try TestSupport.makeDirectory(
            root.appendingPathComponent("2026").appendingPathComponent("06").appendingPathComponent("30")
        )
        for session in sessions {
            let contents = try String(contentsOf: TestSupport.fixtureURL(session.fixture), encoding: .utf8)
            try TestSupport.write(contents, to: day.appendingPathComponent(session.name))
        }
        return root
    }

    private func env(now: Date) -> Env {
        Env(now: { now }, homeDirectory: URL(fileURLWithPath: "/nonexistent"))
    }

    @Test func readsSnapshotFromNormalSession() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let root = try makeSessionsRoot(in: base, sessions: [
                ("rollout-2026-06-30T09-00-00-a.jsonl", "codex-normal.jsonl")
            ])
            let capturedAt = TestSupport.date("2026-06-30T09:07:25.718Z")

            let (snapshot, freshness) = await CodexReader().read(
                sessionsRoot: root, env: env(now: capturedAt.addingTimeInterval(60))
            )
            let result = try #require(snapshot)
            #expect(result.windows.map(\.kind) == [.fiveHour, .weekly])
            #expect(result.fiveHour?.usedPercent == 59)
            #expect(result.planType == "team")
            #expect(result.capturedAt == capturedAt)
            #expect(freshness == .fresh)
        }
    }

    @Test func oldSnapshotIsReportedAsStale() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let root = try makeSessionsRoot(in: base, sessions: [
                ("rollout-2026-06-30T09-00-00-a.jsonl", "codex-normal.jsonl")
            ])
            let capturedAt = TestSupport.date("2026-06-30T09:07:25.718Z")

            let (_, freshness) = await CodexReader().read(
                sessionsRoot: root, env: env(now: capturedAt.addingTimeInterval(3600))
            )
            let age = try #require(freshness.staleAge)
            #expect(abs(age - 3600) < 0.001)
        }
    }

    @Test func picksNewestSnapshotAcrossFiles() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            // The newest event lives in the older-named file, so ordering must come from
            // the event timestamp, not the filename.
            let root = try makeSessionsRoot(in: base, sessions: [
                ("rollout-2026-06-30T09-00-00-a.jsonl", "codex-primary-weekly.jsonl"),
                ("rollout-2026-06-30T10-00-00-b.jsonl", "codex-normal.jsonl")
            ])

            let (snapshot, _) = await CodexReader().read(sessionsRoot: root, env: env(now: Date()))
            #expect(snapshot?.capturedAt == TestSupport.date("2026-06-30T11:22:33.044Z"))
            #expect(snapshot?.windows.map(\.kind) == [.weekly])
        }
    }

    @Test func skipsTruncatedTrailingLine() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let root = try makeSessionsRoot(in: base, sessions: [
                ("rollout-2026-06-30T09-00-00-a.jsonl", "codex-truncated-lastline.jsonl")
            ])

            let (snapshot, _) = await CodexReader().read(sessionsRoot: root, env: env(now: Date()))
            #expect(snapshot?.capturedAt == TestSupport.date("2026-06-30T15:10:10.777Z"))
            #expect(snapshot?.fiveHour?.usedPercent == 33)
        }
    }

    @Test func emptySessionFileIsUnavailable() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let root = try makeSessionsRoot(in: base, sessions: [
                ("rollout-2026-06-30T09-00-00-a.jsonl", "codex-empty.jsonl")
            ])

            let (snapshot, freshness) = await CodexReader().read(sessionsRoot: root, env: env(now: Date()))
            #expect(snapshot == nil)
            #expect(freshness.unavailableReason == "no rate-limit data in recent sessions")
        }
    }

    @Test func sessionWithoutRateLimitsIsUnavailable() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let root = try makeSessionsRoot(in: base, sessions: [
                ("rollout-2026-06-30T09-00-00-a.jsonl", "codex-no-ratelimits.jsonl")
            ])

            let (_, freshness) = await CodexReader().read(sessionsRoot: root, env: env(now: Date()))
            #expect(freshness.unavailableReason == "no rate-limit data in recent sessions")
        }
    }

    @Test func missingSessionsRootIsUnavailable() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let (snapshot, freshness) = await CodexReader().read(
                sessionsRoot: base.appendingPathComponent("absent"), env: env(now: Date())
            )
            #expect(snapshot == nil)
            #expect(freshness.unavailableReason == "no Codex sessions found")
        }
    }

    @Test func windowWithoutResetTimeReachesTheSnapshotAsLive() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
            let day = try TestSupport.makeDirectory(
                root.appendingPathComponent("2026").appendingPathComponent("06").appendingPathComponent("30")
            )
            // swiftlint:disable line_length
            let line = #"""
            {"timestamp":"2026-06-30T09:07:25.718Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":63.0,"window_minutes":300},"plan_type":"team"}}}

            """#
            // swiftlint:enable line_length
            try TestSupport.write(line, to: day.appendingPathComponent("rollout-2026-06-30T09-00-00-a.jsonl"))
            let now = TestSupport.date("2026-06-30T09:08:00.000Z")

            let snapshot = try #require(await CodexReader().read(sessionsRoot: root, env: env(now: now)).0)
            let window = try #require(snapshot.fiveHour)
            #expect(window.usedPercent == 63)
            #expect(window.resetsAt == nil)
            // The menu bar keeps windows that have not elapsed, so this one still shows 63%.
            #expect(snapshot.windows.filter { !$0.hasElapsed(now: now) }.count == 1)
        }
    }

    @Test func instanceReaderReturnsTheSameSnapshotAcrossRepeatedReads() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let root = try makeSessionsRoot(in: base, sessions: [
                ("rollout-2026-06-30T09-00-00-a.jsonl", "codex-normal.jsonl")
            ])
            let now = TestSupport.date("2026-06-30T09:08:00.000Z")

            let reader = CodexReader()
            let first = await reader.read(sessionsRoot: root, env: env(now: now))
            // The second read is served from the locator's listing cache, which only survives
            // because the reader is an instance.
            let second = await reader.read(sessionsRoot: root, env: env(now: now))
            #expect(first.0 == second.0)
            #expect(second.0?.fiveHour?.usedPercent == 59)
        }
    }

    @Test func elapsedWindowIsDetectedAgainstInjectedNow() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let root = try makeSessionsRoot(in: base, sessions: [
                ("rollout-2026-06-30T09-00-00-a.jsonl", "codex-reset-in-past.jsonl")
            ])
            let now = TestSupport.date("2026-06-30T12:01:00.000Z")

            let snapshot = try #require(await CodexReader().read(sessionsRoot: root, env: env(now: now)).0)
            let fiveHour = try #require(snapshot.fiveHour)
            #expect(fiveHour.hasElapsed(now: now))
            #expect(snapshot.limitReached)
            #expect(fiveHour.hasElapsed(now: Date(timeIntervalSince1970: 1_699_999_999)) == false)
        }
    }
}
