import SwiftUI
import WiredPartCore

struct OrdersRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "orders-jpos": IOSJPOsPage()
        case "orders-pos": IOSPurchaseOrdersPage()
        case "orders-returns": IOSReturnsPage()
        default: Text("Unknown orders page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
