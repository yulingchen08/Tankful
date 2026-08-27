import Foundation
import Testing
@testable import TankfulCore

struct UpdateCheckTests {
    @Test func decodesTagFromReleaseJSON() {
        let json = Data(#"{"tag_name":"v0.3.3","name":"Tankful v0.3.3","assets":[]}"#.utf8)
        #expect(UpdateCheck.latestTag(fromReleaseJSON: json) == "v0.3.3")
    }

    @Test func missingTagOrGarbageDecodesToNil() {
        #expect(UpdateCheck.latestTag(fromReleaseJSON: Data(#"{"name":"x"}"#.utf8)) == nil)
        #expect(UpdateCheck.latestTag(fromReleaseJSON: Data("not json".utf8)) == nil)
        #expect(UpdateCheck.latestTag(fromReleaseJSON: Data()) == nil)
    }

    @Test func newerVersionsWin() {
        #expect(UpdateCheck.isNewer("v0.3.3", than: "0.3.2"))
        #expect(UpdateCheck.isNewer("1.0", than: "0.9.9"))
        #expect(UpdateCheck.isNewer("0.3.2.1", than: "0.3.2"))
        // Numeric, not lexicographic.
        #expect(UpdateCheck.isNewer("0.10.0", than: "0.9.0"))
    }

    @Test func equalOrOlderVersionsDoNot() {
        #expect(!UpdateCheck.isNewer("0.3.2", than: "0.3.2"))
        #expect(!UpdateCheck.isNewer("v0.3.2", than: "0.3.2"))
        #expect(!UpdateCheck.isNewer("0.3.1", than: "0.3.2"))
        #expect(!UpdateCheck.isNewer("0.3", than: "0.3.0"))
    }

    @Test func malformedVersionsNeverNag() {
        #expect(!UpdateCheck.isNewer("abc", than: "0.3.2"))
        #expect(!UpdateCheck.isNewer("v0.3.3", than: "unknown"))
        #expect(!UpdateCheck.isNewer("", than: "0.3.2"))
        #expect(!UpdateCheck.isNewer("0.3-beta", than: "0.3.2"))
    }
}
