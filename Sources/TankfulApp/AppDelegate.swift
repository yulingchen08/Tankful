import AppKit
import TankfulCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: QuotaStore?
    private var coordinator: RefreshCoordinator?
    private var statusItemController: StatusItemController?
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProbeMode.applyAppearance()
        let env = ProbeMode.probeHome.map {
            Env(now: { Date() }, homeDirectory: URL(fileURLWithPath: $0))
        } ?? Env.live
        let store = QuotaStore(env: env)
        let coordinator = RefreshCoordinator(store: store, env: env)
        let updateChecker = UpdateChecker()
        let panelController = PanelController(store: store, updateChecker: updateChecker)
        let statusItemController = StatusItemController(store: store)

        store.onRefreshRequested = { [weak coordinator] in coordinator?.refreshNow() }

        panelController.statusItem = statusItemController.statusItem
        statusItemController.onClick = { [weak panelController, weak coordinator] button in
            guard let panelController else { return }
            if panelController.isVisible {
                panelController.hide()
            } else {
                coordinator?.refreshNow()
                updateChecker.checkIfDue()
                panelController.show(below: button)
            }
        }

        self.store = store
        self.coordinator = coordinator
        self.panelController = panelController
        self.statusItemController = statusItemController

        coordinator.start()

        if let probeHome = ProbeMode.probeHome {
            updateChecker.checkIfDue()
            ProbeMode.run(
                panelController: panelController,
                statusItemController: statusItemController,
                probeHome: probeHome
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
