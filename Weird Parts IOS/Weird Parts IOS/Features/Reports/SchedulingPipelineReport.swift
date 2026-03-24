import SwiftUI
import WiredPartCore

/// Pipeline summary — job counts grouped by status.
struct SchedulingPipelineReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var pipelineData: [SchedulingService.PipelineSummaryRow] = []
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if let error = loadError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
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
        .onAppear { loadData() }
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
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
