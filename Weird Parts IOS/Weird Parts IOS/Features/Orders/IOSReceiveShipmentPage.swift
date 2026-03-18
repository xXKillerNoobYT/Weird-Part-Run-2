import SwiftUI
import WiredPartCore

/// Receive shipment workflow page.
///
/// Allows warehouse staff to receive items against a purchase order.
/// Shows PO details and a checklist of line items to mark as received.
struct IOSReceiveShipmentPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var purchaseOrders: [OrdersService.POListItem] = []
    @State private var selectedPO: OrdersService.POListItem?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading purchase orders...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if purchaseOrders.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Open Orders",
                    message: "There are no purchase orders awaiting receipt."
                )
            } else {
                List(purchaseOrders, id: \.id) { po in
                    NavigationLink {
                        IOSPODetailPage(poId: po.id)
                            .environmentObject(appCore)
                    } label: {
                        poRow(po)
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            }
        }
        .navigationTitle("Receive Shipment")
        .refreshable { loadData() }
        .task { loadData() }
    }

    private func poRow(_ po: OrdersService.POListItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(po.poNumber)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.medium)
                Text(po.supplierName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(text: po.status.capitalized, color: statusColor(po.status))
                Text("\(po.lineCount) items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "submitted": .orange
        case "ordered": .blue
        case "partial": .purple
        case "received": .green
        default: .secondary
        }
    }

    private func loadData() {
        guard let service = appCore.ordersService else { return }
        isLoading = purchaseOrders.isEmpty
        loadError = nil
        do {
            // Show POs that are submitted, ordered, or partially received
            purchaseOrders = try service.listPurchaseOrders(status: "submitted")
            let ordered = try service.listPurchaseOrders(status: "ordered")
            purchaseOrders.append(contentsOf: ordered)
            let partial = try service.listPurchaseOrders(status: "partial")
            purchaseOrders.append(contentsOf: partial)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
