import SwiftUI
import WiredPartCore

/// Purchase Order detail page.
///
/// Shows PO header, supplier CRM section with contact info and scores,
/// status-based action buttons, job-grouped line items with delivery timelines,
/// inline draft editing, receipt history, shipping/tracking, cost breakdown,
/// and tabbed notes (PO + Supplier).
struct IOSPODetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let poId: Int64

    @State private var po: OrdersService.PODetail?
    @State private var supplier: Supplier?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionMessage: String?

    // Confirmations
    @State private var showDeleteConfirmation = false
    @State private var showSubmitConfirmation = false
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

    // Line item editing uses POLineEditSheet via .editLineItem(line)

    // Receipt history (legacy batches from order_status_history)
    @State private var receiptBatches: [OrdersService.ReceiptBatch] = []

    // Receipt history entries (from receiving_sessions — 62P)
    @State private var receiptHistoryEntries: [OrdersService.ReceiptHistoryEntry] = []
    @State private var expandedReceiptEntryIds: Set<Int64> = []
    @State private var receiptEntryItems: [Int64: [OrdersService.ReceiptHistoryItem]] = [:]
    @State private var isReceiptHistoryExpanded = false

    // Update ETA
    @State private var etaDate = Date()

    // Report Issue
    @State private var issueDescription = ""
    @State private var issueSeverity = "medium"

    // Double Order
    @State private var availableSuppliers: [PartsService.SupplierWithCount] = []
    @State private var selectedSupplierId: Int64?

    // Contact Supplier
    @State private var supplierChannels: [ChatService.SupplierChannelRow] = []
    @State private var newSupplierMessage = ""
    @State private var channelMessages: [ChatService.MessageRow] = []
    @State private var activeChannelId: Int64?

    // Contact Creator
    @State private var creatorName: String?
    @State private var creatorId: Int64?

    private enum ActiveSheet: Identifiable {
        case receiveShipment
        case manageParts
        case contactSupplier
        case updateETA
        case doubleOrder
        case reportIssue
        case receiptHistory
        case contactCreator
        case help
        case editLineItem(OrdersService.POLineRow)

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
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
        // Mark as Submitted confirmation
        .confirmationDialog(
            "Mark PO as Submitted?",
            isPresented: $showSubmitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark as Submitted") {
                Task { await transitionPO(to: "submitted") }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This changes the PO status to Submitted. You still need to contact the supplier separately (email, phone, or portal) to actually send the order.")
        }
        // Line item editing now uses POLineEditSheet via .sheet(item: $activeSheet)
        // Action message
        .alert("Notice", isPresented: .constant(actionMessage != nil)) {
            Button("OK") { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
        .refreshable { loadData() }
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
                IOSPartsOrderManagementPage(preSelectedSupplierId: po?.supplierId)
                    .environmentObject(appCore)
            }
        case .contactSupplier:
            contactSupplierSheet()
        case .updateETA:
            updateETASheet()
        case .doubleOrder:
            doubleOrderSheet()
        case .reportIssue:
            reportIssueSheet()
        case .receiptHistory:
            receiptHistorySheet()
        case .contactCreator:
            contactCreatorSheet()
        case .editLineItem(let lineItem):
            POLineEditSheet(lineItem: lineItem) { newQty, newPrice in
                Task { await saveLineEdit(lineId: lineItem.id, quantity: newQty, unitPrice: newPrice) }
            }
        case .help:
            PageHelpSheet(
                title: "PO Detail Help",
                sections: [
                    ("What This Page Does", "Shows everything about a Purchase Order -- supplier info, line items grouped by job, delivery timeline, cost breakdown, receipt history, and notes. This is where you manage the full lifecycle of a PO."),
                    ("Status Actions", "Draft POs can be edited inline (tap a line item to change qty/price) and deleted. Submitted/Ordered POs can be received, have their ETA updated, or be cancelled with a required reason. Partially received POs show what's still outstanding."),
                    ("Key Actions", "Receive Shipment: start checking in items. Manage Parts: see all parts for this supplier across POs. Contact Supplier: open a chat channel. Update ETA: set a new expected delivery date. Double Order: re-order remaining items from a different supplier. Report Issue: log a problem."),
                    ("Notes Tabs", "The notes section has two tabs -- PO Notes (about this specific order) and Supplier Notes (general notes about the supplier visible on all their POs). Add notes to keep a paper trail."),
                    ("Tips", "Swipe left on the PO in the list view to quick-delete drafts or cancel active orders. The cost breakdown section shows subtotal, tax, shipping, and grand total. Receipt history tracks every receiving session.")
                ]
            )
        }
    }

    // MARK: - 1. Contact Supplier Sheet

    @ViewBuilder
    private func contactSupplierSheet() -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let sup = supplier {
                    // Supplier info header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sup.name)
                                    .font(.headline)
                                if let rep = sup.repName, !rep.isEmpty {
                                    Text("Rep: \(rep)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            // Quick contact buttons
                            HStack(spacing: 12) {
                                if let phone = sup.phone, !phone.isEmpty,
                                   let url = URL(string: "tel:\(phone)") {
                                    Link(destination: url) {
                                        Image(systemName: "phone.fill")
                                            .font(.title3)
                                            .foregroundStyle(.green)
                                    }
                                    .accessibilityLabel("Call supplier")
                                }
                                if let email = sup.email, !email.isEmpty,
                                   let url = URL(string: "mailto:\(email)") {
                                    Link(destination: url) {
                                        Image(systemName: "envelope.fill")
                                            .font(.title3)
                                            .foregroundStyle(.blue)
                                    }
                                    .accessibilityLabel("Email supplier")
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGroupedBackground))
                }

                // Existing channels list
                if !supplierChannels.isEmpty {
                    List {
                        Section("Existing Channels") {
                            ForEach(supplierChannels, id: \.channelId) { channel in
                                Button {
                                    activeChannelId = channel.channelId
                                    loadChannelMessages(channelId: channel.channelId)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(channel.channelName)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            if let lastMsg = channel.lastMessageAt {
                                                Text("Last message: \(String(lastMsg.prefix(10)))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if channel.unreadCount > 0 {
                                            Text("\(channel.unreadCount)")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.red)
                                                .foregroundStyle(.white)
                                                .clipShape(Capsule())
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }

                        // Active channel messages
                        if let channelId = activeChannelId {
                            Section("Messages") {
                                if channelMessages.isEmpty {
                                    Text("No messages yet. Send the first one below.")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                ForEach(channelMessages) { msg in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(msg.senderName)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                            Spacer()
                                            if let date = msg.createdAt {
                                                Text(String(date.prefix(16)))
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                        Text(msg.content)
                                            .font(.subheadline)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }

                            Section {
                                HStack {
                                    TextField("Type a message...", text: $newSupplierMessage)
                                        .textFieldStyle(.roundedBorder)
                                    Button {
                                        Task { await sendSupplierMessage(channelId: channelId) }
                                    } label: {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .accessibilityLabel("Send message")
                                    .disabled(newSupplierMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                        }
                    }
                } else {
                    // No existing channels — offer to create one
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "bubble.left.and.bubble.right")
                            .decorativeIconFont(48)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("No supplier channel yet")
                            .font(.headline)
                        Text("Create a bridge channel to communicate with this supplier about PO \(po?.poNumber ?? "").")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            Task { await createSupplierChannel() }
                        } label: {
                            Label("Create Supplier Channel", systemImage: "plus.bubble")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal, 32)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Contact Supplier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { activeSheet = nil }
                }
            }
            .task { loadSupplierChannels() }
        }
    }

    // MARK: - 2. Update ETA Sheet

    @ViewBuilder
    private func updateETASheet() -> some View {
        NavigationStack {
            Form {
                Section {
                    if let current = po?.expectedDelivery, !current.isEmpty {
                        HStack {
                            Text("Current ETA")
                            Spacer()
                            Text(current)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Text("Current ETA")
                            Spacer()
                            Text("Not set")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section("New Expected Delivery") {
                    DatePicker(
                        "Expected Delivery",
                        selection: $etaDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                }

                Section {
                    Button {
                        Task { await saveNewETA() }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Save New ETA", systemImage: "calendar.badge.checkmark")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .tint(.blue)
                }
            }
            .navigationTitle("Update ETA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                }
            }
            .onAppear {
                // Pre-populate with current ETA if available
                if let current = po?.expectedDelivery {
                    let fmt = ISO8601DateFormatter()
                    fmt.formatOptions = [.withFullDate]
                    if let date = fmt.date(from: String(current.prefix(10))) {
                        etaDate = date
                    }
                }
            }
        }
    }

    // MARK: - 3. Double Order Sheet

    @ViewBuilder
    private func doubleOrderSheet() -> some View {
        NavigationStack {
            Form {
                if let po {
                    Section("Current Order") {
                        HStack {
                            Text("PO")
                            Spacer()
                            Text(po.poNumber)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Current Supplier")
                            Spacer()
                            Text(po.supplierName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Remaining items summary
                    let remainingLines = po.lines.filter { $0.quantityOrdered > $0.quantityReceived }
                    Section("Remaining Items (\(remainingLines.count))") {
                        if remainingLines.isEmpty {
                            Text("All items have been received.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(remainingLines, id: \.id) { line in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(line.partName ?? "Item")
                                            .font(.subheadline)
                                        Text("Remaining: \(line.quantityOrdered - line.quantityReceived)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let price = line.unitPrice {
                                        Text(formatCurrency(price))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // Pick alternate supplier
                    Section("Select Alternate Supplier") {
                        if availableSuppliers.isEmpty {
                            Text("No other suppliers available.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(availableSuppliers, id: \.supplier.id) { swc in
                                let sup = swc.supplier
                                Button {
                                    selectedSupplierId = sup.id
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(sup.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text("\(swc.partCount) parts linked")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedSupplierId == sup.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .accessibilityLabel("Selected")
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundStyle(.tertiary)
                                                .accessibilityLabel("Not selected")
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }

                    Section {
                        Button {
                            Task { await createDoubleOrder() }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Create Double Order", systemImage: "doc.on.doc.fill")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(selectedSupplierId == nil || remainingLines.isEmpty)
                        .tint(.blue)
                    }
                }
            }
            .navigationTitle("Double Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                }
            }
            .task { loadAvailableSuppliers() }
        }
    }

    // MARK: - 4. Report Issue Sheet

    @ViewBuilder
    private func reportIssueSheet() -> some View {
        NavigationStack {
            Form {
                Section("PO Information") {
                    HStack {
                        Text("PO")
                        Spacer()
                        Text(po?.poNumber ?? "")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Supplier")
                        Spacer()
                        Text(po?.supplierName ?? "")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Issue Details") {
                    Picker("Severity", selection: $issueSeverity) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                        Text("Critical").tag("critical")
                    }

                    TextField("Describe the issue...", text: $issueDescription, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section {
                    Button {
                        Task { await submitIssueReport() }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Submit Issue Report", systemImage: "exclamationmark.triangle.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(issueDescription.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(.orange)
                }

                Section {
                    Text("This will create a note on the PO and log the issue for supplier tracking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        issueDescription = ""
                        issueSeverity = "medium"
                        activeSheet = nil
                    }
                }
            }
        }
    }

    // MARK: - 5. Receipt History Sheet

    @ViewBuilder
    private func receiptHistorySheet() -> some View {
        NavigationStack {
            Group {
                if receiptBatches.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "shippingbox")
                            .decorativeIconFont(48)
                            .foregroundStyle(.secondary)
                        Text("No receiving sessions recorded")
                            .font(.headline)
                        Text("Receiving sessions will appear here as shipments are checked in against this PO.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
                    List {
                        // Summary
                        Section {
                            let totalReceived = receiptBatches.reduce(0) { $0 + $1.totalReceived }
                            let totalOrdered = po?.lines.reduce(0) { $0 + $1.quantityOrdered } ?? 0
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Received")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(totalReceived) of \(totalOrdered) units")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Sessions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(receiptBatches.count)")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                            }
                        }

                        // Timeline
                        Section("Receiving Timeline") {
                            ForEach(receiptBatches) { batch in
                                HStack(alignment: .top, spacing: 12) {
                                    // Timeline dot and line
                                    VStack(spacing: 0) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 10, height: 10)
                                            .accessibilityHidden(true)
                                        if batch.id != receiptBatches.last?.id {
                                            Rectangle()
                                                .fill(Color.green.opacity(0.3))
                                                .frame(width: 2, height: 40)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(String(batch.receivedDate.prefix(10)))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("\(batch.itemCount) items, \(batch.totalReceived) units received")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let by = batch.receivedBy {
                                            HStack(spacing: 4) {
                                                Image(systemName: "person.circle")
                                                    .font(.caption2)
                                                Text(by)
                                                    .font(.caption2)
                                            }
                                            .foregroundStyle(.tertiary)
                                        }
                                    }

                                    Spacer()
                                }
                            }
                        }

                        // Per-line status
                        if let po {
                            let receivedLines = po.lines.filter { $0.quantityReceived > 0 }
                            if !receivedLines.isEmpty {
                                Section("Items Received") {
                                    ForEach(receivedLines, id: \.id) { line in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(line.partName ?? "Item")
                                                    .font(.subheadline)
                                                Text("Received \(line.quantityReceived) of \(line.quantityOrdered)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if line.quantityReceived >= line.quantityOrdered {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                                    .accessibilityLabel("Fully received")
                                            } else {
                                                Text("\(line.quantityOrdered - line.quantityReceived) remaining")
                                                    .font(.caption2)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Receipt History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { activeSheet = nil }
                }
            }
        }
    }

    // MARK: - 6. Contact Creator Sheet

    @ViewBuilder
    private func contactCreatorSheet() -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let po, !po.linkedJPOIds.isEmpty {
                    List {
                        Section("Linked Job Part Orders") {
                            ForEach(po.linkedJPOIds, id: \.self) { jpoId in
                                let detail = try? appCore.ordersService?.getJPODetail(id: jpoId)
                                if let detail {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("JPO #\(detail.id)")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                Text(detail.jobName)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            StatusBadge(text: detail.status.capitalized, color: statusColor(detail.status))
                                        }

                                        // Creator info
                                        HStack(spacing: 8) {
                                            Image(systemName: "person.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(.blue)
                                                .accessibilityHidden(true)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Created by")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Text(detail.requestedByName)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                            }
                                            Spacer()
                                        }

                                        // Action buttons
                                        HStack(spacing: 8) {
                                            Button {
                                                Task { await openDMWithCreator(userId: detail.requestedBy, name: detail.requestedByName) }
                                            } label: {
                                                Label("Send DM", systemImage: "message.fill")
                                                    .font(.caption)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 8)
                                                    .background(Color.blue.opacity(0.12))
                                                    .foregroundStyle(.blue)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                            .buttonStyle(.plain)

                                            if let notes = detail.notes, !notes.isEmpty {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Notes:")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                    Text(notes)
                                                        .font(.caption)
                                                        .lineLimit(2)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                } else {
                                    HStack {
                                        Text("JPO #\(jpoId)")
                                            .font(.subheadline)
                                        Spacer()
                                        Text("Details unavailable")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }

                        // Submitted by info (if different from JPO creator)
                        if let submitter = po.submittedByName {
                            Section("PO Submitted By") {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.green)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(submitter)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("Submitted this PO")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let submittedById = po.submittedBy {
                                        Button {
                                            Task { await openDMWithCreator(userId: submittedById, name: submitter) }
                                        } label: {
                                            Label("DM", systemImage: "message.fill")
                                                .font(.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.blue.opacity(0.12))
                                                .foregroundStyle(.blue)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // No linked JPOs
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "person.fill.questionmark")
                            .decorativeIconFont(48)
                            .foregroundStyle(.secondary)
                        Text("No linked Job Part Orders")
                            .font(.headline)
                        Text("This PO was not generated from a JPO, so there is no job creator to contact.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        // Still show submitted by if available
                        if let submitter = po?.submittedByName, let submittedById = po?.submittedBy {
                            Divider()
                                .padding(.horizontal, 32)
                            VStack(spacing: 8) {
                                Text("PO submitted by:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(submitter)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Button {
                                    Task { await openDMWithCreator(userId: submittedById, name: submitter) }
                                } label: {
                                    Label("Send DM to Submitter", systemImage: "message.fill")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundStyle(.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .padding(.horizontal, 32)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("Contact Creator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { activeSheet = nil }
                }
            }
        }
    }

    // MARK: - Sheet Actions

    private func loadSupplierChannels() {
        guard let chatService = appCore.chatService,
              let userId = appCore.currentUser?.id,
              let supplierId = po?.supplierId else {
            loadError = "Chat service not available"
            isLoading = false
            return
        }
        do {
            let allChannels = try chatService.listSupplierChannels(userId: userId)
            supplierChannels = allChannels.filter { $0.supplierId == supplierId }
            // Auto-select the first channel if only one exists
            if supplierChannels.count == 1, let first = supplierChannels.first {
                activeChannelId = first.channelId
                loadChannelMessages(channelId: first.channelId)
            }
        } catch {
            supplierChannels = []
        }
    }

    private func loadChannelMessages(channelId: Int64) {
        guard let chatService = appCore.chatService else {
            loadError = "Chat service not available"
            isLoading = false
            return
        }
        channelMessages = (try? chatService.getMessages(channelId: channelId, limit: 50)) ?? []
        // Reverse so oldest first
        channelMessages = channelMessages.reversed()
    }

    private func createSupplierChannel() async {
        guard let chatService = appCore.chatService,
              let userId = appCore.currentUser?.id,
              let po else {
            loadError = "Chat service not available"
            isLoading = false
            return
        }
        do {
            let channelName = "\(po.poNumber) — \(po.supplierName)"
            let channelId = try chatService.createSupplierChannel(
                name: channelName,
                supplierId: po.supplierId,
                supplierDisplayName: po.supplierName,
                contactId: nil,
                role: nil,
                createdBy: userId
            )
            activeChannelId = channelId
            loadSupplierChannels()
        } catch {
            actionMessage = userFriendlyError(error, context: "create channel")
        }
    }

    private func sendSupplierMessage(channelId: Int64) async {
        guard let chatService = appCore.chatService,
              let userId = appCore.currentUser?.id else {
            loadError = "Chat service not available"
            return
        }
        let text = newSupplierMessage.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        do {
            _ = try chatService.sendSupplierMessage(
                channelId: channelId,
                senderId: userId,
                content: text,
                direction: "outgoing"
            )
            newSupplierMessage = ""
            loadChannelMessages(channelId: channelId)
        } catch {
            actionMessage = userFriendlyError(error, context: "send")
        }
    }

    private func saveNewETA() async {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            actionMessage = "Service not available"
            return
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        let dateStr = fmt.string(from: etaDate)
        do {
            try service.updatePOExpectedDelivery(id: poId, expectedDelivery: dateStr)
            activeSheet = nil
            loadData()
            actionMessage = "ETA updated to \(dateStr)."
        } catch {
            actionMessage = userFriendlyError(error, context: "update eta")
        }
    }

    private func loadAvailableSuppliers() {
        guard let partsService = appCore.partsService,
              let currentSupplierId = po?.supplierId else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        do {
            let all = try partsService.listSuppliers()
            availableSuppliers = all.filter { $0.supplier.id != currentSupplierId }
        } catch {
            availableSuppliers = []
        }
    }

    private func createDoubleOrder() async {
        guard let service = appCore.ordersService,
              let po,
              let newSupplierId = selectedSupplierId else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }

        let remainingLines = po.lines.filter { $0.quantityOrdered > $0.quantityReceived }
        guard !remainingLines.isEmpty else { return }

        do {
            // Generate a new PO number
            let newPOs = try service.listPurchaseOrders(limit: 1)
            let count = (newPOs.first?.id ?? 0) + 1
            let poNumber = String(format: "PO-%05d", count)

            // Create the new PO
            let newPoId = try service.createPurchaseOrder(
                poNumber: poNumber,
                supplierId: newSupplierId,
                notes: "Double order from \(po.poNumber). Remaining items re-ordered with alternate supplier."
            )

            // Add remaining line items
            for line in remainingLines {
                guard let partId = line.partId else { continue }
                let remaining = line.quantityOrdered - line.quantityReceived
                try service.addPOLineItem(
                    poId: newPoId,
                    partId: partId,
                    quantity: remaining,
                    unitPrice: line.unitPrice
                )
            }

            // Add a note to the original PO
            let author = appCore.currentUser?.displayName ?? "System"
            try service.addPONote(
                poId: poId,
                note: "Double order created: \(poNumber) with alternate supplier for \(remainingLines.count) remaining items.",
                author: author
            )

            activeSheet = nil
            loadData()
            actionMessage = "Double order \(poNumber) created successfully."
        } catch {
            actionMessage = userFriendlyError(error, context: "create double order")
        }
    }

    private func submitIssueReport() async {
        guard let service = appCore.ordersService,
              let po else {
            loadError = "Orders service not available"
            return
        }
        let description = issueDescription.trimmingCharacters(in: .whitespaces)
        guard !description.isEmpty else { return }

        let author = appCore.currentUser?.displayName ?? "System"
        let noteText = "ISSUE REPORT [\(issueSeverity.uppercased())]: \(description)"

        do {
            // Add as a PO note with severity tag
            try service.addPONote(poId: poId, note: noteText, author: author)

            // Also try to create a notebook entry if notebooks service is available
            if let notebooksService = appCore.notebooksService,
               let userId = appCore.currentUser?.id {
                // Try to find or create a quality issues notebook
                let notebookId = try notebooksService.createNotebook(
                    title: "Quality Issues — \(po.supplierName)",
                    notebookType: "quality",
                    createdBy: userId
                )
                try notebooksService.addNotebookEntry(
                    notebookId: notebookId,
                    title: "\(po.poNumber): \(issueSeverity.capitalized) Issue",
                    content: description,
                    entryType: "issue",
                    createdBy: userId
                )
            }

            issueDescription = ""
            issueSeverity = "medium"
            activeSheet = nil
            loadData()
            actionMessage = "Issue report submitted and logged."
        } catch {
            actionMessage = userFriendlyError(error, context: "submit issue")
        }
    }

    private func openDMWithCreator(userId: Int64, name: String) async {
        guard let chatService = appCore.chatService,
              let myId = appCore.currentUser?.id else {
            loadError = "Chat service not available"
            actionMessage = "Chat service not available."
            return
        }

        do {
            // Create a DM channel for this conversation
            let channelName = "DM — \(name)"
            let channelId = try chatService.createChannel(
                name: channelName,
                channelType: "dm",
                createdBy: myId
            )
            // Add the other user to the channel
            try chatService.addUserToSupplierChannel(channelId: channelId, userId: userId)

            activeSheet = nil
            actionMessage = "DM channel created with \(name). Open Chat to continue the conversation."
        } catch {
            actionMessage = userFriendlyError(error, context: "create dm")
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

                // Job-Grouped Line Items
                lineItemsSection(po)

                // Receipt History (62P — collapsible, shows when any receiving data exists)
                receiptHistorySection()

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

    // MARK: - Job-Grouped Line Items

    /// Group PO line items by job, with "General Stock" always sorted last.
    private func groupedLineItems(_ lines: [OrdersService.POLineRow]) -> [(jobName: String, items: [OrdersService.POLineRow])] {
        let grouped = Dictionary(grouping: lines) { $0.jobName ?? "General Stock" }
        return grouped.sorted {
            // "General Stock" always sorts last
            if $0.key == "General Stock" { return false }
            if $1.key == "General Stock" { return true }
            return $0.key < $1.key
        }.map { (jobName: $0.key, items: $0.value) }
    }

    @ViewBuilder
    private func lineItemsSection(_ po: OrdersService.PODetail) -> some View {
        let groups = groupedLineItems(po.lines)

        VStack(alignment: .leading, spacing: 12) {
            Text("Line Items (\(po.lines.count))")
                .font(.headline)

            ForEach(groups, id: \.jobName) { group in
                VStack(alignment: .leading, spacing: 4) {
                    // Job section header with name and item count
                    HStack {
                        Image(systemName: jobGroupIcon(group.jobName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(group.jobName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(group.items.count) \(group.items.count == 1 ? "item" : "items")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)

                    // Lines for this job
                    ForEach(group.items, id: \.id) { line in
                        lineItemRow(line, isDraft: po.status == "draft",
                                    expectedDelivery: po.expectedDelivery)
                    }
                }
            }
        }
    }

    /// Icon for job group header based on source type.
    private func jobGroupIcon(_ jobName: String) -> String {
        switch jobName {
        case "Forecast Restock": "chart.line.uptrend.xyaxis"
        case "Wishlist": "heart"
        case "General", "General Stock": "shippingbox"
        default: "wrench.and.screwdriver"
        }
    }

    // MARK: - Line Item Row

    @ViewBuilder
    private func lineItemRow(_ line: OrdersService.POLineRow, isDraft: Bool, expectedDelivery: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Status icon
                lineStatusIcon(line.lineStatus)

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
                                .accessibilityHidden(true)
                            Text("Price not verified recently")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("Qty: \(line.quantityOrdered)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if line.quantityReceived > 0 {
                            Text("Received: \(line.quantityReceived)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer()

                if let price = line.unitPrice {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatCurrency(price))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(price * Double(line.quantityOrdered)))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }

            // Delivery timeline bar (62O — shows for all non-cancelled/non-draft statuses)
            if line.lineStatus == "pending" || line.lineStatus == "ordered"
                || line.lineStatus == "received" || line.lineStatus == "backorder" {
                DeliveryTimelineBar(
                    orderDateString: line.createdAt,
                    expectedDateString: expectedDelivery,
                    isReceived: line.lineStatus == "received"
                )
            }

            // Backorder actions (per line item)
            if line.lineStatus == "backorder" {
                HStack(spacing: 8) {
                    Button {
                        activeSheet = .updateETA
                    } label: {
                        Label("Update ETA", systemImage: "calendar.badge.clock")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button {
                        activeSheet = .doubleOrder
                    } label: {
                        Label("Double Order", systemImage: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                .padding(.top, 2)
            }

            // Inline editing (for draft POs only)
            if isDraft {
                HStack(spacing: 8) {
                    Button {
                        activeSheet = .editLineItem(line)
                    } label: {
                        Label("Edit Qty / Price", systemImage: "pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.accentColor)
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .dsCard()
    }

    // MARK: - Line Status Icon

    @ViewBuilder
    private func lineStatusIcon(_ status: String) -> some View {
        switch status {
        case "received":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
                .accessibilityLabel("Status: received")
        case "backorder":
            Image(systemName: "clock.badge.exclamationmark.fill")
                .foregroundStyle(.red)
                .font(.body)
                .accessibilityLabel("Status: backorder")
        case "pending", "ordered":
            Image(systemName: "hourglass")
                .foregroundStyle(.blue)
                .font(.body)
                .accessibilityLabel("Status: pending")
        case "cancelled":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.body)
                .accessibilityLabel("Status: cancelled")
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.body)
                .accessibilityLabel("Status: unknown")
        }
    }

    // MARK: - Delivery Timeline Bar
    // Now uses the shared DeliveryTimelineBar component (62O).
    // See Shared/DeliveryTimelineBar.swift for the reusable component.

    // MARK: - Receipt History Section (62P — collapsible with per-item details)

    @ViewBuilder
    private func receiptHistorySection() -> some View {
        let hasEntries = !receiptHistoryEntries.isEmpty
        let hasBatches = !receiptBatches.isEmpty

        if hasEntries || hasBatches {
            VStack(alignment: .leading, spacing: 8) {
                // Collapsible header
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isReceiptHistoryExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("Receipt History")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        let totalSessions = hasEntries ? receiptHistoryEntries.count : receiptBatches.count
                        Text("(\(totalSessions))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Discrepancy badge
                        if hasEntries {
                            let discrepancyCount = receiptHistoryEntries.filter(\.hasDiscrepancies).count
                            if discrepancyCount > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                    Text("\(discrepancyCount)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                }
                                .foregroundStyle(.orange)
                            }
                        }

                        Image(systemName: isReceiptHistoryExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                // Expanded content
                if isReceiptHistoryExpanded {
                    if hasEntries {
                        // 62P: Rich entries from receiving_sessions
                        ForEach(receiptHistoryEntries) { entry in
                            receiptEntryRow(entry)
                        }
                    } else {
                        // Fallback: legacy batches from order_status_history
                        ForEach(receiptBatches) { batch in
                            legacyBatchRow(batch)
                        }
                    }
                }
            }
            .padding()
            .dsCard()
        }
    }

    /// A single receipt entry row (62P) — tappable to expand per-item details.
    @ViewBuilder
    private func receiptEntryRow(_ entry: OrdersService.ReceiptHistoryEntry) -> some View {
        let isExpanded = expandedReceiptEntryIds.contains(entry.id)

        VStack(alignment: .leading, spacing: 6) {
            // Tappable summary row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedReceiptEntryIds.remove(entry.id)
                    } else {
                        expandedReceiptEntryIds.insert(entry.id)
                        // Load items if not already loaded
                        if receiptEntryItems[entry.id] == nil {
                            loadReceiptEntryItems(sessionId: entry.id)
                        }
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    // Timeline dot
                    Circle()
                        .fill(entry.hasDiscrepancies ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                        .accessibilityLabel(entry.hasDiscrepancies ? "Has discrepancies" : "Received")

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(formatSessionDate(entry.sessionDate))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Spacer()
                            if entry.hasDiscrepancies {
                                HStack(spacing: 2) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                    Text("Discrepancy")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(.orange)
                            }
                        }

                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "shippingbox")
                                    .font(.caption2)
                                Text("\(entry.totalItemsReceived) units")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)

                            HStack(spacing: 4) {
                                Image(systemName: "person.circle")
                                    .font(.caption2)
                                Text(entry.receivedBy)
                                    .font(.caption2)
                            }
                            .foregroundStyle(.tertiary)
                        }

                        if let notes = entry.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }
            }
            .buttonStyle(.plain)

            // Per-item details (expanded)
            if isExpanded {
                if let items = receiptEntryItems[entry.id], !items.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            receiptItemDetailRow(item)
                            if item.id != items.last?.id {
                                Divider()
                                    .padding(.leading, 18)
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.leading, 18)
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading items...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.leading, 18)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(entry.hasDiscrepancies ? Color.orange.opacity(0.06) : Color.clear)
        )
    }

    /// Per-item detail row within a receipt entry.
    @ViewBuilder
    private func receiptItemDetailRow(_ item: OrdersService.ReceiptHistoryItem) -> some View {
        HStack(spacing: 8) {
            // Discrepancy indicator
            if item.hasDiscrepancy {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Has discrepancy")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Received correctly")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.partName)
                    .font(.caption)
                    .fontWeight(.medium)
                if let code = item.partCode, !code.isEmpty {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 2) {
                    Text("\(item.receivedQty)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(item.hasDiscrepancy ? .orange : .primary)
                    Text("/")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(item.expectedQty)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if item.hasDiscrepancy {
                    let diff = item.receivedQty - item.expectedQty
                    Text(diff > 0 ? "+\(diff) over" : "\(-diff) short")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(diff > 0 ? .blue : .red)
                }
            }

            if let notes = item.notes, !notes.isEmpty {
                Image(systemName: "note.text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(notes)
                    .accessibilityLabel("Has notes")
            }
        }
        .padding(.vertical, 4)
    }

    /// Legacy batch row fallback (from order_status_history).
    @ViewBuilder
    private func legacyBatchRow(_ batch: OrdersService.ReceiptBatch) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Received \(String(batch.receivedDate.prefix(10)))")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("\(batch.itemCount) items, \(batch.totalReceived) total units")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let by = batch.receivedBy {
                    Text("By: \(by)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
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
                            .foregroundStyle(Color.accentColor)
                    }
                    .disabled(newNoteText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add note")
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
                    actionButton("Mark as Submitted", icon: "checkmark.circle.fill", color: .blue) {
                        showSubmitConfirmation = true
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
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            actionMessage = "Service not available"
            return
        }
        do {
            try service.updatePOStatus(id: poId, status: newStatus)
            loadData()
            if newStatus == "submitted" {
                actionMessage = "PO marked as Submitted. Remember to send the order to the supplier."
            }
        } catch {
            actionMessage = userFriendlyError(error, context: "update status")
        }
    }

    private func deleteDraftPO() async {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            actionMessage = "Service not available"
            return
        }
        do {
            try service.deletePO(id: poId)
            dismiss()
        } catch {
            actionMessage = userFriendlyError(error, context: "delete draft")
        }
    }

    // MARK: - Line Edit (via Sheet)

    private func saveLineEdit(lineId: Int64, quantity: Int, unitPrice: Double?) async {
        guard let service = appCore.ordersService else {
            actionMessage = "Service not available"
            return
        }
        do {
            try service.updatePOLineItem(lineId: lineId, quantity: quantity, unitPrice: unitPrice)
            loadData()
        } catch {
            actionMessage = userFriendlyError(error, context: "update")
        }
    }

    // MARK: - Notes Actions

    private func addPONote() async {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            actionMessage = "Service not available"
            return
        }
        let author = appCore.currentUser?.displayName ?? "Unknown"
        do {
            try service.addPONote(poId: poId, note: newNoteText, author: author)
            newNoteText = ""
            loadData()
        } catch {
            actionMessage = userFriendlyError(error, context: "add note")
        }
    }

    // MARK: - Receipt History Helpers (62P)

    /// Load per-item details for a specific receipt session.
    private func loadReceiptEntryItems(sessionId: Int64) {
        guard let service = appCore.ordersService else { loadError = "Service not available"; return }
        receiptEntryItems[sessionId] = (try? service.getReceiptHistoryItems(sessionId: sessionId)) ?? []
    }

    /// Format a session date string for display (e.g. "Mar 15, 2026 2:30 PM").
    private func formatSessionDate(_ dateStr: String) -> String {
        // Try full datetime first, then date-only
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoDate = ISO8601DateFormatter()
        isoDate.formatOptions = [.withFullDate]

        let date = isoFull.date(from: dateStr)
            ?? isoDate.date(from: String(dateStr.prefix(10)))

        guard let date else { return String(dateStr.prefix(16)) }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Date Helpers

    private func daysSince(_ dateStr: String?) -> Int {
        guard let str = dateStr else { return 0 }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        guard let date = fmt.date(from: String(str.prefix(10))) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0)
    }

    private func daysUntil(_ dateStr: String?) -> Int? {
        guard let str = dateStr else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        guard let date = fmt.date(from: String(str.prefix(10))) else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: date).day
    }

    // MARK: - General Helpers

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

            // Load receipt history (legacy batches)
            receiptBatches = (try? service.getReceiptHistory(poId: poId)) ?? []

            // Load receipt history entries from receiving_sessions (62P)
            receiptHistoryEntries = (try? service.getReceiptHistoryEntries(poId: poId)) ?? []
        } catch {
            loadError = userFriendlyError(error, context: "load PO details")
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

// MARK: - PO Line Edit Sheet

/// Full-featured sheet for editing a PO draft line item's quantity and unit price.
/// Replaces the old cramped `.alert` with text fields.
private struct POLineEditSheet: View {
    let lineItem: OrdersService.POLineRow
    let onSave: (Int, Double?) -> Void

    @State private var quantity: Int
    @State private var unitPriceText: String
    @Environment(\.dismiss) private var dismiss

    init(lineItem: OrdersService.POLineRow, onSave: @escaping (Int, Double?) -> Void) {
        self.lineItem = lineItem
        self.onSave = onSave
        _quantity = State(initialValue: lineItem.quantityOrdered)
        _unitPriceText = State(initialValue: lineItem.unitPrice.map { String(format: "%.2f", $0) } ?? "")
    }

    private var parsedPrice: Double? {
        Double(unitPriceText)
    }

    private var lineTotal: Double {
        Double(quantity) * (parsedPrice ?? 0)
    }

    private var isValid: Bool {
        quantity > 0 && (unitPriceText.isEmpty || parsedPrice != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Part info (read-only context)
                Section("Part") {
                    HStack {
                        Text(lineItem.partName ?? "Item")
                            .font(.headline)
                        Spacer()
                        if let desc = lineItem.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if let jobName = lineItem.jobName {
                        HStack {
                            Text("Job")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(jobName)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }

                // Quantity with stepper
                Section("Quantity") {
                    Stepper(value: $quantity, in: 1...99999) {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text("\(quantity)")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }

                // Unit price text field
                Section("Unit Price") {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $unitPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if !unitPriceText.isEmpty && parsedPrice == nil {
                        Text("Enter a valid number")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // Live total preview
                Section("Line Total") {
                    HStack {
                        Text("Total")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatCurrency(lineTotal))
                            .font(.title2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle("Edit Line Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(quantity, parsedPrice)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}
