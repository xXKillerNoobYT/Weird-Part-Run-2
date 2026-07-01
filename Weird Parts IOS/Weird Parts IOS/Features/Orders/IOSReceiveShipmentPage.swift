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
    @State private var invalidPriceVerificationItemIds = Set<Int64>()
    @State private var isCompleting = false
    @State private var completionMessage: String?
    @State private var activeSheet: ActiveSheet?

    // Routing flow state
    @State private var routingItemId: Int64?  // item currently being routed
    @State private var routingResults: [Int64: RoutingResult] = [:]  // itemId -> result

    // Barcode scanner (61K)
    @State private var showBarcodeScanner = false
    @State private var highlightedItemId: Int64?
    @State private var scanError: String?
    @State private var scannerCountedItemIds = Set<Int64>()
    @State private var manuallyEditedQuantityItemIds = Set<Int64>()

    // Unrouted items warning (62H)
    @State private var showUnroutedWarning = false

    init(sessionId: Int64? = nil) {
        _activeSessionId = State(initialValue: sessionId)
        _isLoading = State(initialValue: sessionId == nil)
    }

    private enum ActiveSheet: Identifiable {
        case qrScanner
        case barcodeScanner
        case routeItem(WarehouseService.ReceivingItemInfo)
        case help
        var id: String { String(describing: self) }
    }

    /// Summary of a completed routing decision for display.
    private struct RoutingResult {
        private enum Source {
            case live(WarehouseService.ReceivingRoute)
            case persisted(WarehouseService.ReceivingRoutingDisposition)
        }

        private let source: Source
        private let routedQty: Int?

        init(route: WarehouseService.ReceivingRoute) {
            self.source = .live(route)
            self.routedQty = nil
        }

        init(disposition: WarehouseService.ReceivingRoutingDisposition, routedQty: Int) {
            self.source = .persisted(disposition)
            self.routedQty = routedQty
        }

        var label: String {
            switch source {
            case .live(let route):
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
                case .jobReturnHolding:
                    "Job return held"
                case .jobReturnDamagedReview:
                    "Job return damaged review"
                case .jobReturnSupplierReview:
                    "Job return supplier review"
                case .jobReturnWrongPartReview:
                    "Job return wrong part review"
                }
            case .persisted(let disposition):
                switch disposition {
                case .staged:
                    "Routed to staging"
                case .supplierReturn:
                    "Return recorded"
                case .writeOff:
                    "Written off"
                case .wrongPart:
                    "Wrong part"
                case .review:
                    "Needs review"
                }
            }
        }
        var icon: String {
            switch source {
            case .live(let route):
                switch route {
                case .stageForJob, .suggestStaging: "tray.and.arrow.down.fill"
                case .restockShelf, .usedToShelf: "archivebox.fill"
                case .recommendReturn, .returnOverstock: "arrow.uturn.backward.circle.fill"
                case .usedWriteOff: "xmark.bin.fill"
                case .damagedReturn: "exclamationmark.triangle.fill"
                case .wrongPart: "questionmark.circle.fill"
                case .jobReturnHolding: "tray.full.fill"
                case .jobReturnDamagedReview: "exclamationmark.triangle.fill"
                case .jobReturnSupplierReview: "arrow.uturn.backward.circle.fill"
                case .jobReturnWrongPartReview: "questionmark.circle.fill"
                }
            case .persisted(let disposition):
                switch disposition {
                case .staged: "tray.and.arrow.down.fill"
                case .supplierReturn: "arrow.uturn.backward.circle.fill"
                case .writeOff: "xmark.bin.fill"
                case .wrongPart: "questionmark.circle.fill"
                case .review: "exclamationmark.triangle.fill"
                }
            }
        }
        var color: Color {
            switch source {
            case .live(let route):
                switch route {
                case .stageForJob, .suggestStaging: .purple
                case .restockShelf: .green
                case .recommendReturn: .orange
                case .returnOverstock: .red
                case .usedToShelf: .green
                case .usedWriteOff: .orange
                case .damagedReturn: .red
                case .wrongPart: .red
                case .jobReturnHolding: .blue
                case .jobReturnDamagedReview: .red
                case .jobReturnSupplierReview: .orange
                case .jobReturnWrongPartReview: .red
                }
            case .persisted(let disposition):
                switch disposition {
                case .staged: .purple
                case .supplierReturn: .orange
                case .writeOff: .orange
                case .wrongPart: .red
                case .review: .red
                }
            }
        }

        var isStaged: Bool {
            switch source {
            case .live(.stageForJob), .live(.suggestStaging):
                true
            case .persisted(.staged):
                true
            default:
                false
            }
        }

        var isShelf: Bool {
            switch source {
            case .live(.restockShelf), .live(.usedToShelf):
                true
            default:
                false
            }
        }

        var isReturn: Bool {
            switch source {
            case .live(.recommendReturn), .live(.returnOverstock), .live(.damagedReturn),
                 .live(.jobReturnDamagedReview), .live(.jobReturnSupplierReview):
                true
            case .persisted(.supplierReturn):
                true
            default:
                false
            }
        }

        func covers(receivedQty: Int) -> Bool {
            guard let routedQty else { return true }
            return routedQty >= receivedQty
        }
    }

    /// Items that have been received (qty > 0) but not yet fully routed (62H).
    private var unroutedItems: [WarehouseService.ReceivingItemInfo] {
        sessionItems.filter { item in
            let qty = receivedQtys[item.id] ?? 0
            return qty > 0 && !(routingResults[item.id]?.covers(receivedQty: qty) ?? false)
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
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert("Receiving Complete", isPresented: Binding(
            get: { completionMessage != nil },
            set: { if !$0 { completionMessage = nil } }
        )) {
            Button("OK") {
                completionMessage = nil
                activeSessionId = nil
                resetReceivingSessionState()
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
                    .accessibilityLabel("Scan PO")
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
            switch sheet {
            case .qrScanner:
                QRScanSheet(expectedType: .po) { result in
                    if let poId = result.entityId {
                        startReceiving(poId: poId)
                    }
                }
                .environmentObject(appCore)
            case .barcodeScanner:
                QRScanSheet(expectedType: .part) { result in
                    handleScannedBarcode(code: result.code)
                }
                .environmentObject(appCore)
            case .routeItem(let item):
                NavigationStack {
                    ReceivingRoutingFlow(
                        item: item,
                        poLineId: item.poLineId,
                        receivedQty: receivedQtys[item.id] ?? item.expectedQty,
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
            case .help:
                PageHelpSheet(
                    title: "Receive Shipment Help",
                    sections: [
                        ("What This Page Does", "Check in parts when a shipment arrives from a supplier. Verify quantities, check prices against the PO, and route each part to its destination (job staging, shelf, or return)."),
                        ("How to Use It", "1. Find the PO in the list or scan its QR code.\n2. Tap 'Receive' to start a receiving session.\n3. For each item, set the received quantity (use +/- or tap 'All').\n4. Verify the price -- tap Matches, Different, or Not Shown.\n5. Tap 'Route This Part' to decide where it goes.\n6. When done, tap 'Complete Receiving' to finalize."),
                        ("Routing Options", "Stage for Job: send directly to a job's staging area. Put on Shelf: restock the shop inventory. Return: flag for return to supplier. The system suggests routing based on pending job demand and stock levels."),
                        ("Price Verification", "If the receipt price differs from the PO price, select 'Different' and enter the actual price. This updates the cost record. 'Not Shown' is for items where the supplier did not include pricing on the packing slip."),
                        ("Tips", "The routing progress summary shows how many items you've routed and a breakdown of decisions. You can re-route any item before completing. Tap 'Back' to exit without completing -- your session is saved.")
                    ]
                )
            }
        }
        .task {
            if activeSessionId != nil {
                loadSessionItems()
            } else {
                loadData()
            }
        }
        .onDisappear {
            NotificationCenter.default.post(name: .receiveShipmentPageInactive, object: nil)
        }
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

    /// Items where received quantity differs from expected (61L).
    private var discrepancyItems: [(item: WarehouseService.ReceivingItemInfo, received: Int)] {
        sessionItems.compactMap { item in
            let received = receivedQtys[item.id] ?? item.expectedQty
            guard received != item.expectedQty else { return nil }
            return (item: item, received: received)
        }
    }

    @ViewBuilder
    private var receivingDetailView: some View {
        ScrollViewReader { scrollProxy in
            List {
                // Pre-filled info banner (61L)
                Section {
                    Label(
                        "Quantities pre-filled from PO. Adjust any short or extra items.",
                        systemImage: "info.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.blue)

                    // Reset to Expected / Clear All buttons (61L)
                    HStack(spacing: 12) {
                        Button {
                            let svc = appCore.warehouseService
                            let items = sessionItems
                            for item in items { receivedQtys[item.id] = item.expectedQty }
                            manuallyEditedQuantityItemIds.formUnion(items.map(\.id))
                            Task {
                                guard let svc else { return }
                                var failed = 0
                                for item in items {
                                    do { try svc.updateSessionItem(itemId: item.id, receivedQty: item.expectedQty) }
                                    catch { failed += 1 }
                                }
                                if failed > 0 { actionError = "Failed to save \(failed) item(s). Pull down to refresh." }
                            }
                        } label: {
                            Label("Reset to Expected", systemImage: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            let svc = appCore.warehouseService
                            let items = sessionItems
                            for item in items { receivedQtys[item.id] = 0 }
                            manuallyEditedQuantityItemIds.formUnion(items.map(\.id))
                            Task {
                                guard let svc else { return }
                                var failed = 0
                                for item in items {
                                    do { try svc.updateSessionItem(itemId: item.id, receivedQty: 0) }
                                    catch { failed += 1 }
                                }
                                if failed > 0 { actionError = "Failed to clear \(failed) item(s). Pull down to refresh." }
                            }
                        } label: {
                            Label("Clear All", systemImage: "xmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Routing progress summary (when items have been routed)
                if !routingResults.isEmpty {
                    Section {
                        routingProgressSummary
                    } header: {
                        Text("Routing Progress")
                    }
                }

                ForEach(sessionItems, id: \.id) { item in
                    let received = receivedQtys[item.id] ?? item.expectedQty
                    let isAdjusted = received != item.expectedQty
                    Section {
                        receivingItemRow(item)
                            .listRowBackground(
                                highlightedItemId == item.id
                                    ? Color.green.opacity(0.15)
                                    : isAdjusted ? Color.orange.opacity(0.08) : nil
                            )
                    } header: {
                        HStack {
                            Text(item.partName)
                            if isAdjusted {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            if let result = routingResults[item.id] {
                                Label(result.label, systemImage: result.icon)
                                    .font(.caption2)
                                    .foregroundStyle(result.color)
                            }
                        }
                    }
                    .id(item.id)
                }

                // Discrepancy summary (61L) — shown before complete button
                if !discrepancyItems.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("\(discrepancyItems.count) item\(discrepancyItems.count == 1 ? "" : "s") differ from expected",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)

                            ForEach(discrepancyItems, id: \.item.id) { entry in
                                HStack {
                                    Text(entry.item.partName)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("Expected: \(entry.item.expectedQty)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("Received: \(entry.received)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(entry.received < entry.item.expectedQty ? .red : .orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Discrepancy Summary")
                    }
                }

                Section {
                    Button {
                        // Check for unrouted items before completing (62H)
                        if !unroutedItems.isEmpty {
                            showUnroutedWarning = true
                        } else {
                            Task { await completeReceiving() }
                        }
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

                // Cancel session button (quantities are auto-saved — no discard dialog needed)
                Section {
                    Button(role: .destructive) {
                        activeSessionId = nil
                        resetReceivingSessionState()
                        loadData()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Cancel Receiving Session", systemImage: "xmark.circle")
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: highlightedItemId) { _, newId in
                // Auto-scroll to highlighted item on barcode scan (61K)
                if let id = newId {
                    withAnimation {
                        scrollProxy.scrollTo(id, anchor: .center)
                    }
                    // Clear highlight after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if highlightedItemId == id {
                            withAnimation { highlightedItemId = nil }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // Quantities are auto-saved — no discard dialog needed (PE-041)
                Button {
                    activeSessionId = nil
                    resetReceivingSessionState()
                    loadData()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
            // Barcode scan button (61K)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .barcodeScanner
                } label: {
                    Image(systemName: "barcode.viewfinder")
                }
                .accessibilityLabel("Scan barcode")
            }
        }
        .alert("Barcode Not Found", isPresented: Binding(
            get: { scanError != nil },
            set: { if !$0 { scanError = nil } }
        )) {
            Button("OK") { scanError = nil }
        } message: {
            Text(scanError ?? "")
        }
        // Unrouted items warning before completing (62H)
        .confirmationDialog(
            "Unrouted Items",
            isPresented: $showUnroutedWarning,
            titleVisibility: .visible
        ) {
            Button("Continue Anyway") {
                Task { await completeReceiving() }
            }
            Button("Go Back and Route Items", role: .cancel) { }
        } message: {
            Text("\(unroutedItems.count) item\(unroutedItems.count == 1 ? " has" : "s have") been received but not routed to a location. Continue anyway?")
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
                        if let items = grouped[label], let result = items.first {
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
                        let current = receivedQtys[item.id] ?? item.expectedQty
                        if current > 0 {
                            let newQty = current - 1
                            receivedQtys[item.id] = newQty
                            manuallyEditedQuantityItemIds.insert(item.id)
                            let svc = appCore.warehouseService
                            let iid = item.id
                            Task {
                                do { try svc?.updateSessionItem(itemId: iid, receivedQty: newQty) }
                                catch { actionError = "Could not save quantity change." }
                            }
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Decrease quantity")

                    Text("\(receivedQtys[item.id] ?? item.expectedQty)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(minWidth: 40)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(
                            (receivedQtys[item.id] ?? item.expectedQty) != item.expectedQty
                                ? .orange : .primary
                        )

                    Button {
                        let current = receivedQtys[item.id] ?? item.expectedQty
                        let newQty = current + 1
                        receivedQtys[item.id] = newQty
                        manuallyEditedQuantityItemIds.insert(item.id)
                        let svc = appCore.warehouseService
                        let iid = item.id
                        Task {
                            do { try svc?.updateSessionItem(itemId: iid, receivedQty: newQty) }
                            catch { actionError = "Could not save quantity change." }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Increase quantity")

                    // Quick-fill to expected qty (shown when quantity differs)
                    if (receivedQtys[item.id] ?? item.expectedQty) != item.expectedQty {
                        Button {
                            let newQty = item.expectedQty
                            receivedQtys[item.id] = newQty
                            manuallyEditedQuantityItemIds.insert(item.id)
                            let svc = appCore.warehouseService
                            let iid = item.id
                            Task {
                                do { try svc?.updateSessionItem(itemId: iid, receivedQty: newQty) }
                                catch { actionError = "Could not save quantity change." }
                            }
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
        let qty = receivedQtys[item.id] ?? item.expectedQty

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
                    invalidPriceVerificationItemIds.remove(itemId)
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
                    invalidPriceVerificationItemIds.insert(itemId)
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
                    invalidPriceVerificationItemIds.remove(itemId)
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
                                return p > 0 ? String(format: "%.2f", p) : ""
                            }
                            return ""
                        },
                        set: { newVal in
                            let parsedPrice = Double(newVal) ?? .nan
                            priceVerifications[itemId] = .different(newPrice: parsedPrice)
                            if isValidReceiveShipmentDifferentPrice(parsedPrice) {
                                invalidPriceVerificationItemIds.remove(itemId)
                            } else {
                                invalidPriceVerificationItemIds.insert(itemId)
                            }
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                }

                if invalidPriceVerificationItemIds.contains(itemId) {
                    Label("Enter a valid actual price greater than $0.00 before completing.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Barcode Scan Handler (61K)

    /// Match scanned barcode/code against session line items by partCode or partName.
    /// Auto-increments received quantity and highlights the matched item.
    private func handleScannedBarcode(code: String) {
        guard !code.isEmpty else {
            scanError = "Empty barcode scanned."
            return
        }

        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Try to match against partCode first, then partName
        let matchedItem = sessionItems.first { item in
            if let partCode = item.partCode,
               partCode.lowercased() == normalizedCode {
                return true
            }
            return false
        } ?? sessionItems.first { item in
            item.partName.lowercased() == normalizedCode
        }

        guard let item = matchedItem else {
            scanError = "No line item matches barcode \"\(code)\". Check the PO or scan a different code."
            return
        }

        // Auto-increment received quantity and auto-save (PE-041).
        // Fresh sessions may display expected quantities, but barcode scans are
        // physical counted units. The first scan starts from zero unless the
        // worker has already saved/edited a quantity for this line.
        let currentQty = receivingBarcodeScanBaseQuantity(
            displayedQty: receivedQtys[item.id],
            persistedReceivedQty: item.receivedQty,
            hasScannerCount: scannerCountedItemIds.contains(item.id),
            hasManualQuantityEdit: manuallyEditedQuantityItemIds.contains(item.id)
        )
        let newQty = currentQty + 1
        receivedQtys[item.id] = newQty
        scannerCountedItemIds.insert(item.id)
        let svc = appCore.warehouseService
        let iid = item.id
        Task {
            do { try svc?.updateSessionItem(itemId: iid, receivedQty: newQty) }
            catch { scanError = "Barcode scan quantity could not be saved." }
        }

        // Highlight the matched item (triggers auto-scroll via onChange)
        withAnimation {
            highlightedItemId = item.id
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
            resetReceivingSessionState()
            loadSessionItems()
        } catch {
            actionError = userFriendlyError(error, context: "receive shipment")
        }
    }

    private func loadSessionItems() {
        guard let service = appCore.warehouseService,
              let sessionId = activeSessionId else {
            loadError = "Warehouse service not available"
            isLoading = false
            return
        }
        do {
            sessionItems = try service.getSessionItems(sessionId: sessionId)
            let currentItemIds = Set(sessionItems.map(\.id))
            routingResults = routingResults.filter { currentItemIds.contains($0.key) }
            // Restore saved quantities from DB (PE-041: auto-save draft persistence).
            // `receivedQty == 0` is a valid saved draft value after Clear All or a
            // manual zero count. Use scannedAt as the persisted-touch marker so
            // untouched fresh-session rows still pre-fill from expectedQty.
            for item in sessionItems {
                let restoredReceivedQty = item.scannedAt == nil ? item.expectedQty : item.receivedQty
                let currentReceivedQty = receivedQtys[item.id] ?? restoredReceivedQty
                if receivedQtys[item.id] == nil {
                    receivedQtys[item.id] = restoredReceivedQty
                }
                if routingResults[item.id] == nil,
                   let disposition = item.routingDisposition,
                   currentReceivedQty > 0,
                   item.routedQty > 0 {
                    routingResults[item.id] = RoutingResult(disposition: disposition, routedQty: item.routedQty)
                }
            }
            postAIContext()
        } catch {
            actionError = userFriendlyError(error, context: "receive shipment")
        }
    }

    private func resetReceivingSessionState() {
        sessionItems = []
        receivedQtys = [:]
        priceVerifications = [:]
        invalidPriceVerificationItemIds = []
        routingResults = [:]
        scannerCountedItemIds = []
        manuallyEditedQuantityItemIds = []
        highlightedItemId = nil
        scanError = nil
    }

    private func completeReceiving() async {
        guard let warehouseService = appCore.warehouseService,
              let sessionId = activeSessionId else {
            loadError = "Warehouse service not available"
            isLoading = false
            return
        }
        guard let userId = appCore.currentUser?.id else {
            actionError = "Not logged in. Please log in and try again."
            return
        }

        actionError = nil

        if let validationError = receiveShipmentDifferentPriceValidationMessage(
            for: sessionItems.map { item in
                ReceiveShipmentPriceValidationItem(id: item.id, partName: item.partName)
            },
            priceVerifications: priceVerifications
        ) {
            invalidPriceVerificationItemIds = Set(sessionItems.compactMap { item in
                if case .different(let newPrice) = priceVerifications[item.id],
                   !isValidReceiveShipmentDifferentPrice(newPrice) {
                    return item.id
                }
                return nil
            })
            actionError = validationError
            return
        }

        invalidPriceVerificationItemIds = []

        isCompleting = true

        do {
            // Update received quantities and any verified invoice cost before completion.
            for item in sessionItems {
                let qty = receivedQtys[item.id] ?? item.expectedQty
                let verifiedCost: Double?
                switch priceVerifications[item.id] {
                case .matches:
                    verifiedCost = item.unitPrice
                case .different(let newPrice):
                    verifiedCost = isValidReceiveShipmentDifferentPrice(newPrice) ? newPrice : nil
                case .notShown, .none:
                    verifiedCost = nil
                }
                try warehouseService.updateSessionItem(itemId: item.id, receivedQty: qty, actualCost: verifiedCost)
            }

            // Complete the session (creates stock movements for non-routed items)
            // Items that were already routed (staged, written off, returned) have their
            // movements created during the routing flow. The session completion adds
            // warehouse stock for unrouted items.
            try warehouseService.completeSession(sessionId: sessionId, completedBy: userId)

            // Process price verifications -> create cost layers
            if let partsService = appCore.partsService {
                for item in sessionItems {
                    guard let partId = item.partId else { continue }
                    let qty = receivedQtys[item.id] ?? item.expectedQty
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
                        if isValidReceiveShipmentDifferentPrice(newPrice) {
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
                    result.isStaged
                }.count
                let shelfCount = routingResults.values.filter { result in
                    result.isShelf
                }.count
                let returnCount = routingResults.values.filter { result in
                    result.isReturn
                }.count
                let otherCount = routedCount - stagedCount - shelfCount - returnCount
                var parts: [String] = []
                if stagedCount > 0 { parts.append("\(stagedCount) routed to staging") }
                if shelfCount > 0 { parts.append("\(shelfCount) shelved") }
                if returnCount > 0 { parts.append("\(returnCount) returning") }
                if otherCount > 0 { parts.append("\(otherCount) routed other ways") }
                summary = "Receiving complete. \(routedCount)/\(totalCount) items with routes: \(parts.joined(separator: ", "))."
            } else {
                summary = "Receiving complete. Stock has been updated."
            }

            await MainActor.run {
                completionMessage = summary
                isCompleting = false
            }
        } catch {
            await MainActor.run {
                actionError = userFriendlyError(error, context: "receive shipment")
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
            postAIContext()
        } catch {
            loadError = userFriendlyError(error, context: "load shipment data")
        }
        isLoading = false
    }

    private func postAIContext() {
        let context: String
        if let sessionId = activeSessionId {
            let receivedUnits = sessionItems.reduce(0) { $0 + (receivedQtys[$1.id] ?? $1.expectedQty) }
            let expectedUnits = sessionItems.reduce(0) { $0 + $1.expectedQty }
            let discrepancyCount = discrepancyItems.count
            let routedCount = routingResults.count
            let routeSummary = Dictionary(grouping: routingResults.values, by: \.label)
                .map { "\($0.key): \($0.value.count)" }
                .sorted()
                .joined(separator: ", ")
            context = """
            Receive Shipment page. Read-only context.
            Active receiving session id: \(sessionId).
            Session items: \(sessionItems.count), expected units: \(expectedUnits), entered received units: \(receivedUnits), discrepancies: \(discrepancyCount), routed items: \(routedCount).
            Route summary: \(routeSummary.isEmpty ? "none yet" : routeSummary). Unrouted received items: \(unroutedItems.count).
            Available read-only guidance: explain receiving progress, discrepancy/routing state, price verification choices, scanner usage, and where visible controls are located. Do not suggest completing or changing receiving directly.
            """
        } else {
            let statusCounts = Dictionary(grouping: purchaseOrders, by: \.status)
                .map { "\($0.key): \($0.value.count)" }
                .sorted()
                .joined(separator: ", ")
            let visible = purchaseOrders.prefix(5).map { "\($0.poNumber) - \($0.supplierName)" }.joined(separator: ", ")
            context = """
            Receive Shipment page. Read-only context.
            No active receiving session. Open purchase orders awaiting receipt: \(purchaseOrders.count). Status counts: \(statusCounts.isEmpty ? "none" : statusCounts).
            Visible PO examples: \(visible.isEmpty ? "none" : visible).
            Available read-only guidance: explain how the receiving list, QR scanner, PO detail links, and Receive buttons are organized. Do not start receiving directly.
            """
        }
        NotificationCenter.default.post(
            name: .receiveShipmentPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }
}

func receivingBarcodeScanBaseQuantity(
    displayedQty: Int?,
    persistedReceivedQty: Int,
    hasScannerCount: Bool,
    hasManualQuantityEdit: Bool
) -> Int {
    if hasScannerCount || hasManualQuantityEdit || persistedReceivedQty > 0 {
        return displayedQty ?? persistedReceivedQty
    }

    return 0
}

struct ReceiveShipmentPriceValidationItem {
    let id: Int64
    let partName: String
}

func isValidReceiveShipmentDifferentPrice(_ price: Double) -> Bool {
    price > 0 && price.isFinite
}

func receiveShipmentDifferentPriceValidationMessage(
    for items: [ReceiveShipmentPriceValidationItem],
    priceVerifications: [Int64: PriceVerification]
) -> String? {
    let invalidDifferentPriceNames = items.compactMap { item -> String? in
        guard case .different(let newPrice) = priceVerifications[item.id],
              !isValidReceiveShipmentDifferentPrice(newPrice) else {
            return nil
        }
        return item.partName
    }

    guard !invalidDifferentPriceNames.isEmpty else { return nil }

    return "Enter a valid actual price greater than $0.00 for: \(invalidDifferentPriceNames.joined(separator: ", "))."
}

// MARK: - Price Verification

enum PriceVerification {
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
