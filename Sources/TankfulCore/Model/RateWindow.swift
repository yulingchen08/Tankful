import Foundation

/// One rate-limit window as reported by Codex.
public struct RateWindow: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case fiveHour
        case weekly
        case other(minutes: Int)

        /// Codex reports the windows in `primary`/`secondary` slots whose meaning is not
        /// stable across sessions, so only `window_minutes` may be used to identify one.
        public init(windowMinutes: Int) {
            switch windowMinutes {
            case 240...360: self = .fiveHour
            case 9000...11000: self = .weekly
            default: self = .other(minutes: windowMinutes)
            }
        }

        /// Display order: 5-hour window first, then weekly, then anything unrecognised.
        var sortKey: (Int, Int) {
            switch self {
            case .fiveHour: (0, 0)
            case .weekly: (1, 0)
            case .other(let minutes): (2, minutes)
            }
        }
    }

    public let kind: Kind
    public let usedPercent: Double
    /// Nil when Codex omitted `resets_at`; the percentage is still authoritative.
    public let resetsAt: Date?

    public init(kind: Kind, usedPercent: Double, resetsAt: Date?) {
        self.kind = kind
        // Clamp on ingest; a percentage outside 0...100 would break every downstream gauge.
        // NaN survives min/max, and the gauges convert with Int(_:), which traps on it.
        self.usedPercent = usedPercent.isNaN ? 0 : min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
    }

    /// An unknown reset time is not an elapsed one, so the window stays live.
    public func hasElapsed(now: Date) -> Bool {
        guard let resetsAt else { return false }
        return now >= resetsAt
    }
}
