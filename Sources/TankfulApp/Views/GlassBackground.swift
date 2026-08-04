import SwiftUI

/// Panel chrome: a frosted card the desktop shows through, with a rim light along its top-leading
/// edge. Values sampled from the reference card: interior ≈ backdrop lifted by white 0.25, rim
/// ≈ white 0.30 over that interior.
struct GlassBackground: View {
    var cornerRadius: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        frosted(shape)
            // Lifts a dark desktop toward the reference's pale card without hiding it.
            .overlay { shape.fill(.white.opacity(0.10)) }
            .overlay { shape.strokeBorder(rimLight, lineWidth: 1) }
    }

    // `glassEffect` only exists in the macOS 26 SDK; Swift 6.2 is the first toolchain that ships it.
    // Nothing may sit underneath it: a material fill there is what made the panel read as opaque.
    @ViewBuilder
    private func frosted(_ shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
        #else
        shape.fill(.ultraThinMaterial)
        #endif
    }

    private var rimLight: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.40), location: 0),
                .init(color: .white.opacity(0.12), location: 0.45),
                .init(color: .white.opacity(0.05), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
