import XCTest
@testable import Weird_Parts

/// Regression coverage for issue #1204: date-only ETAs were parsed as
/// midnight UTC and compared against the current instant, so a same-day
/// expected delivery flipped to "overdue" late in the local day (for
/// timezones west of UTC) and tomorrow's ETA could read as due today.
///
/// All tests inject a fixed clock through `DeliveryTimelineBar.now`, so
/// they are deterministic and genuinely exercise multiple times of day —
/// including instants just before local midnight.
@MainActor
final class DeliveryTimelineBarDateTests: XCTestCase {
    /// Single reference instant captured once per test case so a midnight
    /// rollover mid-test cannot skew date strings against assertions.
    private let reference = Date()
    private let calendar = Calendar.current

    private func dateString(daysFromReference: Int) -> String {
        let date = calendar.date(byAdding: .day, value: daysFromReference, to: reference) ?? reference
        return Formatters.localDateFormatter.string(from: date)
    }

    /// A fixed instant at the given hour of the reference day.
    private func instant(hour: Int, daysFromReference: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: daysFromReference, to: reference) ?? reference
        return calendar.date(bySettingHour: hour, minute: 30, second: 0, of: day) ?? day
    }

    private func makeBar(
        order: String?, expected: String?, at now: Date
    ) -> DeliveryTimelineBar {
        var bar = DeliveryTimelineBar(orderDateString: order, expectedDateString: expected)
        bar.now = { now }
        return bar
    }

    func testSameDayETAIsDueTodayAtEveryHourOfTheDay() {
        for hour in [0, 9, 18, 23] {
            let bar = makeBar(
                order: dateString(daysFromReference: -3),
                expected: dateString(daysFromReference: 0),
                at: instant(hour: hour)
            )
            XCTAssertEqual(bar.daysRemaining, 0, "ETA of today must be due today at \(hour):30, not overdue.")
            XCTAssertEqual(bar.statusText, "Due today")
        }
    }

    func testTomorrowETAIsOneDayRemainingEvenLateEvening() {
        let bar = makeBar(
            order: dateString(daysFromReference: -3),
            expected: dateString(daysFromReference: 1),
            at: instant(hour: 23)
        )
        XCTAssertEqual(bar.daysRemaining, 1, "Tomorrow's ETA must never read as due today, even at 23:30.")
        XCTAssertEqual(bar.statusText, "1d remaining")
    }

    func testYesterdayETAIsOneDayOverdue() {
        let bar = makeBar(
            order: dateString(daysFromReference: -5),
            expected: dateString(daysFromReference: -1),
            at: instant(hour: 9)
        )
        XCTAssertEqual(bar.daysRemaining, -1)
        XCTAssertEqual(bar.statusText, "1d overdue")
    }

    func testFullDatetimeStringsKeepCalendarDaySemantics() {
        // The string init only reads the first 10 characters (the date part),
        // so a trailing time component must not shift the calendar day.
        let bar = makeBar(
            order: "\(dateString(daysFromReference: -1))T23:59:59Z",
            expected: "\(dateString(daysFromReference: 0))T00:00:00Z",
            at: instant(hour: 18)
        )
        XCTAssertEqual(bar.daysRemaining, 0)
        XCTAssertEqual(bar.daysElapsed, 1)
    }

    func testMissingETAShowsNoETA() {
        let bar = makeBar(order: dateString(daysFromReference: -2), expected: nil, at: instant(hour: 12))
        XCTAssertNil(bar.daysRemaining)
        XCTAssertEqual(bar.statusText, "No ETA")
    }
}
