import SwiftUI
import WiredPartCore

/// Vehicle utilization report — days active vs total days in period.
struct FleetUtilizationReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var utilizationData: [FleetService.VehicleUtilizationRow] = []
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
            } else if utilizationData.isEmpty {
                Section {
                    ContentUnavailableView("No Utilization Data",
                        systemImage: "car.fill",
                        description: Text("No vehicle activity found for this period."))
                }
            } else {
                Section("Summary") {
                    LabeledContent("Avg Utilization") {
                        Text("\(Int(avgUtilization * 100))%")
                            .fontWeight(.semibold)
                            .foregroundStyle(avgUtilization > 0.7 ? .green :
                                           avgUtilization > 0.4 ? .orange : .red)
                    }
                    LabeledContent("Active Vehicles") {
                        Text("\(activeCount) of \(utilizationData.count)")
                    }
                }

                Section("By Vehicle") {
                    ForEach(utilizationData) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.vehicleName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(row.daysActive) of \(row.totalDays) days")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                ProgressView(value: row.utilization)
                                    .tint(row.utilization > 0.7 ? .green :
                                          row.utilization > 0.4 ? .orange : .red)
                                    .frame(width: 80)
                                Text("\(Int(row.utilization * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Vehicle Utilization")
        .reportExportToolbar(
            title: "Vehicle Utilization Report",
            columns: ["Vehicle", "Days Active", "Total Days", "Utilization %"],
            rows: utilizationData.map { [$0.vehicleName,
                                          "\($0.daysActive)",
                                          "\($0.totalDays)",
                                          "\(Int($0.utilization * 100))%"] }
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
            PageHelpSheet(title: "Vehicle Utilization Help", sections: [
                ("What This Page Does", "Measures how often each vehicle is actually being used. Compares days active (with at least one trip or assignment) versus total days in the selected period. A higher percentage means the vehicle is being put to work."),
                ("How to Use It", "Pick a date range at the top. The summary shows the fleet average utilization and how many vehicles had activity. Each vehicle row shows a progress bar and percentage. Green is well-used, orange is moderate, red is underused."),
                ("Tips", "Vehicles consistently below 40% utilization might be candidates for reassignment or removal from the fleet. If utilization drops during certain months, plan maintenance during those slow periods.")
            ])
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
    }

    private var avgUtilization: Double {
        guard !utilizationData.isEmpty else { return 0 }
        return utilizationData.reduce(0) { $0 + $1.utilization } / Double(utilizationData.count)
    }
    private var activeCount: Int {
        utilizationData.filter { $0.daysActive > 0 }.count
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
            utilizationData = try service.getVehicleUtilizationReport(
                startDate: startDate, endDate: endDate
            )
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
    }
}
