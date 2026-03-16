import SwiftUI

/// Routes a `/tools/*` path to the appropriate tools page view.
///
/// Extracts the tab ID from the path and switches to the corresponding page.
/// Falls back to ToolRegistryPage when the tab ID is unrecognized.
struct ToolsRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/tools/checkouts" -> "checkouts"
    private var tabId: String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return "registry" }
        return String(components.last ?? "registry")
    }

    var body: some View {
        switch tabId {
        case "dashboard":
            ToolsDashboardPage()
        case "registry":
            ToolRegistryPage()
        case "checkouts":
            ToolCheckoutsPage()
        case "kits":
            ToolKitsPage()
        case "admin":
            ToolsDashboardPage()
        default:
            ToolRegistryPage()
        }
    }
}
