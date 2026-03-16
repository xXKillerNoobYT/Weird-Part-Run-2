import SwiftUI

/// Routes a `/jobs/*` path to the appropriate jobs page view.
///
/// Extracts the tab ID from the path and switches to the corresponding page.
/// Falls back to ActiveJobsPage when the tab ID is unrecognized.
struct JobsRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/jobs/clock" -> "clock"
    private var tabId: String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return "active" }
        return String(components.last ?? "active")
    }

    var body: some View {
        switch tabId {
        case "active":
            ActiveJobsPage()
        case "detail":
            JobDetailPage()
        case "clock":
            ClockPage()
        case "questionnaire":
            QuestionnairePage()
        case "daily-reports":
            DailyReportsPage()
        case "management":
            ActiveJobsPage()
        default:
            ActiveJobsPage()
        }
    }
}
