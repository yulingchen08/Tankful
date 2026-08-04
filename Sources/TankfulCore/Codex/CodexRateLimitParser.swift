import Foundation

/// Turns a single Codex rollout JSONL line into a snapshot.
///
/// Every field is optional and decoded leniently: an unexpected shape must degrade to `nil`
/// rather than throw, and unknown keys (`credits`, `individual_limit`, …) are ignored.
public enum CodexRateLimitParser {
    /// Cheap pre-filter callers can use before paying for JSON decoding.
    public static let lineMarker = "\"rate_limits\""

    public static func snapshot(fromLine line: Substring) -> CodexSnapshot? {
        guard line.contains(lineMarker) else { return nil }
        guard let data = String(line).data(using: .utf8) else { return nil }
        guard let event = try? JSONDecoder().decode(Event.self, from: data) else { return nil }
        guard let payload = event.payload, payload.type == "token_count" else { return nil }
        guard let limits = payload.rateLimits else { return nil }
        guard let timestamp = event.timestamp,
              let capturedAt = ISO8601Timestamp.date(from: timestamp) else { return nil }

        let windows = [limits.primary, limits.secondary].compactMap(window(from:))
        guard !windows.isEmpty else { return nil }

        return CodexSnapshot(
            windows: windows,
            planType: limits.planType,
            capturedAt: capturedAt,
            limitReached: limits.rateLimitReachedType != nil
        )
    }

    private static func window(from raw: RawWindow?) -> RateWindow? {
        guard let raw, let minutes = raw.windowMinutes, let percent = raw.usedPercent else { return nil }
        // `resets_at` is epoch seconds; a missing or implausible one still leaves a usable
        // percentage, and an absurd date would trap the countdown arithmetic in the panel.
        let resetsAt = raw.resetsAt.flatMap(ResetTimestamp.date(epochSeconds:))
        return RateWindow(kind: .init(windowMinutes: minutes), usedPercent: percent, resetsAt: resetsAt)
    }

    // MARK: - Wire format

    private struct Event: Decodable {
        let timestamp: String?
        let payload: Payload?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            timestamp = try? container.decodeIfPresent(String.self, forKey: .timestamp)
            payload = try? container.decodeIfPresent(Payload.self, forKey: .payload)
        }

        enum CodingKeys: String, CodingKey { case timestamp, payload }
    }

    private struct Payload: Decodable {
        let type: String?
        let rateLimits: RawLimits?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try? container.decodeIfPresent(String.self, forKey: .type)
            rateLimits = try? container.decodeIfPresent(RawLimits.self, forKey: .rateLimits)
        }

        enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }
    }

    private struct RawLimits: Decodable {
        let primary: RawWindow?
        let secondary: RawWindow?
        let planType: String?
        let rateLimitReachedType: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            primary = try? container.decodeIfPresent(RawWindow.self, forKey: .primary)
            secondary = try? container.decodeIfPresent(RawWindow.self, forKey: .secondary)
            planType = try? container.decodeIfPresent(String.self, forKey: .planType)
            rateLimitReachedType = try? container.decodeIfPresent(String.self, forKey: .rateLimitReachedType)
        }

        enum CodingKeys: String, CodingKey {
            case primary, secondary
            case planType = "plan_type"
            case rateLimitReachedType = "rate_limit_reached_type"
        }
    }

    private struct RawWindow: Decodable {
        let usedPercent: Double?
        let windowMinutes: Int?
        let resetsAt: Double?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = try? container.decodeIfPresent(Double.self, forKey: .usedPercent)
            windowMinutes = try? container.decodeIfPresent(Int.self, forKey: .windowMinutes)
            resetsAt = try? container.decodeIfPresent(Double.self, forKey: .resetsAt)
        }

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }
    }
}
