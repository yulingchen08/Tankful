import Foundation
import TankfulCore

// Status-line shim for Claude Code: capture the rate limits Claude Code pipes in, then run
// whatever status line the user already had.
//
// Claude Code re-runs this several times a second and prints its stdout verbatim, so stdout
// belongs to the chained command alone, diagnostics go to stderr, and no failure in the
// capture step may stop the chain from running.

/// Status-line payloads are a few KB. All of stdin is buffered so the chained command always
/// receives the exact bytes Claude Code sent; only the parse step is capped, since scanning a
/// runaway payload would cost more than the rate limits hiding in it are worth.
private let parseByteLimit = 4 * 1024 * 1024
private let readChunkSize = 64 * 1024
/// `capturedAt` doubles as the app's liveness signal, so an unchanged snapshot is still
/// rewritten once a minute.
private let rewriteInterval: TimeInterval = 60

private func warn(_ message: String) {
    try? FileHandle.standardError.write(contentsOf: Data("TankfulBridge: \(message)\n".utf8))
}

private func readStandardInput() -> Data {
    var data = Data()
    while true {
        do {
            // A read error is not end of input; treating it as one would hand the chain a
            // truncated payload with nothing said about it.
            guard let chunk = try FileHandle.standardInput.read(upToCount: readChunkSize),
                  !chunk.isEmpty else { break }
            data.append(chunk)
        } catch {
            warn("could not read all of stdin (\(error)); relaying the \(data.count) bytes read so far")
            break
        }
    }
    return data
}

// MARK: - Capture

private func captureSnapshot(stdin: Data, arguments: BridgeArguments) {
    guard stdin.count <= parseByteLimit else {
        warn("stdin is \(stdin.count) bytes, over the \(parseByteLimit)-byte parse cap; rate limits not captured")
        return
    }
    // Most refreshes carry no rate limits at all; a byte scan is far cheaper than parsing.
    guard stdin.range(of: Data(StatusLineRateLimitParser.byteMarker.utf8)) != nil else { return }
    // No readable limits means Claude Code told us nothing, not that the limits are gone,
    // so the existing snapshot stays as it is.
    guard let parsed = StatusLineRateLimitParser.parse(stdin: stdin) else { return }

    let url = arguments.snapshotPath.map { URL(fileURLWithPath: $0) } ?? Env.live.claudeSnapshotURL
    let now = Date()
    guard !isCurrent(snapshotAt: url, hash: parsed.canonicalHash, now: now) else { return }
    do {
        try AtomicFileWriter.write(ClaudeSnapshotFile.encode(parsed, capturedAt: now), to: url)
    } catch {
        warn("could not write \(url.path): \(error)")
    }
}

private func isCurrent(snapshotAt url: URL, hash: String, now: Date) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let modified = attributes[.modificationDate] as? Date else { return false }
    // A negative age means the file is stamped in the future; rewrite rather than trust it.
    let age = now.timeIntervalSince(modified)
    guard age >= 0, age < rewriteInterval else { return false }
    guard let data = try? Data(contentsOf: url),
          let decoded = try? ClaudeSnapshotFile.decode(data) else { return false }
    return decoded.sourceHash == hash
}

// MARK: - Chain

/// Runs the wrapped status line, relaying its bytes unchanged. Nil means it never started.
private func runChain(command: BridgeArguments.ChainCommand, stdin: Data) -> (status: Int32, producedOutput: Bool)? {
    let process = Process()
    switch command {
    case .shell(let line):
        // `sh -c`, not a login shell: profile loading would show up as lag at this cadence.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", line]
    case .program(let path, let arguments):
        // `env` finds the program on PATH the way the shell used to, without evaluating
        // anything in the arguments. It does not expand `~`, so the path is expanded here.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [(path as NSString).expandingTildeInPath] + arguments
    }
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.standardError

    do {
        try process.run()
    } catch {
        warn("could not run chained command: \(error)")
        return nil
    }

    // Feeding stdin from another thread while this one drains stdout; either pipe filling up
    // would otherwise deadlock the pair. A chain that ignores stdin closes the read end
    // early, and SIGPIPE is ignored below so that write fails instead of killing the bridge.
    DispatchQueue.global(qos: .userInitiated).async {
        try? input.fileHandleForWriting.write(contentsOf: stdin)
        try? input.fileHandleForWriting.close()
    }
    let produced = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if !produced.isEmpty {
        try? FileHandle.standardOutput.write(contentsOf: produced)
    }
    return (process.terminationStatus, !produced.isEmpty)
}

/// Last resort when there is nothing to chain to: a status line that at least names the model.
private func printFallbackStatusLine(stdin: Data) {
    let root = (try? JSONSerialization.jsonObject(with: stdin)) as? [String: Any]
    let model = root?["model"] as? [String: Any]
    print(model?["display_name"] as? String ?? "")
}

// MARK: - Entry point

signal(SIGPIPE, SIG_IGN)

let arguments = BridgeArguments.parse(CommandLine.arguments)
let stdinData = readStandardInput()

captureSnapshot(stdin: stdinData, arguments: arguments)

if let command = arguments.chainCommand, let outcome = runChain(command: command, stdin: stdinData) {
    // A chain that both failed and printed nothing would leave the status line blank, which
    // is the one outcome worth overriding.
    if outcome.producedOutput || outcome.status == 0 {
        exit(outcome.status)
    }
    warn("chained command exited \(outcome.status) with no output; falling back")
}
printFallbackStatusLine(stdin: stdinData)
exit(0)
