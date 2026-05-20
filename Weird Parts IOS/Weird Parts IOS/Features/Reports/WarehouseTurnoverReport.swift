import SwiftUI
import WiredPartCore

/// Inventory turnover — parts with the most movement activity in a period.
struct WarehouseTurnoverReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var turnoverData: [WarehouseService.TurnoverRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var dateRange: ReportDateRange = .thisMonth
    @State private var startDate = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var endDate = Date()
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    var body: some View {
        List {
            StandardFilterBar(selectedRange: $dateRange, customStart: $startDate, customEnd: $endDate)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())

            if let error = loadError {
                Section {
                    ErrorStateView(message: error) { loadData() }
                }
            }

            if isLoading {
                Section { ProgressView("Loading...") }
            } else if turnoverData.isEmpty {
                Section {
                    EmptyStateView(
                        icon: "arrow.left.arrow.right",
                        title: "No Movement Data",
                        message: "No stock movements found for this period."
                    )
                }
            } else {
                Section("Summary") {
                    LabeledContent("Parts with Activity") {
                        Text("\(turnoverData.count)")
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Total Movements") {
                        Text("\(totalMovements)")
                    }
                    LabeledContent("Total Qty Moved") {
                        Text("\(totalQtyMoved)")
                    }
                }

                Section("Top Movers") {
                    ForEach(turnoverData) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.partName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let code = row.partCode {
                                    Text(code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(row.movementCount) moves")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(row.totalQtyMoved) qty | \(row.currentStock) on hand")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Inventory Turnover")
        .reportExportToolbar(
            title: "Inventory Turnover Report",
            columns: ["Part", "Code", "Movements", "Qty Moved", "Current Stock"],
            rows: turnoverData.map { [$0.partName, $0.partCode ?? "",
                                       "\($0.movementCount)", "\($0.totalQtyMoved)",
                                       "\($0.currentStock)"] }
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
            PageHelpSheet(title: "Inventory Turnover Help", sections: [
                ("What This Page Does", "Shows which parts have the most movement activity in the selected period. Lists parts by number of movements and total quantity moved, plus current stock on hand. Helps you identify your fastest-moving inventory."),
                ("How to Use It", "Set the date range at the top. The summary tells you how many parts had activity and total movement counts. The list is sorted by most active parts first. Each row shows movement count, quantity moved, and current stock."),
                ("Tips", "High-turnover parts should always be well-stocked to avoid job delays. If a part has lots of movements but low current stock, consider increasing your reorder target. Low-turnover parts taking up shelf space might be candidates for reduction.")
            ])
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
    }

    private var totalMovements: Int { turnoverData.reduce(0) { $0 + $1.movementCount } }
    private var totalQtyMoved: Int { turnoverData.reduce(0) { $0 + $1.totalQtyMoved } }

    private func loadData() {
        isLoading = true
        loadError = nil
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            isLoading = false
            return
        }
        do {
            turnoverData = try service.getTurnoverReport(
                startDate: startDate, endDate: endDate
            )
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
    }
}
