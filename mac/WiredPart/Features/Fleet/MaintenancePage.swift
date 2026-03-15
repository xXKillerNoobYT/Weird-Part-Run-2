import SwiftUI
import WiredPartCore

/// Maintenance records list page.
///
/// Displays a sortable table of all vehicle maintenance records with vehicle name,
/// type, date performed, performer, cost, and odometer reading columns.
/// Supports searching by vehicle name or maintenance type.
struct MaintenancePage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var records: [FleetService.MaintenanceRow] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\FleetService.MaintenanceRow.id)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { load() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Maintenance Records")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(records.count) record\(records.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search maintenance...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { load() }

            Button {
                load()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading maintenance records...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if records.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No maintenance records found")
                    .font(.headline)
                Text("Maintenance records will appear here when logged.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedRecords, sortOrder: $sortOrder) {
                TableColumn("Vehicle", value: \.vehicleName) { record in
                    Text(record.vehicleName)
                        .fontWeight(.medium)
                }
                .width(min: 120, ideal: 160)

                TableColumn("Type") { (record: FleetService.MaintenanceRow) in
                    Text(record.maintenanceTypeName ?? "-")
                }
                .width(min: 100, ideal: 140)

                TableColumn("Performed At", value: \.performedAt) { record in
                    Text(record.performedAt)
                        .font(.caption)
                }
                .width(min: 100, ideal: 140)

                TableColumn("By") { (record: FleetService.MaintenanceRow) in
                    Text(record.performedByName ?? "-")
                }
                .width(min: 100, ideal: 130)

                TableColumn("Cost") { (record: FleetService.MaintenanceRow) in
                    Text(formatCurrency(record.cost))
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 70, ideal: 90)

                TableColumn("Odometer") { (record: FleetService.MaintenanceRow) in
                    if let odo = record.odometerReading {
                        Text("\(odo.formatted()) mi")
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 80, ideal: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedRecords: [FleetService.MaintenanceRow] {
        records.sorted(using: sortOrder)
    }

    // MARK: - Formatters

    private func formatCurrency(_ amount: Double?) -> String {
        guard let amount else { return "-" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = FleetService(db: db)
        isLoading = true
        do {
            let allRecords = try service.listMaintenanceRecords()
            // Client-side search filter
            if searchText.isEmpty {
                records = allRecords
            } else {
                let query = searchText.lowercased()
                records = allRecords.filter {
                    $0.vehicleName.lowercased().contains(query) ||
                    ($0.maintenanceTypeName?.lowercased().contains(query) ?? false) ||
                    ($0.performedByName?.lowercased().contains(query) ?? false)
                }
            }
        } catch {
            print("[MaintenancePage] Load error: \(error)")
        }
        isLoading = false
    }
}
