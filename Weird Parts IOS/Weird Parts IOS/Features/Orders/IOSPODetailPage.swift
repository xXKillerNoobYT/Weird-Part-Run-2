import SwiftUI
import WiredPartCore

/// Purchase Order detail page.
///
/// Shows PO header, supplier CRM section with contact info and scores,
/// status-based action buttons, line items with stale price warnings,
/// shipping/tracking, cost breakdown, and tabbed notes (PO + Supplier).
/// Actions change based on the PO's lifecycle state.
struct IOSPODetailPage: View {
    @EnvironmentObject private var appCore: AppCore

    let poId: Int64

    @State private var po: OrdersService.PODetail?
    @State private var supplier: Supplier?
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

    // Notes
    @State private var selectedNotesTab = 0
    @State private var newNoteText = ""
    @State private var poNotes: [PONoteEntry] = []
    @State private var supplierNotes: [PONoteEntry] = []

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

                // Supplier CRM Section
                supplierCRMSection(po)

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

                // Tabbed Notes
                notesTabSection(po)
            }
            .padding()
        }
    }

    // MARK: - Supplier CRM Section

    @ViewBuilder
    private func supplierCRMSection(_ po: OrdersService.PODetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with name + quick actions
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(po.supplierName)
                        .font(.headline)
                    if let sup = supplier {
                        if let rep = sup.repName, !rep.isEmpty {
                            Text("Rep: \(rep)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let acct = sup.accountNumber, !acct.isEmpty {
                            Text("Acct: \(acct)")
                                .font(.caption)
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                // Quick contact buttons
                if let sup = supplier {
                    HStack(spacing: 12) {
                        if let phone = sup.phone, !phone.isEmpty,
                           let url = URL(string: "tel:\(phone)") {
                            Link(destination: url) {
                                Image(systemName: "phone.fill")
                                    .font(.title3)
                                    .foregroundStyle(.green)
                            }
                        }
                        if let email = sup.email, !email.isEmpty,
                           let url = URL(string: "mailto:\(email)") {
                            Link(destination: url) {
                                Image(systemName: "envelope.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }
                        }
                        Button {
                            activeSheet = .contactSupplier
                        } label: {
                            Image(systemName: "message.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            // Reliability scores
            if let sup = supplier {
                HStack(spacing: 16) {
                    scoreBar(label: "Reliability", value: sup.reliabilityScore, color: .blue)
                    scoreBar(label: "On-Time", value: sup.onTimeRate, color: .green)
                    scoreBar(label: "Quality", value: sup.qualityScore, color: .purple)
                }
            }

            // View supplier profile link
            NavigationLink {
                Text("Supplier Profile")
            } label: {
                Label("View Supplier Profile", systemImage: "person.crop.rectangle")
                    .font(.caption)
            }
        }
        .padding()
        .dsCard()
    }

    // MARK: - Score Bar

    @ViewBuilder
    private func scoreBar(label: String, value: Double?, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let score = value {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.15))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * min(max(score / 100, 0), 1))
                    }
                }
                .frame(height: 6)
                Text("\(Int(score))%")
                    .font(.caption2)
                    .fontWeight(.medium)
            } else {
                Text("--")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Tabbed Notes Section

    @ViewBuilder
    private func notesTabSection(_ po: OrdersService.PODetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Notes", selection: $selectedNotesTab) {
                Text("PO Notes (\(poNotes.count))").tag(0)
                Text("Supplier Notes (\(supplierNotes.count))").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedNotesTab == 0 {
                // PO-specific notes — editable
                ForEach(poNotes) { note in
                    noteRow(note)
                }

                // Add note field
                HStack {
                    TextField("Add a note...", text: $newNoteText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        guard !newNoteText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        Task { await addPONote() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.accentColor)
                    }
                    .disabled(newNoteText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if poNotes.isEmpty {
                    Text("No notes yet. Add communication history for this order.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                }
            } else {
                // Supplier-wide notes — read-only
                ForEach(supplierNotes) { note in
                    noteRow(note)
                }

                if supplierNotes.isEmpty {
                    Text("No supplier notes. Add them from the Supplier Profile page.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .dsCard()
    }

    @ViewBuilder
    private func noteRow(_ note: PONoteEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if let author = note.author {
                    Text(author)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                Spacer()
                Text(note.date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(note.text)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
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

    // MARK: - Notes Actions

    private func addPONote() async {
        guard let service = appCore.ordersService else { return }
        let author = appCore.currentUser?.displayName ?? "Unknown"
        do {
            try service.addPONote(poId: poId, note: newNoteText, author: author)
            newNoteText = ""
            loadData()
        } catch {
            actionMessage = "Failed to add note: \(error.localizedDescription)"
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
            let detail = try service.getPODetail(id: poId)
            po = detail

            // Load supplier details
            if let partsService = appCore.partsService {
                supplier = try? partsService.getSupplier(id: detail.supplierId)
            }

            // Parse PO notes
            if let notesStr = detail.notes, !notesStr.isEmpty {
                poNotes = parseNotes(notesStr)
            } else {
                poNotes = []
            }

            // Parse supplier-wide notes (read-only)
            if let supNotes = supplier?.notes, !supNotes.isEmpty {
                supplierNotes = parseNotes(supNotes)
            } else {
                supplierNotes = []
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    /// Parse timestamped notes from a newline-delimited string.
    /// Expected format: "2026-03-20T14:30:00Z [Author]: Note text"
    /// Falls back to plain text if format doesn't match.
    private func parseNotes(_ raw: String) -> [PONoteEntry] {
        raw.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                let parts = line.components(separatedBy: "]: ")
                guard parts.count >= 2 else {
                    return PONoteEntry(text: line, author: nil, date: "")
                }
                let prefix = parts[0]
                let text = parts.dropFirst().joined(separator: "]: ")
                let prefixParts = prefix.components(separatedBy: " [")
                let date = prefixParts.first ?? ""
                let author = prefixParts.count > 1 ? prefixParts[1] : nil
                return PONoteEntry(text: text, author: author, date: String(date.prefix(10)))
            }
    }
}

// MARK: - Note Entry

private struct PONoteEntry: Identifiable {
    let id = UUID()
    let text: String
    let author: String?
    let date: String
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
