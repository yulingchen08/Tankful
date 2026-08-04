import TankfulCore
import SwiftUI

/// Claude Code's own rate-limit windows, as last captured by the status-line bridge.
struct ClaudeSectionView: View {
    @Environment(QuotaStore.self) private var store

    private static let elapsedNote = "window reset — send a message in Claude Code to refresh"

    var body: some View {
        // The timeline only supplies the tick; the displayed time comes from the injected clock.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            content(now: store.now())
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Claude Code",
                badge: Self.planBadge(store.claudePlanTier),
                freshness: store.claudeFreshness
            )

            ForEach(rows(now: now)) { row in
                QuotaBarRow(item: row, now: now)
            }

            // Staleness only means no status line rendered lately. The bridge stays silent when
            // Claude Code sends no rate limits, so this must not claim the app is closed.
            FreshnessNote(freshness: store.claudeFreshness)
        }
    }

    /// Named windows first, then whatever else Claude Code reported.
    private func rows(now: Date) -> [QuotaBarItem] {
        guard let snapshot = store.claudeSnapshot else { return [] }
        let windows = snapshot.windows.map { window in
            QuotaBarItem(
                id: "claude-\(window.kind.rowID)",
                label: window.kind.rowLabel,
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt,
                hasElapsed: window.hasElapsed(now: now),
                elapsedNote: Self.elapsedNote
            )
        }
        let extras = snapshot.extraWindows.map { extra in
            QuotaBarItem(
                id: "claude-extra-\(extra.id)",
                label: WindowFormat.extraWindowLabel(id: extra.id),
                usedPercent: extra.usedPercent,
                resetsAt: extra.resetsAt,
                hasElapsed: extra.hasElapsed(now: now),
                elapsedNote: Self.elapsedNote
            )
        }
        return windows + extras
    }

    static func planBadge(_ tier: String?) -> String? {
        guard let tier, !tier.isEmpty else { return nil }
        return tier == "claude_max" ? "Max" : tier
    }
}
