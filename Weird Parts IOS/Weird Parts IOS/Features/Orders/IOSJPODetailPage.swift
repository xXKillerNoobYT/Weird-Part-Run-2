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

    // Hold + chat (single item)
    @State private var holdQuestion = ""
    @State private var showHoldPrompt = false
    @State private var holdingLineId: Int64?
    @State private var holdingPartName: String?

    // Bulk hold
    @State private var bulkHoldReason = ""
    @State private var bulkHoldItems: [OrdersService.JPOLineRow] = []
    @State private var isBulkHolding = false

    // Smart routing — stock check before approval
    @State private var showBelowMinWarning = false
    @State private var pendingTransferLine: OrdersService.JPOLineRow?

    private enum ActiveSheet: Identifiable {
        case addLineItem
        case viewChat(Int64)
        case viewPO(Int64)
        case viewMovement(Int64)
        case bulkHold([OrdersService.JPOLineRow])
        case help

        var id: String {
            switch self {
            case .addLineItem:
                "addLineItem"
            case .viewChat(let channelId):
                "viewChat-\(channelId)"
            case .viewPO(let poId):
                "viewPO-\(poId)"
            case .viewMovement(let movementId):
                "viewMovement-\(movementId)"
            case .bulkHold(let items):
                IOSJPODetailBulkHoldSelection.sheetIdentifier(for: items)
            case .help:
                "help"
            }
        }
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
        // Reject confirmation with required reason
        .alert("Reject Part?", isPresented: $showRejectConfirm) {
            TextField("Reason (required)", text: $rejectReason)
            Button("Cancel", role: .cancel) { rejectReason = "" }
            Button("Reject", role: .destructive) {
                guard !rejectReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
        // Hold question prompt
        .alert("Ask About This Part", isPresented: $showHoldPrompt) {
            TextField("Your question...", text: $holdQuestion)
            Button("Cancel", role: .cancel) { holdQuestion = "" }
            Button("Hold + Send Question") {
                guard !holdQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                createHoldWithChat()
            }
        } message: {
            if let name = holdingPartName {
                Text("Ask the requester about \"\(name)\". They'll be notified to respond in chat.")
            }
        }
        
        // Below-min stock warning — approve with transfer vs procurement
        .alert("Stock Warning", isPresented: $showBelowMinWarning) {
            Button("Transfer Anyway") {
                if let line = pendingTransferLine {
                    executeStockTransfer(line)
                    pendingTransferLine = nil
                }
            }
            Button("Send to Procurement") {
                if let line = pendingTransferLine {
                    sendToProcurement(line.id)
                    pendingTransferLine = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingTransferLine = nil
            }
        } message: {
            Text("Pulling this quantity will bring shop stock below minimum level. Transfer anyway or send to procurement for ordering?")
        }
        // Error alert
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onDisappear {
            NotificationCenter.default.post(name: .jpoDetailPageInactive, object: nil)
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .addLineItem:
            AddJPOLineItemSheet(jpoId: jpoId, onSave: { loadData() })
                .environmentObject(appCore)
        case .viewChat(let channelId):
            NavigationStack {
                IOSMessageThreadView(channelId: channelId, channelName: "Hold Q&A")
                    .environmentObject(appCore)
            }
        case .viewPO(let poId):
            NavigationStack {
                IOSPODetailPage(poId: poId)
                    .environmentObject(appCore)
            }
        case .viewMovement(let movementId):
            NavigationStack {
                JPOMovementDetailContent(movementId: movementId)
                    .environmentObject(appCore)
                    .navigationTitle("Movement")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { activeSheet = nil }
                        }
                    }
            }
        case .bulkHold(let items):
            NavigationStack {
                Form {
                    Section("Items to Hold (\(items.count))") {
                        ForEach(items, id: \.id) { item in
                            HStack {
                                Text(item.partName ?? "Unknown Part")
                                Spacer()
                                Text("Qty: \(item.quantity)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Hold Reason") {
                        TextEditor(text: $bulkHoldReason)
                            .frame(minHeight: 80)
                    }
                }
                .navigationTitle("Place Items on Hold")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            activeSheet = nil
                            bulkHoldItems = []
                            bulkHoldReason = ""
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hold All") {
                            Task { await bulkHoldAllItems() }
                        }
                        .disabled(bulkHoldReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBulkHolding)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .interactiveDismissDisabled(!bulkHoldReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBulkHolding)
            }
        case .help:
            PageHelpSheet(
                title: "JPO Detail Help",
                sections: [
                    ("What This Page Does", "Shows all the line items in a Job Purchase Order. You can approve, hold, or reject individual parts, and use bulk actions to handle multiple items at once."),
                    ("How to Use It", "Tap the checkbox next to items to select them for bulk actions. Use Approve to send a part to procurement or trigger a shop transfer. Use Hold to ask the requester a question (opens a chat thread). Use Reject with a required reason."),
                    ("Smart Routing", "When you approve a line, the system checks shop stock. If the shop has enough, it creates a warehouse transfer automatically. If pulling would drop stock below minimum, you get a warning with the choice to transfer anyway or send to procurement for ordering."),
                    ("Delivery Options", "Choose 'Deliver as parts arrive' to send partial shipments to the job site, or 'Wait for complete order' to hold everything until all parts are in. This locks once the first delivery goes out."),
                    ("Tips", "Use the + button to add more parts to this JPO. Tap 'View Chat' on held items to see the Q&A thread. The status summary at the top gives you a quick count of pending, held, approved, and rejected items.")
                ]
            )
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
                    StatusBadge(text: jpo.priority.capitalized, color: priorityColor(jpo.priority, dueDate: jpo.dueDate))
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
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selectedLineIds.contains(line.id) ? "Deselect line item" : "Select line item")
                .accessibilityAddTraits(selectedLineIds.contains(line.id) ? .isSelected : [])

                // Status icon
                lineStatusIcon(line.lineStatus)

                // Part info
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.partName ?? "Unknown Part")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    HStack(spacing: 6) {
                        Text("Qty: \(line.quantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if line.brandSelectionMode == "general" {
                            // Brand deferred to PO creation (#242)
                            Label("General", systemImage: "circle.dashed")
                                .font(.caption2)
                                .foregroundStyle(.teal)
                        }
                    }
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

                Button {
                    holdingLineId = line.id
                    holdingPartName = line.partName ?? "Part"
                    showHoldPrompt = true
                } label: {
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    Text("In stock — transfer request created")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                HStack(spacing: 8) {
                    Button {
                        holdingLineId = line.id
                        holdingPartName = line.partName ?? "Part"
                        showHoldPrompt = true
                    } label: {
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
            }

        case "on_hold":
            VStack(alignment: .leading, spacing: 4) {
                if let reason = line.holdReason {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // Discussion link to the hold chat thread
                if let threadId = line.chatThreadId {
                    Button { activeSheet = .viewChat(threadId) } label: {
                        Label("Discussion", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 8) {
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
                    .accessibilityHidden(true)
                Text("Rejected: \(line.rejectReason ?? "No reason")")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        case "approved":
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Approved — awaiting procurement")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        case "ordered":
            HStack(spacing: 4) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text("Ordered")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

        case "received":
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Received at shop")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        case "delivered":
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Delivered to job")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        case "backorder":
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
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
                .accessibilityHidden(true)
        case "approved":
            Image(systemName: "checkmark.circle").foregroundStyle(.green)
                .accessibilityHidden(true)
        case "on_hold":
            Image(systemName: "pause.circle.fill").foregroundStyle(.yellow)
                .accessibilityHidden(true)
        case "rejected":
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                .accessibilityHidden(true)
        case "transfer":
            Image(systemName: "arrow.right.circle.fill").foregroundStyle(.blue)
                .accessibilityHidden(true)
        case "ordered", "in_procurement":
            Image(systemName: "shippingbox").foregroundStyle(.blue)
                .accessibilityHidden(true)
        case "received":
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityHidden(true)
        case "backorder":
            Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.red)
                .accessibilityHidden(true)
        case "delivered":
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                .accessibilityHidden(true)
        default:
            Image(systemName: "circle").foregroundStyle(.secondary)
                .accessibilityHidden(true)
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

    /// Smart-route a JPO line: check shop stock before sending to procurement.
    /// - If shop has enough AND it won't drop below MIN -> create warehouse transfer
    /// - If shop has enough but would drop below MIN -> show warning, let user choose
    /// - If shop doesn't have enough -> send to procurement (existing behavior)
    private func approveLine(_ lineId: Int64) {
        // Find the line in the current JPO data
        guard let line = jpo?.lines.first(where: { $0.id == lineId }) else {
            // Fallback: just approve normally
            sendToProcurement(lineId)
            return
        }

        guard let partId = line.partId else {
            // No part linked — can't check stock, send to procurement
            sendToProcurement(lineId)
            return
        }

        // Check shop stock for this part
        do {
            let warehouseStock = try appCore.warehouseService?.getStockQty(
                partId: partId, locationType: "warehouse", locationId: 1
            ) ?? 0

            let requestedQty = line.quantity

            if warehouseStock >= requestedQty {
                // Shop has enough — check if it would drop below MIN
                let minStock = try getPartMinStock(partId: partId)
                let remainingAfterTransfer = warehouseStock - requestedQty

                if minStock > 0 && remainingAfterTransfer < minStock {
                    // Would drop below min — show warning
                    pendingTransferLine = line
                    showBelowMinWarning = true
                } else {
                    // Safe to transfer — won't drop below min
                    executeStockTransfer(line)
                }
            } else {
                // Not enough stock — send to procurement
                sendToProcurement(lineId)
            }
        } catch {
            // On error, fall back to standard procurement flow
            actionError = userFriendlyError(error, context: "process order")
            sendToProcurement(lineId)
        }
    }

    /// Execute a warehouse-to-pulled transfer for a JPO line and mark it as "transfer".
    private func executeStockTransfer(_ line: OrdersService.JPOLineRow) {
        guard let warehouseService = appCore.warehouseService,
              let ordersService = appCore.ordersService,
              let partId = line.partId,
              let userId = appCore.currentUser?.id else {
            loadError = "Warehouse service not available"
            sendToProcurement(line.id)
            return
        }

        do {
            // Create a warehouse -> pulled movement for this part
            let movementId = try warehouseService.createMovement(
                partId: partId,
                qty: line.quantity,
                fromLocationType: "warehouse",
                fromLocationId: 1,
                toLocationType: "pulled",
                toLocationId: 1,
                movementType: StockMovement.MovementType.transfer.rawValue,
                reason: "JPO smart route — in stock",
                notes: "Auto-transfer from JPO #\(line.jpoId), line #\(line.id)",
                performedBy: userId
            )

            // Update the JPO line to "transfer" status and link the movement
            try ordersService.updateJPOLineStatus(
                lineId: line.id,
                status: "transfer",
                updatedBy: userId
            )

            // Store the transfer_id on the line for cancel support
            try linkTransferToLine(lineId: line.id, transferId: movementId)

            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "process order")
        }
    }

    /// Send a line to procurement by setting its status to "approved".
    private func sendToProcurement(_ lineId: Int64) {
        guard let service = appCore.ordersService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.updateJPOLineStatus(
                lineId: lineId,
                status: "approved",
                updatedBy: appCore.currentUser?.id
            )
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "process order")
        }
    }

    /// Get the min_stock_level for a part.
    private func getPartMinStock(partId: Int64) throws -> Int {
        guard let partsService = appCore.partsService else {
            loadError = "Parts service not available"
            return 0
        }
        let detail = try partsService.getPart(id: partId)
        return detail.part.minStockLevel ?? 0
    }

    /// Link a movement (transfer) ID to a JPO line item for later cancellation.
    private func linkTransferToLine(lineId: Int64, transferId: Int64) throws {
        guard let ordersService = appCore.ordersService else {
            loadError = "Orders service not available"
            return
        }
        // Use the existing updateJPOLineStatus mechanism — the transfer_id column
        // exists on jpo_line_items. We write directly since ordersService doesn't
        // expose a dedicated setter.
        try ordersService.setJPOLineTransferId(lineId: lineId, transferId: transferId)
    }

    private func createHoldWithChat() {
        guard let service = appCore.ordersService,
              let lineId = holdingLineId,
              let jpo = jpo,
              let userId = appCore.currentUser?.id else {
            loadError = "Orders service not available"
            holdQuestion = ""
            return
        }
        do {
            // If the line was in "transfer" status, cancel the pending movement first
            if let line = jpo.lines.first(where: { $0.id == lineId }),
               line.lineStatus == "transfer",
               let warehouseService = appCore.warehouseService {
                try service.cancelJPOLineTransfer(
                    lineId: lineId,
                    reversedBy: userId,
                    warehouseService: warehouseService
                )
            }

            let channelId = try service.holdJPOLineWithChat(
                lineId: lineId,
                holdReason: holdQuestion,
                userId: userId,
                partName: holdingPartName ?? "Part",
                jpoId: jpo.id
            )

            // Also create a jpo_hold typed thread in ChatService for
            // unified inbox visibility with HOLD badge
            if let chatService = appCore.chatService {
                let jpoNumber = "JPO #\(jpo.id) Line #\(lineId)"
                _ = try chatService.createJPOHoldThread(
                    partName: holdingPartName ?? "Part",
                    jpoNumber: jpoNumber,
                    holdReason: holdQuestion,
                    userId: userId
                )
            }

            holdQuestion = ""
            holdingLineId = nil
            holdingPartName = nil
            loadData()
            activeSheet = .viewChat(channelId)
        } catch {
            holdQuestion = ""
            actionError = userFriendlyError(error, context: "process order")
        }
    }

    private func rejectLine(_ lineId: Int64, reason: String) {
        guard let service = appCore.ordersService else {
            actionError = "Service not available"
            return
        }
        do {
            // If the line was in "transfer" status, cancel the pending movement first
            if let line = jpo?.lines.first(where: { $0.id == lineId }),
               line.lineStatus == "transfer",
               let warehouseService = appCore.warehouseService,
               let userId = appCore.currentUser?.id {
                try service.cancelJPOLineTransfer(
                    lineId: lineId,
                    reversedBy: userId,
                    warehouseService: warehouseService
                )
            }

            try service.updateJPOLineStatus(lineId: lineId, status: "rejected",
                                            reason: reason,
                                            updatedBy: appCore.currentUser?.id)
            loadData()
        } catch { actionError = userFriendlyError(error, context: "process order") }
    }

    private func approveSelected() {
        for lineId in selectedLineIds { approveLine(lineId) }
        selectedLineIds.removeAll()
    }

    private func holdSelected() {
        // Collect ALL selected items and show the bulk hold sheet with the
        // selected rows embedded in the sheet identity. This prevents SwiftUI
        // from presenting a fresh `.bulkHold` sheet before the separate
        // `bulkHoldItems` state write has rendered, which produced an empty
        // "Items to Hold (0)" sheet while the action bar still said "2 selected".
        guard let jpo else { return }
        let items = IOSJPODetailBulkHoldSelection.selectedHoldItems(
            from: jpo.lines,
            selectedLineIds: selectedLineIds
        )
        guard !items.isEmpty else { return }
        bulkHoldItems = items
        bulkHoldReason = ""
        activeSheet = .bulkHold(items)
    }

    /// Apply the same hold reason to ALL items in bulkHoldItems, cancelling
    /// any pending transfers first. Creates an idempotent legacy hold chat for
    /// every selected line and a typed hold thread for unified inbox visibility.
    @MainActor
    private func bulkHoldAllItems() async {
        guard let service = appCore.ordersService,
              let userId = appCore.currentUser?.id else {
            actionError = "Service not available"
            return
        }

        let reason = bulkHoldReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }

        isBulkHolding = true
        defer { isBulkHolding = false }

        var failedTransferCancellationLineIds = Set<Int64>()
        for item in bulkHoldItems {
            do {
                // If the line was in "transfer" status, cancel the pending movement first
                if item.lineStatus == "transfer",
                   let warehouseService = appCore.warehouseService {
                    try service.cancelJPOLineTransfer(
                        lineId: item.id,
                        reversedBy: userId,
                        warehouseService: warehouseService
                    )
                }
            } catch {
                failedTransferCancellationLineIds.insert(item.id)
            }
        }

        let processableHoldItems = IOSJPODetailBulkHoldSelection.processableHoldItems(
            from: bulkHoldItems,
            failedTransferCancellationLineIds: failedTransferCancellationLineIds
        )

        do {
            guard !processableHoldItems.isEmpty else {
                actionError = "Unable to hold selected lines because transfer cancellation failed."
                return
            }

            _ = try service.bulkHoldJPOLinesWithChat(
                lineIds: processableHoldItems.map(\.id),
                holdReason: reason,
                userId: userId
            )

            if let chatService = appCore.chatService, let jpo {
                for item in processableHoldItems {
                    let jpoNumber = "JPO #\(jpo.id) Line #\(item.id)"
                    _ = try chatService.createJPOHoldThread(
                        partName: item.partName ?? "Part",
                        jpoNumber: jpoNumber,
                        holdReason: reason,
                        userId: userId
                    )
                }
            }

            if !failedTransferCancellationLineIds.isEmpty {
                let failedList = failedTransferCancellationLineIds.sorted().map(String.init).joined(separator: ", ")
                actionError = "Some lines were not held because transfer cancellation failed (line IDs: \(failedList))."
            }
        } catch {
            actionError = userFriendlyError(error, context: "process order")
        }

        // Clean up state
        selectedLineIds.removeAll()
        bulkHoldItems = []
        bulkHoldReason = ""
        activeSheet = nil
        loadData()
    }

    private func rejectSelected(reason: String) {
        for lineId in selectedLineIds { rejectLine(lineId, reason: reason) }
        selectedLineIds.removeAll()
    }

    private func updateDeliveryOption(_ option: String) {
        guard let service = appCore.ordersService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.updateJPODeliveryOption(jpoId: jpoId, option: option)
            loadData()
        } catch { actionError = userFriendlyError(error, context: "process order") }
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
    private func priorityColor(_ priority: String, dueDate: String?) -> Color {
        if dueDate != nil {
            return TimelinePriorityColor.color(priority: priority, dueDateString: dueDate)
        }
        return TimelinePriorityColor.fallbackColor(priority: priority)
    }

    private func formatCurrency(_ value: Double) -> String {
        Formatters.formatCurrency(value)
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
            let detail = try service.getJPODetail(id: jpoId)
            jpo = detail
            postAIContext(detail)
        } catch {
            loadError = userFriendlyError(error, context: "load JPO details")
        }
        isLoading = false
    }

    private func postAIContext(_ detail: OrdersService.JPODetail) {
        let statusCounts = Dictionary(grouping: detail.lines, by: \.lineStatus)
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let context = [
            "JPO detail page is open for JPO #\(detail.id).",
            "Job: \(detail.jobName). Status: \(detail.status). Priority: \(detail.priority). Delivery: \(detail.deliveryOption ?? "unset").",
            "Line items: \(detail.lines.count). Line status counts: \(statusCounts.isEmpty ? "none" : statusCounts).",
            "Delivery locked: \(detail.deliveryLocked ? "yes" : "no").",
            "This context is read-only; explain approval state, line status, holds, delivery preference, and next review steps without changing the JPO."
        ].joined(separator: " ")
        NotificationCenter.default.post(
            name: .jpoDetailPageActive,
            object: nil,
            userInfo: ["context": context]
        )
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
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(selectedPart != nil || !notes.isEmpty)
        }
    }

    private func searchParts() {
        guard let service = appCore.partsService, searchText.count >= 2 else {
            if appCore.partsService == nil { errorMessage = "Parts service not available" }
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
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "process order")
        }
    }
}

// MARK: - Movement Detail Content

private struct JPOMovementDetailContent: View {
    @EnvironmentObject var appCore: AppCore
    let movementId: Int64

    @State private var movement: WarehouseService.MovementRow?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading movement...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error",
                    message: error
                )
            } else if let m = movement {
                List {
                    Section("Movement Info") {
                        LabeledContent("Type", value: StockMovement.MovementType.displayName(forRawValue: m.movementType))
                        LabeledContent("Quantity", value: "\(m.qty)")
                        if let reason = m.reason, !reason.isEmpty {
                            LabeledContent("Reason", value: reason)
                        }
                    }

                    Section("Part") {
                        LabeledContent("Name", value: m.partName)
                    }

                    Section("Locations") {
                        if let fromType = m.fromLocationType {
                            LabeledContent("From", value: "\(fromType.capitalized) #\(m.fromLocationId ?? 0)")
                        }
                        if let toType = m.toLocationType {
                            LabeledContent("To", value: "\(toType.capitalized) #\(m.toLocationId ?? 0)")
                        }
                    }

                    Section("Details") {
                        if let byName = m.performedByName, !byName.isEmpty {
                            LabeledContent("Performed By", value: byName)
                        }
                        if let date = m.createdAt {
                            LabeledContent("Date", value: String(date.prefix(16)))
                        }
                        if let notes = m.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(notes)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                EmptyStateView(
                    icon: "questionmark.circle",
                    title: "Movement Not Found",
                    message: "Movement #\(movementId) could not be loaded."
                )
            }
        }
        .task { loadMovement() }
    }

    private func loadMovement() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            isLoading = false
            return
        }
        do {
            movement = try service.getMovement(id: movementId)
        } catch {
            loadError = userFriendlyError(error, context: "load movement")
        }
        isLoading = false
    }
}
