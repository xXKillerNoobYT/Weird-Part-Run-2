import Foundation

/// Shared date range options for all time-based filtering.
enum ReportDateRange: String, CaseIterable, Identifiable {
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case thisPeriod = "This Period"
    case lastPeriod = "Last Period"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisQuarter = "This Quarter"
    case thisYear = "This Year"
    case custom = "Custom"

    nonisolated var id: String { rawValue }

    /// Returns (startDate, endDate) for non-custom ranges.
    /// For `.custom`, returns nil — the caller supplies custom dates.
    nonisolated var dateInterval: (start: Date, end: Date)? {
        dateInterval(containing: Date())
    }

    /// Deterministic variant used by shared UI and tests.
    ///
    /// The default pay-period anchor preserves the existing Jan 1 biweekly
    /// behavior while making the assumption explicit for future payroll wiring.
    nonisolated func dateInterval(
        containing now: Date,
        calendar: Calendar = .current,
        payPeriodAnchor: Date? = nil,
        payPeriodLengthDays: Int = 14
    ) -> (start: Date, end: Date)? {
        let cal = calendar
        switch self {
        case .thisWeek:
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (start, now)
        case .lastWeek:
            guard let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: now),
                  let interval = cal.dateInterval(of: .weekOfYear, for: lastWeek) else {
                return (now.addingTimeInterval(-14 * 86400), now.addingTimeInterval(-7 * 86400))
            }
            return (interval.start, interval.end.addingTimeInterval(-1))
        case .thisPeriod:
            guard payPeriodLengthDays > 0,
                  let anchor = payPeriodAnchor ?? cal.date(from: cal.dateComponents([.year], from: now)) else {
                return (now.addingTimeInterval(-14 * 86400), now)
            }
            let days = cal.dateComponents([.day], from: anchor, to: now).day ?? 0
            let periodIndex = floorDiv(days, payPeriodLengthDays)
            let periodStart = cal.date(byAdding: .day, value: periodIndex * payPeriodLengthDays, to: anchor)
                ?? now.addingTimeInterval(-14 * 86400)
            return (periodStart, now)
        case .lastPeriod:
            guard payPeriodLengthDays > 0,
                  let anchor = payPeriodAnchor ?? cal.date(from: cal.dateComponents([.year], from: now)) else {
                return (now.addingTimeInterval(-28 * 86400), now.addingTimeInterval(-14 * 86400))
            }
            let days = cal.dateComponents([.day], from: anchor, to: now).day ?? 0
            let periodIndex = floorDiv(days, payPeriodLengthDays)
            let periodStart = cal.date(byAdding: .day, value: (periodIndex - 1) * payPeriodLengthDays, to: anchor)
                ?? now.addingTimeInterval(-28 * 86400)
            let periodEnd = cal.date(byAdding: .day, value: periodIndex * payPeriodLengthDays - 1, to: anchor)
                ?? now.addingTimeInterval(-14 * 86400)
            return (periodStart, periodEnd)
        case .thisMonth:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now))
                ?? now.addingTimeInterval(-30 * 86400)
            return (start, now)
        case .lastMonth:
            guard let lastMonth = cal.date(byAdding: .month, value: -1, to: now),
                  let start = cal.date(from: cal.dateComponents([.year, .month], from: lastMonth)),
                  let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
                  let end = cal.date(byAdding: .day, value: -1, to: thisMonthStart) else {
                return (now.addingTimeInterval(-60 * 86400), now.addingTimeInterval(-30 * 86400))
            }
            return (start, end)
        case .thisQuarter:
            let month = cal.component(.month, from: now)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: quarterStartMonth))
                ?? now.addingTimeInterval(-90 * 86400)
            return (start, now)
        case .thisYear:
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now)))
                ?? now.addingTimeInterval(-365 * 86400)
            return (start, now)
        case .custom:
            return nil
        }
    }
}

nonisolated private func floorDiv(_ lhs: Int, _ rhs: Int) -> Int {
    precondition(rhs > 0)
    return lhs >= 0 ? lhs / rhs : -((-lhs + rhs - 1) / rhs)
}
