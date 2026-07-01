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
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()

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

    // Help
    @State private var activeSheet: ActiveSheet?

    // Toast
    @State private var showComingSoon = false

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private enum PartsOrderManagementEmptyReason {
        case noSuppliersWithActivePOs
        case selectSupplier
        case noMatchingParts

        var title: String {
            switch self {
            case .noSuppliersWithActivePOs: "No Suppliers"
            case .selectSupplier, .noMatchingParts: "No Parts"
            }
        }

        var message: String {
            switch self {
            case .noSuppliersWithActivePOs:
                "No suppliers with active purchase orders. Create or activate a purchase order for a supplier to manage its parts here."
            case .selectSupplier:
                "Select a supplier above to view parts."
            case .noMatchingParts:
                "No parts match the current filters."
            }
        }
    }

    private var emptyReason: PartsOrderManagementEmptyReason {
        if suppliers.isEmpty { return .noSuppliersWithActivePOs }
        if selectedSupplierId == nil { return .selectSupplier }
        return .noMatchingParts
    }

    var body: some View {
        VStack(spacing: 0) {
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
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
                    title: emptyReason.title,
                    message: emptyReason.message
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
        .onChange(of: searchText) { _, _ in postAIContext() }
        .onChange(of: dateRange) { _, _ in postAIContext() }
        .onChange(of: customStart) { _, _ in postAIContext() }
        .onChange(of: customEnd) { _, _ in postAIContext() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Parts Management Help",
                sections: [
                    ("What This Page Does", "Shows all parts ordered from a specific supplier across all active purchase orders. This is the supplier-centric view -- see everything you've ordered from one supplier in one place."),
                    ("How to Use It", "Pick a supplier from the cards at the top. Use PO status filters (Draft, Active, Partial, etc.) and part status filters (Waiting, Backorder, Received) to narrow the list. Search by part name, code, job name, or PO number."),
                    ("Multi-Select Actions", "Tap the circle next to parts to select them. The action bar at the bottom lets you move selected parts to a different PO, change quantities, or remove and hold them for a different supplier."),
                    ("Tips", "Parts are grouped by PO number with the PO status and ETA shown in each section header. This view is great for checking what's outstanding with a specific supplier before calling them.")
                ]
            )
        }
        .overlay(alignment: .bottom) {
            if showComingSoon {
                Text("Coming in a future update")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showComingSoon = false }
                        }
                    }
            }
        }
        .task {
            loadSuppliers()
            if let pre = preSelectedSupplierId {
                selectedSupplierId = pre
            } else if let first = suppliers.first {
                selectedSupplierId = first.id
            }
            loadData()
        }
        .onDisappear {
            NotificationCenter.default.post(name: .partsOrderManagementPageInactive, object: nil)
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
                && dateStringFallsInSelectedRange(row.orderDate ?? row.expectedDelivery)
        }
    }

    private var effectiveStart: Date {
        dateRange.dateInterval?.start ?? customStart
    }

    private var effectiveEnd: Date {
        dateRange.dateInterval?.end ?? customEnd
    }

    private func dateStringFallsInSelectedRange(_ rawDate: String?) -> Bool {
        guard let date = parseFilterDate(rawDate) else { return false }
        return date >= Calendar.current.startOfDay(for: effectiveStart) && date <= endOfDay(for: effectiveEnd)
    }

    private func endOfDay(for date: Date) -> Date {
        Calendar.current.dateInterval(of: .day, for: date)?.end.addingTimeInterval(-1) ?? date
    }

    private func parseFilterDate(_ rawDate: String?) -> Date? {
        guard let rawDate, !rawDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Formatters.sqlDateTimeFormatter.date(from: rawDate)
            ?? Formatters.iso8601Fractional.date(from: rawDate)
            ?? Formatters.iso8601Basic.date(from: rawDate)
            ?? Formatters.localDateFormatter.date(from: String(rawDate.prefix(10)))
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
            .accessibilityLabel(selectedPartIds.contains(row.id) ? "Deselect part" : "Select part")

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
                .accessibilityHidden(true)
        case "backorder":
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.red)
                .font(.caption)
                .accessibilityHidden(true)
        case "pending":
            Image(systemName: "hourglass")
                .foregroundStyle(.blue)
                .font(.caption)
                .accessibilityHidden(true)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .accessibilityHidden(true)
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
                    withAnimation { showComingSoon = true }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                Button("Change Qty") {
                    withAnimation { showComingSoon = true }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                Button("Remove + Hold") {
                    withAnimation { showComingSoon = true }
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
            if suppliers.isEmpty {
                selectedSupplierId = nil
                allRows = []
                loadError = nil
            }
        } catch {
            loadError = userFriendlyError(error, context: "load parts orders")
        }
    }

    private func loadData() {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
        guard let suppId = selectedSupplierId else {
            allRows = []
            loadError = nil
            isLoading = false
            return
        }
        isLoading = allRows.isEmpty
        loadError = nil
        do {
            allRows = try service.getPartsForSupplier(supplierId: suppId)
            postAIContext()
        } catch {
            loadError = userFriendlyError(error, context: "load parts orders")
        }
        isLoading = false
    }

    private func postAIContext() {
        let supplierName = suppliers.first(where: { $0.id == selectedSupplierId })?.name ?? "none"
        let selectedQuantity = allRows
            .filter { selectedPartIds.contains($0.id) }
            .reduce(0) { $0 + $1.quantityOrdered }
        let context = [
            "Parts order management page is open.",
            "Selected supplier: \(supplierName). Suppliers with active POs: \(suppliers.count).",
            "Rows loaded: \(allRows.count), filtered rows: \(filteredRows.count), selected rows: \(selectedPartIds.count), selected quantity: \(selectedQuantity).",
            "PO filters draft/active/partial/received/cancelled: \(showDraft)/\(showActive)/\(showPartial)/\(showReceived)/\(showCancelled).",
            "Part filters waiting/backorder/received: \(showWaiting)/\(showBackorder)/\(showReceivedParts). Search text is \(searchText.isEmpty ? "empty" : "active").",
            "This context is read-only; explain supplier-centric PO parts, filters, outstanding quantities, and selection options without moving or editing parts."
        ].joined(separator: " ")
        NotificationCenter.default.post(
            name: .partsOrderManagementPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }
}
