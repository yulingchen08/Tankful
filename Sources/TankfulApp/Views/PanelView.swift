import SwiftUI

struct PanelView: View {
    var body: some View {
        stack
            .padding(16)
            .frame(width: 320)
            .background(GlassBackground())
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tankful")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(.secondary)
            sections
            FooterView()
        }
    }

    // Deliberately not wrapped in a GlassEffectContainer: compared side by side, the container
    // draws the bars' opaque fill through the glass pass, which feathers the fill's trailing edge
    // and desaturates it. A handful of small capsules in an on-demand panel is worth the extra
    // render passes.
    private var sections: some View {
        VStack(alignment: .leading, spacing: 16) {
            CodexSectionView()
            ClaudeSectionView()
        }
    }
}
