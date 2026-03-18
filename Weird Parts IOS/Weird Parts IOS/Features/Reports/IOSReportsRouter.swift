import SwiftUI
import WiredPartCore

struct IOSReportsRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "reports-timesheets": IOSTimesheetsPage()
        case "reports-spending": IOSSpendingPage()
        case "reports-daily-summary": IOSDailyReportsSummaryPage()
        case "reports-profitability": IOSProfitabilityPage()
        case "reports-pre-billing": IOSPreBillingPage()
        case "reports-bookkeeper": IOSBookkeeperExportPage()
        case "reports-labor-overview": IOSLaborOverviewPage()
        default: Text("Unknown reports page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
