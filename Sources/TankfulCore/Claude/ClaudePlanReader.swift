import Foundation

/// Reads the subscription tier out of `~/.claude.json`.
///
/// That file holds a hundred unrelated keys, including project history; only the one key path
/// is decoded and any failure degrades to nil.
public struct ClaudePlanReader: Sendable {
    public init() {}

    public static func organizationType(at url: URL) -> String? {
        // Not mapped: Claude Code rewrites this file in place, and a mapping whose backing file
        // shrinks mid-read faults with SIGBUS instead of returning short.
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(Config.self, from: data))?.oauthAccount?.organizationType
    }

    private struct Config: Decodable {
        let oauthAccount: Account?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            oauthAccount = try? container.decodeIfPresent(Account.self, forKey: .oauthAccount)
        }

        enum CodingKeys: String, CodingKey { case oauthAccount }
    }

    private struct Account: Decodable {
        let organizationType: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            organizationType = try? container.decodeIfPresent(String.self, forKey: .organizationType)
        }

        enum CodingKeys: String, CodingKey { case organizationType }
    }
}
