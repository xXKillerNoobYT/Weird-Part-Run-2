import SwiftUI
import WiredPartCore

/// Fuel cost breakdown by vehicle with date range filtering.
struct FleetFuelCostReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var fuelData: [FleetService.FuelReportRow] = []
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
                    ErrorStateView(message: error) { loadData() }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Fuel Costs Help", sections: [
                ("What This Page Does", "Breaks down fuel spending per vehicle for the date range you select. Shows total gallons, total cost, average cost per gallon, and a per-vehicle breakdown."),
                ("How to Use It", "Set the date range at the top. The summary section shows fleet-wide totals. Below that, each vehicle lists its fuel cost and gallons. Use the export button to save as PDF or CSV."),
                ("Tips", "If one vehicle's cost per gallon is much higher than the rest, check that fuel logs are entered correctly. Compare month-over-month to spot trends in fuel pricing or vehicle efficiency.")
            ])
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
        .onAppear { postPageContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .reportsFleetFuelCostsPageInactive, object: nil)
        }
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
                startDate: startDate, endDate: endDate
            )
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
        postPageContext()
    }

    private func postPageContext() {
        let context = """
        Fleet Fuel Costs report page. Rows: \(fuelData.count). Date range: \(startDate.formatted(date: .abbreviated, time: .omitted)) to \(endDate.formatted(date: .abbreviated, time: .omitted)). Total fuel cost: \(String(format: "%.2f", totalFuelCost)). Total gallons: \(String(format: "%.1f", totalGallons)). Avg cost per gallon: \(String(format: "%.2f", avgCostPerGallon)). Error state: \(loadError ?? "none"). Available read-only actions: summarize fuel spend trends, compare vehicle fuel burden, explain date-filtered totals.
        """
        NotificationCenter.default.post(name: .reportsFleetFuelCostsPageActive, object: nil, userInfo: ["context": context])
    }
}
