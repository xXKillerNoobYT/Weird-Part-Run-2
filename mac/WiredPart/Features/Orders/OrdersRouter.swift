import SwiftUI

/// Routes an `/orders/*` path to the appropriate orders page view.
///
/// Extracts the tab ID from the path and switches to the corresponding page.
/// Falls back to JPOsPage when the tab ID is unrecognized.
struct OrdersRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/orders/purchase-orders" -> "purchase-orders"
    private var tabId: String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return "jpos" }
        return String(components.last ?? "jpos")
    }

    var body: some View {
        switch tabId {
        case "requests", "jpos":
            JPOsPage()
        case "unified-order":
            OrderStagingPage()
        case "purchase-orders":
            PurchaseOrdersPage()
        case "returns":
            OrderReturnsPage()
        case "procurement":
            ProcurementPage()
        case "approvals":
            ApprovalsPage()
        case "special-items":
            SpecialItemsPage()
        case "staging":
            OrderStagingPage()
        default:
            JPOsPage()
        }
    }
}
