import SwiftUI
import WiredPartCore

/// Mileage logs list page for iOS.
///
/// Displays a list of vehicle mileage logs with vehicle name,
/// user, date, total miles, and purpose. Supports pull-to-refresh
/// and search filtering.
struct IOSMileagePage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var mileageLogs: [FleetService.MileageRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?

    var body: some View {
        mileageList
            .navigationTitle("Mileage Logs")
            .searchable(text: $searchText, prompt: "Search mileage logs...")
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Mileage List

    @ViewBuilder
    private var mileageList: some View {
        if isLoading {
            ProgressView("Loading mileage logs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredLogs.isEmpty {
            ContentUnavailableView {
                Label("No Mileage Logs", systemImage: "road.lanes")
            } description: {
                Text("No mileage logs found.")
            }
        } else {
            List(filteredLogs, id: \.id) { log in
                mileageRow(log)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredLogs: [FleetService.MileageRow] {
        guard !searchText.isEmpty else { return mileageLogs }
        let query = searchText.lowercased()
        return mileageLogs.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.userName.lowercased().contains(query) ||
            ($0.purpose?.lowercased().contains(query) ?? false)
        }
    }

    private func mileageRow(_ log: FleetService.MileageRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "speedometer")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(log.vehicleName)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Label(log.userName, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let purpose = log.purpose, !purpose.isEmpty {
                    Text(purpose)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let miles = log.totalMiles {
                    Text(String(format: "%.1f mi", miles))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(log.logDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.fleetService else { return }
        isLoading = mileageLogs.isEmpty
        do {
            mileageLogs = try service.listMileageLogs()
        } catch {
            print("[IOSMileagePage] Load error: \(error)")
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
