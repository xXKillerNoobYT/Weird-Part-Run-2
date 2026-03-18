import SwiftUI
import WiredPartCore

/// Inventory grid page showing all parts with stock counts.
///
/// Provides a searchable list of stock items at the primary warehouse location.
/// Shows part name, code, quantity, and low stock warnings.
struct IOSInventoryGridPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var items: [WarehouseService.LocationStock] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading inventory...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if filteredItems.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Inventory",
                    message: searchText.isEmpty ? "No parts in stock at this location." : "No parts match your search."
                )
            } else {
                List(filteredItems, id: \.partId) { item in
                    inventoryRow(item)
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            }
        }
        .navigationTitle("Inventory")
        .searchable(text: $searchText, prompt: "Search parts...")
        .refreshable { loadData() }
        .task { loadData() }
    }

    private var filteredItems: [WarehouseService.LocationStock] {
        guard !searchText.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter {
            $0.partName.lowercased().contains(query) ||
            ($0.partCode?.lowercased().contains(query) ?? false)
        }
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
                    .foregroundStyle(item.qty <= 0 ? .red : .primary)
                Text("in stock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadData() {
        guard let service = appCore.warehouseService else { return }
        isLoading = items.isEmpty
        loadError = nil
        do {
            // Load stock at the primary warehouse (location_type: "warehouse", id: 1)
            items = try service.getStockAtLocation(locationType: "warehouse", locationId: 1)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
