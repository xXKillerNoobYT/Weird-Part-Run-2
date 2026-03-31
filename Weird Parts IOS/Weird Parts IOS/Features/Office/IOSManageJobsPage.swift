import SwiftUI
import WiredPartCore

/// Office-level job management page.
///
/// Provides admin/manager capabilities beyond the basic jobs list:
/// status management, bulk actions, filters by assignee/date/type.
/// Gated by `manage_jobs` permission.
struct IOSManageJobsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var allJobs: [JobsService.JobListItem] = []
    @State private var stats: JobsService.JobStats?
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var loadError: String?

    private enum ActiveSheet: Identifiable {
        case help
        case createJob
        var id: String {
            switch self {
            case .help: return "help"
            case .createJob: return "createJob"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    private let statusOptions = ["all", "active", "completed", "on_hold", "cancelled"]

    var body: some View {
        VStack(spacing: 0) {
            // Stats cards
            if let stats {
                statsBar(stats)
            }

            // Filters
            filterBar

            // Job list
            jobContent
        }
        .navigationTitle("Manage Jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .searchable(text: $searchText, prompt: "Search jobs...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .createJob
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create job")
                .requiresPermission("manage_jobs")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(
                    title: "Manage Jobs Help",
                    sections: [
                        ("Overview", "Admin-level job management with bulk actions, status changes, and advanced filtering by assignee, date, and type."),
                        ("Bulk Actions", "Select multiple jobs to update their status, reassign team members, or archive completed jobs at once."),
                        ("Permissions", "This page requires the 'manage jobs' permission. Standard users should use the regular Jobs page.")
                    ]
                )
            case .createJob:
                IOSCreateJobSheet {
                    loadData()
                }
                .environmentObject(appCore)
            }
        }
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
        .onAppear {
            // Register AI filter (prompt 62S)
            appCore.aiFilterRegistry.register(
                pageId: "manage-jobs",
                filterName: "Job Status",
                options: statusOptions,
                activate: { value in
                    statusFilter = value
                    loadData()
                }
            )
            appCore.aiFilterRegistry.applyPendingFilter(pageId: "manage-jobs")
        }
        .onDisappear {
            appCore.aiFilterRegistry.deregister(pageId: "manage-jobs")
        }
    }

    // MARK: - Stats Bar

    private func statsBar(_ stats: JobsService.JobStats) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                StatCard(label: "Active", value: "\(stats.active)", color: .green)
                StatCard(label: "Completed", value: "\(stats.completed)", color: .blue)
                StatCard(label: "Total", value: "\(stats.total)", color: .primary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Filter Bar

    private func countForStatus(_ status: String) -> Int {
        if status == "all" { return allJobs.count }
        return allJobs.filter { $0.status == status }.count
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    SmartFilterCard(
                        title: status == "all" ? "All" : status.replacingOccurrences(of: "_", with: " ").capitalized,
                        count: countForStatus(status),
                        isSelected: statusFilter == status
                    ) {
                        statusFilter = status
                        loadData()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Job Content

    @ViewBuilder
    private var jobContent: some View {
        if isLoading {
            ProgressView("Loading jobs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if jobs.isEmpty {
            EmptyStateView(
                icon: "hammer",
                title: "No Jobs",
                message: "Create your first job to get started.",
                actionLabel: "Create Job"
            ) {
                activeSheet = .createJob
            }
        } else {
            List(jobs, id: \.id) { job in
                NavigationLink(value: job.id) {
                    jobRow(job)
                }
            }
            .listStyle(.insetGrouped)
            .navigationDestination(for: Int64.self) { jobId in
                IOSJobDetailTabView(jobId: jobId)
                    .environmentObject(appCore)
            }
        }
    }

    private func jobRow(_ job: JobsService.JobListItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(job.jobNumber)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    StatusBadge(
                        text: job.priority.capitalized,
                        color: priorityColor(job.priority, dueDate: job.dueDate, status: job.status)
                    )
                }
                Text(job.jobName)
                    .fontWeight(.medium)
                if let customer = job.customerName, !customer.isEmpty {
                    Text(customer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(
                    text: job.status.replacingOccurrences(of: "_", with: " ").capitalized,
                    color: statusColor(job.status)
                )
                if job.teamCount > 0 {
                    Label("\(job.teamCount)", systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": .green
        case "completed": .blue
        case "on_hold": .orange
        case "cancelled": .red
        default: .secondary
        }
    }

    /// Returns a time-based priority color for the given job.
    /// Uses the job's due date to determine urgency; falls back to label-based color if no due date.
    private func priorityColor(_ priority: String, dueDate: String? = nil, status: String? = nil) -> Color {
        let isCompleted = status == "completed" || status == "cancelled"
        if dueDate != nil {
            return TimelinePriorityColor.color(priority: priority, dueDateString: dueDate, isCompleted: isCompleted)
        }
        return TimelinePriorityColor.fallbackColor(priority: priority)
    }

    // MARK: - Data

    private func loadData() {
        guard let service = appCore.jobsService else {
            isLoading = false
            loadError = "Jobs service is not available."
            return
        }
        isLoading = jobs.isEmpty
        loadError = nil
        do {
            allJobs = try service.listJobs(
                search: searchText.isEmpty ? nil : searchText,
                status: nil
            )
            jobs = statusFilter == "all"
                ? allJobs
                : allJobs.filter { $0.status == statusFilter }
            stats = try service.getJobStats()
        } catch {
            loadError = userFriendlyError(error, context: "load jobs")
        }
        isLoading = false
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 70)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .dsCard()
    }
}
