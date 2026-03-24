import SwiftUI
import WiredPartCore

/// Mileage summary per vehicle with trip counts and averages.
struct FleetMileageSummaryReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var mileageData: [FleetService.MileageSummaryRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var dateRange: ReportDateRange = .thisMonth

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $dateRange) {
                    ForEach(ReportDateRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: dateRange) { _, _ in loadData() }
            }

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
        .onAppear { loadData() }
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
                startDate: dateRange.startDate, endDate: dateRange.endDate
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
