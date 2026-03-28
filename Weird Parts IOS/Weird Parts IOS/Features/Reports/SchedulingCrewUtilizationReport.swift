import SwiftUI
import WiredPartCore

/// Crew utilization report — scheduled hours vs available hours per employee.
struct SchedulingCrewUtilizationReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var utilizationData: [SchedulingService.CrewUtilizationRow] = []
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
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if isLoading {
                Section { ProgressView("Loading...") }
            } else if utilizationData.isEmpty {
                Section {
                    ContentUnavailableView("No Scheduling Data",
                        systemImage: "person.3",
                        description: Text("No dispatch entries found for this period."))
                }
            } else {
                Section("Summary") {
                    LabeledContent("Avg Utilization") {
                        Text("\(Int(avgUtilization * 100))%")
                            .fontWeight(.semibold)
                            .foregroundStyle(avgUtilization > 0.8 ? .green :
                                           avgUtilization > 0.5 ? .orange : .red)
                    }
                    LabeledContent("Total Scheduled Hours") {
                        Text("\(totalHours, specifier: "%.1f")")
                    }
                    LabeledContent("Employees Scheduled") {
                        Text("\(utilizationData.count)")
                    }
                }

                Section("By Employee") {
                    ForEach(utilizationData) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.employeeName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(row.scheduledHours, specifier: "%.1f")h / \(row.availableHours, specifier: "%.0f")h")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                ProgressView(value: row.utilization)
                                    .tint(row.utilization > 0.8 ? .green :
                                          row.utilization > 0.5 ? .orange : .red)
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
        .navigationTitle("Crew Utilization")
        .reportExportToolbar(
            title: "Crew Utilization Report",
            columns: ["Employee", "Scheduled Hours", "Available Hours", "Utilization %"],
            rows: utilizationData.map { [$0.employeeName,
                                          String(format: "%.1f", $0.scheduledHours),
                                          String(format: "%.1f", $0.availableHours),
                                          "\(Int($0.utilization * 100))%"] }
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Crew Utilization Help", sections: [
                ("What This Page Does", "Shows how much of each employee's available work time is being scheduled. Compares scheduled hours against available hours for the selected period. Helps you spot overloaded or underutilized workers."),
                ("How to Use It", "Set the date range at the top. The summary shows average utilization across all employees. Each row has a progress bar showing the percentage of available hours that are scheduled. Green is well-utilized, red means underbooked."),
                ("Tips", "Aim for 70-85% utilization to leave room for unexpected tasks. If someone is at 100%, they have no buffer for urgent jobs. Spread work across the team when possible.")
            ])
        }
        .refreshable { loadData() }
        .onAppear { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
    }

    private var avgUtilization: Double {
        guard !utilizationData.isEmpty else { return 0 }
        return utilizationData.reduce(0) { $0 + $1.utilization } / Double(utilizationData.count)
    }
    private var totalHours: Double { utilizationData.reduce(0) { $0 + $1.scheduledHours } }

    private func loadData() {
        isLoading = true
        loadError = nil
        guard let service = appCore.schedulingService else {
            loadError = "Scheduling service not available"
            isLoading = false
            return
        }
        do {
            utilizationData = try service.getCrewUtilizationReport(
                startDate: startDate, endDate: endDate
            )
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
    }
}
