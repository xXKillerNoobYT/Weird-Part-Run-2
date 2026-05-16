import SwiftUI
import WiredPartCore

/// Inventory value grouped by category — on hand + on order.
struct WarehouseInventoryValueReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var valueData: [WarehouseService.InventoryValueRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    var body: some View {
        List {
            if let error = loadError {
                Section {
                    ErrorStateView(message: error) { loadData() }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Inventory Value Help", sections: [
                ("What This Page Does", "Shows the total dollar value of your inventory, broken down by category. For each category, you see the on-hand value (what is in the warehouse right now) and on-order value (what has been ordered but not yet received)."),
                ("How to Use It", "The top section shows combined totals. Scroll down to see each category with its item count and values. Use this to understand where your inventory investment is concentrated."),
                ("Tips", "If one category holds most of the value, make sure those items are being tracked carefully. High on-order value means money is committed but not yet in the warehouse. Export this report for insurance or accounting reviews.")
            ])
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onAppear { postPageContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .reportsWarehouseInventoryValuePageInactive, object: nil)
        }
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
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
        postPageContext()
    }

    private func postPageContext() {
        let context = """
        Warehouse Inventory Value report page. Category rows: \(valueData.count). On-hand value total: \(String(format: "%.2f", totalOnHand)). On-order value total: \(String(format: "%.2f", totalOnOrder)). Combined value: \(String(format: "%.2f", totalOnHand + totalOnOrder)). Error state: \(loadError ?? "none"). Available read-only actions: summarize inventory value concentration, explain on-hand vs on-order mix, identify high-value categories.
        """
        NotificationCenter.default.post(name: .reportsWarehouseInventoryValuePageActive, object: nil, userInfo: ["context": context])
    }
}
