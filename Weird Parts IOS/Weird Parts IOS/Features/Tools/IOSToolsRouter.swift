import SwiftUI
import WiredPartCore

struct IOSToolsRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        routedPage
            .onAppear { postActiveContext() }
            .onDisappear { postInactiveContext() }
    }

    @ViewBuilder
    private var routedPage: some View {
        switch tabId {
        case "tools-registry": IOSToolRegistryPage()
        case "tools-checkouts": IOSToolCheckoutsPage()
        case "tools-kits": IOSToolKitsPage()
        case "tools-dashboard": IOSToolsDashboardPage()
        case "tools-admin": IOSToolAdminPage()
        case "tools-maintenance": IOSToolMaintenancePage()
        default: ErrorStateView(message: "Unknown tools page: \(tabId)") { }
        }
    }

    private func postActiveContext() {
        switch tabId {
        case "tools-dashboard":
            NotificationCenter.default.post(name: .toolsDashboardPageActive, object: nil, userInfo: ["context": toolsContext])
        case "tools-checkouts":
            NotificationCenter.default.post(name: .toolCheckoutsPageActive, object: nil, userInfo: ["context": toolsContext])
        case "tools-kits":
            NotificationCenter.default.post(name: .toolKitsPageActive, object: nil, userInfo: ["context": toolsContext])
        case "tools-maintenance":
            NotificationCenter.default.post(name: .toolMaintenancePageActive, object: nil, userInfo: ["context": toolsContext])
        case "tools-admin":
            NotificationCenter.default.post(name: .toolAdminPageActive, object: nil, userInfo: ["context": toolsContext])
        default:
            break
        }
    }

    private func postInactiveContext() {
        switch tabId {
        case "tools-dashboard":
            NotificationCenter.default.post(name: .toolsDashboardPageInactive, object: nil)
        case "tools-checkouts":
            NotificationCenter.default.post(name: .toolCheckoutsPageInactive, object: nil)
        case "tools-kits":
            NotificationCenter.default.post(name: .toolKitsPageInactive, object: nil)
        case "tools-maintenance":
            NotificationCenter.default.post(name: .toolMaintenancePageInactive, object: nil)
        case "tools-admin":
            NotificationCenter.default.post(name: .toolAdminPageInactive, object: nil)
        default:
            break
        }
    }

    private var toolsContext: String {
        switch tabId {
        case "tools-dashboard":
            return "Current page: Tools Dashboard. Visible workflow: read-only tool health, checkout, maintenance, kit, and utilization summaries. Available read-only actions: review tool status, overdue work, and navigation entry points."
        case "tools-checkouts":
            return "Current page: Tool Checkouts. Visible workflow: read-only checkout/return history, active checkout filter, search state, scanner entry point, and overdue status review. Available read-only actions: summarize active/all checkout state and explain checkout status."
        case "tools-kits":
            return "Current page: Tool Kits. Visible workflow: read-only kit composition, assignment, and kit readiness summaries. Available read-only actions: explain kit membership, readiness, and navigation entry points."
        case "tools-maintenance":
            return "Current page: Tool Maintenance. Visible workflow: read-only tool service queue, maintenance status, and due/overdue maintenance review. Available read-only actions: summarize maintenance state and explain filters/statuses."
        case "tools-admin":
            return "Current page: Tool Admin. Visible workflow: read-only admin configuration overview for tool management. Available read-only actions: explain visible settings, permissions, and administrative entry points."
        default:
            return "Current page: Tools. Visible workflow: read-only tool navigation context."
        }
    }
}
