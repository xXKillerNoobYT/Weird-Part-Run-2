import SwiftUI
import WiredPartCore

/// Supplier-centric parts view across all POs.
///
/// Shows all parts ordered from a supplier across all active POs,
/// grouped by PO then by job. Supports multi-select for part-level
/// actions: move to different PO, change qty, remove + hold.
struct IOSPartsOrderManagementPage: View {
    @EnvironmentObject private var appCore: AppCore

    /// Optional pre-filter to a specific supplier (from PO Detail "Manage Parts" button).
    var preSelectedSupplierId: Int64? = nil

    @State private var suppliers: [(id: Int64, name: String, poCount: Int)] = []
    @State private var selectedSupplierId: Int64?
    @State private var allRows: [OrdersService.PartsManagementRow] = []
    @State private var isLoading = true
    @State private var loadError: String?

    // PO status filters
    @State private var showDraft = true
    @State private var showActive = true
    @State private var showPartial = true
    @State private var showReceived = false
    @State private var showCancelled = false

    // Part status filters
    @State private var showWaiting = true
    @State private var showBackorder = true
    @State private var showReceivedParts = false

    // Search
    @State private var searchText = ""

    // Multi-selection
    @State private var selectedPartIds: Set<Int64> = []

    var body: some View {
        VStack(spacing: 0) {
            supplierPicker
            poStatusFilters
            partStatusFilters

            if isLoading {
                ProgressView("Loading parts...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if filteredRows.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Parts",
                    message: selectedSupplierId == nil
                        ? "Select a supplier above to view parts."
                        : "No parts match the current filters."
                )
            } else {
                partsList
            }

            if !selectedPartIds.isEmpty {
                selectionActionBar
            }
        }
        .navigationTitle("Parts Management")
        .searchable(text: $searchText, prompt: "Search parts by name, code, or job...")
        .task {
            loadSuppliers()
            if let pre = preSelectedSupplierId {
                selectedSupplierId = pre
            } else if let first = suppliers.first {
                selectedSupplierId = first.id
            }
            loadData()
        }
    }

    // MARK: - Supplier Picker

