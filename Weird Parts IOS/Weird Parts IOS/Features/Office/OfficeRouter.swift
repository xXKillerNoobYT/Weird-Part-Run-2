import SwiftUI
import WiredPartCore

/// Routes an office tab ID to the appropriate office page view.
///
/// Office is the hub for operations, finance/billing, and HR/admin.
struct OfficeRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        routedView
    }

    @ViewBuilder
    private var routedView: some View {
        switch tabId {
        // Operations
        case "office-manage-jobs":
            IOSManageJobsPage()
        case "office-warehouse-exec":
            IOSWarehouseExecPage()

        // Finance & Billing
        case "office-spending":
            IOSSpendingDashboardPage()
        case "office-timesheets":
            IOSTimesheetsPage()
        case "office-pre-billing":
            IOSPreBillingPage()
        case "office-bookkeeper":
            IOSBookkeeperExportPage()
        case "office-profitability":
            IOSProfitabilityPage()
        case "office-labor-overview":
            IOSLaborOverviewPage()
        case "office-daily-summary":
            IOSDailyReportsSummaryPage()

        // HR & Admin
        case "office-employees":
            IOSEmployeesPage()
        case "office-hats":
            IOSHatsPage()
        case "office-permissions":
            IOSPermissionsPage()

        default:
            OfficePlaceholderView(pageName: tabId.replacingOccurrences(of: "office-", with: "").replacingOccurrences(of: "-", with: " ").capitalized)
        }
    }
}
