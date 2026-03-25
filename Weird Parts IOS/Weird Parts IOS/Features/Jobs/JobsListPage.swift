import SwiftUI
import WiredPartCore

/// Jobs list page for iOS.
///
/// Displays a searchable list of all jobs with smart status cards, sort options,
/// payment hold privacy, and continuous job filtering. Supports pull-to-refresh
/// and search filtering.
struct JobsListPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Types

    enum JobStatusFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case warranty = "Warranty"
        case continuous = "Continuous"
        case complete = "Complete"
        case onHold = "On Hold"
        case paymentHold = "Payment Hold"
        case cancelled = "Cancelled"

        /// The status string used for service queries.
        var queryValue: String? {
            switch self {
            case .all: nil
            case .active: "active"
            case .warranty: "warranty"
            case .continuous: "continuous"
            case .complete: "completed"
            case .onHold: "on_hold"
            case .paymentHold: "payment_hold"
            case .cancelled: "cancelled"
            }
        }
    }

    enum JobSort: String, CaseIterable {
        case recentActivity = "Recent Activity"
        case name = "Name"
        case startDate = "Start Date"
    }

    // MARK: - State

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var allJobs: [JobsService.JobListItem] = []
    @State private var statusCounts: [String: Int] = [:]
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter: JobStatusFilter = .active
    @State private var sortOption: JobSort = .recentActivity
    @State private var showCreateJob = false
    @State private var loadError: String?
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 0) {
            smartCards
            jobsList
        }
        .navigationTitle("Jobs")
        .searchable(text: $searchText, prompt: "Search jobs...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Menu {
                        Picker("Sort", selection: $sortOption) {
                            ForEach(JobSort.allCases, id: \.self) { sort in
                                Text(sort.rawValue).tag(sort)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }

                    Button {
                        showCreateJob = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .requiresPermission("manage_jobs")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $showHelp) {
            PageHelpSheet(
                title: "Jobs Help",
                sections: [
                    ("Overview", "View and manage all jobs. Filter by status using the smart cards at the top, or search by name and job number."),
                    ("Smart Cards", "Tap a status card to filter. The number shows how many jobs have that status. Payment Hold is only visible to managers."),
                    ("Sorting", "Use the sort button in the toolbar to sort by recent activity, name, or start date."),
                    ("Creating Jobs", "Tap the + button to create a new job. Requires manage_jobs permission.")
                ]
            )
        }
        .sheet(isPresented: $showCreateJob) {
            IOSCreateJobSheet {
                loadJobs()
            }
            .environmentObject(appCore)
        }
        .onChange(of: searchText) { loadJobs() }
        .onChange(of: sortOption) { applyFilterAndSort() }
        .refreshable { loadJobs() }
        .task { loadJobs() }
    }

    // MARK: - Smart Cards

    private var smartCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(visibleFilters, id: \.self) { filter in
                    smartCard(filter)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func smartCard(_ filter: JobStatusFilter) -> some View {
        let count = countFor(filter)
        let isActive = statusFilter == filter
        let color = colorFor(filter)
        return Button {
            statusFilter = filter
            applyFilterAndSort()
        } label: {
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(isActive ? .white : color)
                Text(filter.rawValue)
                    .font(.caption2)
                    .foregroundStyle(isActive ? .white.opacity(0.9) : .secondary)
            }
            .frame(minWidth: 70)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? color : color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    /// Payment Hold card only visible to users with manage_jobs permission.
    private var visibleFilters: [JobStatusFilter] {
        var filters = JobStatusFilter.allCases
        if !appCore.hasPermission("manage_jobs") {
            filters.removeAll { $0 == .paymentHold }
        }
        return filters
    }

    private func countFor(_ filter: JobStatusFilter) -> Int {
        if filter == .all { return allJobs.count }
        if filter == .continuous {
            return allJobs.filter { $0.jobType == "continuous" || $0.status == "continuous" }.count
        }
        return statusCounts[filter.queryValue ?? ""] ?? 0
    }

    private func colorFor(_ filter: JobStatusFilter) -> Color {
        switch filter {
        case .all: .primary
        case .active: .green
        case .warranty: .purple
        case .continuous: .gray
        case .complete: .blue
        case .onHold: .orange
        case .paymentHold: .red
        case .cancelled: .red.opacity(0.7)
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
                message: searchText.isEmpty ? "No jobs match this filter." : "No jobs match your search criteria.",
                actionLabel: searchText.isEmpty && statusFilter == .all ? "Create Job" : nil
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
                .opacity(job.jobType == "continuous" ? 0.7 : 1.0)
            }
            .listStyle(.insetGrouped)
        }
    }

    private func jobRow(_ job: JobsService.JobListItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(job.jobNumber)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    priorityBadge(job.priority)
                    if job.jobType == "continuous" {
                        Text("Continuous")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.gray))
                    }
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
                jobStatusBadge(job.status)
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

    private func jobStatusBadge(_ status: String) -> some View {
        let isPaymentHold = status == "payment_hold"
        let hasManagePermission = appCore.hasPermission("manage_jobs")

        if isPaymentHold {
            if hasManagePermission {
                // Managers see $ badge with "Payment Hold"
                return AnyView(
                    HStack(spacing: 2) {
                        Image(systemName: "dollarsign.circle.fill")
                        Text("Payment Hold")
                    }
                    .font(.system(.caption2, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.red))
                    .foregroundStyle(.white)
                )
            } else {
                // Workers see generic "On Hold"
                return AnyView(
                    Text("On Hold")
                        .font(.system(.caption2, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.red.opacity(0.15)))
                        .foregroundStyle(.red)
                )
            }
        }

        let color: Color = switch status {
        case "active": .green
        case "completed": .blue
        case "on_hold": .orange
        case "cancelled": .red
        case "warranty": .purple
        case "continuous": .gray
        default: .secondary
        }
        return AnyView(
            Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.system(.caption2, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.15)))
                .foregroundStyle(color)
        )
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
        guard let service = appCore.jobsService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = jobs.isEmpty && allJobs.isEmpty
        loadError = nil
        do {
            allJobs = try service.listJobs(
                search: searchText.isEmpty ? nil : searchText,
                status: nil
            )
            // Build status counts
            var counts: [String: Int] = [:]
            for j in allJobs {
                counts[j.status, default: 0] += 1
            }
            statusCounts = counts
            applyFilterAndSort()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func applyFilterAndSort() {
        var filtered = allJobs

        // Apply status filter
        if let query = statusFilter.queryValue {
            if statusFilter == .continuous {
                filtered = filtered.filter { $0.jobType == "continuous" || $0.status == "continuous" }
            } else {
                filtered = filtered.filter { $0.status == query }
            }
        }

        // Continuous jobs: only show to assigned workers or managers
        // (We don't have assignment info on JobListItem, so we skip this client-side filter
        //  and rely on the server query. Managers see all.)

        // Apply sort
        switch sortOption {
        case .recentActivity:
            // Default order from service (most recently updated)
            break
        case .name:
            filtered.sort { $0.jobName.localizedCaseInsensitiveCompare($1.jobName) == .orderedAscending }
        case .startDate:
            filtered.sort { ($0.startDate ?? "") > ($1.startDate ?? "") }
        }

        jobs = filtered
    }
}
