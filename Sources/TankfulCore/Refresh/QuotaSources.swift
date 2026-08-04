import Foundation

/// One service's quota reading: the newest snapshot on disk, if any, and how much to trust it.
///
/// Deliberately one method wide, so a test can stand in for a single service without also
/// having to fake plan tiers or watch paths.
public protocol QuotaSource<Snapshot>: Sendable {
    associatedtype Snapshot: Sendable

    func read(env: Env) async -> (Snapshot?, Freshness)
}

/// The subscription tier, which for Claude lives in a different file than the quota snapshot.
public protocol PlanTierSource: Sendable {
    func planTier(env: Env) async -> String?
}

/// The paths whose changes should trigger the next refresh.
///
/// Discovered on every read because the newest session file moves as sessions come and go.
public protocol WatchTargetSource: Sendable {
    func watchTargets(env: Env) async -> WatchTargets
}

/// Everything one refresh found worth watching, across both services.
public struct WatchTargets: Sendable, Equatable {
    /// Watched with a directory vnode: entries appearing or disappearing, never appends.
    public let directories: [URL]
    /// Watched with a file vnode, because appends to them are invisible to the directory
    /// watchers. Empty until a session file exists.
    public let files: [URL]

    public init(directories: [URL], files: [URL]) {
        self.directories = directories
        self.files = files
    }
}
