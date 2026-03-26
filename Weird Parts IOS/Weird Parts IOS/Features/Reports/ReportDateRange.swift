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

    var id: String { rawValue }

    /// Returns (startDate, endDate) for non-custom ranges.
    /// For `.custom`, returns nil — the caller supplies custom dates.
    var dateInterval: (start: Date, end: Date)? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .thisWeek:
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (start, now)
        case .lastWeek:
            let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: now)!
            let interval = cal.dateInterval(of: .weekOfYear, for: lastWeek)!
            return (interval.start, interval.end.addingTimeInterval(-1))
        case .thisPeriod:
            // Pay period = bi-weekly, anchored to Jan 1 of current year
            let yearStart = cal.date(from: cal.dateComponents([.year], from: now))!
            let days = cal.dateComponents([.day], from: yearStart, to: now).day ?? 0
            let periodIndex = days / 14
            let periodStart = cal.date(byAdding: .day, value: periodIndex * 14, to: yearStart)!
            return (periodStart, now)
        case .lastPeriod:
            let yearStart = cal.date(from: cal.dateComponents([.year], from: now))!
            let days = cal.dateComponents([.day], from: yearStart, to: now).day ?? 0
            let periodIndex = days / 14
            let periodStart = cal.date(byAdding: .day, value: (periodIndex - 1) * 14, to: yearStart)!
            let periodEnd = cal.date(byAdding: .day, value: periodIndex * 14 - 1, to: yearStart)!
            return (periodStart, periodEnd)
        case .thisMonth:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            return (start, now)
        case .lastMonth:
            let lastMonth = cal.date(byAdding: .month, value: -1, to: now)!
            let start = cal.date(from: cal.dateComponents([.year, .month], from: lastMonth))!
            let end = cal.date(byAdding: .day, value: -1,
                               to: cal.date(from: cal.dateComponents([.year, .month], from: now))!)!
            return (start, end)
        case .thisQuarter:
            let month = cal.component(.month, from: now)
            let quarterStart = ((month - 1) / 3) * 3 + 1
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: quarterStart))!
            return (start, now)
        case .thisYear:
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now)))!
            return (start, now)
        case .custom:
            return nil
        }
    }
}
