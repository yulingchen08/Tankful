import Foundation

extension RateWindow.Kind {
    /// Panel row title, where there is room to spell the window out.
    public var rowLabel: String {
        switch self {
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        case .other(let minutes): "\(minutes)m"
        }
    }

    /// Row identity for `ForEach`. Keyed on the window, not its position, so a refresh that
    /// drops one window does not animate the remaining row into a value that was never its own.
    public var rowID: String {
        switch self {
        case .fiveHour: "5h"
        case .weekly: "wk"
        case .other(let minutes): "other-\(minutes)"
        }
    }
}

/// How alarming a used percentage is. The panel picks the colour; Core carries no UI types.
public enum UsageLevel: Sendable, Equatable {
    case normal
    case warning
    case critical

    /// Rounded first, so the level always matches the number the panel shows: 89.6 reads as
    /// "90%" and must not be a warning sitting next to a critical 90.
    public init(usedPercent: Double) {
        switch usedPercent.rounded() {
        case ..<70: self = .normal
        case ..<90: self = .warning
        default: self = .critical
        }
    }
}

/// Presentation helpers for the panel, kept in Core so they can be tested without an app target.
public enum WindowFormat {
    /// Claude names its extra windows `seven_day_opus`, `seven_day_sonnet`, …. An id that does
    /// not fit that shape is shown verbatim rather than guessed at.
    public static func extraWindowLabel(id: String) -> String {
        guard let model = ClaudeExtraWindowID.model(in: id) else { return id }
        return model.isEmpty ? "7d" : "7d · \(model.capitalized)"
    }

    /// Nil when the numbers are current and need no caveat under them.
    public static func freshnessNote(_ freshness: Freshness) -> String? {
        switch freshness {
        case .fresh: nil
        case .stale(let age): "as of \(relative(age: age))"
        case .unavailable(let reason): reason
        }
    }

    public static func relative(age: TimeInterval) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(fromTimeInterval: -age)
    }

    public static func relative(date: Date, now: Date) -> String {
        // Sub-minute deltas read as "in 0 seconds"; say "just now" instead.
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
