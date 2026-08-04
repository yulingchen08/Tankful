import Foundation
import Testing
@testable import TankfulCore

/// Both window types clamp on ingest, because every gauge downstream converts the percentage
/// with `Int(_:)`, which traps on NaN and on anything past `Int.max`.
@Suite struct WindowPercentClampTests {

    @Test func rateWindowClampsOutOfRangePercentages() {
        #expect(RateWindow(kind: .fiveHour, usedPercent: -5, resetsAt: nil).usedPercent == 0)
        #expect(RateWindow(kind: .fiveHour, usedPercent: 140, resetsAt: nil).usedPercent == 100)
        #expect(RateWindow(kind: .fiveHour, usedPercent: .infinity, resetsAt: nil).usedPercent == 100)
        #expect(RateWindow(kind: .fiveHour, usedPercent: -.infinity, resetsAt: nil).usedPercent == 0)
    }

    /// NaN compares false against everything, so it survives min/max untouched.
    @Test func rateWindowFoldsNaNToZero() {
        let window = RateWindow(kind: .fiveHour, usedPercent: .nan, resetsAt: nil)
        #expect(window.usedPercent == 0)
        #expect(window.usedPercent.isNaN == false)
    }

    @Test func extraWindowClampsOutOfRangePercentages() {
        #expect(ExtraWindow(id: "seven_day_opus", usedPercent: -5, resetsAt: nil).usedPercent == 0)
        #expect(ExtraWindow(id: "seven_day_opus", usedPercent: 140, resetsAt: nil).usedPercent == 100)
        #expect(ExtraWindow(id: "seven_day_opus", usedPercent: .infinity, resetsAt: nil).usedPercent == 100)
    }

    @Test func extraWindowFoldsNaNToZero() {
        let extra = ExtraWindow(id: "seven_day_opus", usedPercent: .nan, resetsAt: nil)
        #expect(extra.usedPercent == 0)
        #expect(extra.usedPercent.isNaN == false)
    }

    /// The trap this clamping exists to prevent, exercised through the two callers that convert.
    @Test func aFoldedPercentageIsSafeToRender() {
        let window = RateWindow(kind: .fiveHour, usedPercent: .nan, resetsAt: nil)
        #expect(Int(window.usedPercent.rounded()) == 0)
        let snapshot = ClaudeSnapshot(windows: [window], capturedAt: Date())
        let text = StatusTextComposer.statusText(
            codex: nil, codexFreshness: .unavailable(reason: "none"),
            claude: snapshot, claudeFreshness: .fresh, now: Date()
        )
        #expect(text == "C 0% 5h")
    }
}
