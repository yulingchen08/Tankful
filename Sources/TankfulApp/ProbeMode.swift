import AppKit
import SwiftUI

/// Screenshot-capture mode, active only when TANKFUL_PROBE_HOME is set. All data reads are
/// redirected to that fake home; the panel opens itself over a gradient backdrop and writes
/// the capture rect for Scripts/capture-screenshots.sh, which doubles as the ready signal.
@MainActor
enum ProbeMode {
    static var probeHome: String? {
        ProcessInfo.processInfo.environment["TANKFUL_PROBE_HOME"]
    }

    /// Overrides the app's appearance so the script can capture both variants without
    /// touching the system-wide setting.
    static func applyAppearance() {
        switch ProcessInfo.processInfo.environment["TANKFUL_PROBE_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    static func run(
        panelController: PanelController,
        statusItemController: StatusItemController,
        probeHome: String
    ) {
        Task { @MainActor in
            // The first refresh needs a moment to read the fake data before the panel sizes itself.
            try? await Task.sleep(for: .seconds(2))
            panelController.show(below: statusItemController.statusItem.button)

            // The panel is private to PanelController; the app has exactly one NSPanel.
            guard let panel = NSApp.windows.first(where: { $0 is NSPanel }),
                  let screen = NSScreen.main else { return }
            panel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - panel.frame.width / 2,
                y: screen.frame.midY - panel.frame.height / 2
            ))

            let backdrop = makeBackdrop(around: panel.frame)
            backdrop.orderFrontRegardless()
            panel.orderFrontRegardless()

            // Let the glass material settle before declaring the frame ready to capture.
            try? await Task.sleep(for: .seconds(1))
            writeCaptureRect(backdrop.frame, probeHome: probeHome)
        }
    }

    /// The panel's glass is translucent, so capturing it alone yields a mostly transparent PNG.
    /// A gradient behind it gives the material something to frost against.
    private static func makeBackdrop(around panelFrame: NSRect) -> NSWindow {
        let backdrop = NSWindow(
            contentRect: panelFrame.insetBy(dx: -48, dy: -48),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Same level as the panel; ordering the panel afterwards keeps it on top.
        backdrop.level = .popUpMenu
        backdrop.contentView = NSHostingView(rootView: backdropGradient)
        return backdrop
    }

    private static var backdropGradient: some View {
        let isDark = ProcessInfo.processInfo.environment["TANKFUL_PROBE_APPEARANCE"] == "dark"
        let colors = isDark
            ? [Color(red: 0.12, green: 0.14, blue: 0.22), Color(red: 0.21, green: 0.16, blue: 0.30)]
            : [Color(red: 0.78, green: 0.86, blue: 0.98), Color(red: 0.89, green: 0.83, blue: 0.96)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// screencapture -R wants global top-left-origin coordinates, so flip against the
    /// primary screen (the one that defines the global coordinate space).
    private static func writeCaptureRect(_ frame: NSRect, probeHome: String) {
        guard let primary = NSScreen.screens.first else { return }
        let topLeftY = primary.frame.maxY - frame.maxY
        let rect = "\(Int(frame.minX)),\(Int(topLeftY)),\(Int(frame.width)),\(Int(frame.height))"
        let url = URL(fileURLWithPath: probeHome).appendingPathComponent("probe-capture-rect.txt")
        try? rect.write(to: url, atomically: true, encoding: .utf8)
    }
}
