import Foundation
import Testing
@testable import TankfulCore

@Suite struct CountdownFormatTests {
    private let now = TestSupport.date("2026-08-03T12:00:00Z")

    @Test func spellsOutTheUsualRanges() {
        #expect(CountdownFormat.text(from: now, to: now.addingTimeInterval(30)) == "under a minute")
        #expect(CountdownFormat.text(from: now, to: now.addingTimeInterval(90)) == "1m")
        #expect(CountdownFormat.text(from: now, to: now.addingTimeInterval(3900)) == "1h 5m")
        #expect(CountdownFormat.text(from: now, to: now.addingTimeInterval(2 * 86_400 + 3 * 3600)) == "2d 3h")
    }

    @Test func aResetInThePastIsMoments() {
        #expect(CountdownFormat.text(from: now, to: now.addingTimeInterval(-10)) == "moments")
        #expect(CountdownFormat.text(from: now, to: now) == "moments")
    }

    /// The finding: `Int(Double)` traps past `Int.max`, so a junk reset date crashed the panel
    /// on every open. Any date has to produce a string instead.
    @Test func anAbsurdResetDateIsClampedInsteadOfTrapping() {
        #expect(CountdownFormat.text(from: now, to: Date(timeIntervalSince1970: 1e300)) == "400d 0h")
        #expect(CountdownFormat.text(from: now, to: Date(timeIntervalSince1970: .greatestFiniteMagnitude)) == "400d 0h")
        #expect(CountdownFormat.text(from: now, to: Date(timeIntervalSince1970: .infinity)) == "400d 0h")
        #expect(CountdownFormat.text(from: now, to: Date(timeIntervalSince1970: -.infinity)) == "moments")
        #expect(CountdownFormat.text(from: now, to: Date(timeIntervalSince1970: .nan)) == "moments")
        #expect(CountdownFormat.text(from: Date(timeIntervalSince1970: .nan), to: now) == "moments")
    }
}
