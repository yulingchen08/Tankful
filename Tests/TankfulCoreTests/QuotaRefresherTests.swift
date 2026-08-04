import Foundation
import Testing
@testable import TankfulCore

@MainActor
struct QuotaRefresherTests {
    private let now = TestSupport.date("2026-06-30T09:00:00.000Z")

    // MARK: - Single-flight gate

    @Test func concurrentRequestsNeverOverlapAReadInFlight() async {
        let gate = SourceGate(holdsReads: true)
        let harness = Harness(now: now, codexGate: gate)

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { await gate.startedReads == 1 })

        harness.refresher.refreshNow()
        harness.refresher.refreshNow()
        await RefreshTestSupport.settle()
        // The extra requests were remembered, not started alongside the read already running.
        #expect(await gate.startedReads == 1)

        await gate.release()
        #expect(await RefreshTestSupport.waitUntil { !harness.refresher.isRefreshing })
        #expect(await gate.peakConcurrentReads == 1)
    }

    @Test func requestsArrivingMidRefreshCostExactlyOneRerun() async {
        let gate = SourceGate(holdsReads: true)
        let harness = Harness(now: now, codexGate: gate)

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { await gate.startedReads == 1 })
        harness.refresher.refreshNow()
        harness.refresher.refreshNow()
        harness.refresher.refreshNow()

        await gate.release()
        #expect(await RefreshTestSupport.waitUntil { !harness.refresher.isRefreshing })
        await RefreshTestSupport.settle()
        #expect(await gate.startedReads == 2)
        #expect(harness.recorder.results.count == 2)
    }

    @Test func aQuietRefreshRunsExactlyOnce() async {
        let gate = SourceGate()
        let harness = Harness(now: now, codexGate: gate)

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { harness.recorder.results.count == 1 })
        await RefreshTestSupport.settle()
        #expect(await gate.startedReads == 1)
        #expect(harness.recorder.results.count == 1)
        #expect(harness.refresher.isRefreshing == false)
    }

    // MARK: - Stop fencing

    @Test func stopDuringAnInFlightRefreshDropsItsResult() async {
        let gate = SourceGate(holdsReads: true)
        let harness = Harness(now: now, codexGate: gate)

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { await gate.startedReads == 1 })

        harness.refresher.stop()
        await gate.release()
        await RefreshTestSupport.settle()

        #expect(harness.recorder.results.isEmpty)
        #expect(harness.refresher.isRefreshing == false)
    }

    @Test func stopAlsoDropsTheRerunAPendingRequestWouldHaveCaused() async {
        let gate = SourceGate(holdsReads: true)
        let harness = Harness(now: now, codexGate: gate)

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { await gate.startedReads == 1 })
        harness.refresher.refreshNow()

        harness.refresher.stop()
        await gate.release()
        await RefreshTestSupport.settle()

        #expect(await gate.startedReads == 1)
        #expect(harness.recorder.results.isEmpty)
    }

    /// The gate looks idle the moment `stop()` returns, but the read it fenced off is still
    /// suspended in the filesystem. A restart must queue behind it rather than scan alongside it.
    @Test func stopThenStartNeverReadsAlongsideTheStoppedRead() async {
        let gate = SourceGate(holdsReads: true)
        let harness = Harness(now: now, codexGate: gate)

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { await gate.startedReads == 1 })

        harness.refresher.stop()
        harness.refresher.start()
        await RefreshTestSupport.settle()
        #expect(await gate.startedReads == 1)

        await gate.release()
        #expect(await RefreshTestSupport.waitUntil { harness.recorder.results.count == 1 })
        #expect(await gate.peakConcurrentReads == 1)
        #expect(await gate.startedReads == 2)
    }

    /// Fencing the result out is not enough: without the cancel the read keeps touching files
    /// after the owner tore its watchers down.
    @Test func stopCancelsTheReadStillInFlight() async {
        let gate = SourceGate(holdsReads: true)
        let harness = Harness(now: now, codexGate: gate)

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { await gate.startedReads == 1 })

        harness.refresher.stop()
        #expect(await RefreshTestSupport.waitUntil { await gate.wasCancelled })

        await gate.release()
        await RefreshTestSupport.settle()
        #expect(harness.recorder.results.isEmpty)
    }

    /// White-box on purpose: the next task clears the flag before its own read, so a request left
    /// behind by `stop()` has no other observable effect.
    @Test func stopClearsTheRequestItDropped() async {
        let gate = SourceGate(holdsReads: true)
        let harness = Harness(now: now, codexGate: gate)

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { await gate.startedReads == 1 })
        harness.refresher.refreshNow()
        #expect(harness.refresher.pendingRerun)

        harness.refresher.stop()
        #expect(harness.refresher.pendingRerun == false)

        await gate.release()
        await RefreshTestSupport.settle()
    }

    @Test func requestsAfterStopAreIgnored() async {
        let gate = SourceGate()
        let harness = Harness(now: now, codexGate: gate)

        harness.refresher.stop()
        harness.refresher.refreshNow()
        await RefreshTestSupport.settle()

        #expect(await gate.startedReads == 0)
        #expect(harness.recorder.results.isEmpty)
    }

    @Test func startLiftsTheStopFence() async {
        let gate = SourceGate()
        let harness = Harness(now: now, codexGate: gate)

        harness.refresher.stop()
        harness.refresher.start()

        #expect(await RefreshTestSupport.waitUntil { harness.recorder.results.count == 1 })
    }

    // MARK: - Failing sources

    @Test func anUnavailableSourceDoesNotWedgeTheGate() async {
        let gate = SourceGate()
        let harness = Harness(
            now: now,
            codex: FakeQuotaSource(freshness: .unavailable(reason: "no Codex sessions found"), gate: gate)
        )

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { harness.recorder.results.count == 1 })
        #expect(harness.recorder.results.first?.update.codexFreshness == .unavailable(reason: "no Codex sessions found"))
        #expect(harness.refresher.isRefreshing == false)

        // The next request still gets through, which is what "not wedged" means.
        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { harness.recorder.results.count == 2 })
        #expect(await gate.startedReads == 2)
    }

    @Test func oneUnavailableSourceStillDeliversTheOther() async {
        let claude = ClaudeSnapshot(windows: [Self.window(80)], capturedAt: now)
        let harness = Harness(
            now: now,
            codex: FakeQuotaSource(freshness: .unavailable(reason: "no Codex sessions found")),
            claude: FakeQuotaSource(snapshot: claude, freshness: .fresh)
        )

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { harness.recorder.results.count == 1 })
        let update = harness.recorder.results.first?.update
        #expect(update?.codexSnapshot == nil)
        #expect(update?.claudeSnapshot == claude)
    }

    // MARK: - Combined result

    @Test func everySourceIsReadConcurrently() async {
        let gates = (
            codex: SourceGate(holdsReads: true),
            claude: SourceGate(holdsReads: true),
            planTier: SourceGate(holdsReads: true),
            watchTargets: SourceGate(holdsReads: true)
        )
        let harness = Harness(
            now: now,
            codex: FakeQuotaSource(gate: gates.codex),
            claude: FakeQuotaSource(gate: gates.claude),
            planTier: FakePlanTierSource(gate: gates.planTier),
            watchTargets: FakeWatchTargetSource(gate: gates.watchTargets)
        )

        harness.refresher.refreshNow()
        // A sequential read would leave the later gates untouched while the first one is held.
        let allStarted = await RefreshTestSupport.waitUntil {
            let started = await (
                gates.codex.startedReads, gates.claude.startedReads,
                gates.planTier.startedReads, gates.watchTargets.startedReads
            )
            return started == (1, 1, 1, 1)
        }
        #expect(allStarted)

        await gates.codex.release()
        await gates.claude.release()
        await gates.planTier.release()
        await gates.watchTargets.release()
        #expect(await RefreshTestSupport.waitUntil { harness.recorder.results.count == 1 })
    }

    @Test func oneResultCarriesBothServicesAndThePlanTier() async {
        let codex = CodexSnapshot(windows: [Self.window(63)], planType: "pro", capturedAt: now, limitReached: false)
        let claude = ClaudeSnapshot(windows: [Self.window(41)], capturedAt: now)
        let targets = WatchTargets(
            directories: [URL(fileURLWithPath: "/sessions")],
            files: [URL(fileURLWithPath: "/sessions/newest.jsonl")]
        )
        let harness = Harness(
            now: now,
            codex: FakeQuotaSource(snapshot: codex, freshness: .fresh),
            claude: FakeQuotaSource(snapshot: claude, freshness: .stale(age: 700)),
            planTier: FakePlanTierSource(tier: "claude_max"),
            watchTargets: FakeWatchTargetSource(targets: targets)
        )

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { harness.recorder.results.count == 1 })

        let result = harness.recorder.results.first
        #expect(result?.update.codexSnapshot == codex)
        #expect(result?.update.codexFreshness == .fresh)
        #expect(result?.update.claudeSnapshot == claude)
        #expect(result?.update.claudeFreshness == .stale(age: 700))
        #expect(result?.update.claudePlanTier == "claude_max")
        #expect(result?.watchTargets == targets)
    }

    @Test func refreshedAtComesFromTheInjectedClock() async {
        let harness = Harness(now: now)

        harness.refresher.refreshNow()
        #expect(await RefreshTestSupport.waitUntil { harness.recorder.results.count == 1 })
        #expect(harness.recorder.results.first?.refreshedAt == now)
    }

    // MARK: - Helpers

    private static func window(_ percent: Double) -> RateWindow {
        RateWindow(kind: .fiveHour, usedPercent: percent, resetsAt: nil)
    }

    @MainActor
    private struct Harness {
        let recorder = ResultRecorder()
        let refresher: QuotaRefresher

        init(
            now: Date,
            codex: FakeQuotaSource<CodexSnapshot> = FakeQuotaSource(),
            claude: FakeQuotaSource<ClaudeSnapshot> = FakeQuotaSource(),
            planTier: FakePlanTierSource = FakePlanTierSource(),
            watchTargets: FakeWatchTargetSource = FakeWatchTargetSource()
        ) {
            let recorder = recorder
            refresher = QuotaRefresher(
                env: Env(now: { now }, homeDirectory: URL(fileURLWithPath: "/nonexistent")),
                codex: codex,
                claude: claude,
                planTier: planTier,
                watchTargets: watchTargets,
                onResult: { recorder.record($0) }
            )
        }

        init(now: Date, codexGate: SourceGate) {
            self.init(now: now, codex: FakeQuotaSource(gate: codexGate))
        }
    }
}
