import AppKit
import Foundation
import TankfulCore

/// Owns every reason a refresh happens: file writes, a 60s tick, panel opens and wake-from-sleep.
///
/// All of them funnel into Core's `QuotaRefresher`, which holds the single-flight gate. What
/// stays here is the platform half: the timer, the wake notification, the file watchers, and
/// writing the result into the main-actor store.
@MainActor
final class RefreshCoordinator {
    private let store: QuotaStore
    private let env: Env
    private let watcherQueue = DispatchQueue(label: "com.tankful.filewatcher")

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var watchers: [FileWatcher] = []
    private var watchedPaths: [String] = []

    /// Held rather than made per read so its directory-listing cache survives between refreshes,
    /// and shared with the watch-target lookup so one refresh sees one view of the session tree.
    private let codexReader = CodexReader()

    /// Lazy so the result callback can reach back into this instance.
    private lazy var refresher = QuotaRefresher(
        env: self.env,
        codex: self.codexReader,
        claude: ClaudeBridgeReader(),
        planTier: ClaudePlanReader(),
        watchTargets: FileSystemWatchTargets(codex: self.codexReader),
        onResult: { [weak self] result in self?.apply(result) }
    )

    init(store: QuotaStore, env: Env) {
        self.store = store
        self.env = env
    }

    func start() {
        // A second start would strand the first timer and observer, which nothing can reach to
        // invalidate afterwards.
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }

        refresher.start()
    }

    func stop() {
        refresher.stop()
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        watchers.forEach { $0.stop() }
        watchers = []
        watchedPaths = []
    }

    func refreshNow() {
        refresher.refreshNow()
    }

    private func apply(_ result: QuotaRefreshResult) {
        store.apply(result.update, refreshedAt: result.refreshedAt)
        syncWatchers(result.watchTargets)
    }

    /// The session files change as sessions come and go, so the file watchers are re-targeted
    /// whenever the path set moves.
    private func syncWatchers(_ targets: WatchTargets) {
        let paths = targets.directories.map(\.path) + targets.files.map(\.path)
        guard paths != watchedPaths else { return }

        let refresh: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.refreshNow() }
        }
        watchers.forEach { $0.stop() }
        watchers = targets.directories.map {
            FileWatcher(directoryURL: $0, queue: watcherQueue, onChange: refresh)
        } + targets.files.map {
            FileWatcher(fileURL: $0, queue: watcherQueue, onChange: refresh)
        }
        watchers.forEach { $0.start() }
        watchedPaths = paths
    }
}
