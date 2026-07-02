import XCTest
@testable import Weird_Parts

/// Regression coverage for issue #1204: date-only ETAs were parsed as
/// midnight UTC and compared against the current instant, so a same-day
/// expected delivery flipped to "overdue" late in the local day (for
/// timezones west of UTC) and tomorrow's ETA could read as due today.
final class DeliveryTimelineBarDateTests: XCTestCase {
    private func localDateString(daysFromToday: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: daysFromToday, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func testSameDayETAIsDueTodayRegardlessOfTimeOfDay() {
        let bar = DeliveryTimelineBar(
            orderDateString: localDateString(daysFromToday: -3),
            expectedDateString: localDateString(daysFromToday: 0)
        )
        XCTAssertEqual(bar.daysRemaining, 0, "An ETA of today's local date must count as due today until local midnight.")
        XCTAssertEqual(bar.statusText, "Due today")
    }

    func testTomorrowETAIsOneDayRemaining() {
        let bar = DeliveryTimelineBar(
            orderDateString: localDateString(daysFromToday: -3),
            expectedDateString: localDateString(daysFromToday: 1)
        )
        XCTAssertEqual(bar.daysRemaining, 1, "Tomorrow's ETA must never read as due today, even late in the local day.")
        XCTAssertEqual(bar.statusText, "1d remaining")
    }

    func testYesterdayETAIsOneDayOverdue() {
        let bar = DeliveryTimelineBar(
            orderDateString: localDateString(daysFromToday: -5),
            expectedDateString: localDateString(daysFromToday: -1)
        )
        XCTAssertEqual(bar.daysRemaining, -1)
        XCTAssertEqual(bar.statusText, "1d overdue")
    }

    func testFullDatetimeStringsKeepCalendarDaySemantics() {
        // The string init only reads the first 10 characters (the date part),
        // so a trailing time component must not shift the calendar day.
        let bar = DeliveryTimelineBar(
            orderDateString: "\(localDateString(daysFromToday: -1))T23:59:59Z",
            expectedDateString: "\(localDateString(daysFromToday: 0))T00:00:00Z"
        )
        XCTAssertEqual(bar.daysRemaining, 0)
        XCTAssertEqual(bar.daysElapsed, 1)
    }

    func testMissingETAShowsNoETA() {
        let bar = DeliveryTimelineBar(orderDateString: localDateString(daysFromToday: -2), expectedDateString: nil)
        XCTAssertNil(bar.daysRemaining)
        XCTAssertEqual(bar.statusText, "No ETA")
    }
}
