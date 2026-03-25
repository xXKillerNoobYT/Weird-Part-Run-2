import SwiftUI
import WiredPartCore

/// Purchase orders list page for iOS.
///
/// Displays a searchable list of POs with PO number, supplier name,
/// status badge, total cost, and line count. Supports pull-to-refresh,
/// status-based filtering, sort options, swipe actions, and an
/// awaiting delivery KPI summary.
struct IOSPurchaseOrdersPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var purchaseOrders: [OrdersService.POListItem] = []
    @State private var allPurchaseOrders: [OrdersService.POListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var sortOption: SortOption = .newest

    // Swipe / cancel state
    @State private var poToCancel: OrdersService.POListItem?
    @State private var cancelReason = ""
    @State private var aiSummary = ""
    @State private var showCancelConfirm = false
    @State private var isGeneratingSummary = false
    @State private var actionMessage: String?

    private enum ActiveSheet: Identifiable {
        case createPO
        case qrScanner
        case scannedPODetail(Int64)

        var id: String {
            switch self {
            case .createPO: "createPO"
            case .qrScanner: "qrScanner"
            case .scannedPODetail(let poId): "scannedPO-\(poId)"
            }
        }
    }

    private enum SortOption: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case totalHigh = "Total (High)"
        case totalLow = "Total (Low)"
        case supplierAZ = "Supplier A-Z"
        case status = "By Status"
    }

    private let statusOptions = ["all", "draft", "submitted", "ordered", "partial", "received", "cancelled"]

    var body: some View {
        VStack(spacing: 0) {
            statusPicker
            kpiSummary
            poList
        }
        .navigationTitle("Purchase Orders")
        .searchable(text: $searchText, prompt: "Search POs...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { activeSheet = .qrScanner } label: { Image(systemName: "qrcode.viewfinder") }
                Button { activeSheet = .createPO } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button {
                            sortOption = option
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .alert(
            poToCancel?.status == "draft" ? "Delete Draft?" : "Cancel PO?",
            isPresented: $showCancelConfirm
        ) {
            TextField("Reason (required)", text: $cancelReason)
            Button("Keep", role: .cancel) {
                cancelReason = ""
                aiSummary = ""
                poToCancel = nil
            }
            Button(poToCancel?.status == "draft" ? "Delete" : "Cancel PO", role: .destructive) {
                guard !cancelReason.trimmingCharacters(in: .whitespaces).isEmpty else {
                    actionMessage = "Reason is required."
                    return
                }
                Task {
                    if let po = poToCancel {
                        await cancelOrDeletePO(po)
                    }
                    cancelReason = ""
                    aiSummary = ""
                    poToCancel = nil
                }
            }
        } message: {
            if isGeneratingSummary {
                Text("Generating summary...")
            } else {
                Text(aiSummary)
            }
        }
        .alert("Notice", isPresented: .constant(actionMessage != nil)) {
            Button("OK") { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
    }

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .createPO:
            CreatePOSheet(onSave: { loadData() })
                .environmentObject(appCore)
        case .qrScanner:
            QRScanSheet(expectedType: .po) { result in
                if let poId = result.entityId, result.isFound {
                    activeSheet = .scannedPODetail(poId)
                }
            }
            .environmentObject(appCore)
        case .scannedPODetail(let poId):
            NavigationStack {
                IOSPODetailPage(poId: poId)
                    .environmentObject(appCore)
            }
        }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    Button {
                        statusFilter = status
                        loadData()
                    } label: {
                        Text("\(status == "all" ? "All" : status.capitalized) (\(countForStatus(status)))")
                            .font(.caption)
                            .fontWeight(statusFilter == status ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(statusFilter == status ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(statusFilter == status ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - KPI Summary

    @ViewBuilder
    private var kpiSummary: some View {
        if awaitingCount > 0 || pendingTotal > 0 {
            HStack {
                if awaitingCount > 0 {
                    Label("\(awaitingCount) awaiting delivery", systemImage: "shippingbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if pendingTotal > 0 {
                    Text(formatCurrency(pendingTotal) + " pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private var awaitingCount: Int {
        allPurchaseOrders.filter { $0.status == "ordered" || $0.status == "partial" }.count
    }

    private var pendingTotal: Double {
        allPurchaseOrders
            .filter { ["ordered", "partial", "draft", "submitted"].contains($0.status) }
            .compactMap(\.totalCost)
            .reduce(0, +)
    }

    // MARK: - PO List

    @ViewBuilder
    private var poList: some View {
        if isLoading {
            ProgressView("Loading purchase orders...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if sortedPOs.isEmpty {
            EmptyStateView(
                icon: "doc.text.fill",
                title: "No Purchase Orders",
                message: searchText.isEmpty ? "No purchase orders yet." : "No POs match your criteria."
            )
        } else {
            List(sortedPOs, id: \.id) { po in
                NavigationLink {
                    IOSPODetailPage(poId: po.id)
                        .environmentObject(appCore)
                } label: {
                    poRow(po)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if po.status == "draft" {
                        Button(role: .destructive) {
                            poToCancel = po
                            Task { await generateAISummary(for: po) }
                            showCancelConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } else if po.status != "received" && po.status != "cancelled" {
                        Button(role: .destructive) {
                            poToCancel = po
                            Task { await generateAISummary(for: po) }
                            showCancelConfirm = true
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredPOs: [OrdersService.POListItem] {
        guard !searchText.isEmpty else { return purchaseOrders }
        let query = searchText.lowercased()
        return purchaseOrders.filter {
            $0.poNumber.lowercased().contains(query) ||
            $0.supplierName.lowercased().contains(query)
        }
    }

    private var sortedPOs: [OrdersService.POListItem] {
        let filtered = filteredPOs
        switch sortOption {
        case .newest:
            return filtered.sorted { ($0.orderDate ?? "") > ($1.orderDate ?? "") }
        case .oldest:
            return filtered.sorted { ($0.orderDate ?? "") < ($1.orderDate ?? "") }
        case .totalHigh:
            return filtered.sorted { ($0.totalCost ?? 0) > ($1.totalCost ?? 0) }
        case .totalLow:
            return filtered.sorted { ($0.totalCost ?? 0) < ($1.totalCost ?? 0) }
        case .supplierAZ:
            return filtered.sorted { $0.supplierName < $1.supplierName }
        case .status:
            let order = ["draft": 0, "submitted": 1, "ordered": 2, "partial": 3, "received": 4, "cancelled": 5]
            return filtered.sorted { (order[$0.status] ?? 99) < (order[$1.status] ?? 99) }
        }
    }

    private func poRow(_ po: OrdersService.POListItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(po.poNumber)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Text(po.supplierName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let date = formatDate(po.orderDate) {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(po.status)
                if let total = po.totalCost {
                    Text(String(format: "$%.2f", total))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Label("\(po.lineCount) lines", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "draft": .secondary
        case "submitted": .orange
        case "ordered": .blue
        case "partial": .purple
        case "received": .green
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    private func countForStatus(_ status: String) -> Int {
        if status == "all" { return allPurchaseOrders.count }
        return allPurchaseOrders.filter { $0.status == status }.count
    }

    private func formatDate(_ isoString: String?) -> String? {
        guard let str = isoString else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        guard let date = iso.date(from: String(str.prefix(10))) else { return str }
        let display = DateFormatter()
        display.dateStyle = .medium
        return display.string(from: date)
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    // MARK: - AI Summary

    private func generateAISummary(for po: OrdersService.POListItem) async {
        isGeneratingSummary = true
        let fallback = "\(po.poNumber): \(po.lineCount) items from \(po.supplierName). Total: \(po.totalCost.map { String(format: "$%.2f", $0) } ?? "N/A")."

        let aiService = FoundationModelsService()
        let context: [String: String] = [
            "PO Number": po.poNumber,
            "Supplier": po.supplierName,
            "Status": po.status,
            "Items": "\(po.lineCount) line items",
            "Total": po.totalCost.map { String(format: "$%.2f", $0) } ?? "N/A",
            "Ordered": po.orderDate ?? "N/A"
        ]
        let result = await aiService.generatePreFill(
            fieldType: "purchase order summary for a cancellation confirmation dialog (1-2 sentences)",
            contextData: context
        )
        await MainActor.run {
            aiSummary = result.text ?? fallback
            isGeneratingSummary = false
        }
    }

    // MARK: - Cancel / Delete

    private func cancelOrDeletePO(_ po: OrdersService.POListItem) async {
        guard let service = appCore.ordersService else {
            actionMessage = "Service not available"
            return
        }
        do {
            if po.status == "draft" {
                try service.deletePO(id: po.id)
            } else {
                try service.updatePOStatus(id: po.id, status: "cancelled")
            }
            loadData()
        } catch {
            actionMessage = "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
        isLoading = purchaseOrders.isEmpty
        loadError = nil
        do {
            allPurchaseOrders = try service.listPurchaseOrders(status: nil)
            purchaseOrders = statusFilter == "all"
                ? allPurchaseOrders
                : allPurchaseOrders.filter { $0.status == statusFilter }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
