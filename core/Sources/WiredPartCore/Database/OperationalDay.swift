import Foundation

/// Explicit local-day boundaries for services that persist timestamps in UTC.
///
/// SQLite's `localtime` modifier reads process-global timezone state. Computing
/// UTC boundaries with an injected calendar keeps concurrent tests isolated and
/// preserves device-local bucketing in production through the `.current` default.
struct OperationalDay: Sendable {
    let calendar: Calendar
    let now: @Sendable () -> Date

    init(
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        // Persisted date-only values and SQLite timestamps use the proleptic
        // Gregorian calendar. Preserve the injected/device time zone while
        // avoiding user calendar preferences changing SQL boundary values.
        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = calendar.timeZone
        self.calendar = gregorianCalendar
        self.now = now
    }

    func interval(containing date: Date) -> OperationalDayInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let localDate = dateString(from: start)
        return OperationalDayInterval(
            localStartDate: localDate,
            localEndDate: localDate,
            utcStart: utcTimestamp(start),
            utcEnd: utcTimestamp(end)
        )
    }

    func interval(startDate: String, endDate: String) -> OperationalDayInterval? {
        guard let start = date(from: startDate), let endDay = date(from: endDate),
              let end = calendar.date(byAdding: .day, value: 1, to: endDay),
              start <= endDay else {
            return nil
        }
        return OperationalDayInterval(
            localStartDate: startDate,
            localEndDate: endDate,
            utcStart: utcTimestamp(start),
            utcEnd: utcTimestamp(end)
        )
    }

    func dateString(from date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    func dateString(fromPersistedTimestamp timestamp: String) -> String? {
        if timestamp.count <= 10 {
            return String(timestamp.prefix(10))
        }
        guard let date = CoreFormatters.parseDateTimeUTC(timestamp) else { return nil }
        return dateString(from: date)
    }

    func utcTimestamp(_ date: Date) -> String {
        CoreFormatters.dateTimeSpaceUTC.string(from: date)
    }

    private func date(from value: String) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

}

struct OperationalDayInterval: Sendable {
    let localStartDate: String
    let localEndDate: String
    let utcStart: String
    let utcEnd: String

    func exactDayPredicate(_ expression: String) -> String {
        """
        ((length(\(expression)) <= 10 AND date(\(expression)) = date(?))
          OR (length(\(expression)) > 10
              AND julianday(\(expression)) >= julianday(?)
              AND julianday(\(expression)) < julianday(?)))
        """
    }

    func rangePredicate(_ expression: String) -> String {
        """
        ((length(\(expression)) <= 10
          AND date(\(expression)) >= date(?)
          AND date(\(expression)) <= date(?))
         OR (length(\(expression)) > 10
             AND julianday(\(expression)) >= julianday(?)
             AND julianday(\(expression)) < julianday(?)))
        """
    }

    func startsAtOrAfterPredicate(_ expression: String) -> String {
        """
        ((length(\(expression)) <= 10 AND date(\(expression)) >= date(?))
         OR (length(\(expression)) > 10
             AND julianday(\(expression)) >= julianday(?)))
        """
    }

    var exactArguments: [String] { [localStartDate, utcStart, utcEnd] }
    var rangeArguments: [String] { [localStartDate, localEndDate, utcStart, utcEnd] }
    var startArguments: [String] { [localStartDate, utcStart] }
}
