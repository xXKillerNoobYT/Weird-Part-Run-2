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
        default:
            Text("Unknown jobs page: \(tabId)")
                .foregroundStyle(.secondary)
        }
    }
}
