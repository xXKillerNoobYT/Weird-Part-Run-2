import SwiftUI
import WiredPartCore

struct OrdersRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "orders-jpos": IOSJPOsPage()
        case "orders-procurement": IOSProcurementPage()
        case "orders-pos": IOSPurchaseOrdersPage()
        case "orders-parts": IOSPartsOrderManagementPage()
        case "orders-staging": IOSOrderStagingPage()
        case "orders-approvals": IOSApprovalsPage()
        case "orders-returns": IOSReturnsPage()
        default: Text("Unknown orders page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
