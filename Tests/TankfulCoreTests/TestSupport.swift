import Foundation
import Testing
@testable import TankfulCore

/// Convenience the app itself has no use for, so it lives here rather than on the shipped type.
extension CodexSnapshot {
    var weekly: RateWindow? { windows.first { $0.kind == .weekly } }
}

extension ClaudeSnapshot {
    var weekly: RateWindow? { windows.first { $0.kind == .weekly } }
}

enum TestSupport {
    static func fixtureURL(_ name: String) throws -> URL {
        let root = try #require(Bundle.module.resourceURL).appendingPathComponent("Fixtures", isDirectory: true)
        let url = root.appendingPathComponent(name)
        try #require(FileManager.default.fileExists(atPath: url.path), "missing fixture \(name)")
        return url
    }

    static func fixtureText(_ name: String) throws -> String {
        try String(contentsOf: fixtureURL(name), encoding: .utf8)
    }

    /// First line of a fixture carrying rate-limit data.
    static func rateLimitLine(in text: String) throws -> Substring {
        let line = text.split(separator: "\n").first { $0.contains("\"rate_limits\"") }
        return try #require(line)
    }

    /// Non-throwing so it can initialise stored properties; a literal that does not parse is a
    /// typo in the test itself, which should stop the run rather than compare against a
    /// plausible-looking wrong date.
    static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else { preconditionFailure("unparseable date \(iso)") }
        return date
    }

    static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let url = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }

    static func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let url = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        return try await body(url)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tankful-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func makeDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func write(_ contents: String, to url: URL) throws -> URL {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func setModificationDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