    private var supplierPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suppliers, id: \.id) { supplier in
                    Button {
                        selectedSupplierId = supplier.id
                        selectedPartIds.removeAll()
                        loadData()
                    } label: {
                        VStack(spacing: 2) {
                            Text(supplier.name)
                                .font(.caption)
                                .fontWeight(selectedSupplierId == supplier.id ? .bold : .regular)
                            Text("\(supplier.poCount) POs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedSupplierId == supplier.id ? Color.accentColor : Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(selectedSupplierId == supplier.id ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - PO Status Filters

    private var poStatusFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterToggle("Draft", isOn: $showDraft, color: .secondary)
                filterToggle("Active", isOn: $showActive, color: .blue)
                filterToggle("Partial", isOn: $showPartial, color: .purple)
                filterToggle("Received", isOn: $showReceived, color: .green)
                filterToggle("Cancelled", isOn: $showCancelled, color: .red)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Part Status Filters

    private var partStatusFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterToggle("Waiting", isOn: $showWaiting, color: .blue)
                filterToggle("Backorder", isOn: $showBackorder, color: .red)
                filterToggle("Received", isOn: $showReceivedParts, color: .green)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private func filterToggle(_ label: String, isOn: Binding<Bool>, color: Color) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isOn.wrappedValue ? color.opacity(0.2) : Color.clear)
                )
                .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
                .foregroundStyle(isOn.wrappedValue ? color : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtered Data

    private var filteredRows: [OrdersService.PartsManagementRow] {
        allRows.filter { row in
            let poPass: Bool = {
                switch row.poStatus {
                case "draft": return showDraft
                case "submitted", "ordered": return showActive
                case "partial": return showPartial
                case "received": return showReceived
                case "cancelled": return showCancelled
                default: return true
                }
            }()

            let partPass: Bool = {
                switch row.lineStatus {
                case "received": return showReceivedParts
                case "pending": return showWaiting
                case "backorder": return showBackorder
                default: return true
                }
            }()

            let searchPass: Bool = {
                guard !searchText.isEmpty else { return true }
                let query = searchText.lowercased()
                return row.partName.lowercased().contains(query) ||
                    (row.partCode?.lowercased().contains(query) ?? false) ||
                    (row.jobName?.lowercased().contains(query) ?? false) ||
                    row.poNumber.lowercased().contains(query)
            }()

            return poPass && partPass && searchPass
        }
    }

    /// Group filtered rows by PO.
    private var groupedByPO: [(poNumber: String, poStatus: String, rows: [OrdersService.PartsManagementRow])] {
        let dict = Dictionary(grouping: filteredRows, by: \.poNumber)
        return dict.map { (poNumber: $0.key, poStatus: $0.value.first?.poStatus ?? "", rows: $0.value) }
            .sorted { $0.poNumber < $1.poNumber }
    }

    // MARK: - Parts List

    private var partsList: some View {
        List {
            ForEach(groupedByPO, id: \.poNumber) { group in
                Section {
                    ForEach(group.rows) { row in
                        partRow(row)
                    }
                } header: {
                    HStack {
                        Text(group.poNumber)
                            .font(.caption)
                            .fontWeight(.bold)
                        StatusBadge(text: group.poStatus.capitalized, color: statusColor(group.poStatus))
                        Spacer()
                        if let eta = group.rows.first?.expectedDelivery {
                            Text("ETA: \(eta)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { loadData() }
    }

    @ViewBuilder
    private func partRow(_ row: OrdersService.PartsManagementRow) -> some View {
        HStack(spacing: 10) {
            // Checkbox
            Button {
                if selectedPartIds.contains(row.id) {
                    selectedPartIds.remove(row.id)
                } else {
                    selectedPartIds.insert(row.id)
                }
            } label: {
                Image(systemName: selectedPartIds.contains(row.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedPartIds.contains(row.id) ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Status icon
            statusIcon(row.lineStatus)

            // Part info
            VStack(alignment: .leading, spacing: 2) {
                Text(row.partName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let code = row.partCode {
                    Text(code)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                if let job = row.jobName {
                    Label(job, systemImage: "hammer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Qty + price
            VStack(alignment: .trailing, spacing: 2) {
                Text("qty: \(row.quantityOrdered)")
                    .font(.caption)
                if row.quantityReceived > 0 {
                    Text("\(row.quantityReceived) recv'd")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                if let price = row.unitPrice {
                    Text(String(format: "$%.2f", price * Double(row.quantityOrdered)))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .frame(minHeight: 50)
    }

    @ViewBuilder
    private func statusIcon(_ status: String) -> some View {
        switch status {
        case "received":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case "backorder":
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.red)
                .font(.caption)
        case "pending":
            Image(systemName: "hourglass")
                .foregroundStyle(.blue)
                .font(.caption)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Text("\(selectedPartIds.count) selected")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button("Move to PO") {
                    // TODO: Move to different PO sheet
                }
                .font(.caption)
                .buttonStyle(.bordered)
                Button("Change Qty") {
                    // TODO: Change quantity sheet
                }
                .font(.caption)
                .buttonStyle(.bordered)
                Button("Remove + Hold") {
                    // TODO: Remove and hold for different supplier
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
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
        default: .secondary
        }
    }

    // MARK: - Data Loading

    private func loadSuppliers() {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
        do {
            suppliers = try service.getSuppliersWithActivePOs()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadData() {
        guard let service = appCore.ordersService, let suppId = selectedSupplierId else {
            isLoading = false
            return
        }
        isLoading = allRows.isEmpty
        loadError = nil
        do {
            allRows = try service.getPartsForSupplier(supplierId: suppId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
