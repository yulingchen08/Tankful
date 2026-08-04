import TankfulCore
import SwiftUI

/// One row's worth of display state. Codex windows, Claude windows and Claude's extra windows
/// all flatten into this, so the row never has to know which of them it is drawing.
struct QuotaBarItem: Identifiable, Equatable {
    let id: String
    let label: String
    let usedPercent: Double
    /// Nil when the source omitted a reset time; the percentage still stands.
    let resetsAt: Date?
    let hasElapsed: Bool
    /// What the user has to do to get a fresh number once the window rolled over.
    let elapsedNote: String
}

extension UsageLevel {
    var tint: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

/// A label, a percentage and a glass capsule filled to match it.
struct QuotaBarRow: View {
    let item: QuotaBarItem
    let now: Date

    private static let trackHeight: CGFloat = 14

    /// The tint has to follow the number on screen, or 89.6 reads as an orange "90%" next to a
    /// red one.
    private var displayPercent: Double { item.usedPercent.rounded() }

    private var tint: Color { UsageLevel(usedPercent: displayPercent).tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            headline
            track
            caption
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            // An elapsed window's percentage describes a window that no longer exists.
            Text(item.hasElapsed ? "—" : "\(Int(displayPercent))%")
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(item.hasElapsed ? Color.secondary : .primary)
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                trackBase
                fill(availableWidth: proxy.size.width)
            }
        }
        .frame(height: Self.trackHeight)
        .opacity(item.hasElapsed ? 0.45 : 1)
    }

    /// Sampled from the reference: the track is translucent white laid on the card's glass, not a
    /// pane of glass of its own. Measured, a second `glassEffect` here darkens by as much as the
    /// white lifts, and the track vanishes into the card over a bright desktop.
    private var trackBase: some View {
        // `.primary` keeps the sampled white 0.22 in dark mode and flips to a dark track in light
        // mode, where a white one would vanish into the card.
        Capsule()
            .fill(.primary.opacity(0.22))
            .overlay { Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 1) }
    }

    /// A plain gradient layer: the fill animates on every refresh, which is exactly where glass
    /// is not worth its render passes. Opaque colour and no outer shadow, so the edge stays sharp
    /// and nothing bleeds outside the capsule.
    @ViewBuilder
    private func fill(availableWidth: CGFloat) -> some View {
        let fraction = min(max(item.usedPercent / 100, 0), 1)
        if !item.hasElapsed, fraction > 0 {
            Capsule()
                .fill(
                    // The reference runs near-white at the leading edge into saturated colour at the
                    // head. Held back from pure white so a few-percent pill still shows its tint.
                    LinearGradient(
                        stops: [
                            .init(color: tint.mix(with: .white, by: 0.80), location: 0),
                            .init(color: tint.mix(with: .white, by: 0.45), location: 0.35),
                            .init(color: tint, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                // A few percent still has to look like a pill rather than a squeezed sliver.
                .frame(width: max(availableWidth * fraction, Self.trackHeight))
                .overlay { gloss }
                .animation(.snappy, value: item.usedPercent)
        }
    }

    /// Thin highlight along the top edge; the reference keeps its gloss to roughly the top sixth.
    private var gloss: some View {
        Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.28), location: 0),
                        .init(color: .white.opacity(0.05), location: 0.22),
                        .init(color: .clear, location: 0.4)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    @ViewBuilder
    private var caption: some View {
        if item.hasElapsed {
            Text(item.elapsedNote)
                .font(.footnote)
                .italic()
                .foregroundStyle(.secondary)
        } else if let resetsAt = item.resetsAt {
            Text("resets in \(CountdownFormat.text(from: now, to: resetsAt))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
