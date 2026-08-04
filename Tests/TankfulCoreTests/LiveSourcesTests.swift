import Foundation
import Testing
@testable import TankfulCore

struct LiveSourcesTests {
    @Test func claudeSnapshotDirectoryIsWatchedOnceItExists() throws {
        try TestSupport.withTemporaryDirectory { base in
            let directory = base.appendingPathComponent("Tankful", isDirectory: true)
            let snapshot = directory.appendingPathComponent("claude-rate-limits.json")

            #expect(FileSystemWatchTargets.claudeSnapshotDirectory(snapshotURL: snapshot) == nil)
            try TestSupport.makeDirectory(directory)
            #expect(FileSystemWatchTargets.claudeSnapshotDirectory(snapshotURL: snapshot) == directory)
        }
    }

    @Test func watchTargetsCombineCodexPathsWithTheClaudeSnapshotDirectory() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let day = base.appendingPathComponent(".codex/sessions/2026/06/30", isDirectory: true)
            try TestSupport.makeDirectory(day)
            try TestSupport.write("{}", to: day.appendingPathComponent("rollout-2026-06-30T09-00-00-a.jsonl"))
            let env = Env(now: { Date() }, homeDirectory: base)
            try TestSupport.makeDirectory(env.claudeSnapshotURL.deletingLastPathComponent())

            let targets = await FileSystemWatchTargets(codex: CodexReader()).watchTargets(env: env)

            // Compared by resolved path: the temporary directory reaches here through /private.
            let paths = targets.directories.map { $0.resolvingSymlinksInPath().path }
            #expect(targets.files.map(\.lastPathComponent) == ["rollout-2026-06-30T09-00-00-a.jsonl"])
            #expect(paths.contains(day.resolvingSymlinksInPath().path))
            #expect(paths.last == env.claudeSnapshotURL.deletingLastPathComponent()
                .resolvingSymlinksInPath().path)
        }
    }

    /// The watch lookup and the read go through one reader, so a refresh cannot watch a file the
    /// same refresh did not read.
    @Test func watchedFilesAreTheOnesTheSharedReaderJustRead() async throws {
        try await TestSupport.withTemporaryDirectory { base in
            let day = base.appendingPathComponent(".codex/sessions/2026/06/30", isDirectory: true)
            try TestSupport.makeDirectory(day)
            for hour in ["07", "08", "09"] {
                try TestSupport.write("{}", to: day.appendingPathComponent("rollout-2026-06-30T\(hour)-00-00.jsonl"))
            }
            let env = Env(now: { Date() }, homeDirectory: base)
            let reader = CodexReader()

            _ = await reader.read(sessionsRoot: env.codexSessionsRoot, env: env)
            let targets = await FileSystemWatchTargets(codex: reader).watchTargets(env: env)

            #expect(targets.files.map(\.lastPathComponent) == [
                "rollout-2026-06-30T09-00-00.jsonl",
                "rollout-2026-06-30T08-00-00.jsonl",
                "rollout-2026-06-30T07-00-00.jsonl"
            ])
        }
    }
}
