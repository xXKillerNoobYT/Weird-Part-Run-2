import SwiftUI
import WiredPartCore

/// Inventory turnover — parts with the most movement activity in a period.
struct WarehouseTurnoverReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var turnoverData: [WarehouseService.TurnoverRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var startDate = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var endDate = Date()

    var body: some View {
        List {
            StandardFilterBar(startDate: $startDate, endDate: $endDate)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())

            if let error = loadError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if isLoading {
                Section { ProgressView("Loading...") }
            } else if turnoverData.isEmpty {
                Section {
                    ContentUnavailableView("No Movement Data",
                        systemImage: "arrow.left.arrow.right",
                        description: Text("No stock movements found for this period."))
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
        .onAppear { loadData() }
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
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
