import SwiftUI

/// Time-based priority coloring utility.
///
/// Replaces label-based priority colors (urgent=red, high=orange, etc.) with
/// colors that reflect the actual TIME REMAINING until a due date. This gives
/// users a real-time sense of urgency that updates automatically as deadlines
/// approach, rather than relying on a static label that may not match reality.
///
/// Color mapping:
/// - **Red**: Overdue (past due date)
/// - **Orange**: Due within 24 hours
/// - **Yellow**: Due within 96 hours (4 days)
/// - **Green**: More than 96 hours remaining
/// - **Gray**: Completed items
/// - **Secondary**: No due date available
struct TimelinePriorityColor {

    // MARK: - Primary API (Date-Based)

    /// Returns a color based on how much time remains until `dueDate`.
    ///
    /// - Parameters:
    ///   - dueDate: The deadline as a `Date`. If `nil`, returns `.secondary`.
    ///   - now: The comparison time. Defaults to the current date in app code.
    ///   - isCompleted: Whether the item is already completed (returns `.gray`).
    /// - Returns: A `Color` reflecting the urgency of the deadline.
    static func color(for dueDate: Date?, now: Date = Date(), isCompleted: Bool = false) -> Color {
        if isCompleted { return .gray }
        guard let dueDate = dueDate else { return .secondary }

        let hoursRemaining = dueDate.timeIntervalSince(now) / 3600

        if hoursRemaining < 0 { return DS.SemanticColor.error }
        else if hoursRemaining < 24 { return DS.SemanticColor.warning }
        else if hoursRemaining < 96 { return DS.SemanticColor.caution }
        else { return DS.SemanticColor.success }
    }

    /// Convenience overload: accepts a priority label AND a due date.
    /// The priority label is intentionally ignored — color comes from time.
    ///
    /// This signature exists so call sites that previously passed a priority string
    /// can migrate without changing their argument structure.
    static func color(priority: String?, dueDate: Date?, now: Date = Date(), isCompleted: Bool = false) -> Color {
        return color(for: dueDate, now: now, isCompleted: isCompleted)
    }

    // MARK: - String Date Parsing

    /// Convenience overload that parses a date string (ISO 8601 or SQLite datetime)
    /// into a `Date` before computing the color.
    ///
    /// - Parameters:
    ///   - dateString: An ISO 8601 or "yyyy-MM-dd HH:mm:ss" formatted date string.
    ///   - isCompleted: Whether the item is already completed.
    /// - Returns: A `Color` reflecting the urgency of the deadline.
    static func color(for dateString: String?, now: Date = Date(), isCompleted: Bool = false) -> Color {
        return color(for: parseDate(dateString), now: now, isCompleted: isCompleted)
    }

    /// Convenience overload: accepts a priority label AND a date string.
    /// The priority label is intentionally ignored — color comes from time.
    static func color(priority: String?, dueDateString: String?, now: Date = Date(), isCompleted: Bool = false) -> Color {
        return color(for: parseDate(dueDateString), now: now, isCompleted: isCompleted)
    }

    // MARK: - Urgency Label

    /// Returns a human-readable urgency label based on time remaining.
    ///
    /// Examples: "Overdue", "Due today", "Due in 3d", "No deadline", "Completed".
    static func urgencyLabel(for dueDate: Date?, now: Date = Date(), isCompleted: Bool = false) -> String {
        if isCompleted { return "Completed" }
        guard let dueDate = dueDate else { return "No deadline" }

        let hoursRemaining = dueDate.timeIntervalSince(now) / 3600

        if hoursRemaining < 0 { return "Overdue" }
        else if hoursRemaining < 24 { return "Due today" }
        else {
            let days = Int(hoursRemaining / 24)
            return "Due in \(days)d"
        }
    }

    /// String-based convenience overload for urgency label.
    static func urgencyLabel(for dateString: String?, now: Date = Date(), isCompleted: Bool = false) -> String {
        return urgencyLabel(for: parseDate(dateString), now: now, isCompleted: isCompleted)
    }

    // MARK: - Date Parsing

    /// Parses ISO 8601 or SQLite datetime strings into a Date.
    private static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }

        // ISO 8601 with timezone
        if let date = Formatters.iso8601Basic.date(from: dateString) { return date }

        // SQLite datetime: "yyyy-MM-dd HH:mm:ss"
        if let date = Formatters.sqlDateTimeFormatter.date(from: dateString) { return date }

        // Date-only: "yyyy-MM-dd"
        if let date = Formatters.localDateFormatter.date(from: String(dateString.prefix(10))) { return date }

        return nil
    }
}
