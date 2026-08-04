import Foundation

/// Wire names for the two windows Tankful shows first-class. Shared by the parser's
/// canonical hash and the snapshot file so both spell them the same way.
enum ClaudeWindowID {
    static let fiveHour = "five_hour"
    static let sevenDay = "seven_day"

    static func kind(for id: String) -> RateWindow.Kind? {
        switch id {
        case fiveHour: .fiveHour
        case sevenDay: .weekly
        default: nil
        }
    }

    static func id(for kind: RateWindow.Kind) -> String {
        switch kind {
        case .fiveHour: fiveHour
        case .weekly: sevenDay
        case .other(let minutes): "other_\(minutes)"
        }
    }
}

/// The versioned JSON the bridge writes and the app reads back.
///
/// Encoding is byte-deterministic (sorted keys, whole-second ISO8601) so the bridge can
/// compare bytes to decide whether a write is needed.
public enum ClaudeSnapshotFile {
    public static let currentVersion = 1
    public static let source = "statusline"

    public struct DecodedSnapshot: Sendable, Equatable {
        public let version: Int
        public let capturedAt: Date
        public let sourceHash: String?
        public let windows: [RateWindow]
        public let extraWindows: [ExtraWindow]
    }

    public static func encode(
        _ parsed: StatusLineRateLimitParser.ParsedRateLimits,
        capturedAt: Date
    ) throws -> Data {
        let payload = Payload(
            version: currentVersion,
            capturedAt: capturedAt,
            source: source,
            sourceHash: parsed.canonicalHash,
            windows: parsed.windows.map {
                Window(id: ClaudeWindowID.id(for: $0.kind), usedPercent: $0.usedPercent, resetsAt: $0.resetsAt)
            },
            extraWindows: parsed.extras.map {
                Window(id: $0.id, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    public static func decode(_ data: Data) throws -> DecodedSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Payload.self, from: data)

        // The file is as untrusted as the payload it came from: nothing stops a hand-written one
        // from listing the same window thousands of times, so the same bounds apply on the way in.
        var windows: [RateWindow] = []
        var extras: [ExtraWindow] = payload.extraWindows.map {
            ClaudeWindowBounds.extra(id: $0.id, percent: $0.usedPercent, resetsAt: $0.resetsAt)
        }
        for window in payload.windows {
            // A window id this version does not know still carries a usable percentage,
            // so it degrades to an extra instead of being dropped.
            if let kind = ClaudeWindowID.kind(for: window.id) {
                let decoded = RateWindow(kind: kind, usedPercent: window.usedPercent, resetsAt: window.resetsAt)
                ClaudeWindowBounds.insert(decoded, into: &windows)
            } else {
                extras.append(ClaudeWindowBounds.extra(id: window.id, percent: window.usedPercent, resetsAt: window.resetsAt))
            }
        }

        return DecodedSnapshot(
            version: payload.version,
            capturedAt: payload.capturedAt,
            sourceHash: payload.sourceHash,
            windows: windows,
            extraWindows: ClaudeWindowBounds.cappedExtras(extras)
        )
    }

    // MARK: - Wire format

    private struct Payload: Codable {
        let version: Int
        let capturedAt: Date
        let source: String?
        let sourceHash: String?
        let windows: [Window]
        let extraWindows: [Window]

        init(
            version: Int,
            capturedAt: Date,
            source: String,
            sourceHash: String,
            windows: [Window],
            extraWindows: [Window]
        ) {
            self.version = version
            self.capturedAt = capturedAt
            self.source = source
            self.sourceHash = sourceHash
            self.windows = windows
            self.extraWindows = extraWindows
        }

        /// Only `version` and `capturedAt` are load-bearing; everything else may be missing
        /// in a file written by a different bridge build.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            capturedAt = try container.decode(Date.self, forKey: .capturedAt)
            source = (try? container.decodeIfPresent(String.self, forKey: .source)).flatMap { $0 }
            sourceHash = (try? container.decodeIfPresent(String.self, forKey: .sourceHash)).flatMap { $0 }
            windows = (try? container.decodeIfPresent([Window].self, forKey: .windows)).flatMap { $0 } ?? []
            extraWindows = (try? container.decodeIfPresent([Window].self, forKey: .extraWindows)).flatMap { $0 } ?? []
        }
    }

    private struct Window: Codable {
        let id: String
        let usedPercent: Double
        let resetsAt: Date?

        /// An explicit `null` keeps the field visible to anyone reading the file by hand;
        /// the synthesised encoder would drop the key instead.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(usedPercent, forKey: .usedPercent)
            try container.encode(resetsAt, forKey: .resetsAt)
        }
    }
}
