import AppKit
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
            header
            sections
            FooterView()
        }
    }

    private var header: some View {
        HStack {
            Text("Tankful")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(.secondary)
            Spacer()
            // PanelIcon is the tank artwork cut out from its tile; the full AppIcon square
            // reads as a dark blob at this size.
            if let icon = Self.panelIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            }
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

    /// In the .app the PNG sits in Contents/Resources. Bundle.module only probes the
    /// bundle root and the build machine's absolute .build path, so calling it first
    /// would crash any bundle built on another machine; it stays as the fallback for
    /// `swift run`, where the resource bundle does sit next to the executable.
    private static let panelIcon: NSImage? = {
        if let url = Bundle.main.url(forResource: "PanelIcon", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return Bundle.module.image(forResource: "PanelIcon")
    }()
}
