import Foundation

/// One refresh's worth of state, so both services always land in the same observation cycle
/// and the panel never shows half a refresh.
public struct QuotaUpdate: Sendable, Equatable {
    public var codexSnapshot: CodexSnapshot?
    public var codexFreshness: Freshness
    public var claudeSnapshot: ClaudeSnapshot?
    public var claudeFreshness: Freshness
    public var claudePlanTier: String?

    public init(
        codexSnapshot: CodexSnapshot?,
        codexFreshness: Freshness,
        claudeSnapshot: ClaudeSnapshot?,
        claudeFreshness: Freshness,
        claudePlanTier: String?
    ) {
        self.codexSnapshot = codexSnapshot
        self.codexFreshness = codexFreshness
        self.claudeSnapshot = claudeSnapshot
        self.claudeFreshness = claudeFreshness
        self.claudePlanTier = claudePlanTier
    }
}

/// What one completed refresh produced: the state to show, and where to listen for the change
/// that should trigger the next one.
public struct QuotaRefreshResult: Sendable, Equatable {
    public let update: QuotaUpdate
    public let watchTargets: WatchTargets
    public let refreshedAt: Date

    public init(update: QuotaUpdate, watchTargets: WatchTargets, refreshedAt: Date) {
        self.update = update
        self.watchTargets = watchTargets
        self.refreshedAt = refreshedAt
    }
}

/// Turns any number of refresh requests into non-overlapping reads of every source.
///
/// Requests arrive from unrelated places — a file write, a timer, a panel open, waking from
/// sleep — so they are funnelled through one single-flight gate: a request that lands while a
/// read is in flight is remembered and costs exactly one re-run, no matter how many arrive.
///
/// Main-actor isolated because callers request refreshes from the main actor and consume the
/// result there; that also makes the gate's state transitions ordered rather than racy.
@MainActor
public final class QuotaRefresher {
    private let env: Env
    private let codex: any QuotaSource<CodexSnapshot>
    private let claude: any QuotaSource<ClaudeSnapshot>
    private let planTier: any PlanTierSource
    private let watchTargets: any WatchTargetSource
    private let onResult: @MainActor (QuotaRefreshResult) -> Void

    /// Internal rather than private so tests can tell an idle gate from a wedged one.
    private(set) var isRefreshing = false
    /// Internal for the same reason: a request dropped by `stop()` has no other visible effect.
    private(set) var pendingRerun = false
    private var refreshTask: Task<Void, Never>?
    /// Set by `stop()`, so requests arriving after a teardown start nothing.
    private var isStopped = false
    /// Bumped by `stop()`. A task carries the generation it started in, which is how it tells
    /// "I still own the gate" from "a stop happened and a later start owns it now".
    private var generation = 0

    public init(
        env: Env,
        codex: any QuotaSource<CodexSnapshot>,
        claude: any QuotaSource<ClaudeSnapshot>,
        planTier: any PlanTierSource,
        watchTargets: any WatchTargetSource,
        onResult: @escaping @MainActor (QuotaRefreshResult) -> Void
    ) {
        self.env = env
        self.codex = codex
        self.claude = claude
        self.planTier = planTier
        self.watchTargets = watchTargets
        self.onResult = onResult
    }

    /// Lifts the stop fence and takes the first reading.
    public func start() {
        isStopped = false
        refreshNow()
    }

    public func refreshNow() {
        guard !isStopped else { return }
        guard !isRefreshing else {
            pendingRerun = true
            return
        }
        isRefreshing = true
        let generation = generation
        // A stopped read stays suspended until whatever it is waiting on returns, so the next
        // one queues behind it rather than putting a second full filesystem scan in flight.
        let stopped = refreshTask
        refreshTask = Task { @MainActor in
            await stopped?.value
            defer {
                // Only while this task still owns the gate: after a stop, the gate belongs to
                // whichever task the next start put in flight.
                if generation == self.generation {
                    isRefreshing = false
                    refreshTask = nil
                }
            }
            repeat {
                pendingRerun = false
                let result = await load()
                // A read that finished after `stop()` must not deliver state to an owner that
                // has already torn its watchers down. The generation alone decides that; adding
                // `isStopped` or `Task.isCancelled` here would only mask a missing `cancel()`.
                guard generation == self.generation else { return }
                onResult(result)
            } while pendingRerun
        }
    }

    /// Fences off everything in flight. The read itself may still be suspended in a syscall;
    /// the next `start()` waits for it rather than reading alongside it.
    public func stop() {
        isStopped = true
        generation &+= 1
        refreshTask?.cancel()
        isRefreshing = false
        pendingRerun = false
    }

    /// Every source is read concurrently and assembled into one result, so a caller can never
    /// apply half a refresh.
    private func load() async -> QuotaRefreshResult {
        let env = env
        async let targets = watchTargets.watchTargets(env: env)
        async let codexRead = codex.read(env: env)
        async let claudeRead = claude.read(env: env)
        async let tier = planTier.planTier(env: env)

        let (codexSnapshot, codexFreshness) = await codexRead
        let (claudeSnapshot, claudeFreshness) = await claudeRead
        return QuotaRefreshResult(
            update: QuotaUpdate(
                codexSnapshot: codexSnapshot,
                codexFreshness: codexFreshness,
                claudeSnapshot: claudeSnapshot,
                claudeFreshness: claudeFreshness,
                claudePlanTier: await tier
            ),
            watchTargets: await targets,
            refreshedAt: env.now()
        )
    }
}
