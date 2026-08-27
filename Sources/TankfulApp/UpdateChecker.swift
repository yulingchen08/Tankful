import AppKit
import Observation
import TankfulCore

/// The app's single network touchpoint: an anonymous GET to GitHub's release API when the
/// panel opens, at most once every six hours. Nothing about the user or their quota rides
/// along; the response only ever raises the "update available" row.
@MainActor
@Observable
final class UpdateChecker {
    /// Set only when the released tag is strictly newer than the running version.
    private(set) var availableTag: String?

    private var lastCheckedAt: Date?
    private var inFlight = false

    private static let interval: TimeInterval = 6 * 60 * 60
    private static let latestReleaseAPI =
        URL(string: "https://api.github.com/repos/yulingchen08/Tankful/releases/latest")!

    var releasePage: URL {
        let tag = availableTag ?? "latest"
        let path = availableTag == nil ? "releases/latest" : "releases/tag/\(tag)"
        return URL(string: "https://github.com/yulingchen08/Tankful/\(path)")!
    }

    func checkIfDue() {
        // Screenshot fixtures must not depend on the network or today's real release.
        if let fake = ProcessInfo.processInfo.environment["TANKFUL_PROBE_LATEST"] {
            availableTag = fake
            return
        }
        guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return
        }
        if inFlight { return }
        if let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < Self.interval { return }

        inFlight = true
        Task {
            defer { inFlight = false }
            guard let (data, _) = try? await URLSession.shared.data(from: Self.latestReleaseAPI),
                  let tag = UpdateCheck.latestTag(fromReleaseJSON: data) else { return }
            // Only a completed request counts as checked; failures retry on the next open.
            lastCheckedAt = Date()
            if UpdateCheck.isNewer(tag, than: current) {
                availableTag = tag
            }
        }
    }
}
