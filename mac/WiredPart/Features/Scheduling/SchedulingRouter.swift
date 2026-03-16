import SwiftUI

/// Routes a `/scheduling/*` path to the appropriate scheduling page view.
///
/// Extracts the tab ID from the path and switches to the corresponding page.
/// Falls back to ScheduleCalendarPage when the tab ID is unrecognized.
struct SchedulingRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/scheduling/dispatch" -> "dispatch"
    private var tabId: String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return "calendar" }
        return String(components.last ?? "calendar")
    }

    var body: some View {
        switch tabId {
        case "calendar":
            ScheduleCalendarPage()
        case "my-schedule":
            ScheduleCalendarPage()
        case "dispatch":
            DispatchBoardPage()
        case "dispatch-admin":
            DispatchBoardPage()
        case "availability":
            PlaceholderView(path: path)
        case "time-off":
            TimeOffPage()
        case "templates":
            DispatchTemplatesPage()
        case "sub-schedule":
            PlaceholderView(path: path)
        default:
            ScheduleCalendarPage()
        }
    }
}
