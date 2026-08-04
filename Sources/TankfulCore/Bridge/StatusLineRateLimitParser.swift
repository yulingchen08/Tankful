import CryptoKit
import Foundation

/// Turns the JSON Claude Code pipes into a status-line command into rate-limit windows.
///
/// The documented shape is `rate_limits.five_hour.used_percentage` plus epoch `resets_at`,
/// but each window may be absent, the whole field may be missing, and the CLI also knows an
/// `utilization` + ISO8601 spelling and a `limits` array. Every read is therefore defensive:
/// an unexpected shape degrades to fewer windows, never to a throw.
///
/// JSONSerialization rather than Decodable: sibling window names are open-ended
/// (`seven_day_opus`, …), so the parser has to enumerate unknown keys, which a
/// `CodingKeys`-driven decoder cannot do without a dynamic-key shim of its own.
public enum StatusLineRateLimitParser {
    /// Cheap pre-filter callers can use before paying for JSON parsing.
    public static let byteMarker = "rate_limits"

    public struct ParsedRateLimits: Sendable, Equatable {
        public var windows: [RateWindow]
        public var extras: [ExtraWindow]
        /// Lets the bridge skip a write when nothing changed.
        public var canonicalHash: String

        public init(windows: [RateWindow], extras: [ExtraWindow], canonicalHash: String) {
            self.windows = windows
            self.extras = extras
            self.canonicalHash = canonicalHash
        }
    }

    public static func parse(stdin: Data) -> ParsedRateLimits? {
        guard let root = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any] else { return nil }
        guard let limits = root[byteMarker] as? [String: Any] else { return nil }

        var windows: [RateWindow] = []
        var extras: [ExtraWindow] = []

        for (key, value) in limits {
            guard let object = value as? [String: Any], let percent = percent(in: object) else { continue }
            let resetsAt = resetDate(in: object)
            if let kind = ClaudeWindowID.kind(for: key) {
                ClaudeWindowBounds.insert(RateWindow(kind: kind, usedPercent: percent, resetsAt: resetsAt), into: &windows)
            } else {
                extras.append(ClaudeWindowBounds.extra(id: key, percent: percent, resetsAt: resetsAt))
            }
        }

        if windows.isEmpty {
            let fallback = parseLimitsArray(limits["limits"])
            windows = fallback.windows
            extras.append(contentsOf: fallback.extras)
        }

        extras = ClaudeWindowBounds.cappedExtras(extras)
        guard !windows.isEmpty || !extras.isEmpty else { return nil }
        windows.sort { $0.kind.sortKey < $1.kind.sortKey }
        extras.sort { $0.id < $1.id }
        return ParsedRateLimits(
            windows: windows,
            extras: extras,
            canonicalHash: canonicalHash(windows: windows, extras: extras)
        )
    }

    // MARK: - Field readers

    private static func percent(in object: [String: Any]) -> Double? {
        // `used_percentage` and `percent` are always 0–100; only `utilization` needs a scale guess.
        if let value = object["used_percentage"] as? NSNumber { return value.doubleValue }
        if let value = object["percent"] as? NSNumber { return value.doubleValue }
        if let value = object["utilization"] as? NSNumber { return utilizationPercent(value) }
        return nil
    }

    /// `utilization` appears both as 0–100 and as a 0–1 fraction. JSONSerialization keeps the
    /// JSON literal's numeric type, and a fraction is always written with a decimal point, so an
    /// integer literal is read on the 0–100 scale — `1` is 1%, not 100%.
    ///
    /// Residual ambiguity: a float `1.0` could be either 1% or a full fraction, and is read as
    /// the fraction (100%) because that is the shape Claude Code emits.
    private static func utilizationPercent(_ value: NSNumber) -> Double {
        let raw = value.doubleValue
        guard CFNumberIsFloatType(value), raw <= 1 else { return raw }
        return raw * 100
    }

    private static func resetDate(in object: [String: Any]) -> Date? {
        guard let raw = object["resets_at"] else { return nil }
        if let number = raw as? NSNumber {
            return ResetTimestamp.date(epochSeconds: number.doubleValue)
        }
        if let text = raw as? String { return ISO8601Timestamp.date(from: text) }
        return nil
    }

    // MARK: - `limits` array fallback

    /// Unlike the object form, whose keys are unique, an array can repeat a window any number of
    /// times. Both lists are therefore bounded as they are built, so a payload with 80,000
    /// entries costs 80,000 cheap rejections instead of an 80,000-row snapshot.
    private static func parseLimitsArray(_ value: Any?) -> (windows: [RateWindow], extras: [ExtraWindow]) {
        guard let elements = value as? [Any] else { return ([], []) }
        var windows: [RateWindow] = []
        var extras: [ExtraWindow] = []
        for (index, element) in elements.enumerated() {
            guard let object = element as? [String: Any], let percent = percent(in: object) else { continue }
            let resetsAt = resetDate(in: object)
            let id = identifier(in: object) ?? "limit-\(index)"
            if let kind = kind(forLabel: id) {
                ClaudeWindowBounds.insert(RateWindow(kind: kind, usedPercent: percent, resetsAt: resetsAt), into: &windows)
            } else {
                extras.append(ClaudeWindowBounds.extra(id: id, percent: percent, resetsAt: resetsAt))
                extras = ClaudeWindowBounds.cappedExtras(extras)
            }
        }
        return (windows, extras)
    }

    private static func identifier(in object: [String: Any]) -> String? {
        for key in ["kind", "group", "name"] {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    /// Only an exact name is promoted to a first-class window. Matching a substring turns
    /// `seven_day_opus` into a second `seven_day`, leaving two rows labelled "Weekly" and no
    /// stable answer for which one is the weekly window.
    private static func kind(forLabel label: String) -> RateWindow.Kind? {
        switch label.lowercased() {
        case ClaudeWindowID.fiveHour, "5h": .fiveHour
        case ClaudeWindowID.sevenDay, "7d": .weekly
        default: nil
        }
    }

    // MARK: - Canonical hash

    private static func canonicalHash(windows: [RateWindow], extras: [ExtraWindow]) -> String {
        let entries = windows.map {
            entry(id: ClaudeWindowID.id(for: $0.kind), percent: $0.usedPercent, resetsAt: $0.resetsAt)
        } + extras.map {
            entry(id: $0.id, percent: $0.usedPercent, resetsAt: $0.resetsAt)
        }
        let canonical = entries.sorted().joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func entry(id: String, percent: Double, resetsAt: Date?) -> String {
        let epoch = resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "nil"
        return "\(id):\(String(format: "%.1f", percent)):\(epoch)"
    }
}
