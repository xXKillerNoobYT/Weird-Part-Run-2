import SwiftUI

/// Routes a `/warehouse/*` path to the appropriate warehouse page view.
///
/// Extracts the tab ID from the path and switches to the corresponding page.
/// Falls back to WarehouseDashboardPage when the tab ID is unrecognized.
struct WarehouseRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/warehouse/movements" -> "movements"
    private var tabId: String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return "dashboard" }
        return String(components.last ?? "dashboard")
    }

    var body: some View {
        switch tabId {
        case "dashboard":
            WarehouseDashboardPage()
        case "movements":
            MovementsPage()
        case "staging":
            StagingPage()
        case "receiving":
            ReceivingPage()
        case "returns":
            ReturnsPage()
        case "audit":
            WarehouseAuditPage()
        default:
            WarehouseDashboardPage()
        }
    }
}
