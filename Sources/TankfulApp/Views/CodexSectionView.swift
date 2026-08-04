import TankfulCore
import SwiftUI

struct CodexSectionView: View {
    @Environment(QuotaStore.self) private var store

    private static let elapsedNote = "window reset — start a Codex turn to refresh"

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
                title: "Codex",
                badge: store.codexSnapshot?.planType,
                freshness: store.codexFreshness
            )

            if store.codexSnapshot?.limitReached == true {
                limitBanner
            }

            ForEach(rows(now: now)) { row in
                QuotaBarRow(item: row, now: now)
            }

            FreshnessNote(freshness: store.codexFreshness)
        }
    }

    private func rows(now: Date) -> [QuotaBarItem] {
        let windows = store.codexSnapshot?.windows ?? []
        return windows.map { window in
            QuotaBarItem(
                id: "codex-\(window.kind.rowID)",
                label: window.kind.rowLabel,
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt,
                hasElapsed: window.hasElapsed(now: now),
                elapsedNote: Self.elapsedNote
            )
        }
    }

    private var limitBanner: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.octagon.fill")
            Text("Rate limit reached")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.red))
    }
}
