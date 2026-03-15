import SwiftUI
import GRDB
import WiredPartCore

/// Active jobs list page.
///
/// Displays a searchable, sortable table of all jobs with status, priority,
/// customer, team count, and date columns. Supports filtering by status
/// and searching by job number, name, or customer.
struct ActiveJobsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var stats: JobsService.JobStats?
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\JobsService.JobListItem.jobNumber)]

    private let statusOptions = ["all", "active", "completed", "on_hold", "cancelled"]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadJobs() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Active Jobs")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                if let stats {
                    Text("\(stats.active) active · \(stats.total) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Picker("Status", selection: $statusFilter) {
                ForEach(statusOptions, id: \.self) { status in
                    Text(status == "all" ? "All Statuses" : status.replacingOccurrences(of: "_", with: " ").capitalized)
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            .onChange(of: statusFilter) { loadJobs() }

            TextField("Search jobs...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { loadJobs() }

            Button {
                loadJobs()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading jobs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if jobs.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "hammer")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No jobs found")
                    .font(.headline)
                Text("Create a job to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedJobs, sortOrder: $sortOrder) {
                TableColumn("Job #", value: \.jobNumber) { job in
                    Text(job.jobNumber)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Name", value: \.jobName) { job in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.jobName)
                            .fontWeight(.medium)
                        if let customer = job.customerName, !customer.isEmpty {
                            Text(customer)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .width(min: 150, ideal: 220)

                TableColumn("Status", value: \.status) { job in
                    statusBadge(job.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Priority", value: \.priority) { job in
                    priorityBadge(job.priority)
                }
                .width(min: 70, ideal: 80)

                TableColumn("Team", value: \.teamCount) { job in
                    Text("\(job.teamCount)")
                }
                .width(min: 50, ideal: 60)

                TableColumn("Start") { (job: JobsService.JobListItem) in
                    Text(job.startDate ?? "-")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Due") { (job: JobsService.JobListItem) in
                    Text(job.dueDate ?? "-")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedJobs: [JobsService.JobListItem] {
        jobs.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "completed": .blue
        case "on_hold": .orange
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func priorityBadge(_ priority: String) -> some View {
        let color: Color = switch priority {
        case "urgent": .red
        case "high": .orange
        case "normal": .blue
        case "low": .secondary
        default: .secondary
        }
        return Text(priority.capitalized)
            .font(.caption)
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadJobs() {
        guard let service = appCore.jobsService else { return }
        isLoading = true
        do {
            jobs = try service.listJobs(
                search: searchText.isEmpty ? nil : searchText,
                status: statusFilter == "all" ? nil : statusFilter
            )
            stats = try service.getJobStats()
        } catch {
            print("[ActiveJobsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
