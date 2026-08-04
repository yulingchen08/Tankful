import Foundation
import Testing
@testable import TankfulCore

@Suite struct CodexRateLimitParserTests {

    @Test func parsesFiveHourAndWeeklyWindows() throws {
        let text = try TestSupport.fixtureText("codex-normal.jsonl")
        let snapshot = try #require(CodexRateLimitParser.snapshot(fromLine: TestSupport.rateLimitLine(in: text)))

        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(snapshot.fiveHour?.usedPercent == 59)
        #expect(snapshot.weekly?.usedPercent == 9)
        #expect(snapshot.planType == "team")
        #expect(snapshot.limitReached == false)
        #expect(snapshot.capturedAt == TestSupport.date("2026-06-30T09:07:25.718Z"))
        #expect(snapshot.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1782811263))
    }

    @Test func nullSecondaryYieldsSingleWindow() throws {
        let text = try TestSupport.fixtureText("codex-null-secondary.jsonl")
        let snapshot = try #require(CodexRateLimitParser.snapshot(fromLine: TestSupport.rateLimitLine(in: text)))

        #expect(snapshot.windows.map(\.kind) == [.fiveHour])
        #expect(snapshot.fiveHour?.usedPercent == 41.5)
        #expect(snapshot.weekly == nil)
        #expect(snapshot.planType == "pro")
    }

    @Test func primarySlotCarryingWeeklyWindowIsClassifiedByMinutes() throws {
        let text = try TestSupport.fixtureText("codex-primary-weekly.jsonl")
        let snapshot = try #require(CodexRateLimitParser.snapshot(fromLine: TestSupport.rateLimitLine(in: text)))

        #expect(snapshot.windows.map(\.kind) == [.weekly])
        #expect(snapshot.weekly?.usedPercent == 13)
        #expect(snapshot.fiveHour == nil)
    }

    /// The finding: an absurd `resets_at` survived into the panel, where the countdown trapped.
    /// The percentage is still the number the user came for, so only the date is dropped.
    @Test func resetTimeOutsideThePlausibilityBandIsDroppedButThePercentSurvives() throws {
        // swiftlint:disable line_length
        let junkDates = ["1e300", "-1e300", "1782811263000", "0"]
        for value in junkDates {
            let line: Substring = #"""
            {"timestamp":"2026-06-30T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":63.0,"window_minutes":300,"resets_at":\#(value)},"secondary":null}}}
            """#[...]
            // swiftlint:enable line_length
            let window = try #require(CodexRateLimitParser.snapshot(fromLine: line)?.fiveHour, "for \(value)")
            #expect(window.usedPercent == 63)
            #expect(window.resetsAt == nil, "for \(value)")
        }
    }

    @Test func aResetTimeInsideTheBandIsKept() throws {
        // swiftlint:disable line_length
        let line: Substring = #"""
        {"timestamp":"2026-06-30T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":63.0,"window_minutes":300,"resets_at":1782811263},"secondary":null}}}
        """#[...]
        // swiftlint:enable line_length
        let window = try #require(CodexRateLimitParser.snapshot(fromLine: line)?.fiveHour)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_782_811_263))
    }

    @Test func unrecognisedWindowLengthKeepsItsMinutes() {
        // swiftlint:disable line_length
        let line: Substring = #"""
        {"timestamp":"2026-06-30T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":5.0,"window_minutes":1440,"resets_at":1782811263},"secondary":null}}}
        """#[...]
        // swiftlint:enable line_length
        let snapshot = CodexRateLimitParser.snapshot(fromLine: line)
        #expect(snapshot?.windows.map(\.kind) == [.other(minutes: 1440)])
    }

    @Test func windowWithoutResetTimeKeepsItsPercentageAndStaysLive() throws {
        // swiftlint:disable line_length
        let line: Substring = #"""
        {"timestamp":"2026-06-30T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":63.0,"window_minutes":300},"secondary":null}}}
        """#[...]
        // swiftlint:enable line_length
        let window = try #require(CodexRateLimitParser.snapshot(fromLine: line)?.fiveHour)

        #expect(window.usedPercent == 63)
        #expect(window.resetsAt == nil)
        // A missing reset time is not an elapsed window, so the menu bar still shows the number.
        #expect(window.hasElapsed(now: Date(timeIntervalSince1970: 4_000_000_000)) == false)
    }

    @Test func percentIsClampedToZeroAndHundred() {
        // swiftlint:disable line_length
        let line: Substring = #"""
        {"timestamp":"2026-06-30T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":150.0,"window_minutes":300,"resets_at":1782811263},"secondary":{"used_percent":-5.0,"window_minutes":10080,"resets_at":1783398063}}}}
        """#[...]
        // swiftlint:enable line_length
        let snapshot = CodexRateLimitParser.snapshot(fromLine: line)
        #expect(snapshot?.fiveHour?.usedPercent == 100)
        #expect(snapshot?.weekly?.usedPercent == 0)
    }

    @Test func unknownFieldsAreIgnored() throws {
        let text = try TestSupport.fixtureText("codex-unknown-fields.jsonl")
        let snapshot = try #require(CodexRateLimitParser.snapshot(fromLine: TestSupport.rateLimitLine(in: text)))

        #expect(snapshot.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(snapshot.fiveHour?.usedPercent == 22.5)
        #expect(snapshot.weekly?.usedPercent == 66)
        #expect(snapshot.planType == "team")
    }

    @Test func limitReachedIsReportedWhenTypePresent() throws {
        let text = try TestSupport.fixtureText("codex-reset-in-past.jsonl")
        let snapshot = try #require(CodexRateLimitParser.snapshot(fromLine: TestSupport.rateLimitLine(in: text)))
        #expect(snapshot.limitReached)
    }

    @Test func malformedJsonYieldsNil() {
        let line: Substring = #"{"timestamp":"2026-06-30T09:00:00.000Z","rate_limits":{"primary":"#[...]
        #expect(CodexRateLimitParser.snapshot(fromLine: line) == nil)
    }

    @Test func nonTokenCountEventYieldsNil() {
        // swiftlint:disable line_length
        let line: Substring = #"""
        {"timestamp":"2026-06-30T09:00:00.000Z","type":"event_msg","payload":{"type":"agent_message","rate_limits":{"primary":{"used_percent":5.0,"window_minutes":300,"resets_at":1782811263}}}}
        """#[...]
        // swiftlint:enable line_length
        #expect(CodexRateLimitParser.snapshot(fromLine: line) == nil)
    }

    @Test func lineWithoutRateLimitsYieldsNil() throws {
        let text = try TestSupport.fixtureText("codex-no-ratelimits.jsonl")
        for line in text.split(separator: "\n") {
            #expect(CodexRateLimitParser.snapshot(fromLine: line) == nil)
        }
    }

    @Test func rateLimitsWithBothWindowsNullYieldsNil() {
        // swiftlint:disable line_length
        let line: Substring = #"""
        {"timestamp":"2026-06-30T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":null,"secondary":null,"plan_type":"team"}}}
        """#[...]
        // swiftlint:enable line_length
        #expect(CodexRateLimitParser.snapshot(fromLine: line) == nil)
    }

    @Test func timestampWithoutFractionalSecondsIsAccepted() {
        // swiftlint:disable line_length
        let line: Substring = #"""
        {"timestamp":"2026-06-30T09:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":5.0,"window_minutes":300,"resets_at":1782811263}}}}
        """#[...]
        // swiftlint:enable line_length
        #expect(CodexRateLimitParser.snapshot(fromLine: line)?.capturedAt == Date(timeIntervalSince1970: 1782810000))
    }
}
