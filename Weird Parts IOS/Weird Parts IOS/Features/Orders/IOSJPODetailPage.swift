import SwiftUI
import WiredPartCore

/// JPO (Job Purchase Order) detail page.
///
/// Shows JPO header with delivery options, per-part line items with
/// Approve/Hold/Reject actions, bulk selection with action bar,
/// status-specific content per line, and a summary section.
struct IOSJPODetailPage: View {
    @EnvironmentObject private var appCore: AppCore

    let jpoId: Int64

    @State private var jpo: OrdersService.JPODetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?

    // Sheets
    @State private var activeSheet: ActiveSheet?

    // Selection + reject
    @State private var selectedLineIds: Set<Int64> = []
    @State private var rejectReason = ""
    @State private var showRejectConfirm = false
    @State private var rejectingLineId: Int64? // nil = reject selected

    private enum ActiveSheet: Identifiable {
        case addLineItem
        case viewChat(Int64)
        case viewPO(Int64)
        case viewMovement(Int64)

        var id: String { String(describing: self) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ErrorStateView(message: error) { loadData() }
                } else if let jpo {
                    jpoContent(jpo)
                }
            }

            // Bulk action bar
            if !selectedLineIds.isEmpty {
                bulkActionBar
            }
        }
        .navigationTitle("JPO #\(jpoId)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .addLineItem
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        // Reject confirmation with required reason
        .alert("Reject Part?", isPresented: $showRejectConfirm) {
            TextField("Reason (required)", text: $rejectReason)
            Button("Cancel", role: .cancel) { rejectReason = "" }
            Button("Reject", role: .destructive) {
                guard !rejectReason.trimmingCharacters(in: .whitespaces).isEmpty else {
                    actionError = "Rejection reason is required."
                    return
                }
                if let lineId = rejectingLineId {
                    rejectLine(lineId, reason: rejectReason)
                } else {
                    rejectSelected(reason: rejectReason)
                }
                rejectReason = ""
            }
        } message: {
            Text("A reason is required for rejection. The requester will be notified.")
        }
        // Error alert
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task { loadData() }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .addLineItem:
            AddJPOLineItemSheet(jpoId: jpoId, onSave: { loadData() })
                .environmentObject(appCore)
        case .viewChat(let threadId):
            NavigationStack {
                Text("Chat Thread #\(threadId) — Coming Soon")
                    .navigationTitle("Chat")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .viewPO(let poId):
            NavigationStack {
                IOSPODetailPage(poId: poId)
                    .environmentObject(appCore)
            }
        case .viewMovement(let movementId):
            NavigationStack {
                Text("Movement #\(movementId) — Coming Soon")
                    .navigationTitle("Movement")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func jpoContent(_ jpo: OrdersService.JPODetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 8) {
                    StatusBadge(text: jpo.status.capitalized, color: statusColor(jpo.status))
                    StatusBadge(text: jpo.priority.capitalized, color: priorityColor(jpo.priority))
                    Spacer()
                }

                // Info
                JPODetailField(label: "Job", value: jpo.jobName)
                JPODetailField(label: "Requested By", value: jpo.requestedByName)
                if let approved = jpo.approvedByName {
                    JPODetailField(label: "Approved By", value: approved)
                }
                if let notes = jpo.notes, !notes.isEmpty {
                    JPODetailField(label: "Notes", value: notes)
                }

                // Delivery option picker
                deliveryOptionSection(jpo)

                // Line items summary
                lineStatusSummary(jpo)

                // Line Items
                VStack(alignment: .leading, spacing: 8) {
                    Text("Line Items (\(jpo.lines.count))")
                        .font(.headline)

                    if jpo.lines.isEmpty {
                        Text("No line items. Tap + to add parts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(jpo.lines, id: \.id) { line in
                            lineItemRow(line)
                        }
                    }
                }
            }
            .padding()
            .padding(.bottom, selectedLineIds.isEmpty ? 0 : 60)
        }
    }

    // MARK: - Delivery Option

    @ViewBuilder
    private func deliveryOptionSection(_ jpo: OrdersService.JPODetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Delivery")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Delivery Option", selection: Binding(
                get: { jpo.deliveryOption ?? "partial" },
                set: { updateDeliveryOption($0) }
            )) {
                Text("Deliver as parts arrive").tag("partial")
                Text("Wait for complete order").tag("full")
            }
            .pickerStyle(.segmented)
            .disabled(jpo.deliveryLocked)
            if jpo.deliveryLocked {
                Text("Locked — parts already delivered")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .dsCard()
    }

    // MARK: - Line Status Summary

    @ViewBuilder
    private func lineStatusSummary(_ jpo: OrdersService.JPODetail) -> some View {
        let statuses = jpo.lines.map(\.lineStatus)
        let pending = statuses.filter { $0 == "pending" }.count
        let approved = statuses.filter { $0 == "approved" || $0 == "in_procurement" }.count
        let transfers = statuses.filter { $0 == "transfer" }.count
        let held = statuses.filter { $0 == "on_hold" }.count
        let rejected = statuses.filter { $0 == "rejected" }.count

        if !statuses.isEmpty {
            HStack(spacing: 12) {
                if transfers > 0 {
                    Label("\(transfers) transfer", systemImage: "arrow.right.circle")
                        .font(.caption2).foregroundStyle(.blue)
                }
                if pending > 0 {
                    Label("\(pending) pending", systemImage: "clock")
                        .font(.caption2).foregroundStyle(.orange)
                }
                if held > 0 {
                    Label("\(held) on hold", systemImage: "pause.circle")
                        .font(.caption2).foregroundStyle(.yellow)
                }
                if approved > 0 {
                    Label("\(approved) approved", systemImage: "checkmark.circle")
                        .font(.caption2).foregroundStyle(.green)
                }
                if rejected > 0 {
                    Label("\(rejected) rejected", systemImage: "xmark.circle")
                        .font(.caption2).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Line Item Row

    @ViewBuilder
    private func lineItemRow(_ line: OrdersService.JPOLineRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Checkbox for bulk selection
                Button {
                    if selectedLineIds.contains(line.id) {
                        selectedLineIds.remove(line.id)
                    } else {
                        selectedLineIds.insert(line.id)
                    }
                } label: {
                    Image(systemName: selectedLineIds.contains(line.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedLineIds.contains(line.id) ? Color.accentColor : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)

                // Status icon
                lineStatusIcon(line.lineStatus)

                // Part info
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.partName ?? "Unknown Part")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Qty: \(line.quantity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Price
                if let price = line.unitPrice {
                    Text(formatCurrency(price * Double(line.quantity)))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }

            // Status-specific content
            lineStatusContent(line)
        }
        .padding(10)
        .dsCard()
    }

    // MARK: - Line Status Content

    @ViewBuilder
    private func lineStatusContent(_ line: OrdersService.JPOLineRow) -> some View {
        switch line.lineStatus {
        case "pending":
            HStack(spacing: 8) {
                Button { approveLine(line.id) } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Button { holdLine(line.id) } label: {
                    Label("Hold", systemImage: "pause.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.yellow)

                Button {
                    rejectingLineId = line.id
                    showRejectConfirm = true
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

        case "transfer":
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.blue)
                Text("In stock — transfer request created")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

        case "on_hold":
            VStack(alignment: .leading, spacing: 4) {
                if let reason = line.holdReason {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.yellow)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    if let threadId = line.chatThreadId {
                        Button { activeSheet = .viewChat(threadId) } label: {
                            Label("View Chat", systemImage: "message.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button { approveLine(line.id) } label: {
                        Label("Approve", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)

                    Button {
                        rejectingLineId = line.id
                        showRejectConfirm = true
                    } label: {
                        Label("Reject", systemImage: "xmark.circle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }

        case "rejected":
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Rejected: \(line.rejectReason ?? "No reason")")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        case "approved":
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                Text("Approved — awaiting procurement")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        case "ordered":
            HStack(spacing: 4) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.blue)
                Text("Ordered")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

        case "received":
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Received at shop")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        case "delivered":
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Delivered to job")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        case "backorder":
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.red)
                Text("On backorder")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Line Status Icon

    @ViewBuilder
    private func lineStatusIcon(_ status: String) -> some View {
        switch status {
        case "pending":
            Image(systemName: "clock").foregroundStyle(.orange)
        case "approved":
            Image(systemName: "checkmark.circle").foregroundStyle(.green)
        case "on_hold":
            Image(systemName: "pause.circle.fill").foregroundStyle(.yellow)
        case "rejected":
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case "transfer":
            Image(systemName: "arrow.right.circle.fill").foregroundStyle(.blue)
        case "ordered", "in_procurement":
            Image(systemName: "shippingbox").foregroundStyle(.blue)
        case "received":
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case "backorder":
            Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.red)
        case "delivered":
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        default:
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    // MARK: - Bulk Action Bar

    private var bulkActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Text("\(selectedLineIds.count) selected")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button { approveSelected() } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Button { holdSelected() } label: {
                    Label("Hold", systemImage: "questionmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.yellow)

                Button {
                    showRejectConfirm = true
                    rejectingLineId = nil
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Actions

    private func approveLine(_ lineId: Int64) {
        guard let service = appCore.ordersService else { return }
        do {
            try service.updateJPOLineStatus(lineId: lineId, status: "approved",
                                            updatedBy: appCore.currentUser?.id)
            loadData()
        } catch { actionError = error.localizedDescription }
    }

    private func holdLine(_ lineId: Int64) {
        guard let service = appCore.ordersService else { return }
        do {
            try service.updateJPOLineStatus(lineId: lineId, status: "on_hold",
                                            reason: "Question pending",
                                            updatedBy: appCore.currentUser?.id)
            loadData()
        } catch { actionError = error.localizedDescription }
    }

    private func rejectLine(_ lineId: Int64, reason: String) {
        guard let service = appCore.ordersService else { return }
        do {
            try service.updateJPOLineStatus(lineId: lineId, status: "rejected",
                                            reason: reason,
                                            updatedBy: appCore.currentUser?.id)
            loadData()
        } catch { actionError = error.localizedDescription }
    }

    private func approveSelected() {
        for lineId in selectedLineIds { approveLine(lineId) }
        selectedLineIds.removeAll()
    }

    private func holdSelected() {
        for lineId in selectedLineIds { holdLine(lineId) }
        selectedLineIds.removeAll()
    }

    private func rejectSelected(reason: String) {
        for lineId in selectedLineIds { rejectLine(lineId, reason: reason) }
        selectedLineIds.removeAll()
    }

    private func updateDeliveryOption(_ option: String) {
        guard let service = appCore.ordersService else { return }
        do {
            try service.updateJPODeliveryOption(jpoId: jpoId, option: option)
            loadData()
        } catch { actionError = error.localizedDescription }
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "pending": .orange
        case "approved": .green
        case "rejected": .red
        case "ordered": .blue
        case "in_review": .purple
        case "complete": .green
        default: .secondary
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "urgent": .red
        case "high": .orange
        case "normal": .blue
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
        isLoading = jpo == nil
        loadError = nil
        do {
            jpo = try service.getJPODetail(id: jpoId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Detail Field

private struct JPODetailField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

// MARK: - Add JPO Line Item Sheet

private struct AddJPOLineItemSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let jpoId: Int64
    let onSave: () -> Void

    @State private var searchText = ""
    @State private var searchResults: [Part] = []
    @State private var selectedPart: Part?
    @State private var quantity = 1
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Part") {
                    TextField("Search parts...", text: $searchText)
                        .onChange(of: searchText) { searchParts() }

                    if let part = selectedPart {
                        HStack {
                            Text(part.name)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Change") { selectedPart = nil }
                                .font(.caption)
                        }
                        .padding(.vertical, 2)
                    } else if !searchResults.isEmpty {
                        ForEach(searchResults, id: \.id) { part in
                            Button {
                                selectedPart = part
                                searchText = part.name
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(part.name)
                                        .fontWeight(.medium)
                                    if let code = part.code, !code.isEmpty {
                                        Text(code)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section("Details") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                    TextField("Notes (optional)", text: $notes)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Line Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(selectedPart == nil)
                }
            }
        }
    }

    private func searchParts() {
        guard let service = appCore.partsService, searchText.count >= 2 else {
            searchResults = []
            return
        }
        do {
            searchResults = try service.searchParts(query: searchText, limit: 10)
        } catch {
            searchResults = []
        }
    }

    private func save() {
        guard let service = appCore.ordersService,
              let part = selectedPart,
              let partId = part.id else {
            errorMessage = "Service unavailable or no part selected"
            return
        }
        let userId = appCore.currentUser?.id
        do {
            try service.addJPOLineItem(
                jpoId: jpoId,
                partId: partId,
                quantity: quantity,
                notes: notes.isEmpty ? nil : notes,
                userId: userId
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
