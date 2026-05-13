import Foundation
import Testing
@testable import Weird_Parts

@Suite("StandardFilterBar hardening")
@MainActor
struct StandardFilterBarTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    @Test func quickChipsUseMinimumTouchTarget() {
        #expect(StandardFilterBarLayout.minimumTapTarget >= 44)
    }

    @Test func customRangePolicyClampsEndToStartWhenDatesAreReversed() {
        let start = date(2026, 5, 13)
        let end = date(2026, 5, 8)

        let normalized = StandardFilterBarCustomRange.normalized(start: start, end: end)

        #expect(normalized.start == start)
        #expect(normalized.end == start)
    }

    @Test func thisPeriodUsesExplicitAnchorAndLength() {
        let anchor = date(2026, 1, 7)
        let now = date(2026, 2, 5, hour: 15)

        let interval = ReportDateRange.thisPeriod.dateInterval(
            containing: now,
            calendar: calendar,
            payPeriodAnchor: anchor,
            payPeriodLengthDays: 14
        )

        #expect(interval?.start == date(2026, 2, 4))
        #expect(interval?.end == now)
    }

    @Test func lastPeriodUsesExplicitAnchorAndLength() {
        let anchor = date(2026, 1, 7)
        let now = date(2026, 2, 5, hour: 15)

        let interval = ReportDateRange.lastPeriod.dateInterval(
            containing: now,
            calendar: calendar,
            payPeriodAnchor: anchor,
            payPeriodLengthDays: 14
        )

        #expect(interval?.start == date(2026, 1, 21))
        #expect(interval?.end == date(2026, 2, 3))
    }

    @Test func customRangeStillHasNoCalculatedInterval() {
        #expect(ReportDateRange.custom.dateInterval(containing: date(2026, 5, 13), calendar: calendar) == nil)
    }

    @Test func dateFilterMatchesInclusiveCustomDates() {
        let start = date(2026, 5, 10)
        let end = date(2026, 5, 13)

        #expect(StandardFilterBarDateFilter.contains("2026-05-10", selectedRange: .custom, customStart: start, customEnd: end, calendar: calendar))
        #expect(StandardFilterBarDateFilter.contains("2026-05-13T18:55:40Z", selectedRange: .custom, customStart: start, customEnd: end, calendar: calendar))
        #expect(!StandardFilterBarDateFilter.contains("2026-05-14", selectedRange: .custom, customStart: start, customEnd: end, calendar: calendar))
    }

    @Test func reportBuilderKeepsOriginalQuickRangeChoices() {
        #expect(ReportBuilderFilterConfiguration.quickDateRanges == [.thisWeek, .thisMonth, .thisQuarter, .custom])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour))!
    }
}
