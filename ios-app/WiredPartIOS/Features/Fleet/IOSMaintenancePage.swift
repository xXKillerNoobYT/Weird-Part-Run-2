import SwiftUI
import WiredPartCore

/// Maintenance records list page for iOS.
///
/// Displays a list of vehicle maintenance records with vehicle name,
/// maintenance type, date, cost, and odometer reading.
/// Supports pull-to-refresh and search filtering.
struct IOSMaintenancePage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var records: [FleetService.MaintenanceRow] = []
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            maintenanceList
                .navigationTitle("Maintenance")
                .searchable(text: $searchText, prompt: "Search maintenance records...")
                .refreshable { loadData() }
                .task { loadData() }
        }
    }

    // MARK: - Maintenance List

    @ViewBuilder
    private var maintenanceList: some View {
        if isLoading {
            ProgressView("Loading maintenance records...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredRecords.isEmpty {
            ContentUnavailableView {
                Label("No Maintenance Records", systemImage: "wrench.and.screwdriver")
            } description: {
                Text("No maintenance records found.")
            }
        } else {
            List(filteredRecords, id: \.id) { record in
                maintenanceRow(record)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredRecords: [FleetService.MaintenanceRow] {
        guard !searchText.isEmpty else { return records }
        let query = searchText.lowercased()
        return records.filter {
            $0.vehicleName.lowercased().contains(query) ||
            ($0.maintenanceTypeName?.lowercased().contains(query) ?? false) ||
            ($0.performedByName?.lowercased().contains(query) ?? false)
        }
    }

    private func maintenanceRow(_ record: FleetService.MaintenanceRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.vehicleName)
                    .fontWeight(.medium)
                if let typeName = record.maintenanceTypeName {
                    Text(typeName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(record.performedAt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let performer = record.performedByName {
                        Text("by \(performer)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let cost = record.cost {
                    Text(String(format: "$%.2f", cost))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                if let odo = record.odometerReading {
                    Text("\(odo.formatted()) mi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.fleetService else { return }
        isLoading = records.isEmpty
        do {
            records = try service.listMaintenanceRecords()
        } catch {
            print("[IOSMaintenancePage] Load error: \(error)")
        }
        isLoading = false
    }
}
