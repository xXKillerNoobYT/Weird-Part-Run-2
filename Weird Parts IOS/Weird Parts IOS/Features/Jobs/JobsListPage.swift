import SwiftUI
import WiredPartCore

/// Jobs list page for iOS.
///
/// Displays a searchable list of all jobs grouped by status. Shows job number,
/// name, customer, priority badge, and team count. Supports pull-to-refresh
/// and search filtering.
struct JobsListPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

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
            statusPicker
            jobsList
        }
        .navigationTitle("Jobs")
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
                loadJobs()
            }
            .environmentObject(appCore)
        }
        .onChange(of: searchText) { loadJobs() }
        .refreshable { loadJobs() }
        .task { loadJobs() }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    Button {
                        statusFilter = status
                        loadJobs()
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
            .padding(.vertical, 8)
        }
    }

    // MARK: - Jobs List

    @ViewBuilder
    private var jobsList: some View {
        if isLoading {
            ProgressView("Loading jobs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadJobs() }
        } else if jobs.isEmpty {
            EmptyStateView(
                icon: "hammer",
                title: "No Jobs",
                message: searchText.isEmpty ? "Create your first job to get started." : "No jobs match your search criteria.",
                actionLabel: searchText.isEmpty ? "Create Job" : nil
            ) {
                showCreateJob = true
            }
        } else {
            List(jobs, id: \.id) { job in
                NavigationLink {
                    IOSJobDetailTabView(jobId: job.id)
                        .environmentObject(appCore)
                } label: {
                    jobRow(job)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private func jobRow(_ job: JobsService.JobListItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.jobNumber)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    priorityBadge(job.priority)
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
                statusBadge(job.status)
                if job.teamCount > 0 {
                    Label("\(job.teamCount)", systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.jobName), \(job.jobNumber), status \(job.status), priority \(job.priority)")
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
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
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
            .font(.caption2)
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadJobs() {
        guard let service = appCore.jobsService else { return }
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
