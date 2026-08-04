import Foundation

/// Rate-limit state captured from a single Codex `token_count` event.
///
/// Codex only emits this on a model turn, so the values can be arbitrarily old.
public struct CodexSnapshot: Sendable, Equatable {
    public let windows: [RateWindow]
    public let planType: String?
    public let capturedAt: Date
    public let limitReached: Bool

    public init(windows: [RateWindow], planType: String?, capturedAt: Date, limitReached: Bool) {
        self.windows = windows.sorted { $0.kind.sortKey < $1.kind.sortKey }
        self.planType = planType
        self.capturedAt = capturedAt
        self.limitReached = limitReached
    }

    public var fiveHour: RateWindow? { windows.first { $0.kind == .fiveHour } }

    public func freshness(now: Date, freshThreshold: TimeInterval = 900) -> Freshness {
        let age = now.timeIntervalSince(capturedAt)
        return age > freshThreshold ? .stale(age: age) : .fresh
    }
}
