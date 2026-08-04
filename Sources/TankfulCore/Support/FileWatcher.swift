import Foundation

/// Watches one directory or one file with a vnode source and fires a debounced callback.
///
/// The two modes see different things. A directory's vnode reports `.write` only when an entry
/// is added, removed or renamed — appending to a file already inside it is invisible. A file's
/// own vnode does report `.write`/`.extend` on every append, which is the only way to notice a
/// session growing.
///
/// `pending` is confined to `queue`, which must be serial; `source` is lock-guarded so `deinit`
/// can cancel it from any thread.
public final class FileWatcher: @unchecked Sendable {
    private let url: URL
    private let eventMask: DispatchSource.FileSystemEvent
    private let queue: DispatchQueue
    private let debounceInterval: TimeInterval
    private let onChange: @Sendable () -> Void

    private let lock = NSLock()
    private var lockedSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    public convenience init(
        directoryURL: URL,
        queue: DispatchQueue,
        debounceInterval: TimeInterval = 2,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.init(url: directoryURL, eventMask: .write, queue: queue,
                  debounceInterval: debounceInterval, onChange: onChange)
    }

    /// `.extend` covers the plain append; `.write` covers a rewrite in place.
    public convenience init(
        fileURL: URL,
        queue: DispatchQueue,
        debounceInterval: TimeInterval = 2,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.init(url: fileURL, eventMask: [.write, .extend], queue: queue,
                  debounceInterval: debounceInterval, onChange: onChange)
    }

    private init(
        url: URL,
        eventMask: DispatchSource.FileSystemEvent,
        queue: DispatchQueue,
        debounceInterval: TimeInterval,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.url = url
        self.eventMask = eventMask
        self.queue = queue
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    /// `cancel()` is safe from any thread, and a `pending` item left behind holds only a weak
    /// reference, so it lapses on its own.
    deinit {
        source?.cancel()
    }

    public func start() {
        queue.async { [self] in startOnQueue() }
    }

    public func stop() {
        queue.async { [self] in stopOnQueue() }
    }

    private var source: DispatchSourceFileSystemObject? {
        get { lock.withLock { lockedSource } }
        set { lock.withLock { lockedSource = newValue } }
    }

    private func startOnQueue() {
        guard source == nil else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: eventMask,
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.schedule() }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    private func stopOnQueue() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    /// A burst of appends should cost one refresh, not one per event.
    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pending = nil
            onChange()
        }
        pending = item
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }
}
