import Foundation

/// Replaces a file in one step so a reader never sees a half-written one.
///
/// The app never calls this; only the bridge executable writes snapshots.
public enum AtomicFileWriter {
    public enum WriteError: Error, Equatable {
        case temporaryFileNotCreated(path: String)
        case writeFailed(code: Int32)
        case renameFailed(code: Int32)
    }

    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
        if !exists || !isDirectory.boolValue {
            // 0700 only reaches directories created here; an existing one keeps its own mode.
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        // The temp file is a sibling so the rename stays on one volume.
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).tmp-\(getpid())")
        let descriptor = try createOwnerOnlyFile(at: temporary.path)
        do {
            try writeAll(data, to: descriptor)
            close(descriptor)
        } catch {
            close(descriptor)
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }

        guard rename(temporary.path, url.path) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temporary)
            throw WriteError.renameFailed(code: code)
        }
    }

    /// `open` applies the mode when the inode appears, so the contents are never readable by
    /// anyone else — a create-then-chmod leaves them at the umask default for the whole write.
    ///
    /// The temp path is predictable, so it is unlinked first (which drops a planted symlink
    /// rather than writing through it) and then created with `O_EXCL`, so a link re-planted in
    /// between fails the open instead of redirecting the write.
    private static func createOwnerOnlyFile(at path: String) throws -> Int32 {
        unlink(path)
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw WriteError.temporaryFileNotCreated(path: path) }
        return descriptor
    }

    /// A single `write` may be short, so anything left over is written again.
    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                return Darwin.write(descriptor, base + offset, data.count - offset)
            }
            guard written > 0 else { throw WriteError.writeFailed(code: errno) }
            offset += written
        }
    }
}
