import Foundation

/// The decisions behind the update hint, kept pure so the app's one network call stays
/// a dumb fetch: parse GitHub's release JSON, compare two version strings.
public enum UpdateCheck {
    /// The `tag_name` of a GitHub release payload, nil for anything that does not decode.
    public static func latestTag(fromReleaseJSON data: Data) -> String? {
        struct Release: Decodable {
            let tagName: String
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(Release.self, from: data).tagName
    }

    /// Numeric per-component comparison, so 0.10 beats 0.9. A malformed version on either
    /// side answers false: never nag on data that cannot be read.
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let latestParts = components(latest), let currentParts = components(current) else {
            return false
        }
        for index in 0..<max(latestParts.count, currentParts.count) {
            let lhs = index < latestParts.count ? latestParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private static func components(_ raw: String) -> [Int]? {
        let trimmed = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let parts = trimmed.split(separator: ".")
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part) else { return nil }
            numbers.append(number)
        }
        return numbers
    }
}
