import SwiftUI
import WiredPartCore

/// Mileage summary per vehicle with trip counts and averages.
struct FleetMileageSummaryReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var mileageData: [FleetService.MileageSummaryRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var dateRange: ReportDateRange = .thisMonth
    @State private var startDate = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var endDate = Date()
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    var body: some View {
        List {
            StandardFilterBar(selectedRange: $dateRange, customStart: $startDate, customEnd: $endDate)
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
            } else if mileageData.isEmpty {
                Section {
                    ContentUnavailableView("No Mileage Data",
                        systemImage: "speedometer",
                        description: Text("No mileage logs found for this period."))
                }
            } else {
                Section("Summary") {
                    LabeledContent("Total Miles") {
                        Text("\(totalMiles, specifier: "%.1f")")
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Total Trips") {
                        Text("\(totalTrips)")
                    }
                    LabeledContent("Avg Miles/Trip") {
                        Text("\(avgMilesPerTrip, specifier: "%.1f")")
                    }
                }

                Section("By Vehicle") {
                    ForEach(mileageData) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.vehicleName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(row.tripCount) trips")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(row.totalMiles, specifier: "%.1f") mi")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("avg \(row.avgMilesPerTrip, specifier: "%.1f")/trip")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Mileage Summary")
        .reportExportToolbar(
            title: "Mileage Summary Report",
            columns: ["Vehicle", "Total Miles", "Trips", "Avg Miles/Trip"],
            rows: mileageData.map { [$0.vehicleName,
                                      String(format: "%.1f", $0.totalMiles),
                                      "\($0.tripCount)",
                                      String(format: "%.1f", $0.avgMilesPerTrip)] }
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Mileage Summary Help", sections: [
                ("What This Page Does", "Shows total miles driven per vehicle over the selected period, including trip counts and average miles per trip. Helps you track vehicle usage and plan maintenance based on mileage."),
                ("How to Use It", "Set the date range at the top. The summary section shows fleet-wide totals. Each vehicle row shows total miles, trip count, and average miles per trip. Export for reimbursement or fleet tracking."),
                ("Tips", "Vehicles with very high mileage may need oil changes or tire rotations sooner. Compare mileage against fuel costs to spot vehicles with poor fuel efficiency.")
            ])
        }
        .onAppear { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
    }

    private var totalMiles: Double { mileageData.reduce(0) { $0 + $1.totalMiles } }
    private var totalTrips: Int { mileageData.reduce(0) { $0 + $1.tripCount } }
    private var avgMilesPerTrip: Double { totalTrips > 0 ? totalMiles / Double(totalTrips) : 0 }

    private func loadData() {
        isLoading = true
        loadError = nil
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }
        do {
            mileageData = try service.getMileageSummaryReport(
                startDate: startDate, endDate: endDate
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
