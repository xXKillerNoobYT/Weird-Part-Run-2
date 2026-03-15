import SwiftUI
import WiredPartCore

/// Fuel logs list page.
///
/// Displays a sortable table of all fuel log entries with vehicle name,
/// user, date, gallons, cost, and station columns. Supports searching
/// by vehicle name, user name, or station.
struct FuelPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var logs: [FleetService.FuelRow] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\FleetService.FuelRow.id)]

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
                Text("Fuel Logs")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(logs.count) log\(logs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search fuel logs...", text: $searchText)
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
            ProgressView("Loading fuel logs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if logs.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "fuelpump")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No fuel logs found")
                    .font(.headline)
                Text("Fuel entries will appear here when logged.")
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
                .width(min: 100, ideal: 130)

                TableColumn("Date", value: \.logDate) { log in
                    Text(log.logDate)
                        .font(.caption)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Gallons") { (log: FleetService.FuelRow) in
                    if let gallons = log.gallons {
                        Text(String(format: "%.2f", gallons))
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 60, ideal: 80)

                TableColumn("Cost") { (log: FleetService.FuelRow) in
                    Text(formatCurrency(log.totalCost))
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 70, ideal: 90)

                TableColumn("Station") { (log: FleetService.FuelRow) in
                    Text(log.station ?? "-")
                        .lineLimit(1)
                        .foregroundStyle(log.station != nil ? .primary : .secondary)
                }
                .width(min: 100, ideal: 160)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedLogs: [FleetService.FuelRow] {
        logs.sorted(using: sortOrder)
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
            let allLogs = try service.listFuelLogs()
            // Client-side search filter
            if searchText.isEmpty {
                logs = allLogs
            } else {
                let query = searchText.lowercased()
                logs = allLogs.filter {
                    $0.vehicleName.lowercased().contains(query) ||
                    $0.userName.lowercased().contains(query) ||
                    ($0.station?.lowercased().contains(query) ?? false)
                }
            }
        } catch {
            print("[FuelPage] Load error: \(error)")
        }
        isLoading = false
    }
}
