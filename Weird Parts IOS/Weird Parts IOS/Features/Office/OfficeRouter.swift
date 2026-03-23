import SwiftUI
import WiredPartCore

/// Routes an office tab ID to the appropriate office page view.
///
/// Office is the hub for operations and finance/billing.
/// HR/admin pages (employees, hats, permissions) are in the People module.
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
        case "office-deletion-approvals":
            IOSDeletionApprovalsPage()

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

        default:
            ErrorStateView(message: "Unknown office page: \(tabId)") { }
        }
    }
}
