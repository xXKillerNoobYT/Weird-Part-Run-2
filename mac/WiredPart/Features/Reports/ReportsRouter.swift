import SwiftUI

/// Routes a `/reports/*` path to the appropriate reports page view.
///
/// Extracts the tab ID from the path and switches to the corresponding page.
/// Falls back to TimesheetsPage when the tab ID is unrecognized.
struct ReportsRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/reports/spending" -> "spending"
    private var tabId: String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return "timesheets" }
        return String(components.last ?? "timesheets")
    }

    var body: some View {
        switch tabId {
        case "overview":
            DailyReportsSummaryPage()
        case "timesheets":
            TimesheetsPage()
        case "daily-summary":
            DailyReportsSummaryPage()
        case "pre-billing":
            PlaceholderView(path: path)
        case "spending":
            SpendingPage()
        case "profitability":
            ProfitabilityPage()
        case "bookkeeper":
            PlaceholderView(path: path)
        default:
            TimesheetsPage()
        }
    }
}
