import SwiftUI
import WiredPartCore

/// Dispatch efficiency by date — scheduled vs dispatched vs completed.
struct SchedulingDispatchEfficiencyReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var efficiencyData: [SchedulingService.DispatchEfficiencyRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var startDate = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
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
            } else if efficiencyData.isEmpty {
                Section {
                    EmptyStateView(
                        icon: "paperplane",
                        title: "No Dispatch Data",
                        message: "No dispatch entries found for this period."
                    )
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Dispatch Efficiency Help", sections: [
                ("What This Page Does", "Tracks how well dispatch assignments are being completed each day. For every date, it shows how many jobs were scheduled, dispatched, and completed. The completion rate tells you how reliable your dispatch process is."),
                ("How to Use It", "Set a date range to see daily efficiency numbers. The summary shows the overall average completion rate. Each date row breaks down scheduled, dispatched, and completed counts with a color-coded percentage."),
                ("Tips", "A completion rate below 80% means jobs are being scheduled but not finished. Look at the days with the lowest rates to find patterns. Weather, missing materials, or crew shortages are common causes.")
            ])
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
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
                startDate: startDate, endDate: endDate
            )
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
    }
}
