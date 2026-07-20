import Foundation
import Testing
@testable import WiredPartCore

@Suite("OperationalDay")
struct OperationalDayTests {
    @Test("User calendar preference cannot change Gregorian persistence boundaries")
    func nonGregorianCalendarUsesGregorianDateBoundaries() throws {
        var buddhistCalendar = Calendar(identifier: .buddhist)
        buddhistCalendar.timeZone = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        let date = try Date("2026-07-20T10:30:00Z", strategy: .iso8601)

        let interval = OperationalDay(calendar: buddhistCalendar).interval(containing: date)

        #expect(interval.localStartDate == "2026-07-20")
        #expect(interval.localEndDate == "2026-07-20")
        #expect(interval.utcStart == "2026-07-20 10:00:00")
        #expect(interval.utcEnd == "2026-07-21 10:00:00")
    }
}