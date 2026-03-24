import Foundation

/// Shared date range picker for all time-based reports.
enum ReportDateRange: String, CaseIterable {
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisQuarter = "This Quarter"
    case thisYear = "This Year"

    var startDate: Date {
        let cal = Calendar.current
        switch self {
        case .thisWeek:
            return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        case .lastWeek:
            let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
            return cal.dateInterval(of: .weekOfYear, for: lastWeek)?.start ?? lastWeek
        case .thisMonth:
            return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        case .lastMonth:
            let lastMonth = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            return cal.date(from: cal.dateComponents([.year, .month], from: lastMonth)) ?? lastMonth
        case .thisQuarter:
            let month = cal.component(.month, from: Date())
            let quarterStart = ((month - 1) / 3) * 3 + 1
            return cal.date(from: DateComponents(year: cal.component(.year, from: Date()), month: quarterStart)) ?? Date()
        case .thisYear:
            return cal.date(from: DateComponents(year: cal.component(.year, from: Date()))) ?? Date()
        }
    }

    var endDate: Date { Date() }
}
