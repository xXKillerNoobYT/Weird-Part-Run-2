import SwiftUI
import WiredPartCore

/// Mileage logs list page.
///
/// Displays a sortable table of all mileage log entries with vehicle name,
/// user, date, miles, and purpose columns. Supports searching by vehicle
/// name, user name, or purpose.
struct MileagePage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var logs: [FleetService.MileageRow] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\FleetService.MileageRow.id)]

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
                Text("Mileage Logs")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(logs.count) log\(logs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search mileage...", text: $searchText)
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
            ProgressView("Loading mileage logs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if logs.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "speedometer")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No mileage logs found")
                    .font(.headline)
                Text("Mileage entries will appear here when logged.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedLogs, sortOrder: $sortOrder) {
                TableColumn("Vehicle", value: \.vehicleName) { log in
                    Text(log.vehicleName)
                        .fontWeight(.medium)
                }
                .width(min: 120, ideal: 160)

                TableColumn("User", value: \.userName) { log in
                    Text(log.userName)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Date", value: \.logDate) { log in
                    Text(log.logDate)
                        .font(.caption)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Miles") { (log: FleetService.MileageRow) in
                    if let miles = log.totalMiles {
                        Text(String(format: "%.1f", miles))
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 60, ideal: 80)

                TableColumn("Purpose") { (log: FleetService.MileageRow) in
                    Text(log.purpose ?? "-")
                        .lineLimit(1)
                        .foregroundStyle(log.purpose != nil ? .primary : .secondary)
                }
                .width(min: 140, ideal: 220)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedLogs: [FleetService.MileageRow] {
        logs.sorted(using: sortOrder)
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = FleetService(db: db)
        isLoading = true
        do {
            let allLogs = try service.listMileageLogs()
            // Client-side search filter
            if searchText.isEmpty {
                logs = allLogs
            } else {
                let query = searchText.lowercased()
                logs = allLogs.filter {
                    $0.vehicleName.lowercased().contains(query) ||
                    $0.userName.lowercased().contains(query) ||
                    ($0.purpose?.lowercased().contains(query) ?? false)
                }
            }
        } catch {
            print("[MileagePage] Load error: \(error)")
        }
        isLoading = false
    }
}
