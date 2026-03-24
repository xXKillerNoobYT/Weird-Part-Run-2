import SwiftUI
import WiredPartCore

/// Dispatch efficiency by date — scheduled vs dispatched vs completed.
struct SchedulingDispatchEfficiencyReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var efficiencyData: [SchedulingService.DispatchEfficiencyRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var dateRange: ReportDateRange = .thisWeek

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
            } else if efficiencyData.isEmpty {
                Section {
                    ContentUnavailableView("No Dispatch Data",
                        systemImage: "paperplane",
                        description: Text("No dispatch entries found for this period."))
                }
            } else {
                Section("Summary") {
                    LabeledContent("Avg Completion Rate") {
                        Text("\(Int(avgEfficiency * 100))%")
                            .fontWeight(.semibold)
                            .foregroundStyle(avgEfficiency > 0.8 ? .green :
                                           avgEfficiency > 0.5 ? .orange : .red)
                    }
                    LabeledContent("Total Scheduled") {
                        Text("\(totalScheduled)")
                    }
                    LabeledContent("Total Completed") {
                        Text("\(totalCompleted)")
                    }
                }

                Section("By Date") {
                    ForEach(efficiencyData) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.date)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(row.efficiency * 100))%")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(row.efficiency > 0.8 ? .green :
                                                    row.efficiency > 0.5 ? .orange : .red)
                            }
                            HStack(spacing: 16) {
                                Label("\(row.scheduledCount) scheduled", systemImage: "calendar")
                                Label("\(row.dispatchedCount) dispatched", systemImage: "paperplane")
                                Label("\(row.completedCount) done", systemImage: "checkmark.circle")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Dispatch Efficiency")
        .reportExportToolbar(
            title: "Dispatch Efficiency Report",
            columns: ["Date", "Scheduled", "Dispatched", "Completed", "Efficiency"],
            rows: efficiencyData.map { [$0.date,
                                         "\($0.scheduledCount)",
                                         "\($0.dispatchedCount)",
                                         "\($0.completedCount)",
                                         "\(Int($0.efficiency * 100))%"] }
        )
        .onAppear { loadData() }
    }

    private var avgEfficiency: Double {
        guard !efficiencyData.isEmpty else { return 0 }
        return efficiencyData.reduce(0) { $0 + $1.efficiency } / Double(efficiencyData.count)
    }
    private var totalScheduled: Int { efficiencyData.reduce(0) { $0 + $1.scheduledCount } }
    private var totalCompleted: Int { efficiencyData.reduce(0) { $0 + $1.completedCount } }

    private func loadData() {
        isLoading = true
        loadError = nil
        guard let service = appCore.schedulingService else {
            loadError = "Scheduling service not available"
            isLoading = false
            return
        }
        do {
            efficiencyData = try service.getDispatchEfficiencyReport(
                startDate: dateRange.startDate, endDate: dateRange.endDate
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
