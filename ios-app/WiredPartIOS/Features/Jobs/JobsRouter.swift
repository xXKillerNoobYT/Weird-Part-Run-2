import SwiftUI
import WiredPartCore

/// Routes a jobs tab ID to the appropriate jobs page view.
///
/// Each jobs sub-page is a standalone SwiftUI view that queries
/// the database directly for its data.
struct JobsRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        routedView
    }

    @ViewBuilder
    private var routedView: some View {
        switch tabId {
        case "jobs-list":
            JobsListPage()
        case "jobs-labor":
            LaborPage()
        case "jobs-reports":
            JobReportsPage()
        case "jobs-clock":
            IOSClockPage()
        case "jobs-detail":
            JobsListPage() // Job detail requires selection; show list for drill-down
        case "jobs-questionnaire":
            LaborPage() // Questionnaire requires labor entry context; show labor page
        case "jobs-daily-reports":
            IOSDailyReportsPage()
        default:
            Text("Unknown jobs page: \(tabId)")
                .foregroundStyle(.secondary)
        }
    }
}
