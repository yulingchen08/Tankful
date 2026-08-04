import Foundation

/// Sanity band for a `resets_at` epoch, shared by both parsers so they agree on what is junk.
enum ResetTimestamp {
    /// 2020-01-01 to 2100-01-01. A value outside this band is milliseconds, a duration, or
    /// junk; comparing against the clock instead would make the parsers impure.
    private static let plausibleRange: ClosedRange<Double> = 1_577_836_800...4_102_444_800

    /// Nil for anything out of band, which leaves the window's percentage usable and keeps an
    /// absurd date out of the countdown arithmetic downstream. NaN fails `contains`.
    static func date(epochSeconds: Double) -> Date? {
        guard plausibleRange.contains(epochSeconds) else { return nil }
        return Date(timeIntervalSince1970: epochSeconds)
    }
}
