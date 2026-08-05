import AppKit
import Foundation
import Observation
import TankfulCore

/// The menu-bar item: gauge icon plus the most-constrained live window across both services,
/// e.g. `X 63% wk`.
@MainActor
final class StatusItemController: NSObject {
    let statusItem: NSStatusItem
    private let store: QuotaStore

    var onClick: (NSStatusBarButton?) -> Void = { _ in }

    init(store: QuotaStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        observeStore()
    }

    @objc private func handleClick() {
        onClick(statusItem.button)
    }

    /// Template line-art version of the app icon. Loaded from Contents/Resources in the
    /// .app, from the SwiftPM bundle under `swift run`; the SF Symbol covers a bundle
    /// assembled without the resource.
    private static func menuBarIcon() -> NSImage? {
        let icon: NSImage?
        if let url = Bundle.main.url(forResource: "MenuIcon", withExtension: "png") {
            icon = NSImage(contentsOf: url)
        } else {
            icon = Bundle.module.image(forResource: "MenuIcon")
        }
        guard let icon else {
            let symbol = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Tankful")
            symbol?.isTemplate = true
            return symbol
        }
        icon.size = NSSize(width: 18, height: 18)
        icon.isTemplate = true
        icon.accessibilityDescription = "Tankful"
        return icon
    }

    /// `withObservationTracking` fires once, so it re-registers itself after every change.
    private func observeStore() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }

    private func render() {
        // Every store read has to happen before any early return: a render that reads nothing
        // registers no dependency, and the observation never fires again.
        let text = StatusTextComposer.statusText(
            codex: store.codexSnapshot,
            codexFreshness: store.codexFreshness,
            claude: store.claudeSnapshot,
            claudeFreshness: store.claudeFreshness,
            now: store.now()
        )
        // Read for its dependency alone. It moves on every refresh, so a refresh that produces
        // an identical snapshot still re-renders — which is what advances an elapsed window.
        _ = store.lastRefreshAt

        guard let button = statusItem.button else { return }
        button.title = text.map { " \($0)" } ?? ""
        button.imagePosition = text == nil ? .imageOnly : .imageLeading
    }
}
