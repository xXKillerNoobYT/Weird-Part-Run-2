import SwiftUI
import WiredPartCore

struct OrdersRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "orders-jpos": IOSJPOsPage()
        case "orders-pos": IOSPurchaseOrdersPage()
        case "orders-procurement": IOSProcurementPage()
        case "orders-parts": IOSPartsOrderManagementPage()
        case "orders-staging": IOSOrderStagingPage()
        case "orders-approvals": IOSApprovalsPage()
        case "orders-returns": IOSReturnsPage()
        case "orders-wishlist": IOSWishlistPage()
        default: ErrorStateView(message: "Unknown orders page: \(tabId)") { }
        }
    }
}
