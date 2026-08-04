import Foundation
import Testing
@testable import TankfulCore

@Suite struct CodexWatchTargetsTests {

    @discardableResult
    private func dayDirectory(_ root: URL, _ year: String, _ month: String, _ day: String) throws -> URL {
        try TestSupport.makeDirectory(
            root.appendingPathComponent(year).appendingPathComponent(month).appendingPathComponent(day)
        )
    }

    private func watchTargets(in root: URL) -> WatchTargets {
        var locator = CodexSessionLocator()
        return locator.watchTargets(sessionsRoot: root)
    }

    /// Symlinks resolved on both sides: the temporary directory is reached through `/var`,
    /// while a directory listing reports it under `/private/var`.
    private func names(_ urls: [URL], from root: URL) -> [String] {
        let base = root.resolvingSymlinksInPath().path
        return urls.map { $0.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "<root>") }
    }

    @Test func watchesEveryDirectoryLevelPlusTheCandidateFiles() throws {
        try TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
            let older = try dayDirectory(root, "2026", "06", "29")
            let newer = try dayDirectory(root, "2026", "06", "30")
            try TestSupport.write("{}\n", to: older.appendingPathComponent("rollout-2026-06-29T20-00-00-a.jsonl"))
            try TestSupport.write("{}\n", to: newer.appendingPathComponent("rollout-2026-06-30T08-00-00-b.jsonl"))
            try TestSupport.write("{}\n", to: newer.appendingPathComponent("rollout-2026-06-30T09-00-00-c.jsonl"))

            let targets = watchTargets(in: root)
            #expect(names(targets.directories, from: root)
                == ["<root>", "<root>/2026", "<root>/2026/06", "<root>/2026/06/30"])
            #expect(targets.files.map(\.lastPathComponent) == [
                "rollout-2026-06-30T09-00-00-c.jsonl",
                "rollout-2026-06-30T08-00-00-b.jsonl",
                "rollout-2026-06-29T20-00-00-a.jsonl"
            ])
        }
    }

    /// The reader picks by `capturedAt`, not by name, so a session that is not the newest by name
    /// still decides the answer. Watching only the newest name left its appends to the 60s timer.
    @Test func everyFileTheReaderConsidersIsWatched() throws {
        try TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
            let day = try dayDirectory(root, "2026", "06", "30")
            for hour in ["07", "08", "09"] {
                try TestSupport.write("{}\n", to: day.appendingPathComponent("rollout-2026-06-30T\(hour)-00-00.jsonl"))
            }

            var locator = CodexSessionLocator()
            let candidates = locator.candidateFiles(sessionsRoot: root)
            #expect(locator.watchTargets(sessionsRoot: root).files == candidates)
            #expect(candidates.count == 3)
        }
    }

    /// The first session of a month appears by creating a directory in the year, which no other
    /// watched level reports.
    @Test func theYearDirectoryIsWatchedSoAMonthRolloverIsSeen() throws {
        try TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
            let june = try dayDirectory(root, "2026", "06", "30")
            try TestSupport.write("{}\n", to: june.appendingPathComponent("rollout-2026-06-30T09-00-00-a.jsonl"))

            let year = root.appendingPathComponent("2026").resolvingSymlinksInPath().path
            let watched = watchTargets(in: root).directories.map { $0.resolvingSymlinksInPath().path }
            #expect(watched.contains(year))
        }
    }

    /// Just after midnight today's directory exists but is still empty, so the file to watch is
    /// yesterday's — while the empty directory stays watched for the first session of the day.
    @Test func emptyNewestDayKeepsItsDirectoryAndFallsBackToYesterdaysFile() throws {
        try TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
            let older = try dayDirectory(root, "2026", "06", "29")
            try dayDirectory(root, "2026", "06", "30")
            try TestSupport.write("{}\n", to: older.appendingPathComponent("rollout-2026-06-29T20-00-00-a.jsonl"))

            let targets = watchTargets(in: root)
            #expect(names(targets.directories, from: root)
                == ["<root>", "<root>/2026", "<root>/2026/06", "<root>/2026/06/30"])
            #expect(targets.files.map(\.lastPathComponent) == ["rollout-2026-06-29T20-00-00-a.jsonl"])
        }
    }

    @Test func newestDayCarriesItsOwnMonthAcrossAMonthBoundary() throws {
        try TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
            let may = try dayDirectory(root, "2026", "05", "31")
            let june = try dayDirectory(root, "2026", "06", "01")
            try TestSupport.write("{}\n", to: may.appendingPathComponent("rollout-2026-05-31T23-50-00-a.jsonl"))
            try TestSupport.write("{}\n", to: june.appendingPathComponent("rollout-2026-06-01T00-10-00-b.jsonl"))

            let targets = watchTargets(in: root)
            #expect(names(targets.directories, from: root)
                == ["<root>", "<root>/2026", "<root>/2026/06", "<root>/2026/06/01"])
            #expect(targets.files.first?.lastPathComponent == "rollout-2026-06-01T00-10-00-b.jsonl")
        }
    }

    @Test func missingRootYieldsNoTargets() throws {
        try TestSupport.withTemporaryDirectory { base in
            let targets = watchTargets(in: base.appendingPathComponent("absent"))
            #expect(targets.directories.isEmpty)
            #expect(targets.files.isEmpty)
        }
    }

    @Test func emptyRootIsWatchedOnItsOwn() throws {
        try TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))

            let targets = watchTargets(in: root)
            #expect(names(targets.directories, from: root) == ["<root>"])
            #expect(targets.files.isEmpty)
        }
    }

    /// No day directory yet, so the descent stops where the tree does.
    @Test func partialTreeIsWatchedAsDeepAsItGoes() throws {
        try TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
            try TestSupport.makeDirectory(root.appendingPathComponent("2026").appendingPathComponent("06"))

            let targets = watchTargets(in: root)
            #expect(names(targets.directories, from: root) == ["<root>", "<root>/2026", "<root>/2026/06"])
            #expect(targets.files.isEmpty)
        }
    }

    @Test func nonSessionFilesAreNeverWatched() throws {
        try TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
            let day = try dayDirectory(root, "2026", "06", "30")
            try TestSupport.write("{}\n", to: day.appendingPathComponent("notes.txt"))

            #expect(watchTargets(in: root).files.isEmpty)
        }
    }

    /// The point of locating both in Core: the watched files are the ones the reader reads.
    @Test func watchedFilesAreTheFilesTheLocatorReads() throws {
        try TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
            let previousYear = try dayDirectory(root, "2025", "12", "31")
            let newYear = try dayDirectory(root, "2026", "01", "01")
            try TestSupport.write(
                "{}\n", to: previousYear.appendingPathComponent("rollout-2025-12-31T23-50-00-a.jsonl")
            )
            try TestSupport.write("{}\n", to: newYear.appendingPathComponent("rollout-2026-01-01T00-10-00-b.jsonl"))

            var locator = CodexSessionLocator()
            let candidates = locator.candidateFiles(sessionsRoot: root)
            #expect(watchTargets(in: root).files == candidates)
        }
    }

    @Test func watchedFileHoldsTheSnapshotTheReaderReports() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
            let day = try dayDirectory(root, "2026", "06", "30")
            let contents = try TestSupport.fixtureText("codex-normal.jsonl")
            try TestSupport.write(contents, to: day.appendingPathComponent("rollout-2026-06-30T09-00-00-a.jsonl"))

            let watched = try #require(watchTargets(in: root).files.first)
            let env = Env(now: { Date() }, homeDirectory: URL(fileURLWithPath: "/nonexistent"))
            let snapshot = try #require(await CodexReader().read(sessionsRoot: root, env: env).0)

            let lines = try TailChunkReader.lines(at: watched) { $0.contains(CodexRateLimitParser.lineMarker) }
            let fromWatchedFile = try #require(lines.compactMap(CodexRateLimitParser.snapshot(fromLine:)).first)
            #expect(fromWatchedFile == snapshot)
        }
    }

    /// Watch lookup must not poison the listing cache the reader shares with it.
    @Test func watchLookupLeavesTheLocatorUsableForReads() throws {
        try TestSupport.withTemporaryDirectory { base in
            let root = try TestSupport.makeDirectory(base.appendingPathComponent("sessions"))
            let day = try dayDirectory(root, "2026", "06", "30")
            try TestSupport.write("{}\n", to: day.appendingPathComponent("rollout-2026-06-30T05-00-00.jsonl"))

            var locator = CodexSessionLocator()
            #expect(locator.watchTargets(sessionsRoot: root).files.count == 1)
            #expect(locator.candidateFiles(sessionsRoot: root).count == 1)

            try TestSupport.write("{}\n", to: day.appendingPathComponent("rollout-2026-06-30T06-00-00.jsonl"))
            try TestSupport.setModificationDate(Date(timeIntervalSince1970: 1_800_000_000), of: day)
            #expect(locator.watchTargets(sessionsRoot: root).files.first?.lastPathComponent
                == "rollout-2026-06-30T06-00-00.jsonl")
        }
    }
}
