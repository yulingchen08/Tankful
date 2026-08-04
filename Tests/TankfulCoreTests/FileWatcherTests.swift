import Foundation
import Testing
@testable import TankfulCore

@Suite struct FileWatcherTests {

    @Test func firesDebouncedCallbackWhenDirectoryChanges() throws {
        try TestSupport.withTemporaryDirectory { dir in
            let queue = DispatchQueue(label: "tankful.tests.watcher")
            let fired = DispatchSemaphore(value: 0)
            let watcher = FileWatcher(directoryURL: dir, queue: queue, debounceInterval: 0.05) {
                fired.signal()
            }

            watcher.start()
            queue.sync {}  // the source must exist before the write, or the event is missed

            try TestSupport.write("{}\n", to: dir.appendingPathComponent("new.jsonl"))
            #expect(fired.wait(timeout: .now() + 5) == .success)

            watcher.stop()
            queue.sync {}
        }
    }

    /// The directory vnode is blind to appends, so an ongoing session is only noticed by
    /// watching its file directly.
    @Test func firesWhenTheWatchedFileIsAppendedTo() throws {
        try TestSupport.withTemporaryDirectory { dir in
            let file = try TestSupport.write("{}\n", to: dir.appendingPathComponent("rollout.jsonl"))
            let queue = DispatchQueue(label: "tankful.tests.watcher.file")
            let fired = DispatchSemaphore(value: 0)
            let watcher = FileWatcher(fileURL: file, queue: queue, debounceInterval: 0.05) {
                fired.signal()
            }

            watcher.start()
            queue.sync {}

            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("{\"appended\":true}\n".utf8))
            try handle.close()

            #expect(fired.wait(timeout: .now() + 5) == .success)

            watcher.stop()
            queue.sync {}
        }
    }

    @Test func stoppedWatcherDoesNotFire() throws {
        try TestSupport.withTemporaryDirectory { dir in
            let queue = DispatchQueue(label: "tankful.tests.watcher.stopped")
            let fired = DispatchSemaphore(value: 0)
            let watcher = FileWatcher(directoryURL: dir, queue: queue, debounceInterval: 0.05) {
                fired.signal()
            }

            watcher.start()
            queue.sync {}
            watcher.stop()
            queue.sync {}

            try TestSupport.write("{}\n", to: dir.appendingPathComponent("new.jsonl"))
            #expect(fired.wait(timeout: .now() + 0.5) == .timedOut)
        }
    }
}
