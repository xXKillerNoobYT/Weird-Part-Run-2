import SwiftUI
import WiredPartCore

/// Inventory grid page showing all parts with stock counts.
///
/// Provides a searchable list of stock items with a location picker,
/// smart card filters for stock status, low-stock color coding,
/// and swipe actions for transfer/audit.
struct IOSInventoryGridPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var items: [WarehouseService.LocationStock] = []
    @State private var allLocations: [LocationOption] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var selectedLocationType = "warehouse"
    @State private var selectedLocationId: Int64 = 1
    @State private var selectedFilter: StockFilter?
    @State private var actionError: String?
    @AppStorage("lastInventoryLocationType") private var lastLocationType = "warehouse"
    @AppStorage("lastInventoryLocationId") private var lastLocationId: Int = 1

    private struct LocationOption: Identifiable, Hashable {
        let locationType: String
        let locationId: Int64
        var id: String { "\(locationType)-\(locationId)" }
        var label: String {
            "\(locationType.capitalized) #\(locationId)"
        }
    }

    private enum StockFilter: String, CaseIterable {
        case lowStock = "Low Stock"
        case outOfStock = "Out of Stock"
        case healthy = "Healthy"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Location picker
            locationPicker

            // Smart card filters
            if !items.isEmpty {
                smartCardFilters
            }

            // Content
            if isLoading {
                ProgressView("Loading inventory...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if displayedItems.isEmpty {
                if searchText.isEmpty && selectedFilter == nil {
                    EmptyStateView(
                        icon: "shippingbox",
                        title: "No Inventory",
                        message: "No parts in stock at this location. Use the Movement Wizard to transfer parts here."
                    )
                } else {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Results",
                        message: "No parts match your current filters."
                    )
                }
            } else {
                inventoryList
            }
        }
        .navigationTitle("Inventory")
        .searchable(text: $searchText, prompt: "Search parts...")
        .refreshable { loadData() }
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .onChange(of: selectedLocationId) {
            lastLocationType = selectedLocationType
            lastLocationId = Int(selectedLocationId)
            loadData()
        }
        .task {
            selectedLocationType = lastLocationType
            selectedLocationId = Int64(lastLocationId)
            loadLocations()
            loadData()
        }
    }

    // MARK: - Location Picker

    private var locationPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.blue)

            if allLocations.isEmpty {
                Text("Warehouse #1")
                    .font(.subheadline)
                    .fontWeight(.medium)
            } else {
                Picker("Location", selection: Binding(
                    get: { LocationOption(locationType: selectedLocationType, locationId: selectedLocationId) },
                    set: { opt in
                        selectedLocationType = opt.locationType
                        selectedLocationId = opt.locationId
                    }
                )) {
                    ForEach(allLocations) { loc in
                        Text(loc.label).tag(loc)
                    }
                }
                .pickerStyle(.menu)
            }

            Spacer()

            Text("\(items.count) parts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(StockFilter.allCases, id: \.self) { filter in
                    let count = countForFilter(filter)
                    smartCard(filter: filter, count: count)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func countForFilter(_ filter: StockFilter) -> Int {
        items.filter { item in
            switch filter {
            case .outOfStock: item.qty <= 0
            case .lowStock: item.qty > 0 && item.qty <= 5
            case .healthy: item.qty > 5
            }
        }.count
    }

    private func smartCard(filter: StockFilter, count: Int) -> some View {
        let isSelected = selectedFilter == filter
        let color = filterColor(filter)

        return Button {
            selectedFilter = isSelected ? nil : filter
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: filterIcon(filter))
                        .font(.caption)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(filter.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 85)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }

    private func filterIcon(_ filter: StockFilter) -> String {
        switch filter {
        case .outOfStock: "xmark.circle.fill"
        case .lowStock: "exclamationmark.triangle.fill"
        case .healthy: "checkmark.circle.fill"
        }
    }

    private func filterColor(_ filter: StockFilter) -> Color {
        switch filter {
        case .outOfStock: .red
        case .lowStock: .orange
        case .healthy: .green
        }
    }

    // MARK: - Inventory List

    @ViewBuilder
    private var inventoryList: some View {
        List(displayedItems, id: \.partId) { item in
            inventoryRow(item)
                .swipeActions(edge: .trailing) {
                    Button {
                        NotificationCenter.default.post(
                            name: .navigateToModule,
                            object: nil,
                            userInfo: [
                                "moduleId": "warehouse-movements",
                                "sourceLocationType": selectedLocationType,
                                "sourceLocationId": selectedLocationId,
                                "partId": item.partId
                            ]
                        )
                    } label: {
                        Label("Transfer", systemImage: "arrow.left.arrow.right")
                    }
                    .tint(.blue)

                    Button {
                        auditItem(item)
                    } label: {
                        Label("Audit", systemImage: "clipboard")
                    }
                    .tint(.orange)
                }
        }
        .listStyle(.insetGrouped)
    }

    private var displayedItems: [WarehouseService.LocationStock] {
        var result = items

        // Stock status filter
        if let filter = selectedFilter {
            result = result.filter { item in
                switch filter {
                case .outOfStock: item.qty <= 0
                case .lowStock: item.qty > 0 && item.qty <= 5
                case .healthy: item.qty > 5
                }
            }
        }

        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.partName.lowercased().contains(query) ||
                ($0.partCode?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    private func inventoryRow(_ item: WarehouseService.LocationStock) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.partName)
                    .fontWeight(.medium)
                if let code = item.partCode, !code.isEmpty {
                    Text(code)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(item.qty)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        item.qty <= 0 ? .red :
                        item.qty <= 5 ? .orange :
                        .primary
                    )
                Text("in stock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func auditItem(_ item: WarehouseService.LocationStock) {
        guard let service = appCore.warehouseService else { return }
        do {
            try service.recordAuditRecount(
                partId: item.partId,
                locationType: item.locationType,
                locationId: item.locationId
            )
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Data Loading

    private func loadLocations() {
        guard let service = appCore.warehouseService else { return }
        do {
            let allStock = try service.getLocationStock()
            var seen: Set<String> = []
            var options: [LocationOption] = []
            for s in allStock {
                let key = "\(s.locationType)-\(s.locationId)"
                if !seen.contains(key) {
                    seen.insert(key)
                    options.append(LocationOption(locationType: s.locationType, locationId: s.locationId))
                }
            }
            allLocations = options.sorted { $0.label < $1.label }
        } catch {
            // Non-critical — location picker just won't show options
        }
    }

    private func loadData() {
        guard let service = appCore.warehouseService else { return }
        isLoading = items.isEmpty
        loadError = nil
        do {
            items = try service.getStockAtLocation(locationType: selectedLocationType, locationId: selectedLocationId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
