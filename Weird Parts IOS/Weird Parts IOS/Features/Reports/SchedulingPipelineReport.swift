import SwiftUI
import WiredPartCore

/// Pipeline summary — job counts grouped by status.
struct SchedulingPipelineReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var pipelineData: [SchedulingService.PipelineSummaryRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    var body: some View {
        List {
            if let error = loadError {
                Section {
                    ErrorStateView(message: error) { loadData() }
                }
            }

            if isLoading {
                Section { ProgressView("Loading...") }
            } else if pipelineData.isEmpty {
                Section {
                    ContentUnavailableView("No Pipeline Data",
                        systemImage: "rectangle.stack",
                        description: Text("No jobs found in the system."))
                }
            } else {
                Section("Overview") {
                    LabeledContent("Total Jobs") {
                        Text("\(totalJobs)")
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Total Estimated Hours") {
                        Text("\(totalHours, specifier: "%.0f")")
                    }
                }

                Section("By Status") {
                    ForEach(pipelineData) { row in
                        HStack {
                            Circle()
                                .fill(statusColor(row.status))
                                .frame(width: 10, height: 10)
                                .accessibilityLabel("Status: \(displayStatus(row.status))")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayStatus(row.status))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(row.totalEstimatedHours, specifier: "%.0f") est. hours")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.jobCount)")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(statusColor(row.status))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pipeline Summary")
        .reportExportToolbar(
            title: "Pipeline Summary Report",
            columns: ["Status", "Job Count", "Estimated Hours"],
            rows: pipelineData.map { [displayStatus($0.status),
                                       "\($0.jobCount)",
                                       String(format: "%.0f", $0.totalEstimatedHours)] }
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
            PageHelpSheet(title: "Pipeline Summary Help", sections: [
                ("What This Page Does", "Shows all jobs in the system grouped by status: active, scheduled, pending, on hold, and completed. Gives you a bird's-eye view of your work pipeline and estimated hours in each stage."),
                ("How to Use It", "Each status group shows a colored dot, the job count, and total estimated hours. The overview at the top gives fleet-wide totals. Use this to check if your pipeline is balanced."),
                ("Tips", "Too many jobs in 'pending' may mean approvals are bottlenecked. If 'on hold' keeps growing, follow up on what is blocking those jobs. A healthy pipeline has most jobs in 'active' or 'scheduled'.")
            ])
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onAppear { postPageContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .reportsSchedulingPipelineSummaryPageInactive, object: nil)
        }
    }

    private var totalJobs: Int { pipelineData.reduce(0) { $0 + $1.jobCount } }
    private var totalHours: Double { pipelineData.reduce(0) { $0 + $1.totalEstimatedHours } }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return .green
        case "scheduled": return .blue
        case "pending": return .orange
        case "on_hold": return .yellow
        case "completed": return .gray
        default: return .secondary
        }
    }

    private func displayStatus(_ status: String) -> String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func loadData() {
        isLoading = true
        loadError = nil
        guard let service = appCore.schedulingService else {
            loadError = "Scheduling service not available"
            isLoading = false
            return
        }
        do {
            pipelineData = try service.getPipelineSummaryReport()
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
        postPageContext()
    }

    private func postPageContext() {
        let context = """
        Scheduling Pipeline Summary report page. Status rows: \(pipelineData.count). Total jobs: \(totalJobs). Total estimated hours: \(String(format: "%.0f", totalHours)). Error state: \(loadError ?? "none"). Available read-only actions: summarize pipeline stage mix, identify bottleneck statuses, explain hours distribution across statuses.
        """
        NotificationCenter.default.post(name: .reportsSchedulingPipelineSummaryPageActive, object: nil, userInfo: ["context": context])
    }
}
