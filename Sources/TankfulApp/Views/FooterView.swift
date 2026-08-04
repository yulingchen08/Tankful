import TankfulCore
import SwiftUI

struct FooterView: View {
    @Environment(QuotaStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text(lastRefreshText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Refresh") { store.requestRefresh() }
                .buttonStyle(.borderless)
                .font(.footnote)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.footnote)
        }
    }

    private var lastRefreshText: String {
        guard let lastRefreshAt = store.lastRefreshAt else { return "never refreshed" }
        return "updated \(WindowFormat.relative(date: lastRefreshAt, now: store.now()))"
    }
}
