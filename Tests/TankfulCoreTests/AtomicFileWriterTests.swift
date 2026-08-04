import Foundation
import Testing
@testable import TankfulCore

@Suite struct AtomicFileWriterTests {

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue
    }

    private func temporaryResidue(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".tmp-") }
    }

    @Test func createsTheMissingParentChain() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = base.appendingPathComponent("Application Support/Tankful/claude-rate-limits.json")
            try AtomicFileWriter.write(Data("hello".utf8), to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func writesTheExactBytes() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = base.appendingPathComponent("snapshot.json")
            let payload = Data([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x31, 0x7D])
            try AtomicFileWriter.write(payload, to: url)
            #expect(try Data(contentsOf: url) == payload)
        }
    }

    @Test func fileIsOwnerOnly() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = base.appendingPathComponent("snapshot.json")
            try AtomicFileWriter.write(Data("x".utf8), to: url)
            #expect(try mode(of: url) == 0o600)
        }
    }

    /// Samples the temp file's mode while the write is still running. Creating the file at the
    /// umask default and chmod'ing it afterwards leaves the contents readable to everyone for the
    /// length of the write, and that window is what this catches: against a `createFile`-then-
    /// chmod writer the samples come back 0644.
    ///
    /// The payload is large enough that the window lasts tens of milliseconds, and the sampler
    /// signals that it is running before the write starts, so "never sampled" is a failure rather
    /// than a silent pass.
    @Test func theTemporaryFileIsOwnerOnlyForTheWholeWrite() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = base.appendingPathComponent("snapshot.json")
            let temporary = base.appendingPathComponent(".snapshot.json.tmp-\(getpid())")
            let payload = Data(repeating: 0x61, count: 48 * 1024 * 1024)

            let samples = ModeSamples()
            let sampling = DispatchSemaphore(value: 0)
            let sampled = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                sampling.signal()
                let deadline = Date().addingTimeInterval(10)
                while Date() < deadline, !FileManager.default.fileExists(atPath: url.path) {
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: temporary.path),
                       let mode = attributes[.posixPermissions] as? NSNumber {
                        samples.insert(mode.intValue)
                    }
                }
                sampled.signal()
            }
            sampling.wait()
            try AtomicFileWriter.write(payload, to: url)
            sampled.wait()

            let observed = samples.values
            #expect(observed.contains(0o600), "the write window was never sampled")
            #expect(observed == [0o600])
        }
    }

    /// Written from the sampling thread and read from the test's.
    private final class ModeSamples: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: Set<Int> = []

        func insert(_ mode: Int) {
            lock.lock()
            defer { lock.unlock() }
            samples.insert(mode)
        }

        var values: Set<Int> {
            lock.lock()
            defer { lock.unlock() }
            return samples
        }
    }

    @Test func createdDirectoryIsOwnerOnly() throws {
        try TestSupport.withTemporaryDirectory { base in
            let directory = base.appendingPathComponent("Tankful", isDirectory: true)
            try AtomicFileWriter.write(Data("x".utf8), to: directory.appendingPathComponent("snapshot.json"))
            #expect(try mode(of: directory) == 0o700)
        }
    }

    @Test func overwriteReplacesTheOldContentAndLeavesNoResidue() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = base.appendingPathComponent("snapshot.json")
            try AtomicFileWriter.write(Data("first".utf8), to: url)
            try AtomicFileWriter.write(Data("second".utf8), to: url)
            #expect(try String(contentsOf: url, encoding: .utf8) == "second")
            #expect(try temporaryResidue(in: base).isEmpty)
        }
    }

    @Test func aFileWhereTheParentDirectoryShouldBeThrowsWithoutResidue() throws {
        try TestSupport.withTemporaryDirectory { base in
            // The parent path is an ordinary file, so no directory can be created there.
            let blocker = base.appendingPathComponent("Tankful")
            try TestSupport.write("not a directory", to: blocker)

            let error = #expect(throws: CocoaError.self) {
                try AtomicFileWriter.write(Data("x".utf8), to: blocker.appendingPathComponent("snapshot.json"))
            }
            #expect(error?.code == .fileWriteFileExists)
            #expect(try temporaryResidue(in: base).isEmpty)
            #expect(try String(contentsOf: blocker, encoding: .utf8) == "not a directory")
        }
    }

    /// The temp path is predictable, so a symlink planted there must not redirect the write.
    /// `createFile` replaces the link instead of writing through it; a refactor to
    /// `data.write(to:)` would follow it, which is what this pins down.
    @Test func aSymlinkAtTheTemporaryPathIsReplacedRatherThanFollowed() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = base.appendingPathComponent("snapshot.json")
            let victim = base.appendingPathComponent("victim.txt")
            try TestSupport.write("do not touch", to: victim)
            try FileManager.default.createSymbolicLink(
                at: base.appendingPathComponent(".snapshot.json.tmp-\(getpid())"),
                withDestinationURL: victim
            )

            try AtomicFileWriter.write(Data("payload".utf8), to: url)

            #expect(try String(contentsOf: victim, encoding: .utf8) == "do not touch")
            #expect(try String(contentsOf: url, encoding: .utf8) == "payload")
            #expect(try mode(of: url) == 0o600)
        }
    }

    /// Same hazard with a dangling link, which is the case an existence check misses: following
    /// it would create a file at a path of the attacker's choosing.
    @Test func aDanglingSymlinkAtTheTemporaryPathCreatesNothingAtItsTarget() throws {
        try TestSupport.withTemporaryDirectory { base in
            let url = base.appendingPathComponent("snapshot.json")
            let planted = base.appendingPathComponent("planted.txt")
            try FileManager.default.createSymbolicLink(
                at: base.appendingPathComponent(".snapshot.json.tmp-\(getpid())"),
                withDestinationURL: planted
            )

            try AtomicFileWriter.write(Data("payload".utf8), to: url)

            #expect(FileManager.default.fileExists(atPath: planted.path) == false)
            #expect(try String(contentsOf: url, encoding: .utf8) == "payload")
        }
    }
}
