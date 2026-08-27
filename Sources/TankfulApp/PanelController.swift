import AppKit
import SwiftUI

/// The drop-down panel. Borderless and non-activating so opening it never steals focus.
@MainActor
final class PanelController {
    private let panel: NSPanel
    private let hostingController: NSHostingController<AnyView>
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Clicks on the status item must reach its own action instead of being eaten as an
    /// outside-click dismissal, otherwise the panel closes and reopens on every toggle.
    weak var statusItem: NSStatusItem?

    init(store: QuotaStore, updateChecker: UpdateChecker) {
        hostingController = NSHostingController(
            rootView: AnyView(PanelView().environment(store).environment(updateChecker))
        )
        hostingController.sizingOptions = [.preferredContentSize]

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    var isVisible: Bool { panel.isVisible }

    func show(below button: NSStatusBarButton?) {
        position(below: button)
        panel.orderFrontRegardless()
        installMonitors()
    }

    func hide() {
        removeMonitors()
        panel.orderOut(nil)
    }

    // MARK: - Placement

    private func position(below button: NSStatusBarButton?) {
        panel.setContentSize(hostingController.view.fittingSize)
        guard let button, let buttonWindow = button.window else { return }

        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 6)

        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }

    // MARK: - Outside-click dismissal

    private func installMonitors() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let clickedWindow = event.window
            MainActor.assumeIsolated {
                guard let self else { return }
                let isOwnWindow = clickedWindow === self.panel
                    || clickedWindow === self.statusItem?.button?.window
                if !isOwnWindow { self.hide() }
            }
            return event
        }
    }

    /// A monitor outlives the object that installed it, so one left behind would keep calling
    /// into a torn-down controller.
    isolated deinit {
        removeMonitors()
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
