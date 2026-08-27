import Foundation

/// Builds the menu-bar title: the worst live window across both services, e.g. `X 63% wk`.
///
/// Pure so the pick can be tested without an app target; the status item only renders what
/// this returns.
public enum StatusTextComposer {
    /// Nil means icon-only: nothing on disk is worth putting a number on.
    public static func statusText(
        codex: CodexSnapshot?,
        codexFreshness: Freshness,
        claude: ClaudeSnapshot?,
        claudeFreshness: Freshness,
        now: Date
    ) -> String? {
        var candidates: [Candidate] = []
        // Stale numbers still beat no number; only "unavailable" means there is nothing to show.
        if !isUnavailable(codexFreshness), let codex {
            candidates += codex.windows
                .filter { !$0.hasElapsed(now: now) }
                .map { Candidate(marker: "X", percent: $0.usedPercent, label: compactLabel(for: $0.kind)) }
        }
        if !isUnavailable(claudeFreshness), let claude {
            candidates += claude.windows
                .filter { !$0.hasElapsed(now: now) }
                .map { Candidate(marker: "C", percent: $0.usedPercent, label: compactLabel(for: $0.kind)) }
            // A per-model weekly window is often the binding constraint, so extras compete too —
            // but only the ones this can name, since an id it cannot read would put raw text
            // (or nothing at all) in the menu bar. The panel still shows those verbatim.
            candidates += claude.extraWindows
                .filter { !$0.hasElapsed(now: now) }
                .compactMap { extra in
                    compactExtraLabel(id: extra.id).map {
                        Candidate(marker: "C", percent: extra.usedPercent, label: $0)
                    }
                }
        }
        guard let worst = candidates.max(by: { $0.percent < $1.percent }) else { return nil }
        return "\(worst.marker) \(Int(worst.percent.rounded()))% \(worst.label)"
            .trimmingCharacters(in: .whitespaces)
    }

    private struct Candidate {
        let marker: String
        let percent: Double
        let label: String
    }

    private static func isUnavailable(_ freshness: Freshness) -> Bool {
        if case .unavailable = freshness { return true }
        return false
    }

    /// Menu-bar suffix: must stay narrow.
    private static func compactLabel(for kind: RateWindow.Kind) -> String {
        switch kind {
        case .fiveHour: "5h"
        case .weekly: "wk"
        case .other(let minutes): "\(minutes)m"
        }
    }

    /// Claude names its extra windows `seven_day_opus`, `seven_day_sonnet`, …; the model alone
    /// identifies them once `wk` is already taken by the plain weekly window. Nil for any other
    /// shape, which keeps an unreadable id out of the menu bar.
    private static func compactExtraLabel(id: String) -> String? {
        guard let model = ClaudeExtraWindowID.model(in: id) else { return nil }
        return model.isEmpty ? "wk" : model.replacingOccurrences(of: "_", with: " ")
    }
}

/// Shared reading of Claude's extra-window ids, so the menu bar and the panel agree on what
/// `seven_day_opus` means.
public enum ClaudeExtraWindowID {
    /// The model an id names (`seven_day_opus` → `opus`), `""` for the bare `seven_day`, or nil
    /// when the id has some other shape and should be shown verbatim.
    public static func model(in id: String) -> String? {
        guard id == ClaudeWindowID.sevenDay || id.hasPrefix("\(ClaudeWindowID.sevenDay)_") else { return nil }
        return String(id.dropFirst(ClaudeWindowID.sevenDay.count).drop { $0 == "_" })
    }
}
