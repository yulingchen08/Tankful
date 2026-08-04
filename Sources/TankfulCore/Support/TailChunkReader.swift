import Foundation

/// Reads matching lines from the end of a large line-delimited file without loading it whole.
public enum TailChunkReader {
    /// Returns lines matching `predicate` from the tail of `url`, newest first.
    ///
    /// Reads the last `initialChunk` bytes and splits on newlines. Unless the read started at
    /// offset 0, the first line of the chunk is a fragment of a line that began before the
    /// offset, so it is always discarded. When nothing matches and the file extends past the
    /// chunk, the chunk doubles and the read is retried, up to `maxChunk` bytes per attempt.
    public static func lines(
        at url: URL,
        initialChunk: Int = 64 * 1024,
        maxChunk: Int = 1024 * 1024,
        matching predicate: (Substring) -> Bool
    ) throws -> [Substring] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        var chunk = max(1, min(initialChunk, maxChunk))

        while true {
            let offset = size > UInt64(chunk) ? size - UInt64(chunk) : 0
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()

            // A chunk boundary can split a multi-byte scalar; the damage lands in the
            // fragment line, which is discarded anyway.
            let text = String(decoding: data, as: UTF8.self)
            var candidates = text.split(separator: "\n", omittingEmptySubsequences: false)
            if offset > 0, !candidates.isEmpty { candidates.removeFirst() }

            let matches = candidates.filter(predicate)
            if !matches.isEmpty { return matches.reversed() }

            if offset == 0 || chunk >= maxChunk { return [] }
            chunk = chunk <= maxChunk / 2 ? chunk * 2 : maxChunk
        }
    }
}
