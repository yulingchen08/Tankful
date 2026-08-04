import Foundation
import Testing
@testable import TankfulCore

@Suite struct ISO8601TimestampTests {

    @Test func parsesBothSpellingsOfTheSameInstant() {
        let withFraction = ISO8601Timestamp.date(from: "2026-06-30T09:07:25.000Z")
        let withoutFraction = ISO8601Timestamp.date(from: "2026-06-30T09:07:25Z")
        #expect(withFraction == Date(timeIntervalSince1970: 1_782_810_445))
        #expect(withFraction == withoutFraction)
    }

    @Test func keepsFractionalPrecision() throws {
        let date = try #require(ISO8601Timestamp.date(from: "2026-06-30T09:07:25.718Z"))
        #expect(date.timeIntervalSince1970 == 1_782_810_445.718)
    }

    @Test func rejectsWhatIsNotATimestamp() {
        #expect(ISO8601Timestamp.date(from: "") == nil)
        #expect(ISO8601Timestamp.date(from: "1782810445") == nil)
        #expect(ISO8601Timestamp.date(from: "2026-06-30") == nil)
    }
}
