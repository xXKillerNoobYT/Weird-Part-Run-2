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
