import SwiftUI
import WiredPartCore

/// Fuel cost breakdown by vehicle with date range filtering.
struct FleetFuelCostReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var fuelData: [FleetService.FuelReportRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var dateRange: ReportDateRange = .thisMonth

    var body: some View {
        List {
            // Date range picker
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
            } else if fuelData.isEmpty {
                Section {
                    ContentUnavailableView("No Fuel Data",
                        systemImage: "fuelpump",
                        description: Text("No fuel logs found for this period."))
                }
            } else {
                // Summary
                Section("Summary") {
                    LabeledContent("Total Fuel Cost") {
                        Text("$\(totalFuelCost, specifier: "%.2f")")
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Total Gallons") {
                        Text("\(totalGallons, specifier: "%.1f")")
                    }
                    LabeledContent("Avg Cost/Gallon") {
                        Text("$\(avgCostPerGallon, specifier: "%.2f")")
                    }
                }

                // Per-vehicle breakdown
                Section("By Vehicle") {
                    ForEach(fuelData) { row in
                        HStack {
                            Text(row.vehicleName)
                                .font(.subheadline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$\(row.totalCost, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(row.gallons, specifier: "%.1f") gal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fuel Costs")
        .reportExportToolbar(
            title: "Fuel Cost Report",
            columns: ["Vehicle", "Gallons", "Cost", "Cost/Gallon"],
            rows: fuelData.map { [$0.vehicleName,
                                   String(format: "%.1f", $0.gallons),
                                   String(format: "%.2f", $0.totalCost),
                                   String(format: "%.2f", $0.costPerGallon)] }
        )
        .onAppear { loadData() }
    }

    private var totalFuelCost: Double { fuelData.reduce(0) { $0 + $1.totalCost } }
    private var totalGallons: Double { fuelData.reduce(0) { $0 + $1.gallons } }
    private var avgCostPerGallon: Double { totalGallons > 0 ? totalFuelCost / totalGallons : 0 }

    private func loadData() {
        isLoading = true
        loadError = nil
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }
        do {
            fuelData = try service.getFuelCostReport(
                startDate: dateRange.startDate, endDate: dateRange.endDate
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
