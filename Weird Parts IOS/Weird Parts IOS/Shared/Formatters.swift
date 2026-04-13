import Foundation

/// Shared formatting utilities for the WiredPart iOS app.
///
/// Consolidates date, time, and currency formatting that was previously
/// duplicated across 12+ view files. Use these instead of creating local
/// `DateFormatter` or `NumberFormatter` instances per view.
enum Formatters {

    // MARK: - Cached Formatters

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    /// UTC yyyy-MM-dd — for ISO 8601 storage and DB comparisons.
    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Local-timezone yyyy-MM-dd — for "today" display labels and local date comparisons.
    static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Local-timezone yyyy-MM-dd'T'HH:mm:ss — for parsing non-ISO datetime strings (e.g. break records).
    static let localDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// ISO 8601 with fractional seconds — for parsing server timestamps (e.g. `2026-04-12T14:30:00.000Z`).
    static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// ISO 8601 without fractional seconds — for parsing basic server timestamps (e.g. `2026-04-12T14:30:00Z`).
    static let iso8601Basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    /// Full dateStyle — for dashboard greeting dates (e.g., "Sunday, April 12, 2026").
    static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    /// Medium date + short time — for session/receipt display (e.g., "Apr 12, 2026, 2:30 PM").
    static let mediumDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// HH:mm — for work-schedule time strings stored in settings (e.g., "08:00", "17:30").
    static let timeHHmmFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Day-of-week abbreviation — for chart axis labels (e.g., "Mon", "Tue").
    static let dayOfWeekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// ISO 8601 date-only (UTC) — for ETA/delivery date fields (e.g., "2026-04-12").
    static let iso8601DateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    /// Short date display — for condensed date cells (e.g., "4/12/26").
    static let shortDateDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    /// SQLite datetime — for parsing "yyyy-MM-dd HH:mm:ss" DB strings.
    /// Uses en_US_POSIX locale to ensure reliable fixed-format parsing.
    static let sqlDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Month + day — for week range start labels (e.g., "Apr 12").
    static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Month + day + year — for week range end labels (e.g., "Apr 12, 2026").
    static let monthDayYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()

    // MARK: - Formatting Functions

    /// Format a `Date` as a medium-length date string (e.g., "Mar 19, 2026").
    static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// Format a date string by truncating to "YYYY-MM-DD" (first 10 characters).
    /// Safe for ISO 8601 and SQLite datetime strings.
    static func formatDateString(_ dateStr: String) -> String {
        if dateStr.count >= 10 { return String(dateStr.prefix(10)) }
        return dateStr
    }

    /// Format a `Date` as a short time string (e.g., "2:30 PM").
    static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Format a `Double` as a currency string (e.g., "$1,234.56").
    static func formatCurrency(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    /// Safely count an optional array, returning 0 for nil.
    static func safeCount<T>(_ array: [T]?) -> Int {
        array?.count ?? 0
    }
}
