import Foundation

/// Shared date range options for all time-based filtering.
///
/// This type intentionally lives with the shared UI primitives instead of the
/// Reports feature so jobs, warehouse, orders, fleet, scheduling, and reports
/// screens all depend on one program-wide filter contract.
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

    var id: Self { self }

    struct PayPeriodConfiguration: Equatable, Sendable {
        let anchorDate: Date
        let lengthInDays: Int

        init(anchorDate: Date, lengthInDays: Int = 14) {
            self.anchorDate = anchorDate
            self.lengthInDays = max(1, lengthInDays)
        }

        static func defaultForYear(containing date: Date = Date(), calendar: Calendar = .current) -> PayPeriodConfiguration {
            let anchor = calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
            return PayPeriodConfiguration(anchorDate: anchor, lengthInDays: 14)
        }
    }

    /// Returns (startDate, endDate) for non-custom ranges using current clock/settings defaults.
    /// For `.custom`, returns nil — the caller supplies custom dates.
    var dateInterval: (start: Date, end: Date)? {
        dateInterval(now: Date(), calendar: .current)
    }

    /// Deterministic range resolver for tests and shared callers that know the
    /// shop's configured pay-period anchor/length.
    func dateInterval(
        now: Date,
        calendar: Calendar = .current,
        payPeriod: PayPeriodConfiguration? = nil
    ) -> (start: Date, end: Date)? {
        let cal = calendar
        let payPeriod = payPeriod ?? .defaultForYear(containing: now, calendar: cal)
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
            let anchorStart = cal.startOfDay(for: payPeriod.anchorDate)
            let nowStart = cal.startOfDay(for: now)
            let days = cal.dateComponents([.day], from: anchorStart, to: nowStart).day ?? 0
            let periodIndex = Self.floorDivide(days, by: payPeriod.lengthInDays)
            let periodStart = cal.date(byAdding: .day, value: periodIndex * payPeriod.lengthInDays, to: anchorStart)
                ?? now.addingTimeInterval(TimeInterval(-payPeriod.lengthInDays * 86400))
            return (periodStart, now)
        case .lastPeriod:
            let anchorStart = cal.startOfDay(for: payPeriod.anchorDate)
            let nowStart = cal.startOfDay(for: now)
            let days = cal.dateComponents([.day], from: anchorStart, to: nowStart).day ?? 0
            let currentPeriodIndex = Self.floorDivide(days, by: payPeriod.lengthInDays)
            let previousPeriodIndex = currentPeriodIndex - 1
            let previousPeriodStart = cal.date(byAdding: .day, value: previousPeriodIndex * payPeriod.lengthInDays, to: anchorStart)
                ?? now.addingTimeInterval(TimeInterval(-2 * payPeriod.lengthInDays * 86400))
            let currentPeriodStart = cal.date(byAdding: .day, value: currentPeriodIndex * payPeriod.lengthInDays, to: anchorStart)
                ?? now.addingTimeInterval(TimeInterval(-payPeriod.lengthInDays * 86400))
            let periodEnd = currentPeriodStart.addingTimeInterval(-1)
            return (previousPeriodStart, periodEnd)
        case .thisMonth:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now))
                ?? now.addingTimeInterval(-30 * 86400)
            return (start, now)
        case .lastMonth:
            guard let lastMonth = cal.date(byAdding: .month, value: -1, to: now),
                  let start = cal.date(from: cal.dateComponents([.year, .month], from: lastMonth)),
                  let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
                return (now.addingTimeInterval(-60 * 86400), now.addingTimeInterval(-30 * 86400))
            }
            return (start, thisMonthStart.addingTimeInterval(-1))
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

    private static func floorDivide(_ dividend: Int, by divisor: Int) -> Int {
        let quotient = dividend / divisor
        let remainder = dividend % divisor
        return remainder < 0 ? quotient - 1 : quotient
    }
}

/// Shared evaluator for StandardFilterBar-backed date filtering.
///
/// Rows without a parseable date stay visible: the date bar should narrow rows
/// with known dates, not make undated legacy rows disappear by default.
enum StandardDateRangeFilter {
    static func contains(
        _ rawDate: String?,
        selectedRange: ReportDateRange,
        customStart: Date,
        customEnd: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let date = parse(rawDate) else { return true }
        let interval = selectedRange.dateInterval ?? (start: customStart, end: customEnd)
        return date >= calendar.startOfDay(for: interval.start)
            && date < exclusiveEndOfDay(for: interval.end, calendar: calendar)
    }

    private static func exclusiveEndOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .day, for: date)?.end ?? date
    }

    private static func parse(_ rawDate: String?) -> Date? {
        guard let trimmed = rawDate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return Formatters.sqlDateTimeFormatter.date(from: trimmed)
            ?? Formatters.iso8601Fractional.date(from: trimmed)
            ?? Formatters.iso8601Basic.date(from: trimmed)
            ?? Formatters.localDateFormatter.date(from: String(trimmed.prefix(10)))
    }
}
