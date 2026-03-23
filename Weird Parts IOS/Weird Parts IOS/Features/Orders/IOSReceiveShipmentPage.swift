import SwiftUI
import WiredPartCore

/// Receive shipment workflow page.
///
/// Shows POs awaiting receipt. Tapping "Receive" starts a session and opens
/// the line-item checklist with quantity inputs and price verification.
struct IOSReceiveShipmentPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var purchaseOrders: [OrdersService.POListItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?

    // Active receiving session
    @State private var activeSessionId: Int64?
    @State private var sessionItems: [WarehouseService.ReceivingItemInfo] = []
    @State private var receivedQtys: [Int64: Int] = [:]  // itemId -> qty
    @State private var priceVerifications: [Int64: PriceVerification] = [:]  // itemId -> verification
    @State private var isCompleting = false
    @State private var completionMessage: String?
    @State private var activeSheet: ActiveSheet?

    // Routing flow state
    @State private var routingItemId: Int64?  // item currently being routed
    @State private var routingResults: [Int64: RoutingResult] = [:]  // itemId -> result

    private enum ActiveSheet: Identifiable {
        case qrScanner
        case routeItem(WarehouseService.ReceivingItemInfo)
        var id: String { String(describing: self) }
    }

    /// Summary of a completed routing decision for display.
    private struct RoutingResult {
        let route: WarehouseService.ReceivingRoute
        var label: String {
            switch route {
            case .stageForJob(_, let jobName, _):
                "Staged for \(jobName)"
            case .suggestStaging(let demands):
                "Staged for \(demands.first?.jobName ?? "job")"
            case .restockShelf:
                "Put on shelf"
            case .recommendReturn:
                "Return recommended"
            case .returnOverstock:
                "Return (overstocked)"
            case .usedToShelf:
                "Used - shelved"
            case .usedWriteOff:
                "Used - written off"
            case .damagedReturn:
                "Damaged - returning"
            case .wrongPart:
                "Wrong part"
            }
        }
        var icon: String {
            switch route {
            case .stageForJob, .suggestStaging: "tray.and.arrow.down.fill"
            case .restockShelf, .usedToShelf: "archivebox.fill"
            case .recommendReturn, .returnOverstock: "arrow.uturn.backward.circle.fill"
            case .usedWriteOff: "xmark.bin.fill"
            case .damagedReturn: "exclamationmark.triangle.fill"
            case .wrongPart: "questionmark.circle.fill"
            }
        }
        var color: Color {
            switch route {
            case .stageForJob, .suggestStaging: .purple
            case .restockShelf: .green
            case .recommendReturn: .orange
            case .returnOverstock: .red
            case .usedToShelf: .green
            case .usedWriteOff: .orange
            case .damagedReturn: .red
            case .wrongPart: .red
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let _ = activeSessionId {
                receivingDetailView
            } else if isLoading {
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
                    poRow(po)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(activeSessionId != nil ? "Receiving" : "Receive Shipment")
        .refreshable {
            if activeSessionId != nil {
                loadSessionItems()
            } else {
                loadData()
            }
        }
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert("Receiving Complete", isPresented: .constant(completionMessage != nil)) {
            Button("OK") {
                completionMessage = nil
                activeSessionId = nil
                sessionItems = []
                priceVerifications = [:]
                receivedQtys = [:]
                loadData()
            }
        } message: {
            Text(completionMessage ?? "")
        }
        .toolbar {
            if activeSessionId == nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .qrScanner
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .qrScanner:
                QRScanSheet(expectedType: .po) { result in
                    if let poId = result.entityId {
                        startReceiving(poId: poId)
                    }
                }
                .environmentObject(appCore)
            case .routeItem(let item):
                NavigationStack {
                    ReceivingRoutingFlow(
                        item: item,
                        poLineId: item.poLineId,
                        receivedQty: receivedQtys[item.id] ?? item.receivedQty,
                        onRouteComplete: { route in
                            routingResults[item.id] = RoutingResult(route: route)
                        },
                        onDismiss: {
                            activeSheet = nil
                        }
                    )
                    .navigationTitle("Route Part")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { activeSheet = nil }
                        }
                    }
                    .environmentObject(appCore)
                }
            }
        }
        .task { loadData() }
    }

    // MARK: - PO List

    private func poRow(_ po: OrdersService.POListItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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

            HStack(spacing: 8) {
                NavigationLink {
                    IOSPODetailPage(poId: po.id)
                        .environmentObject(appCore)
                } label: {
                    Label("View Details", systemImage: "doc.text")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    startReceiving(poId: po.id)
                } label: {
                    Label("Receive", systemImage: "shippingbox.and.arrow.backward")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Receiving Detail View

    @ViewBuilder
    private var receivingDetailView: some View {
        List {
            // Routing progress summary (when items have been routed)
            if !routingResults.isEmpty {
                Section {
                    routingProgressSummary
                } header: {
                    Text("Routing Progress")
                }
            }

            ForEach(sessionItems, id: \.id) { item in
                Section {
                    receivingItemRow(item)
                } header: {
                    HStack {
                        Text(item.partName)
                        Spacer()
                        if let result = routingResults[item.id] {
                            Label(result.label, systemImage: result.icon)
                                .font(.caption2)
                                .foregroundStyle(result.color)
                        }
                    }
                }
            }

            Section {
                Button {
                    Task { await completeReceiving() }
                } label: {
                    HStack {
                        Spacer()
                        if isCompleting {
                            ProgressView()
                        } else {
                            Label("Complete Receiving", systemImage: "checkmark.circle.fill")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .frame(minHeight: 44)
                .disabled(isCompleting)
            }

            if let error = actionError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    activeSessionId = nil
                    sessionItems = []
                    priceVerifications = [:]
                    receivedQtys = [:]
                    routingResults = [:]
                    loadData()
                }
            }
        }
    }

    // MARK: - Routing Progress Summary

    private var routingProgressSummary: some View {
        let routedCount = routingResults.count
        let totalCount = sessionItems.count
        let allRouted = routedCount == totalCount

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: allRouted ? "checkmark.circle.fill" : "arrow.triangle.branch")
                    .foregroundStyle(allRouted ? .green : .blue)
                Text("\(routedCount)/\(totalCount) items routed")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if allRouted {
                    Text("All routed")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // Mini summary of routing decisions
            let grouped = Dictionary(grouping: routingResults.values, by: \.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(grouped.keys.sorted()), id: \.self) { label in
                        let items = grouped[label]!
                        let result = items.first!
                        HStack(spacing: 4) {
                            Image(systemName: result.icon)
                                .font(.caption2)
                            Text("\(items.count)x \(label)")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(result.color.opacity(0.12))
                        .foregroundStyle(result.color)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func receivingItemRow(_ item: WarehouseService.ReceivingItemInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Part info
            if let code = item.partCode {
                Text(code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Expected vs received
            HStack {
                Text("Expected: \(item.expectedQty)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let price = item.unitPrice {
                    Text(String(format: "Order price: $%.2f", price))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Quantity input
            HStack {
                Text("Received:")
                    .font(.subheadline)
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        let current = receivedQtys[item.id] ?? item.receivedQty
                        if current > 0 {
                            receivedQtys[item.id] = current - 1
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Text("\(receivedQtys[item.id] ?? item.receivedQty)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(minWidth: 40)
                        .multilineTextAlignment(.center)

                    Button {
                        let current = receivedQtys[item.id] ?? item.receivedQty
                        receivedQtys[item.id] = current + 1
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    // Quick-fill to expected qty
                    if (receivedQtys[item.id] ?? item.receivedQty) != item.expectedQty {
                        Button {
                            receivedQtys[item.id] = item.expectedQty
                        } label: {
                            Text("All")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Price verification
            priceVerificationView(item: item)

            Divider()

            // Routing section
            routingSection(item: item)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Routing Section

    @ViewBuilder
    private func routingSection(item: WarehouseService.ReceivingItemInfo) -> some View {
        let qty = receivedQtys[item.id] ?? item.receivedQty
        let isRouted = routingResults[item.id] != nil

        VStack(alignment: .leading, spacing: 8) {
            if let result = routingResults[item.id] {
                // Show routing result
                HStack(spacing: 8) {
                    Image(systemName: result.icon)
                        .foregroundStyle(result.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Routed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(result.label)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(result.color)
                    }
                    Spacer()
                    // Allow re-routing
                    Button {
                        routingResults[item.id] = nil
                        activeSheet = .routeItem(item)
                    } label: {
                        Text("Re-route")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(result.color.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if qty > 0 {
                // Show route button
                Button {
                    activeSheet = .routeItem(item)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                        Text("Route This Part")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            } else {
                // Zero quantity — no routing needed
                HStack(spacing: 6) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                    Text("No routing needed (qty: 0)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Price Verification

    @ViewBuilder
    private func priceVerificationView(item: WarehouseService.ReceivingItemInfo) -> some View {
        let itemId = item.id
        let currentVerification = priceVerifications[itemId]

        VStack(alignment: .leading, spacing: 8) {
            Text("Price on receipt?")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    priceVerifications[itemId] = .matches
                } label: {
                    Label("Matches", systemImage: currentVerification.isMatches ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(currentVerification.isMatches ? Color.green.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    priceVerifications[itemId] = .different(newPrice: 0)
                } label: {
                    Label("Different", systemImage: currentVerification.isDifferent ? "exclamationmark.circle.fill" : "circle")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(currentVerification.isDifferent ? Color.orange.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    priceVerifications[itemId] = .notShown
                } label: {
                    Label("Not Shown", systemImage: currentVerification.isNotShown ? "questionmark.circle.fill" : "circle")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(currentVerification.isNotShown ? Color.secondary.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // New price input when "Different" is selected
            if case .different = currentVerification {
                HStack {
                    Text("Actual price: $")
                        .font(.caption)
                    TextField("0.00", text: Binding(
                        get: {
                            if case .different(let p) = priceVerifications[itemId] {
                                return p > 0 ? String(format: "%.5f", p) : ""
                            }
                            return ""
                        },
                        set: { newVal in
                            priceVerifications[itemId] = .different(newPrice: Double(newVal) ?? 0)
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                }
            }
        }
    }

    // MARK: - Actions

    private func startReceiving(poId: Int64) {
        guard let service = appCore.warehouseService else {
            actionError = "Warehouse service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            actionError = "Not logged in"
            return
        }
        do {
            let sessionId = try service.startReceivingSession(poId: poId, startedBy: userId)
            activeSessionId = sessionId
            loadSessionItems()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func loadSessionItems() {
        guard let service = appCore.warehouseService,
              let sessionId = activeSessionId else { return }
        do {
            sessionItems = try service.getSessionItems(sessionId: sessionId)
            // Pre-fill received qtys
            for item in sessionItems {
                if receivedQtys[item.id] == nil {
                    receivedQtys[item.id] = item.receivedQty
                }
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func completeReceiving() async {
        guard let warehouseService = appCore.warehouseService,
              let sessionId = activeSessionId else { return }
        isCompleting = true
        actionError = nil

        do {
            // Update received quantities
            for item in sessionItems {
                let qty = receivedQtys[item.id] ?? item.receivedQty
                try warehouseService.updateSessionItem(itemId: item.id, receivedQty: qty)
            }

            // Complete the session (creates stock movements for non-routed items)
            // Items that were already routed (staged, written off, returned) have their
            // movements created during the routing flow. The session completion adds
            // warehouse stock for unrouted items.
            let userId = appCore.currentUser?.id ?? 0
            try warehouseService.completeSession(sessionId: sessionId, completedBy: userId)

            // Process price verifications -> create cost layers
            if let partsService = appCore.partsService {
                for item in sessionItems {
                    guard let partId = item.partId else { continue }
                    let qty = receivedQtys[item.id] ?? item.receivedQty
                    guard qty > 0 else { continue }

                    let verification = priceVerifications[item.id]

                    switch verification {
                    case .matches:
                        // Use order price, mark as verified
                        let orderPrice = item.unitPrice ?? 0
                        if orderPrice > 0 {
                            _ = try partsService.addCostLayer(
                                partId: partId,
                                qty: qty,
                                unitCost: orderPrice,
                                poLineId: item.poLineId
                            )
                        }
                        try partsService.markPriceVerified(partId: partId)

                    case .different(let newPrice):
                        // Use actual receipt price
                        if newPrice > 0 {
                            _ = try partsService.addCostLayer(
                                partId: partId,
                                qty: qty,
                                unitCost: newPrice,
                                poLineId: item.poLineId
                            )
                            try partsService.markPriceVerified(partId: partId)
                        }

                    case .notShown:
                        // Skip -- don't update cost_last_updated, don't create cost layer
                        break

                    case .none:
                        // No verification selected -- skip
                        break
                    }
                }
            }

            // Build completion summary
            let routedCount = routingResults.count
            let totalCount = sessionItems.count
            let summary: String
            if routedCount > 0 {
                let stagedCount = routingResults.values.filter { result in
                    switch result.route {
                    case .stageForJob, .suggestStaging: return true
                    default: return false
                    }
                }.count
                let shelfCount = routingResults.values.filter { result in
                    switch result.route {
                    case .restockShelf, .usedToShelf: return true
                    default: return false
                    }
                }.count
                let returnCount = routingResults.values.filter { result in
                    switch result.route {
                    case .recommendReturn, .returnOverstock, .damagedReturn: return true
                    default: return false
                    }
                }.count
                var parts: [String] = []
                if stagedCount > 0 { parts.append("\(stagedCount) staged for jobs") }
                if shelfCount > 0 { parts.append("\(shelfCount) shelved") }
                if returnCount > 0 { parts.append("\(returnCount) returning") }
                summary = "Receiving complete. \(routedCount)/\(totalCount) items routed: \(parts.joined(separator: ", "))."
            } else {
                summary = "Receiving complete. Stock has been updated."
            }

            await MainActor.run {
                completionMessage = summary
                isCompleting = false
            }
        } catch {
            await MainActor.run {
                actionError = error.localizedDescription
                isCompleting = false
            }
        }
    }

    // MARK: - Helpers

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
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
        isLoading = purchaseOrders.isEmpty
        loadError = nil
        do {
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

// MARK: - Price Verification

private enum PriceVerification {
    case matches
    case different(newPrice: Double)
    case notShown
}

extension Optional where Wrapped == PriceVerification {
    var isMatches: Bool {
        if case .matches = self { return true }
        return false
    }
    var isDifferent: Bool {
        if case .different = self { return true }
        return false
    }
    var isNotShown: Bool {
        if case .notShown = self { return true }
        return false
    }
}
