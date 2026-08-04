import Foundation
@testable import TankfulCore

/// Counts reads and, until released, holds each one open — which is how a test keeps a refresh
/// in flight long enough to make more requests land on top of it.
actor SourceGate {
    private var isHeld: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private(set) var startedReads = 0
    private(set) var peakConcurrentReads = 0
    /// Whether a held read was cancelled, which is the only way to tell a stopped refresh from
    /// one that is merely fenced out at delivery time.
    private(set) var wasCancelled = false
    private var concurrentReads = 0

    init(holdsReads: Bool = false) {
        isHeld = holdsReads
    }

    func enter() async {
        startedReads += 1
        concurrentReads += 1
        peakConcurrentReads = max(peakConcurrentReads, concurrentReads)
        if isHeld {
            await withTaskCancellationHandler {
                await withCheckedContinuation { waiters.append($0) }
            } onCancel: {
                Task { await self.markCancelled() }
            }
        }
        concurrentReads -= 1
    }

    private func markCancelled() {
        wasCancelled = true
    }

    /// Lets every held read return, and leaves the gate open for later ones.
    func release() {
        isHeld = false
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

struct FakeQuotaSource<Snapshot: Sendable>: QuotaSource {
    let snapshot: Snapshot?
    let freshness: Freshness
    let gate: SourceGate

    init(snapshot: Snapshot? = nil, freshness: Freshness = .fresh, gate: SourceGate = SourceGate()) {
        self.snapshot = snapshot
        self.freshness = freshness
        self.gate = gate
    }

    func read(env: Env) async -> (Snapshot?, Freshness) {
        await gate.enter()
        return (snapshot, freshness)
    }
}

struct FakePlanTierSource: PlanTierSource {
    let tier: String?
    let gate: SourceGate

    init(tier: String? = nil, gate: SourceGate = SourceGate()) {
        self.tier = tier
        self.gate = gate
    }

    func planTier(env: Env) async -> String? {
        await gate.enter()
        return tier
    }
}

struct FakeWatchTargetSource: WatchTargetSource {
    let targets: WatchTargets
    let gate: SourceGate

    init(targets: WatchTargets = WatchTargets(directories: [], files: []), gate: SourceGate = SourceGate()) {
        self.targets = targets
        self.gate = gate
    }

    func watchTargets(env: Env) async -> WatchTargets {
        await gate.enter()
        return targets
    }
}

@MainActor
final class ResultRecorder {
    private(set) var results: [QuotaRefreshResult] = []

    func record(_ result: QuotaRefreshResult) {
        results.append(result)
    }
}

@MainActor
enum RefreshTestSupport {
    /// Polls rather than sleeping, so a satisfied condition costs nothing; the millisecond
    /// fallback only runs while the work is genuinely still on another thread, and the cap
    /// turns a wedged gate into a failing test rather than a hung one.
    @discardableResult
    static func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            await Task.yield()
        }
        for _ in 0..<2000 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return await condition()
    }

    /// Gives any work the refresher might still start a chance to show up, so a test can assert
    /// that nothing more happened rather than only that nothing had happened yet.
    static func settle() async {
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
        for _ in 0..<50 { await Task.yield() }
    }
}
