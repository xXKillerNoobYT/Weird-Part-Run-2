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
    @State private var activeSheet: ActiveSheet?
    @AppStorage("lastInventoryLocationType") private var lastLocationType = "warehouse"
    @AppStorage("lastInventoryLocationId") private var lastLocationId: Int = 1

    // Cached stock counts — populated via single pass in loadData(); avoids per-render filter scans
    @State private var stockCounts: [StockFilter: Int] = [:]

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private struct LocationOption: Identifiable, Hashable {
        let locationType: String
        let locationId: Int64
        var id: String { "\(locationType)-\(locationId)" }
        var label: String {
            "\(locationType.capitalized) #\(locationId)"
        }
    }

    private var selectedLocation: LocationOption {
        LocationOption(locationType: selectedLocationType, locationId: selectedLocationId)
    }

    private enum StockFilter: String, CaseIterable {
        case lowStock = "Low Stock"
        case outOfStock = "Out of Stock"
        case healthy = "Healthy"
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "warehouse-inventory")

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
                title: "Inventory Help",
                sections: [
                    ("Overview", "View stock levels at any warehouse location. Color-coded indicators show low stock, out of stock, and healthy levels."),
                    ("Location Picker", "Use the picker at the top to switch between warehouse locations, trucks, trailers, and job sites."),
                    ("Actions", "Swipe a part row to quickly transfer stock or start an audit. Use the filter chips to focus on problem areas.")
                ]
            )
        }
        .refreshable { loadData() }
        .onAppear {
            NotificationCenter.default.post(
                name: .inventoryGridPageActive,
                object: nil,
                userInfo: [
                    "context": "Inventory Grid: \(items.count) items at \(selectedLocationType) #\(selectedLocationId), filter: \(selectedFilter?.rawValue ?? "none")."
                ]
            )
        }
        .onDisappear {
            NotificationCenter.default.post(name: .inventoryGridPageInactive, object: nil)
        }
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .onChange(of: selectedLocation) {
            persistSelectedLocation()
            loadData()
        }
        .task {
            selectedLocationType = lastLocationType
            selectedLocationId = Int64(lastLocationId)
            loadLocations()
            loadData()
            appCore.onboardingManager?.markCompleted("wh-inventory-view")
        }
    }

    // MARK: - Location Picker

    private var locationPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            if allLocations.isEmpty {
                Text("Default Warehouse")
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
                    let count = stockCounts[filter, default: 0]
                    smartCard(filter: filter, count: count)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
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
                        .accessibilityHidden(true)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(filter.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 85, minHeight: 44)
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
                        transferItem(item)
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
        .scrollDismissesKeyboard(.interactively)
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

    /// Navigate to Movements with the swiped part pre-targeted (#1373).
    ///
    /// Reuses the dashboard QR scanner's context-preserving pattern (#700): the
    /// scanned/swiped part context is stashed in `QRScanRouteStore` (keyed by the
    /// destination tab) BEFORE the `.navigateToModule` notification posts, so
    /// `WarehouseMovementsPage` consumes it on appear and opens the movement
    /// wizard with the part preselected instead of landing on the bare list.
    private func transferItem(_ item: WarehouseService.LocationStock) {
        QRScanRouteStore.shared.stash(
            QRScanRouteContext(
                entityType: .part,
                entityId: item.partId,
                code: item.partCode ?? "",
                searchHint: item.partCode,
                action: .moveStock
            ),
            for: "warehouse-movements"
        )

        var userInfo: [String: Any] = [
            "moduleId": "warehouse",
            "tabId": "warehouse-movements",
            "action": QRScanAction.moveStock.rawValue,
            "entityType": QREntityType.part.rawValue,
            "entityId": item.partId
        ]
        if let code = item.partCode {
            userInfo["code"] = code
        }
        NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: userInfo)
    }

    private func auditItem(_ item: WarehouseService.LocationStock) {
        guard let service = appCore.warehouseService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.recordAuditRecount(
                partId: item.partId,
                locationType: item.locationType,
                locationId: item.locationId
            )
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    // MARK: - Data Loading

    private func persistSelectedLocation() {
        lastLocationType = selectedLocationType
        lastLocationId = Int(selectedLocationId)
    }

    private func loadLocations() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            isLoading = false
            return
        }
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
        guard let service = appCore.warehouseService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = items.isEmpty
        loadError = nil
        do {
            items = try service.getStockAtLocation(locationType: selectedLocationType, locationId: selectedLocationId)
            // Single-pass stock counts — avoids per-render filter scans in smart card filters
            var counts: [StockFilter: Int] = [.outOfStock: 0, .lowStock: 0, .healthy: 0]
            for item in items {
                if item.qty <= 0 { counts[.outOfStock, default: 0] += 1 }
                else if item.qty <= 5 { counts[.lowStock, default: 0] += 1 }
                else { counts[.healthy, default: 0] += 1 }
            }
            stockCounts = counts
        } catch {
            loadError = userFriendlyError(error, context: "load inventory")
        }
        isLoading = false
    }
}
