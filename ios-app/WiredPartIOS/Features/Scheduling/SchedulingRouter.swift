import SwiftUI
import WiredPartCore

struct SchedulingRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "scheduling-calendar": IOSScheduleCalendarPage()
        case "scheduling-dispatch": IOSDispatchPage()
        default: Text("Unknown scheduling page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
