import Foundation
import Testing
@testable import TankfulCore

@Suite struct CodexSessionLocatorTests {

    private func dayDirectory(_ root: URL, _ year: String, _ month: String, _ day: String) throws -> URL {
        try TestSupport.makeDirectory(
            root.appendingPathComponent(year).appendingPathComponent(month).appendingPathComponent(day)
        )
    }

    @Test func picksNewestFilesAcrossTwoDayDirectories() throws {
        try TestSupport.withTemporaryDirectory { root in
            let older = try dayDirectory(root, "2026", "06", "29")
            let newer = try dayDirectory(root, "2026", "06", "30")
            try TestSupport.write("{}\n", to: older.appendingPathComponent("rollout-2026-06-29T20-00-00-a.jsonl"))
            try TestSupport.write("{}\n", to: newer.appendingPathComponent("rollout-2026-06-30T08-00-00-b.jsonl"))
            try TestSupport.write("{}\n", to: newer.appendingPathComponent("rollout-2026-06-30T09-00-00-c.jsonl"))

            var locator = CodexSessionLocator()
            let files = locator.candidateFiles(sessionsRoot: root).map(\.lastPathComponent)
            #expect(files == [
                "rollout-2026-06-30T09-00-00-c.jsonl",
                "rollout-2026-06-30T08-00-00-b.jsonl",
                "rollout-2026-06-29T20-00-00-a.jsonl"
            ])
        }
    }

    @Test func emptyNewestDayFallsBackToPreviousDay() throws {
        try TestSupport.withTemporaryDirectory { root in
            let older = try dayDirectory(root, "2026", "06", "29")
            _ = try dayDirectory(root, "2026", "06", "30")
            try TestSupport.write("{}\n", to: older.appendingPathComponent("rollout-2026-06-29T20-00-00-a.jsonl"))

            var locator = CodexSessionLocator()
            #expect(locator.candidateFiles(sessionsRoot: root).map(\.lastPathComponent)
                == ["rollout-2026-06-29T20-00-00-a.jsonl"])
        }
    }

    @Test func spansMonthAndYearBoundaries() throws {
        try TestSupport.withTemporaryDirectory { root in
            let previousYear = try dayDirectory(root, "2025", "12", "31")
            let newYear = try dayDirectory(root, "2026", "01", "01")
            try TestSupport.write(
                "{}\n", to: previousYear.appendingPathComponent("rollout-2025-12-31T23-50-00-a.jsonl")
            )
            try TestSupport.write("{}\n", to: newYear.appendingPathComponent("rollout-2026-01-01T00-10-00-b.jsonl"))

            var locator = CodexSessionLocator()
            #expect(locator.candidateFiles(sessionsRoot: root).map(\.lastPathComponent)
                == ["rollout-2026-01-01T00-10-00-b.jsonl", "rollout-2025-12-31T23-50-00-a.jsonl"])
        }
    }

    @Test func limitsResultToThreeNewestFiles() throws {
        try TestSupport.withTemporaryDirectory { root in
            let day = try dayDirectory(root, "2026", "06", "30")
            for hour in ["05", "06", "07", "08"] {
                try TestSupport.write("{}\n", to: day.appendingPathComponent("rollout-2026-06-30T\(hour)-00-00.jsonl"))
            }

            var locator = CodexSessionLocator()
            #expect(locator.candidateFiles(sessionsRoot: root).map(\.lastPathComponent) == [
                "rollout-2026-06-30T08-00-00.jsonl",
                "rollout-2026-06-30T07-00-00.jsonl",
                "rollout-2026-06-30T06-00-00.jsonl"
            ])
        }
    }

    @Test func missingRootYieldsNoCandidates() throws {
        try TestSupport.withTemporaryDirectory { root in
            var locator = CodexSessionLocator()
            #expect(locator.candidateFiles(sessionsRoot: root.appendingPathComponent("absent")).isEmpty)
        }
    }

    @Test func cacheInvalidatesWhenDirectoryModificationDateChanges() throws {
        try TestSupport.withTemporaryDirectory { root in
            let day = try dayDirectory(root, "2026", "06", "30")
            try TestSupport.write("{}\n", to: day.appendingPathComponent("rollout-2026-06-30T05-00-00.jsonl"))

            var locator = CodexSessionLocator()
            #expect(locator.candidateFiles(sessionsRoot: root).count == 1)

            try TestSupport.write("{}\n", to: day.appendingPathComponent("rollout-2026-06-30T06-00-00.jsonl"))
            try TestSupport.setModificationDate(Date(timeIntervalSince1970: 1_800_000_000), of: day)

            #expect(locator.candidateFiles(sessionsRoot: root).map(\.lastPathComponent) == [
                "rollout-2026-06-30T06-00-00.jsonl",
                "rollout-2026-06-30T05-00-00.jsonl"
            ])
        }
    }

    @Test func cachedListingIsReusedWhileModificationDateIsUnchanged() throws {
        try TestSupport.withTemporaryDirectory { root in
            let day = try dayDirectory(root, "2026", "06", "30")
            try TestSupport.write("{}\n", to: day.appendingPathComponent("rollout-2026-06-30T05-00-00.jsonl"))

            // Whole seconds only: the filesystem truncates the value it stores back.
            let stamp = Date(timeIntervalSince1970: 1_800_000_000)
            try TestSupport.setModificationDate(stamp, of: day)

            var locator = CodexSessionLocator()
            #expect(locator.candidateFiles(sessionsRoot: root).count == 1)

            try TestSupport.write("{}\n", to: day.appendingPathComponent("rollout-2026-06-30T06-00-00.jsonl"))
            try TestSupport.setModificationDate(stamp, of: day)

            #expect(locator.candidateFiles(sessionsRoot: root).count == 1)
        }
    }
}
