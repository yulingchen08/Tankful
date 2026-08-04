import Foundation

/// Reads the ISO8601 timestamps Codex and Claude Code write.
enum ISO8601Timestamp {
    /// Codex writes fractional seconds, but `.withFractionalSeconds` rejects strings without
    /// them, so both spellings have to be tried.
    static func date(from value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? wholeSecondFormatter.date(from: value)
    }

    /// ISO8601DateFormatter is thread-safe once its options are set, so one instance per
    /// spelling is shared.
    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let wholeSecondFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
