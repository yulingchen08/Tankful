import Foundation
import Testing
@testable import TankfulCore

@Suite struct BridgeArgumentsTests {

    @Test func bareInvocationHasNothingSet() {
        #expect(BridgeArguments.parse(["/usr/local/bin/tankful-bridge"]) == BridgeArguments())
        #expect(BridgeArguments.parse([]) == BridgeArguments())
    }

    @Test func readsTheSnapshotPath() {
        let arguments = BridgeArguments.parse(["bridge", "--snapshot-path", "/tmp/snap.json"])
        #expect(arguments.snapshotPath == "/tmp/snap.json")
        #expect(arguments.chainCommand == nil)
    }

    @Test func aLoneSeparatorLeavesNoChainCommand() {
        #expect(BridgeArguments.parse(["bridge", "--"]).chainCommand == nil)
    }

    /// What the installer writes: one quoted word that still needs a shell to expand and split.
    @Test func aSingleWordAfterTheSeparatorIsAShellCommandLine() {
        let arguments = BridgeArguments.parse(["bridge", "--", "~/bin/ccstatusline --flag value"])
        #expect(arguments.chainCommand == .shell("~/bin/ccstatusline --flag value"))
    }

    /// The finding: re-joining these with spaces and handing them to `sh -c` dropped the
    /// caller's own quoting, so `$(…)` inside an argument was evaluated.
    @Test func severalWordsAfterTheSeparatorAreAProgramAndItsArguments() {
        let arguments = BridgeArguments.parse(["bridge", "--", "/bin/echo", "hello $(touch /tmp/x)world"])
        #expect(arguments.chainCommand == .program(path: "/bin/echo", arguments: ["hello $(touch /tmp/x)world"]))
    }

    @Test func aChainPathContainingSpacesIsNotSplit() {
        let arguments = BridgeArguments.parse(["bridge", "--", "/opt/my tools/status line", "--flag"])
        #expect(arguments.chainCommand == .program(path: "/opt/my tools/status line", arguments: ["--flag"]))
    }

    @Test func snapshotPathAndChainCommandCombine() {
        let arguments = BridgeArguments.parse([
            "bridge", "--snapshot-path", "/tmp/snap.json", "--unknown", "--", "npx", "ccstatusline@latest"
        ])
        #expect(arguments.snapshotPath == "/tmp/snap.json")
        #expect(arguments.chainCommand == .program(path: "npx", arguments: ["ccstatusline@latest"]))
    }

    @Test func flagsAfterTheSeparatorAreNotParsedAsBridgeFlags() {
        let arguments = BridgeArguments.parse(["bridge", "--", "other", "--snapshot-path", "/elsewhere"])
        #expect(arguments.snapshotPath == nil)
        #expect(arguments.chainCommand == .program(path: "other", arguments: ["--snapshot-path", "/elsewhere"]))
    }

    @Test func anEmptyFirstWordLeavesNoChainCommand() {
        #expect(BridgeArguments.parse(["bridge", "--", ""]).chainCommand == nil)
    }
}
