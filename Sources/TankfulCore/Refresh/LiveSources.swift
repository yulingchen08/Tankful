import Foundation

// What the app hands `QuotaRefresher` in production. Every read below is synchronous blocking
// file I/O, so each one is detached at utility priority rather than borrowing the priority of
// whatever asked for the refresh.

extension CodexReader: QuotaSource {
    public nonisolated func read(env: Env) async -> (CodexSnapshot?, Freshness) {
        await Task.detached(priority: .utility) {
            await self.read(sessionsRoot: env.codexSessionsRoot, env: env)
        }.value
    }
}

extension ClaudeBridgeReader: QuotaSource {
    public func read(env: Env) async -> (ClaudeSnapshot?, Freshness) {
        await Task.detached(priority: .utility) {
            Self.read(snapshotURL: env.claudeSnapshotURL, env: env)
        }.value
    }
}

extension ClaudePlanReader: PlanTierSource {
    public func planTier(env: Env) async -> String? {
        await Task.detached(priority: .utility) {
            Self.organizationType(at: env.claudeConfigURL)
        }.value
    }
}

/// Finds the watch paths by looking at the real filesystem: Codex's session directories plus
/// the session files it is reading, and the directory the bridge rewrites its snapshot into.
public struct FileSystemWatchTargets: WatchTargetSource {
    /// The same reader the refresh reads through, so both share one listing cache and one view
    /// of the tree; a separate locator would answer from a different filesystem instant.
    private let codex: CodexReader

    public init(codex: CodexReader) {
        self.codex = codex
    }

    public func watchTargets(env: Env) async -> WatchTargets {
        let codex = codex
        return await Task.detached(priority: .utility) {
            let codexTargets = await codex.watchTargets(sessionsRoot: env.codexSessionsRoot)
            let claude = Self.claudeSnapshotDirectory(snapshotURL: env.claudeSnapshotURL)
            return WatchTargets(
                directories: codexTargets.directories + [claude].compactMap { $0 },
                files: codexTargets.files
            )
        }.value
    }

    /// The bridge writes the snapshot by renaming a temp file into place, which a directory
    /// vnode reports but a file vnode does not survive — the rename swaps the inode the file
    /// watcher still holds open.
    ///
    /// Nil before the bridge has ever run: watching the parent instead would fire on every
    /// unrelated write under Application Support, and the 60s tick re-targets within a minute
    /// of the first install anyway.
    static func claudeSnapshotDirectory(snapshotURL: URL) -> URL? {
        let directory = snapshotURL.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: directory.path) ? directory : nil
    }
}
