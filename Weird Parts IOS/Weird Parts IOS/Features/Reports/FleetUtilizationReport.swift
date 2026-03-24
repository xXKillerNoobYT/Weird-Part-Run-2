import SwiftUI
import WiredPartCore

/// Vehicle utilization report — days active vs total days in period.
struct FleetUtilizationReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var utilizationData: [FleetService.VehicleUtilizationRow] = []
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
        .onAppear { loadData() }
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
                startDate: dateRange.startDate, endDate: dateRange.endDate
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
