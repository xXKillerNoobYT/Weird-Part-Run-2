import SwiftUI
import WiredPartCore

/// Maintenance cost trends over time with per-record detail.
struct FleetMaintenanceTrendsReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var trendData: [FleetService.MaintenanceTrendRow] = []
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
            } else if trendData.isEmpty {
                Section {
                    ContentUnavailableView("No Maintenance Data",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("No maintenance records found for this period."))
                }
            } else {
                Section("Summary") {
                    LabeledContent("Total Cost") {
                        Text("$\(totalCost, specifier: "%.2f")")
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Records") {
                        Text("\(trendData.count)")
                    }
                    LabeledContent("Avg Cost/Record") {
                        Text("$\(avgCost, specifier: "%.2f")")
                    }
                }

                Section("Maintenance Records") {
                    ForEach(trendData) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.vehicleName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("$\(row.cost, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            HStack {
                                Text(row.maintenanceType)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatDate(row.performedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Maintenance Trends")
        .reportExportToolbar(
            title: "Maintenance Trends Report",
            columns: ["Vehicle", "Type", "Cost", "Date"],
            rows: trendData.map { [$0.vehicleName, $0.maintenanceType,
                                    String(format: "%.2f", $0.cost),
                                    formatDate($0.performedAt)] }
        )
        .onAppear { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
    }

    private var totalCost: Double { trendData.reduce(0) { $0 + $1.cost } }
    private var avgCost: Double { trendData.isEmpty ? 0 : totalCost / Double(trendData.count) }

    private func formatDate(_ str: String) -> String {
        // Extract date portion from ISO string
        String(str.prefix(10))
    }

    private func loadData() {
        isLoading = true
        loadError = nil
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }
        do {
            trendData = try service.getMaintenanceTrendsReport(
                startDate: startDate, endDate: endDate
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
