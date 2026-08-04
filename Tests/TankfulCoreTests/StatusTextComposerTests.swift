import Foundation
import Testing
@testable import TankfulCore

/// The menu bar shows one number, so what these lock in is which window wins the pick.
@Suite struct StatusTextComposerTests {
    private let now = TestSupport.date("2026-08-03T12:00:00Z")
    private var past: Date { now.addingTimeInterval(-60) }
    private var future: Date { now.addingTimeInterval(3600) }

    private func compose(
        codexWindows: [RateWindow] = [],
        codexFreshness: Freshness = .fresh,
        claudeWindows: [RateWindow] = [],
        claudeExtraWindows: [ExtraWindow] = [],
        claudeFreshness: Freshness = .fresh
    ) -> String? {
        StatusTextComposer.statusText(
            codex: CodexSnapshot(windows: codexWindows, planType: nil, capturedAt: now, limitReached: false),
            codexFreshness: codexFreshness,
            claude: ClaudeSnapshot(windows: claudeWindows, extraWindows: claudeExtraWindows, capturedAt: now),
            claudeFreshness: claudeFreshness,
            now: now
        )
    }

    @Test func nothingToShowIsNil() {
        #expect(compose() == nil)
    }

    @Test func missingSnapshotsAreNil() {
        let text = StatusTextComposer.statusText(
            codex: nil,
            codexFreshness: .unavailable(reason: "no sessions"),
            claude: nil,
            claudeFreshness: .unavailable(reason: "no snapshot"),
            now: now
        )
        #expect(text == nil)
    }

    @Test func worstWindowAcrossBothServicesWins() {
        let text = compose(
            codexWindows: [RateWindow(kind: .weekly, usedPercent: 63, resetsAt: future)],
            claudeWindows: [RateWindow(kind: .fiveHour, usedPercent: 20, resetsAt: future)]
        )
        #expect(text == "X 63% wk")
    }

    /// The finding: an Opus weekly window in the extras used to be invisible in the menu bar.
    @Test func claudeExtraWindowWinsWhenItIsTheWorst() {
        let text = compose(
            claudeWindows: [RateWindow(kind: .fiveHour, usedPercent: 20, resetsAt: future)],
            claudeExtraWindows: [ExtraWindow(id: "seven_day_opus", usedPercent: 95, resetsAt: future)]
        )
        #expect(text == "C 95% opus")
    }

    @Test func extraWindowBeatsCodexToo() {
        let text = compose(
            codexWindows: [RateWindow(kind: .fiveHour, usedPercent: 50, resetsAt: future)],
            claudeExtraWindows: [ExtraWindow(id: "seven_day_sonnet", usedPercent: 88, resetsAt: nil)]
        )
        #expect(text == "C 88% sonnet")
    }

    @Test func elapsedExtraWindowIsSkipped() {
        let text = compose(
            claudeWindows: [RateWindow(kind: .fiveHour, usedPercent: 20, resetsAt: future)],
            claudeExtraWindows: [ExtraWindow(id: "seven_day_opus", usedPercent: 95, resetsAt: past)]
        )
        #expect(text == "C 20% 5h")
    }

    @Test func extraWindowWithoutResetTimeStaysLive() {
        let text = compose(claudeExtraWindows: [ExtraWindow(id: "seven_day", usedPercent: 71, resetsAt: nil)])
        #expect(text == "C 71% wk")
    }

    /// An id the composer cannot name would put raw payload text in the menu bar, so it is left
    /// to the panel. An empty one used to compose a title with a trailing space.
    @Test func extraWithAnIdTheMenuBarCannotNameIsSkipped() {
        #expect(compose(claudeExtraWindows: [ExtraWindow(id: "monthly", usedPercent: 30, resetsAt: nil)]) == nil)
        #expect(compose(claudeExtraWindows: [ExtraWindow(id: "", usedPercent: 30, resetsAt: nil)]) == nil)
    }

    @Test func anUnnameableExtraDoesNotOutrankAWindowThatCanBeNamed() {
        let text = compose(
            claudeWindows: [RateWindow(kind: .fiveHour, usedPercent: 20, resetsAt: future)],
            claudeExtraWindows: [ExtraWindow(id: "overall_status", usedPercent: 99, resetsAt: future)]
        )
        #expect(text == "C 20% 5h")
    }

    @Test func unavailableClaudeHidesItsExtrasToo() {
        let text = compose(
            codexWindows: [RateWindow(kind: .fiveHour, usedPercent: 10, resetsAt: future)],
            claudeExtraWindows: [ExtraWindow(id: "seven_day_opus", usedPercent: 95, resetsAt: future)],
            claudeFreshness: .unavailable(reason: "no snapshot")
        )
        #expect(text == "X 10% 5h")
    }

    @Test func staleNumbersStillShow() {
        let text = compose(
            claudeExtraWindows: [ExtraWindow(id: "seven_day_opus", usedPercent: 44, resetsAt: future)],
            claudeFreshness: .stale(age: 4000)
        )
        #expect(text == "C 44% opus")
    }
}
