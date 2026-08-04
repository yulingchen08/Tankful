import Foundation

/// Finds the Codex rollout files most likely to hold the latest rate-limit event.
///
/// Session paths are `<root>/YYYY/MM/DD/rollout-<ISO8601>-<uuid>.jsonl`, so both the
/// directory descent and the file ordering are plain lexicographic sorts; no per-file stat.
public struct CodexSessionLocator: Sendable {
    /// Two day directories, because just after midnight today's directory can be empty
    /// while the newest session still lives in yesterday's.
    private static let dayDirectoryProbeCount = 2
    private static let maxFiles = 3

    private var cache: [String: CachedListing] = [:]
    private var visitedPaths: Set<String> = []

    public init() {}

    public mutating func candidateFiles(sessionsRoot: URL) -> [URL] {
        visitedPaths.removeAll(keepingCapacity: true)
        defer { pruneCache() }

        let dayDirectories = newestDayDirectories(root: sessionsRoot)
        guard !dayDirectories.isEmpty else { return [] }
        return newestFiles(in: dayDirectories)
    }

    /// The paths worth watching for new Codex activity.
    ///
    /// Sessions live at `<root>/YYYY/MM/DD/rollout-*.jsonl`. A directory vnode only reports
    /// entries appearing or disappearing, so the directories catch a new session file and every
    /// rollover — never the appends to an ongoing session. That is what the files are for,
    /// watched directly with file vnodes.
    ///
    /// The watched files are exactly the ones `candidateFiles` returns. Watching only the newest
    /// missed appends to the other candidates, which is what two concurrent sessions produce.
    public mutating func watchTargets(sessionsRoot: URL) -> WatchTargets {
        visitedPaths.removeAll(keepingCapacity: true)
        defer { pruneCache() }

        let dayDirectories = newestDayDirectories(root: sessionsRoot)
        guard let newestDay = dayDirectories.first else {
            return WatchTargets(directories: existingChain(root: sessionsRoot), files: [])
        }
        // The year directory too: the first session of a month appears by creating a directory
        // in it, which no other level sees.
        let month = newestDay.deletingLastPathComponent()
        return WatchTargets(
            directories: [sessionsRoot, month.deletingLastPathComponent(), month, newestDay],
            files: newestFiles(in: dayDirectories)
        )
    }

    /// Rollout names start with an ISO timestamp, so lexicographic order is chronological.
    private mutating func newestFiles(in dayDirectories: [URL]) -> [URL] {
        dayDirectories
            .flatMap { entries(in: $0).files }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(Self.maxFiles)
            .map { $0 }
    }

    /// Before any session exists the descent stops short of a day directory. Watching the
    /// deepest level that does exist still catches the next one appearing.
    private mutating func existingChain(root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var directories = [root]
        var cursor = root
        while directories.count < 3, let newest = entries(in: cursor).directories.first {
            directories.append(newest)
            cursor = newest
        }
        return directories
    }

    /// Yesterday's day directory stops being visited once the date rolls over.
    private mutating func pruneCache() {
        cache = cache.filter { visitedPaths.contains($0.key) }
    }

    private mutating func newestDayDirectories(root: URL) -> [URL] {
        var days: [URL] = []
        for year in entries(in: root).directories {
            for month in entries(in: year).directories {
                for day in entries(in: month).directories {
                    days.append(day)
                    if days.count >= Self.dayDirectoryProbeCount { return days }
                }
            }
        }
        return days
    }

    // MARK: - Listing cache

    private struct CachedListing {
        let modifiedAt: Date?
        let directories: [URL]
        let files: [URL]
    }

    private mutating func entries(in directory: URL) -> (directories: [URL], files: [URL]) {
        visitedPaths.insert(directory.path)
        let modifiedAt = modificationDate(of: directory)
        if let cached = cache[directory.path], cached.modifiedAt == modifiedAt {
            return (cached.directories, cached.files)
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var directories: [URL] = []
        var files: [URL] = []
        for url in contents {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory == true {
                directories.append(url)
            } else if url.pathExtension == "jsonl" {
                files.append(url)
            }
        }
        directories.sort { $0.lastPathComponent > $1.lastPathComponent }

        cache[directory.path] = CachedListing(modifiedAt: modifiedAt, directories: directories, files: files)
        return (directories, files)
    }

    private func modificationDate(of directory: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        return attributes?[.modificationDate] as? Date
    }
}
