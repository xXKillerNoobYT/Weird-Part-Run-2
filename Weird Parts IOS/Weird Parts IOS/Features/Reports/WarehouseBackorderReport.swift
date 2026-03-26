import SwiftUI
import WiredPartCore

/// Backorder status — PO line items not yet fully received.
struct WarehouseBackorderReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var backorderData: [WarehouseService.BackorderRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Backorder Status Help", sections: [
                ("What This Page Does", "Lists all PO line items that have not been fully received yet. Shows each part, how many were ordered, how many have arrived, and how many are still pending. Helps you track what is still missing."),
                ("How to Use It", "The summary shows the total number of backordered items and outstanding quantity. Each row shows the part name, supplier, quantities received vs ordered, and expected delivery date if available."),
                ("Tips", "Check this page before planning jobs that need specific parts. If expected dates are missing, follow up with the supplier. Parts that have been backordered for a long time may need to be re-ordered from a different supplier.")
            ])
        }
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
