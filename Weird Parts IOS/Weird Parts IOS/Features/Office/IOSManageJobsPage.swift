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
    @State private var stats: JobsService.JobStats?
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var showCreateJob = false
    @State private var loadError: String?

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
        .searchable(text: $searchText, prompt: "Search jobs...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateJob = true
                } label: {
                    Image(systemName: "plus")
                }
                .requiresPermission("manage_jobs")
            }
        }
        .sheet(isPresented: $showCreateJob) {
            IOSCreateJobSheet {
                loadData()
            }
            .environmentObject(appCore)
        }
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
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

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    Button {
                        statusFilter = status
                        loadData()
                    } label: {
                        Text(status == "all" ? "All" : status.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .fontWeight(statusFilter == status ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(statusFilter == status ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(statusFilter == status ? .white : .primary)
                    }
                    .buttonStyle(.plain)
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
                showCreateJob = true
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
                        color: priorityColor(job.priority)
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

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "urgent": .red
        case "high": .orange
        case "normal": .blue
        case "low": .secondary
        default: .secondary
        }
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
            jobs = try service.listJobs(
                search: searchText.isEmpty ? nil : searchText,
                status: statusFilter == "all" ? nil : statusFilter
            )
            stats = try service.getJobStats()
        } catch {
            loadError = error.localizedDescription
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
