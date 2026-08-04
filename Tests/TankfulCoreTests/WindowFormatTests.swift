import Foundation
import Testing
@testable import TankfulCore

@Suite struct WindowFormatTests {

    // MARK: - Row identity

    @Test func rowLabelsSpellTheWindowOut() {
        #expect(RateWindow.Kind.fiveHour.rowLabel == "5-hour")
        #expect(RateWindow.Kind.weekly.rowLabel == "Weekly")
        #expect(RateWindow.Kind.other(minutes: 45).rowLabel == "45m")
    }

    @Test func rowIDsAreDistinctPerWindow() {
        #expect(RateWindow.Kind.fiveHour.rowID == "5h")
        #expect(RateWindow.Kind.weekly.rowID == "wk")
        #expect(RateWindow.Kind.other(minutes: 45).rowID == "other-45")
        #expect(RateWindow.Kind.other(minutes: 45).rowID != RateWindow.Kind.other(minutes: 46).rowID)
    }

    // MARK: - Usage level

    @Test func usageLevelThresholds() {
        #expect(UsageLevel(usedPercent: 0) == .normal)
        #expect(UsageLevel(usedPercent: 69) == .normal)
        #expect(UsageLevel(usedPercent: 70) == .warning)
        #expect(UsageLevel(usedPercent: 89) == .warning)
        #expect(UsageLevel(usedPercent: 90) == .critical)
        #expect(UsageLevel(usedPercent: 100) == .critical)
    }

    /// The level follows the rounded number on screen, not the raw percentage behind it.
    @Test func usageLevelFollowsTheDisplayedRounding() {
        #expect(UsageLevel(usedPercent: 69.4) == .normal)
        #expect(UsageLevel(usedPercent: 69.6) == .warning)
        #expect(UsageLevel(usedPercent: 89.4) == .warning)
        #expect(UsageLevel(usedPercent: 89.6) == .critical)
    }

    // MARK: - Extra windows

    @Test func extraWindowLabels() {
        #expect(WindowFormat.extraWindowLabel(id: "seven_day_opus") == "7d · Opus")
        #expect(WindowFormat.extraWindowLabel(id: "seven_day") == "7d")
        #expect(WindowFormat.extraWindowLabel(id: "something_else") == "something_else")
        #expect(WindowFormat.extraWindowLabel(id: "") == "")
    }

    // MARK: - Freshness note

    @Test func freshDataCarriesNoNote() {
        #expect(WindowFormat.freshnessNote(.fresh) == nil)
    }

    @Test func staleDataIsDatedAndUnavailableDataExplainsItself() {
        #expect(WindowFormat.freshnessNote(.stale(age: 3600))?.hasPrefix("as of ") == true)
        #expect(WindowFormat.freshnessNote(.unavailable(reason: "no Codex sessions found"))
            == "no Codex sessions found")
    }

    // MARK: - Relative time

    @Test func subMinuteDeltasReadAsJustNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(WindowFormat.relative(date: now, now: now) == "just now")
        #expect(WindowFormat.relative(date: now.addingTimeInterval(-59), now: now) == "just now")
        // A future date is not "not yet a minute old", but it must not read as stale either.
        #expect(WindowFormat.relative(date: now.addingTimeInterval(30), now: now) == "just now")
    }

    @Test func aMinuteOldIsSpelledOut() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(WindowFormat.relative(date: now.addingTimeInterval(-60), now: now) == "1 minute ago")
        // The age spelling is what the panel puts after "as of", so it has to read as past tense.
        #expect(WindowFormat.relative(age: 3600) == "1 hour ago")
    }
}
