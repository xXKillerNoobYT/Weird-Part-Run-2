import SwiftUI
import WiredPartCore

/// Purchase Order detail page.
///
/// Shows PO header, supplier info, status-based action buttons,
/// line items with stale price warnings, shipping/tracking,
/// and cost breakdown. Actions change based on the PO's lifecycle state.
struct IOSPODetailPage: View {
    @EnvironmentObject private var appCore: AppCore

    let poId: Int64

    @State private var po: OrdersService.PODetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionMessage: String?

    // Confirmations
    @State private var showDeleteConfirmation = false
    @State private var showCancelConfirmation = false
    @State private var showCancelRemainingConfirmation = false
    @State private var cancelReason = ""

    // Sheets
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case receiveShipment
        case manageParts
        case contactSupplier
        case updateETA
        case doubleOrder
        case reportIssue
        case receiptHistory
        case contactCreator

        var id: String { String(describing: self) }
    }

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
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        // Delete Draft confirmation
        .alert("Delete Draft?", isPresented: $showDeleteConfirmation) {
            Button("Keep Draft", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteDraftPO() }
            }
        } message: {
            Text("This will permanently delete this draft purchase order.")
        }
        // Cancel PO confirmation
        .alert("Cancel Purchase Order?", isPresented: $showCancelConfirmation) {
            TextField("Reason (required)", text: $cancelReason)
            Button("Keep Order", role: .cancel) { cancelReason = "" }
            Button("Cancel PO", role: .destructive) {
                Task {
                    guard !cancelReason.trimmingCharacters(in: .whitespaces).isEmpty else {
                        actionMessage = "Cancellation reason is required."
                        return
                    }
                    await transitionPO(to: "cancelled")
                    cancelReason = ""
                }
            }
        } message: {
            Text("This will cancel the entire purchase order. A reason is required.")
        }
        // Cancel Remaining confirmation
        .alert("Cancel Remaining Items?", isPresented: $showCancelRemainingConfirmation) {
            TextField("Reason (required)", text: $cancelReason)
            Button("Keep Remaining", role: .cancel) { cancelReason = "" }
            Button("Cancel Remaining", role: .destructive) {
                Task {
                    guard !cancelReason.trimmingCharacters(in: .whitespaces).isEmpty else {
                        actionMessage = "Cancellation reason is required."
                        return
                    }
                    await transitionPO(to: "cancelled")
                    cancelReason = ""
                }
            }
        } message: {
            Text("This will cancel all unreceived items. Contact the supplier first to confirm. A reason is required.")
        }
        // Action message
        .alert("Notice", isPresented: .constant(actionMessage != nil)) {
            Button("OK") { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
        .task { loadData() }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .receiveShipment:
            NavigationStack {
                IOSReceiveShipmentPage()
                    .environmentObject(appCore)
            }
        case .manageParts:
            NavigationStack {
                Text("Parts Management — Coming Soon")
                    .navigationTitle("Manage Parts")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .contactSupplier:
            NavigationStack {
                Text("Supplier Contact — Coming Soon")
                    .navigationTitle("Contact Supplier")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .updateETA:
            NavigationStack {
                Text("Update ETA — Coming Soon")
                    .navigationTitle("Update ETA")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .doubleOrder:
            NavigationStack {
                Text("Double Order — Coming Soon")
                    .navigationTitle("Double Order")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .reportIssue:
            NavigationStack {
                Text("Report Issue — Coming Soon")
                    .navigationTitle("Report Issue")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .receiptHistory:
            NavigationStack {
                Text("Receipt History — Coming Soon")
                    .navigationTitle("Receipt History")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .contactCreator:
            NavigationStack {
                Text("Contact Creator — Coming Soon")
                    .navigationTitle("Contact Creator")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - Content

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

                // Action Buttons
                actionButtons(for: po.status)

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
                                // Stale price warning
                                if let partId = line.partId,
                                   let service = appCore.partsService,
                                   (try? service.isPartPriceStale(partId: partId)) == true {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                        Text("Price not verified recently")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
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

    // MARK: - Action Buttons

    @ViewBuilder
    private func actionButtons(for status: String) -> some View {
        VStack(spacing: 8) {
            switch status {
            case "draft":
                HStack(spacing: 8) {
                    actionButton("Submit to Supplier", icon: "paperplane.fill", color: .blue) {
                        await transitionPO(to: "submitted")
                    }
                    actionButton("Delete Draft", icon: "trash", color: .red) {
                        showDeleteConfirmation = true
                    }
                }
                actionButton("Manage Parts", icon: "list.bullet.rectangle", color: .accentColor) {
                    activeSheet = .manageParts
                }

            case "submitted":
                HStack(spacing: 8) {
                    actionButton("Mark Ordered", icon: "checkmark.circle.fill", color: .blue) {
                        await transitionPO(to: "ordered")
                    }
                    actionButton("Drafting / Unclear", icon: "questionmark.circle", color: .yellow) {
                        await transitionPO(to: "drafting")
                    }
                }
                HStack(spacing: 8) {
                    actionButton("Cancel PO", icon: "xmark.circle", color: .red) {
                        showCancelConfirmation = true
                    }
                    actionButton("Contact Supplier", icon: "message.fill", color: .green) {
                        activeSheet = .contactSupplier
                    }
                }

            case "ordered":
                HStack(spacing: 8) {
                    actionButton("Receive Shipment", icon: "shippingbox.and.arrow.backward.fill", color: .green) {
                        activeSheet = .receiveShipment
                    }
                    actionButton("Update ETA", icon: "calendar.badge.clock", color: .orange) {
                        activeSheet = .updateETA
                    }
                }
                HStack(spacing: 8) {
                    actionButton("Cancel PO", icon: "xmark.circle", color: .red) {
                        showCancelConfirmation = true
                    }
                    actionButton("Contact Supplier", icon: "message.fill", color: .green) {
                        activeSheet = .contactSupplier
                    }
                }
                actionButton("Manage Parts", icon: "list.bullet.rectangle", color: .accentColor) {
                    activeSheet = .manageParts
                }

            case "partial":
                HStack(spacing: 8) {
                    actionButton("Receive More", icon: "shippingbox.and.arrow.backward.fill", color: .green) {
                        activeSheet = .receiveShipment
                    }
                    actionButton("Cancel Remaining", icon: "xmark.circle", color: .red) {
                        showCancelRemainingConfirmation = true
                    }
                }
                HStack(spacing: 8) {
                    actionButton("Contact Supplier", icon: "message.fill", color: .green) {
                        activeSheet = .contactSupplier
                    }
                    actionButton("Double Order", icon: "doc.on.doc", color: .orange) {
                        activeSheet = .doubleOrder
                    }
                }
                actionButton("Manage Parts", icon: "list.bullet.rectangle", color: .accentColor) {
                    activeSheet = .manageParts
                }

            case "received":
                HStack(spacing: 8) {
                    actionButton("Report Issue", icon: "exclamationmark.triangle", color: .orange) {
                        activeSheet = .reportIssue
                    }
                    actionButton("View History", icon: "clock.arrow.circlepath", color: .secondary) {
                        activeSheet = .receiptHistory
                    }
                }

            case "drafting":
                HStack(spacing: 8) {
                    actionButton("Resume Draft", icon: "pencil.circle.fill", color: .blue) {
                        await transitionPO(to: "draft")
                    }
                    actionButton("Contact Job Creator", icon: "person.fill.questionmark", color: .orange) {
                        activeSheet = .contactCreator
                    }
                }

            case "cancelled":
                EmptyView()

            default:
                EmptyView()
            }
        }
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status Transitions

    private func transitionPO(to newStatus: String) async {
        guard let service = appCore.ordersService else { return }
        do {
            try service.updatePOStatus(id: poId, status: newStatus)
            loadData()
        } catch {
            actionMessage = "Failed to update status: \(error.localizedDescription)"
        }
    }

    private func deleteDraftPO() async {
        guard let service = appCore.ordersService else { return }
        do {
            try service.deletePO(id: poId)
            actionMessage = "Draft deleted."
        } catch {
            actionMessage = "Failed to delete draft: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "draft": .secondary
        case "submitted": .orange
        case "ordered": .blue
        case "partial": .purple
        case "received": .green
        case "cancelled": .red
        case "drafting": .yellow
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
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
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
