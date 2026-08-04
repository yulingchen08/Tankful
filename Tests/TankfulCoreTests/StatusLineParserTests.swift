import Foundation
import Testing
@testable import TankfulCore

/// Every case feeds the parser raw stdin bytes; nothing here touches the disk or the clock.
@Suite struct StatusLineParserTests {

    private func parse(_ json: String) -> StatusLineRateLimitParser.ParsedRateLimits? {
        StatusLineRateLimitParser.parse(stdin: Data(json.utf8))
    }

    /// Inside the parser's plausibility band: 2026-08-04.
    private let resetEpoch: Double = 1_785_000_000
    private let laterResetEpoch: Double = 1_785_500_000

    @Test func readsBothDocumentedWindows() throws {
        let parsed = try #require(parse("""
        {"session_id":"s1","rate_limits":{\
        "five_hour":{"used_percentage":42.5,"resets_at":1785000000},\
        "seven_day":{"used_percentage":10,"resets_at":1785500000}}}
        """))
        #expect(parsed.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(parsed.windows.map(\.usedPercent) == [42.5, 10])
        #expect(parsed.windows[0].resetsAt == Date(timeIntervalSince1970: resetEpoch))
        #expect(parsed.windows[1].resetsAt == Date(timeIntervalSince1970: laterResetEpoch))
        #expect(parsed.extras.isEmpty)
    }

    @Test func fiveHourAloneIsEnough() throws {
        let parsed = try #require(parse(#"{"rate_limits":{"five_hour":{"used_percentage":7}}}"#))
        #expect(parsed.windows.map(\.kind) == [.fiveHour])
        #expect(parsed.windows[0].resetsAt == nil)
        #expect(parsed.extras.isEmpty)
    }

    @Test func sevenDayAloneIsEnough() throws {
        let parsed = try #require(parse(#"{"rate_limits":{"seven_day":{"used_percentage":63}}}"#))
        #expect(parsed.windows.map(\.kind) == [.weekly])
        #expect(parsed.windows[0].usedPercent == 63)
    }

    @Test func missingRateLimitsFieldIsNil() {
        #expect(parse(#"{"session_id":"s1","model":{"id":"claude"}}"#) == nil)
    }

    @Test func emptyStdinIsNil() {
        #expect(StatusLineRateLimitParser.parse(stdin: Data()) == nil)
    }

    @Test func garbageBytesAreNil() {
        #expect(StatusLineRateLimitParser.parse(stdin: Data([0xFF, 0x00, 0x11, 0x42])) == nil)
    }

    @Test func rateLimitsWithoutAnyReadablePercentIsNil() {
        #expect(parse(#"{"rate_limits":{"five_hour":{"foo":1},"note":"none"}}"#) == nil)
    }

    @Test func utilizationSpellingOnTheHundredScale() throws {
        let parsed = try #require(parse(#"{"rate_limits":{"five_hour":{"utilization":42}}}"#))
        #expect(parsed.windows[0].usedPercent == 42)
    }

    @Test func utilizationSpellingOnTheFractionalScale() throws {
        let parsed = try #require(parse(#"{"rate_limits":{"five_hour":{"utilization":0.42}}}"#))
        #expect(parsed.windows[0].usedPercent == 42)
    }

    /// An integer literal is never a fraction, so 1 must not be rescaled to 100%.
    @Test func integerUtilizationOfOneIsOnePercent() throws {
        let parsed = try #require(parse(#"{"rate_limits":{"five_hour":{"utilization":1}}}"#))
        #expect(parsed.windows[0].usedPercent == 1)
    }

    @Test func integerUtilizationOfZeroStaysZero() throws {
        let parsed = try #require(parse(#"{"rate_limits":{"five_hour":{"utilization":0}}}"#))
        #expect(parsed.windows[0].usedPercent == 0)
    }

    /// The documented spelling is always 0–100, so no scale guessing may touch it.
    @Test func usedPercentageBelowOneIsNotRescaled() throws {
        let parsed = try #require(parse(#"{"rate_limits":{"five_hour":{"used_percentage":0.5}}}"#))
        #expect(parsed.windows[0].usedPercent == 0.5)
    }

    @Test func percentSpellingBelowOneIsNotRescaled() throws {
        let parsed = try #require(parse(#"{"rate_limits":{"five_hour":{"percent":0.5}}}"#))
        #expect(parsed.windows[0].usedPercent == 0.5)
    }

    @Test func isoResetTimeWithFractionalSeconds() throws {
        let parsed = try #require(parse("""
        {"rate_limits":{"five_hour":{"utilization":50,"resets_at":"2026-08-03T15:00:00.500Z"}}}
        """))
        #expect(parsed.windows[0].resetsAt == TestSupport.date("2026-08-03T15:00:00.500Z"))
    }

    @Test func isoResetTimeWithoutFractionalSeconds() throws {
        let parsed = try #require(parse("""
        {"rate_limits":{"five_hour":{"utilization":50,"resets_at":"2026-08-03T15:00:00Z"}}}
        """))
        #expect(parsed.windows[0].resetsAt == TestSupport.date("2026-08-03T15:00:00Z"))
    }

    @Test func percentAboveOneHundredIsClamped() throws {
        let parsed = try #require(parse(#"{"rate_limits":{"five_hour":{"used_percentage":150}}}"#))
        #expect(parsed.windows[0].usedPercent == 100)
    }

    @Test func negativePercentIsClamped() throws {
        let parsed = try #require(parse(#"{"rate_limits":{"seven_day":{"used_percentage":-5}}}"#))
        #expect(parsed.windows[0].usedPercent == 0)
    }

    @Test func resetTimeBelowThePlausibilityBandIsDropped() throws {
        // 2001; too old to be a real reset, but the percentage is still good.
        let parsed = try #require(parse(#"{"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":1000000000}}}"#))
        #expect(parsed.windows[0].usedPercent == 30)
        #expect(parsed.windows[0].resetsAt == nil)
    }

    @Test func resetTimeAboveThePlausibilityBandIsDropped() throws {
        // Epoch milliseconds land far past 2100.
        let parsed = try #require(
            parse(#"{"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":1785000000000}}}"#)
        )
        #expect(parsed.windows[0].resetsAt == nil)
    }

    @Test func siblingWindowsBecomeExtras() throws {
        let parsed = try #require(parse("""
        {"rate_limits":{\
        "five_hour":{"used_percentage":11},\
        "seven_day_opus":{"used_percentage":12,"resets_at":1785000000},\
        "seven_day_sonnet":{"used_percentage":13}}}
        """))
        #expect(parsed.windows.map(\.kind) == [.fiveHour])
        #expect(parsed.extras.map(\.id) == ["seven_day_opus", "seven_day_sonnet"])
        #expect(parsed.extras.map(\.usedPercent) == [12, 13])
        #expect(parsed.extras[0].resetsAt == Date(timeIntervalSince1970: resetEpoch))
        #expect(parsed.extras[1].resetsAt == nil)
    }

    @Test func limitsArrayFallbackPromotesRecognisableGroups() throws {
        let parsed = try #require(parse("""
        {"rate_limits":{"limits":[\
        {"group":"seven_day","percent":33,"resets_at":1785000000},\
        {"group":"opus_weekly","percent":8},\
        {"percent":5}]}}
        """))
        #expect(parsed.windows.map(\.kind) == [.weekly])
        #expect(parsed.windows[0].usedPercent == 33)
        #expect(parsed.windows[0].resetsAt == Date(timeIntervalSince1970: resetEpoch))
        #expect(parsed.extras.map(\.id) == ["limit-2", "opus_weekly"])
    }

    /// The finding: matching the recognisable part promoted `seven_day_opus` to a second
    /// `seven_day`, so the panel showed two rows labelled "Weekly" and neither was the weekly.
    @Test func limitsArrayFallbackOnlyPromotesAnExactName() throws {
        let parsed = try #require(parse("""
        {"rate_limits":{"limits":[\
        {"group":"seven_day","percent":20,"resets_at":1785000000},\
        {"group":"seven_day_opus","percent":95}]}}
        """))
        #expect(parsed.windows.map(\.kind) == [.weekly])
        #expect(parsed.windows.map(\.usedPercent) == [20])
        #expect(parsed.extras.map(\.id) == ["seven_day_opus"])
        #expect(parsed.extras.map(\.usedPercent) == [95])
    }

    @Test func limitsArrayFallbackPromotesShorthandFiveHour() throws {
        let parsed = try #require(parse(#"{"rate_limits":{"limits":[{"name":"5h","used_percentage":21}]}}"#))
        #expect(parsed.windows.map(\.kind) == [.fiveHour])
        #expect(parsed.windows[0].usedPercent == 21)
    }

    // MARK: - Bounds

    /// Anything on the machine can write this payload, and every extra becomes a panel row.
    @Test func theNumberOfExtraWindowsIsCapped() throws {
        let siblings = (0..<10_000).map { #""w\#($0)":{"used_percentage":\#($0 % 100)}"# }
        let parsed = try #require(parse(#"{"rate_limits":{\#(siblings.joined(separator: ","))}}"#))
        #expect(parsed.extras.count == 16)
        // The busiest windows are the ones kept.
        #expect(parsed.extras.allSatisfy { $0.usedPercent == 99 })
    }

    @Test func extrasBelowTheCapAreAllKept() throws {
        let siblings = (0..<16).map { #""w\#($0)":{"used_percentage":1}"# }
        let parsed = try #require(parse(#"{"rate_limits":{\#(siblings.joined(separator: ","))}}"#))
        #expect(parsed.extras.count == 16)
    }

    @Test func anAbsurdlyLongWindowIdIsTruncated() throws {
        let id = String(repeating: "a", count: 1_000_000)
        let parsed = try #require(parse(#"{"rate_limits":{"\#(id)":{"used_percentage":50}}}"#))
        #expect(parsed.extras.count == 1)
        #expect(parsed.extras[0].id.count == 64)
        #expect(parsed.extras[0].usedPercent == 50)
    }

    // MARK: - Hostile payloads

    /// The array form can name one window any number of times. Unbounded, 80,000 entries became
    /// 80,000 panel rows sharing a single `ForEach` id and a 4 MB snapshot file.
    @Test func aRepeatedWindowInTheLimitsArrayCollapsesToOneRow() throws {
        let elements = (0..<80_000).map { #"{"kind":"5h","percent":\#($0 % 100)}"# }
        let parsed = try #require(parse(#"{"rate_limits":{"limits":[\#(elements.joined(separator: ","))]}}"#))
        #expect(parsed.windows.count == 1)
        #expect(parsed.windows.map(\.kind) == [.fiveHour])
        #expect(parsed.extras.isEmpty)
    }

    /// The busiest reading is the one worth warning about, so it is the one that survives.
    @Test func theBusiestReadingWinsAmongRepeatsOfAWindow() throws {
        let parsed = try #require(parse("""
        {"rate_limits":{"limits":[\
        {"kind":"5h","percent":10},{"kind":"5h","percent":90},{"kind":"5h","percent":30},\
        {"kind":"7d","percent":4},{"kind":"7d","percent":2}]}}
        """))
        #expect(parsed.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(parsed.windows.map(\.usedPercent) == [90, 4])
    }

    @Test func anUnboundedArrayOfUnnamedLimitsStaysCapped() throws {
        let elements = (0..<20_000).map { #"{"kind":"custom-\#($0)","percent":\#($0 % 100)}"# }
        let parsed = try #require(parse(#"{"rate_limits":{"limits":[\#(elements.joined(separator: ","))]}}"#))
        #expect(parsed.windows.isEmpty)
        #expect(parsed.extras.count == 16)
        #expect(Set(parsed.extras.map(\.id)).count == 16)
        #expect(parsed.extras.allSatisfy { $0.usedPercent == 99 })
    }

    @Test func canonicalHashIgnoresKeyOrder() throws {
        let first = try #require(parse("""
        {"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1785000000},"seven_day":{"used_percentage":10}}}
        """))
        let second = try #require(parse("""
        {"rate_limits":{"seven_day":{"used_percentage":10},"five_hour":{"resets_at":1785000000,"used_percentage":42}}}
        """))
        #expect(first.canonicalHash == second.canonicalHash)
        #expect(first.canonicalHash.count == 64)
    }

    @Test func canonicalHashTracksPercentChanges() throws {
        let first = try #require(parse(#"{"rate_limits":{"five_hour":{"used_percentage":42}}}"#))
        let second = try #require(parse(#"{"rate_limits":{"five_hour":{"used_percentage":43}}}"#))
        #expect(first.canonicalHash != second.canonicalHash)
    }
}
