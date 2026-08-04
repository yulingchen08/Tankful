import TankfulCore
import SwiftUI

/// Service name, plan badge and a freshness dot. Identical for both services, so the sections
/// differ only in what they feed it.
struct SectionHeader: View {
    let title: String
    let badge: String?
    let freshness: Freshness

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)
            if let badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.secondary.opacity(0.18)))
            }
            Spacer(minLength: 0)
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .help(dotDescription)
        }
    }

    private var dotColor: Color {
        switch freshness {
        case .fresh: .green
        case .stale: .orange
        case .unavailable: .gray
        }
    }

    private var dotDescription: String {
        switch freshness {
        case .fresh: "up to date"
        case .stale: "last seen a while ago"
        case .unavailable: "no data"
        }
    }
}
