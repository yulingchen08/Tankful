import Foundation

/// Reads the snapshot the bridge executable left behind.
///
/// Every failure carries the one thing the user can do about it, because this text is the
/// only diagnostic the menu bar shows.
public struct ClaudeBridgeReader: Sendable {
    public init() {}

    public static func read(snapshotURL: URL, env: Env) -> (ClaudeSnapshot?, Freshness) {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return (nil, .unavailable(reason: "bridge not installed — run Scripts/install-claude-bridge.sh"))
        }
        guard let data = try? Data(contentsOf: snapshotURL),
              let decoded = try? ClaudeSnapshotFile.decode(data) else {
            return (nil, .unavailable(reason: "snapshot unreadable — reinstall the bridge"))
        }
        guard decoded.version <= ClaudeSnapshotFile.currentVersion else {
            return (nil, .unavailable(reason: "snapshot from a newer bridge — update Tankful"))
        }
        // Clock skew or a bad write; a future timestamp would otherwise read as fresh forever.
        guard decoded.capturedAt <= env.now().addingTimeInterval(300) else {
            return (nil, .unavailable(reason: "snapshot has a future timestamp"))
        }
        guard !decoded.windows.isEmpty || !decoded.extraWindows.isEmpty else {
            return (nil, .unavailable(reason: "no rate-limit data yet — send a message in Claude Code"))
        }

        let snapshot = ClaudeSnapshot(
            windows: decoded.windows,
            extraWindows: decoded.extraWindows,
            capturedAt: decoded.capturedAt
        )
        return (snapshot, snapshot.freshness(now: env.now()))
    }
}
