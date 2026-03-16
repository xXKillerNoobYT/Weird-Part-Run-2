import SwiftUI
import WiredPartCore

/// Fuel log list page for iOS.
///
/// Displays a searchable list of fuel logs with vehicle name, date,
/// gallons, cost, and station. Uses FleetService.listFuelLogs().
/// Supports pull-to-refresh and search filtering.
struct IOSFuelPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var fuelLogs: [FleetService.FuelRow] = []
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            fuelList
                .navigationTitle("Fuel Logs")
                .searchable(text: $searchText, prompt: "Search fuel logs...")
                .refreshable { loadData() }
                .task { loadData() }
        }
    }

    // MARK: - Fuel List

    @ViewBuilder
    private var fuelList: some View {
        if isLoading {
            ProgressView("Loading fuel logs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredLogs.isEmpty {
            ContentUnavailableView {
                Label("No Fuel Logs", systemImage: "fuelpump")
            } description: {
                Text("No fuel logs found.")
            }
        } else {
            List(filteredLogs, id: \.id) { log in
                fuelRow(log)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredLogs: [FleetService.FuelRow] {
        guard !searchText.isEmpty else { return fuelLogs }
        let query = searchText.lowercased()
        return fuelLogs.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.userName.lowercased().contains(query) ||
            ($0.station?.lowercased().contains(query) ?? false)
        }
    }

    private func fuelRow(_ log: FleetService.FuelRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "fuelpump.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(log.vehicleName)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(log.logDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let station = log.station, !station.isEmpty {
                        Text(station)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let cost = log.totalCost {
                    Text(String(format: "$%.2f", cost))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                if let gallons = log.gallons {
                    Text(String(format: "%.1f gal", gallons))
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
        isLoading = fuelLogs.isEmpty
        do {
            fuelLogs = try service.listFuelLogs()
        } catch {
            print("[IOSFuelPage] Load error: \(error)")
        }
        isLoading = false
    }
}
