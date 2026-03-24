import SwiftUI
import WiredPartCore

/// Inventory value grouped by category — on hand + on order.
struct WarehouseInventoryValueReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var valueData: [WarehouseService.InventoryValueRow] = []
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if let error = loadError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if isLoading {
                Section { ProgressView("Loading...") }
            } else if valueData.isEmpty {
                Section {
                    ContentUnavailableView("No Inventory Data",
                        systemImage: "shippingbox",
                        description: Text("No inventory categories found."))
                }
            } else {
                Section("Total Value") {
                    LabeledContent("On Hand") {
                        Text("$\(totalOnHand, specifier: "%.2f")")
                            .fontWeight(.semibold)
                    }
                    LabeledContent("On Order") {
                        Text("$\(totalOnOrder, specifier: "%.2f")")
                    }
                    LabeledContent("Combined") {
                        Text("$\(totalOnHand + totalOnOrder, specifier: "%.2f")")
                            .fontWeight(.bold)
                    }
                }

                Section("By Category") {
                    ForEach(valueData) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.categoryName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(row.itemCount) items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$\(row.onHandValue, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if row.onOrderValue > 0 {
                                    Text("+$\(row.onOrderValue, specifier: "%.2f") on order")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Inventory Value")
        .reportExportToolbar(
            title: "Inventory Value Report",
            columns: ["Category", "Items", "On Hand Value", "On Order Value"],
            rows: valueData.map { [$0.categoryName, "\($0.itemCount)",
                                    String(format: "%.2f", $0.onHandValue),
                                    String(format: "%.2f", $0.onOrderValue)] }
        )
        .onAppear { loadData() }
    }

    private var totalOnHand: Double { valueData.reduce(0) { $0 + $1.onHandValue } }
    private var totalOnOrder: Double { valueData.reduce(0) { $0 + $1.onOrderValue } }

    private func loadData() {
        isLoading = true
        loadError = nil
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            isLoading = false
            return
        }
        do {
            valueData = try service.getInventoryValueReport()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
