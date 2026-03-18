import SwiftUI
import WiredPartCore

/// Purchase Order detail page.
///
/// Shows PO header, supplier info, line items, shipping/tracking,
/// and cost breakdown.
struct IOSPODetailPage: View {
    @EnvironmentObject private var appCore: AppCore

    let poId: Int64

    @State private var po: OrdersService.PODetail?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let po {
                poContent(po)
            }
        }
        .navigationTitle("PO \(po?.poNumber ?? "#\(poId)")")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { loadData() }
    }

    @ViewBuilder
    private func poContent(_ po: OrdersService.PODetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Status
                HStack(spacing: 8) {
                    StatusBadge(text: po.status.capitalized, color: statusColor(po.status))
                    Spacer()
                    if let date = po.orderDate {
                        Text("Ordered: \(date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Supplier
                VStack(alignment: .leading, spacing: 4) {
                    Text("Supplier")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(po.supplierName)
                        .font(.body)
                        .fontWeight(.medium)
                }

                // Shipping
                if let tracking = po.trackingNumber, !tracking.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tracking")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(tracking)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                if let expected = po.expectedDelivery {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Expected Delivery")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(expected)
                            .font(.body)
                    }
                }

                // Line Items
                VStack(alignment: .leading, spacing: 8) {
                    Text("Line Items (\(po.lines.count))")
                        .font(.headline)

                    ForEach(po.lines, id: \.id) { line in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.partName ?? "Item")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Qty: \(line.quantityOrdered) | Received: \(line.quantityReceived)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let price = line.unitPrice {
                                Text(formatCurrency(price * Double(line.quantityOrdered)))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        .padding(10)
                        .dsCard()
                    }
                }

                // Cost Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cost Summary")
                        .font(.headline)
                    if let subtotal = po.subtotal {
                        CostLine(label: "Subtotal", value: formatCurrency(subtotal))
                    }
                    if let tax = po.taxAmount {
                        CostLine(label: "Tax", value: formatCurrency(tax))
                    }
                    if let shipping = po.shippingCost {
                        CostLine(label: "Shipping", value: formatCurrency(shipping))
                    }
                    if let total = po.totalCost {
                        Divider()
                        CostLine(label: "Total", value: formatCurrency(total), bold: true)
                    }
                }
                .padding()
                .dsCard()

                if let notes = po.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(notes)
                            .font(.body)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "draft": .secondary
        case "sent": .blue
        case "partial": .orange
        case "received": .green
        case "cancelled": .red
        default: .secondary
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func loadData() {
        guard let service = appCore.ordersService else { return }
        isLoading = po == nil
        loadError = nil
        do {
            po = try service.getPODetail(id: poId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Cost Line

private struct CostLine: View {
    let label: String
    let value: String
    var bold: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .fontWeight(bold ? .bold : .regular)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(bold ? .bold : .medium)
        }
    }
}
