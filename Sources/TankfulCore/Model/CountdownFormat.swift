import Foundation

/// How long until a window resets, in words.
///
/// Lives in Core rather than the app so the clamping is testable: a reset date that survived
/// its parser would otherwise reach `Int(_: Double)`, which traps on anything past `Int.max`.
public enum CountdownFormat {
    /// Longer than any real quota window, so a larger interval is junk and clamps here.
    private static let maxSeconds: Double = 400 * 24 * 60 * 60

    public static func text(from now: Date, to resetsAt: Date) -> String {
        let interval = resetsAt.timeIntervalSince(now)
        // NaN passes through min/max unchanged, so it is folded to zero before the conversion.
        let seconds = Int(interval.isNaN ? 0 : min(max(interval, 0), maxSeconds))
        guard seconds > 0 else { return "moments" }
        let minutes = seconds / 60
        let days = minutes / (60 * 24)
        let hours = (minutes / 60) % 24
        if days > 0 { return "\(days)d \(hours)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        if minutes >= 1 { return "\(minutes)m" }
        return "under a minute"
    }
}
