import SwiftUI
import WiredPartCore

/// Backorder status — PO line items not yet fully received.
struct WarehouseBackorderReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var backorderData: [WarehouseService.BackorderRow] = []
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
            } else if backorderData.isEmpty {
                Section {
                    ContentUnavailableView("No Backorders",
                        systemImage: "checkmark.circle",
                        description: Text("All PO items are fully received."))
                }
            } else {
                Section("Summary") {
                    LabeledContent("Backordered Items") {
                        Text("\(backorderData.count)")
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Total Qty Outstanding") {
                        Text("\(totalBackordered)")
                    }
                }

                Section("Backorder Details") {
                    ForEach(backorderData) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.partName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(row.qtyBackordered) pending")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                    .fontWeight(.medium)
                            }
                            HStack {
                                if let code = row.partCode {
                                    Text(code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let supplier = row.supplierName {
                                    Text("from \(supplier)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(row.qtyReceived)/\(row.qtyOrdered) received")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let expected = row.expectedDate, !expected.isEmpty {
                                Label("Expected: \(String(expected.prefix(10)))", systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Backorder Status")
        .reportExportToolbar(
            title: "Backorder Status Report",
            columns: ["Part", "Code", "Ordered", "Received", "Backordered", "Supplier"],
            rows: backorderData.map { [$0.partName, $0.partCode ?? "",
                                        "\($0.qtyOrdered)", "\($0.qtyReceived)",
                                        "\($0.qtyBackordered)",
                                        $0.supplierName ?? ""] }
        )
        .onAppear { loadData() }
    }

    private var totalBackordered: Int { backorderData.reduce(0) { $0 + $1.qtyBackordered } }

    private func loadData() {
        isLoading = true
        loadError = nil
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            isLoading = false
            return
        }
        do {
            backorderData = try service.getBackorderReport()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
