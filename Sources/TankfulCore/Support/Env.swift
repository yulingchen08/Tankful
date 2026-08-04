import Foundation

/// Injected environment. Nothing in Core reads the clock or the home directory directly,
/// so tests never touch the real `~`.
public struct Env: Sendable {
    public var now: @Sendable () -> Date
    public var homeDirectory: URL
    public var applicationSupportDirectory: URL

    /// Nil derives Application Support from `homeDirectory`, which is what tests want.
    public init(
        now: @escaping @Sendable () -> Date,
        homeDirectory: URL,
        applicationSupportDirectory: URL? = nil
    ) {
        self.now = now
        self.homeDirectory = homeDirectory
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
    }

    public static let live = Env(
        now: { Date() },
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportDirectory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    )

    public var codexSessionsRoot: URL {
        homeDirectory.appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    /// Written by the bridge executable, read by the app.
    public var claudeSnapshotURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("Tankful", isDirectory: true)
            .appendingPathComponent("claude-rate-limits.json", isDirectory: false)
    }

    public var claudeConfigURL: URL {
        homeDirectory.appendingPathComponent(".claude.json", isDirectory: false)
    }
}
