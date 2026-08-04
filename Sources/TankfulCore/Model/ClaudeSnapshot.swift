import Foundation

/// A rate-limit window Claude Code reports that Tankful has no first-class slot for
/// (`seven_day_opus`, `seven_day_sonnet`, …). Carried verbatim so a new window shows up
/// without a code change.
public struct ExtraWindow: Sendable, Equatable {
    public let id: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        // Same reason as RateWindow: a percentage outside 0...100 breaks every gauge, and NaN
        // survives min/max only to trap in the Int conversion the gauges do.
        self.usedPercent = usedPercent.isNaN ? 0 : min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
    }

    /// An unknown reset time is not an elapsed one, so the window stays live.
    public func hasElapsed(now: Date) -> Bool {
        guard let resetsAt else { return false }
        return now >= resetsAt
    }
}

/// Rate-limit state Claude Code handed to the statusline command.
///
/// Claude Code only refreshes this while a session is rendering its status line, so the
/// values can be arbitrarily old.
public struct ClaudeSnapshot: Sendable, Equatable {
    public let windows: [RateWindow]
    public let extraWindows: [ExtraWindow]
    public let capturedAt: Date

    public init(windows: [RateWindow], extraWindows: [ExtraWindow] = [], capturedAt: Date) {
        self.windows = windows.sorted { $0.kind.sortKey < $1.kind.sortKey }
        self.extraWindows = extraWindows
        self.capturedAt = capturedAt
    }

    public var fiveHour: RateWindow? { windows.first { $0.kind == .fiveHour } }

    /// The bridge rewrites the file on every status-line render, so ten minutes of silence
    /// already means the session is idle or the bridge stopped running.
    public func freshness(now: Date, freshThreshold: TimeInterval = 600) -> Freshness {
        let age = now.timeIntervalSince(capturedAt)
        return age > freshThreshold ? .stale(age: age) : .fresh
    }
}
