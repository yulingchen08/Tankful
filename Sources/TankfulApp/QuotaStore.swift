import Foundation
import Observation
import TankfulCore

/// The only state the UI reads. Every mutation goes through `apply`.
@MainActor
@Observable
final class QuotaStore {
    var codexSnapshot: CodexSnapshot?
    var codexFreshness: Freshness = .unavailable(reason: "loading")
    var claudeSnapshot: ClaudeSnapshot?
    var claudeFreshness: Freshness = .unavailable(reason: "loading")
    /// From `~/.claude.json`, not from the snapshot; the bridge never sees the plan.
    var claudePlanTier: String?
    var lastRefreshAt: Date?

    @ObservationIgnored private let env: Env

    /// Set by the app delegate so the footer's Refresh button can reach the coordinator.
    @ObservationIgnored var onRefreshRequested: @MainActor () -> Void = {}

    init(env: Env) {
        self.env = env
    }

    func now() -> Date { env.now() }

    func apply(_ update: QuotaUpdate, refreshedAt: Date) {
        codexSnapshot = update.codexSnapshot
        codexFreshness = update.codexFreshness
        claudeSnapshot = update.claudeSnapshot
        claudeFreshness = update.claudeFreshness
        claudePlanTier = update.claudePlanTier
        lastRefreshAt = refreshedAt
    }

    func requestRefresh() {
        onRefreshRequested()
    }
}
