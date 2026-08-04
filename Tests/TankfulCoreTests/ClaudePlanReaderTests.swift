import Foundation
import Testing
@testable import TankfulCore

@Suite struct ClaudePlanReaderTests {

    @Test func readsOrganizationTypeFromAConfigWithManyOtherKeys() throws {
        let url = try TestSupport.fixtureURL("claude-config.json")
        #expect(ClaudePlanReader.organizationType(at: url) == "claude_max")
    }

    @Test func missingFileYieldsNil() throws {
        try TestSupport.withTemporaryDirectory { directory in
            #expect(ClaudePlanReader.organizationType(at: directory.appendingPathComponent("absent.json")) == nil)
        }
    }

    @Test(arguments: ["{}", "{\"oauthAccount\":null}", "{\"oauthAccount\":{}}", "not json"])
    func unexpectedShapesYieldNil(contents: String) throws {
        try TestSupport.withTemporaryDirectory { directory in
            let url = try TestSupport.write(contents, to: directory.appendingPathComponent("config.json"))
            #expect(ClaudePlanReader.organizationType(at: url) == nil)
        }
    }
}
