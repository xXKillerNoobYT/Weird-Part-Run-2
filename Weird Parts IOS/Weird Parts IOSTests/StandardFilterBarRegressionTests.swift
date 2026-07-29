import XCTest
@testable import Weird_Parts

final class StandardFilterBarRegressionTests: XCTestCase {
    // Product-behavior assertions remain executable; checkout source contracts live in the CI manifest.
    @MainActor
    func testPayPeriodRangesUseInjectedAnchorAndLength() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 4)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 12)))
        let config = ReportDateRange.PayPeriodConfiguration(anchorDate: anchor, lengthInDays: 7)

        let thisPeriod = try XCTUnwrap(ReportDateRange.thisPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(thisPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 18))))
        XCTAssertEqual(thisPeriod.end, now)

        let lastPeriod = try XCTUnwrap(ReportDateRange.lastPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(lastPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))))
        XCTAssertEqual(lastPeriod.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 17, hour: 23, minute: 59, second: 59))))
    }

    @MainActor
    func testPayPeriodRangesFloorDivideWhenAnchorIsAfterNow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 18)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 15, hour: 12)))
        let config = ReportDateRange.PayPeriodConfiguration(anchorDate: anchor, lengthInDays: 7)

        let thisPeriod = try XCTUnwrap(ReportDateRange.thisPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(thisPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))))
        XCTAssertEqual(thisPeriod.end, now)

        let lastPeriod = try XCTUnwrap(ReportDateRange.lastPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(lastPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 4))))
        XCTAssertEqual(lastPeriod.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 23, minute: 59, second: 59))))
    }

    @MainActor
    func testPayPeriodRangesNormalizeAnchorTimeToDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 4, hour: 15, minute: 30)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 6)))
        let config = ReportDateRange.PayPeriodConfiguration(anchorDate: anchor, lengthInDays: 7)

        let thisPeriod = try XCTUnwrap(ReportDateRange.thisPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(thisPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 18))))
        XCTAssertEqual(thisPeriod.end, now)

        let lastPeriod = try XCTUnwrap(ReportDateRange.lastPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(lastPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))))
        XCTAssertEqual(lastPeriod.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 17, hour: 23, minute: 59, second: 59))))
    }

    @MainActor
    func testLastMonthReturnsInclusiveEndOfFinalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)))

        let lastMonth = try XCTUnwrap(ReportDateRange.lastMonth.dateInterval(now: now, calendar: calendar))
        XCTAssertEqual(lastMonth.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))))
        XCTAssertEqual(lastMonth.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 23, minute: 59, second: 59))))
    }

}
