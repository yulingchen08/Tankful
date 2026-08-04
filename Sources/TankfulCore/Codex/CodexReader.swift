import Foundation

/// Reads the newest Codex rate-limit snapshot available on disk.
///
/// An instance keeps its locator between reads so the directory-listing cache actually survives;
/// it is an actor so refreshes run off the main thread.
public actor CodexReader {
    private var locator = CodexSessionLocator()

    public init() {}

    /// The paths whose changes mean the next read would see something new.
    ///
    /// Shares the reader's locator on purpose: the listing cache makes this a second lookup
    /// rather than a second scan, so the files being watched are the files just read.
    public func watchTargets(sessionsRoot: URL) -> WatchTargets {
        locator.watchTargets(sessionsRoot: sessionsRoot)
    }

    public func read(sessionsRoot: URL, env: Env) -> (CodexSnapshot?, Freshness) {
        let candidates = locator.candidateFiles(sessionsRoot: sessionsRoot)
        guard !candidates.isEmpty else {
            return (nil, .unavailable(reason: "no Codex sessions found"))
        }

        var newest: CodexSnapshot?
        for file in candidates {
            let lines = (try? TailChunkReader.lines(at: file) { $0.contains(CodexRateLimitParser.lineMarker) }) ?? []
            for line in lines {
                guard let snapshot = CodexRateLimitParser.snapshot(fromLine: line) else { continue }
                if newest == nil || snapshot.capturedAt > newest!.capturedAt { newest = snapshot }
                // Lines arrive newest first, so the rest of this file is older.
                break
            }
        }

        guard let snapshot = newest else {
            return (nil, .unavailable(reason: "no rate-limit data in recent sessions"))
        }
        return (snapshot, snapshot.freshness(now: env.now()))
    }
}
