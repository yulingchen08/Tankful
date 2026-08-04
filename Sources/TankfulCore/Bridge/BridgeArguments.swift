import Foundation

/// Command line of the bridge executable.
///
/// The bridge stands in front of whatever status line the user already had, so everything
/// after `--` is the command to run afterwards and must survive unparsed.
public struct BridgeArguments: Sendable, Equatable {
    /// How the chained status line has to be started.
    public enum ChainCommand: Sendable, Equatable {
        /// Nothing followed the one word, so it is a whole command line — the shape the
        /// installer writes, which still needs a shell for `~`, pipes and quoting.
        case shell(String)
        /// Several words, which were quoted by whoever wrote them. Re-joining and re-parsing
        /// them through a shell would strip that quoting and evaluate `$(…)` in their argument.
        case program(path: String, arguments: [String])
    }

    public var snapshotPath: String?
    public var chainCommand: ChainCommand?

    public init(snapshotPath: String? = nil, chainCommand: ChainCommand? = nil) {
        self.snapshotPath = snapshotPath
        self.chainCommand = chainCommand
    }

    /// `argv` includes argv[0]. Unknown flags are ignored so a future flag cannot break an
    /// installed status line.
    public static func parse(_ argv: [String]) -> BridgeArguments {
        var arguments = BridgeArguments()
        var index = 1
        while index < argv.count {
            let argument = argv[index]
            if argument == "--" {
                arguments.chainCommand = chainCommand(from: Array(argv[(index + 1)...]))
                break
            }
            if argument == "--snapshot-path", index + 1 < argv.count {
                arguments.snapshotPath = argv[index + 1]
                index += 2
                continue
            }
            index += 1
        }
        return arguments
    }

    private static func chainCommand(from rest: [String]) -> ChainCommand? {
        guard let first = rest.first, !first.isEmpty else { return nil }
        guard rest.count > 1 else { return .shell(first) }
        return .program(path: first, arguments: Array(rest.dropFirst()))
    }
}
