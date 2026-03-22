import SwiftUI
import WiredPartCore

/// Purchase orders list page for iOS.
///
/// Displays a searchable list of POs with PO number, supplier name,
/// status badge, total cost, and line count. Supports pull-to-refresh
/// and status-based filtering.
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

    private let statusOptions = ["all", "draft", "submitted", "ordered", "partial", "received", "cancelled"]

    var body: some View {
        VStack(spacing: 0) {
            statusPicker
            poList
        }
        .navigationTitle("Purchase Orders")
        .searchable(text: $searchText, prompt: "Search POs...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { activeSheet = .qrScanner } label: { Image(systemName: "qrcode.viewfinder") }
                Button { activeSheet = .createPO } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
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

    // MARK: - PO List

    @ViewBuilder
    private var poList: some View {
        if isLoading {
            ProgressView("Loading purchase orders...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredPOs.isEmpty {
            EmptyStateView(
                icon: "doc.text.fill",
                title: "No Purchase Orders",
                message: searchText.isEmpty ? "No purchase orders yet." : "No POs match your criteria."
            )
        } else {
            List(filteredPOs, id: \.id) { po in
                NavigationLink {
                    IOSPODetailPage(poId: po.id)
                        .environmentObject(appCore)
                } label: {
                    poRow(po)
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
