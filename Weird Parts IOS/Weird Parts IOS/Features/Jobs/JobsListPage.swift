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

    // MARK: - ActiveSheet

    private enum ActiveSheet: Identifiable {
        case help
        case createJob
        case jobDetail(Int64)

        var id: String {
            switch self {
            case .help: return "help"
            case .createJob: return "createJob"
            case .jobDetail(let id): return "jobDetail-\(id)"
            }
        }
    }

    private struct QuickStatusTarget: Identifiable {
        let job: JobsService.JobListItem
        var id: Int64 { job.id }
    }

    private struct CachedJobSummary {
        let text: String
        let generatedAt: Date
    }

    // MARK: - State

    @State private var activeSheet: ActiveSheet?
    @State private var jobs: [JobsService.JobListItem] = []
    @State private var allJobs: [JobsService.JobListItem] = []
    @State private var statusCounts: [String: Int] = [:]
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter: JobStatusFilter = .active
    @State private var sortOption: JobSort = .recentActivity
    @State private var loadError: String?
    @State private var quickStatusTarget: QuickStatusTarget?
    @State private var jobSummaryCache: [Int64: CachedJobSummary] = [:]
    /// Cached stage definitions keyed by template id.
    @State private var stagesByTemplateId: [Int64: [JobsService.JobStageStatus]] = [:]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "jobs-list")
            SkippedModuleHint(moduleId: "jobs")
            smartCards
            jobsList
        }
        .task { appCore.onboardingManager?.markCompleted("jobs-view-list") }
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
                    .accessibilityLabel("Sort jobs")

                    Button {
                        activeSheet = .createJob
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create new job")
                    .accessibilityIdentifier("createJobButton")
                    .requiresPermission("manage_jobs")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(
                    title: "Jobs Help",
                    sections: [
                        ("Overview", "View and manage all jobs. Filter by status using the smart cards at the top, or search by name and job number."),
                        ("Smart Cards", "Tap a status card to filter. The number shows how many jobs have that status. Payment Hold is only visible to managers."),
                        ("Sorting", "Use the sort button in the toolbar to sort by recent activity, name, or start date."),
                        ("Creating Jobs", "Tap the + button to create a new job. Requires manage_jobs permission.")
                    ]
                )
            case .createJob:
                IOSCreateJobSheet {
                    loadJobs()
                }
                .environmentObject(appCore)
            case .jobDetail(let jobId):
                NavigationStack {
                    IOSJobDetailTabView(jobId: jobId)
                        .environmentObject(appCore)
                }
            }
        }
        .confirmationDialog(
            "Change Status",
            isPresented: Binding(
                get: { quickStatusTarget != nil },
                set: { if !$0 { quickStatusTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = quickStatusTarget {
                let statuses: [(String, String)] = [
                    ("active", "Active"),
                    ("on_hold", "On Hold"),
                    ("payment_hold", "Payment Hold"),
                    ("completed", "Completed"),
                    ("warranty", "Warranty"),
                    ("continuous", "Continuous")
                ]
                ForEach(statuses, id: \.0) { status, label in
                    if target.job.status != status {
                        Button(label) {
                            updateJobStatus(job: target.job, newStatus: status)
                        }
                    }
                }
                Button("Cancel", role: .cancel) { quickStatusTarget = nil }
            }
        } message: {
            if let target = quickStatusTarget {
                Text("Job: \(target.job.jobName ?? target.job.jobNumber)"  )
            }
        }
        .onChange(of: searchText) { loadJobs() }
        .onChange(of: sortOption) { applyFilterAndSort() }
        .refreshable { loadJobs() }
        .task { loadJobs() }
        .onAppear {
            NotificationCenter.default.post(
                name: .jobsListPageActive,
                object: nil,
                userInfo: [
                    "context": "Jobs List: \(allJobs.count) total jobs, filter: \(statusFilter.rawValue), showing \(jobs.count) jobs. Status counts: \(statusCounts.map { "\($0.key): \($0.value)" }.joined(separator: ", "))"
                ]
            )
        }
        .onDisappear {
            NotificationCenter.default.post(name: .jobsListPageInactive, object: nil)
        }
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
        .accessibilityIdentifier("jobFilter_\(filter.rawValue)")
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
                activeSheet = .createJob
            }
        } else {
            List(jobs, id: \.id) { job in
                NavigationLink {
                    IOSJobDetailTabView(jobId: job.id)
                        .environmentObject(appCore)
                } label: {
                    jobCard(job)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if appCore.hasPermission("manage_jobs") {
                        Button { quickStatusTarget = QuickStatusTarget(job: job) } label: {
                            Label("Status", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .tint(.blue)
                    }

                    Button { activeSheet = .jobDetail(job.id) } label: {
                        Label("Detail", systemImage: "doc.text.magnifyingglass")
                    }
                    .tint(.indigo)
                }
                .listRowBackground(job.jobType == "continuous" || job.status == "continuous" ? Color(.systemGray6) : Color(.secondarySystemGroupedBackground))
            }
            .listStyle(.insetGrouped)
        }
    }

    private func jobCard(_ job: JobsService.JobListItem) -> some View {
        let isContinuous = job.jobType == "continuous" || job.status == "continuous"
        let stageStatuses = stageStatuses(for: job)
        let activeStage = activeStageName(stageStatuses, isContinuous: isContinuous)
        let stageProgress = stageProgressFraction(stageStatuses, isContinuous: isContinuous)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIcon(for: job.status, isContinuous: isContinuous))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(colorForStatus(job.status, isContinuous: isContinuous))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(colorForStatus(job.status, isContinuous: isContinuous).opacity(0.12)))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(job.jobNumber)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        priorityBadge(job.priority, dueDate: job.dueDate, status: job.status)
                        if isContinuous {
                            Label("Continuous", systemImage: "arrow.clockwise")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.gray)
                        }
                    }

                    Text(job.jobName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let customer = job.customerName, !customer.isEmpty {
                        Text(customer)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(jobSummary(for: job, stageName: activeStage, progress: stageProgress, isContinuous: isContinuous))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityLabel("AI summary: \(jobSummary(for: job, stageName: activeStage, progress: stageProgress, isContinuous: isContinuous))")
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    jobStatusBadge(job.status)
                    if job.teamCount > 0 {
                        Label("\(job.teamCount)", systemImage: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !isContinuous {
                progressMetric(
                    title: activeStage,
                    valueText: "\(Int((stageProgress * 100).rounded()))%",
                    fraction: stageProgress,
                    tint: .blue
                )
                if !stageStatuses.isEmpty {
                    JobStageProgressBar(stages: stageStatuses, compact: true)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Continuous service job — no stage progression")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                if let estimated = job.estimatedHours, estimated > 0 {
                    progressMetric(
                        title: "Hours",
                        valueText: "\(formatNumber(job.laborHours))/\(formatNumber(estimated))h",
                        fraction: min(job.laborHours / estimated, 1),
                        tint: .orange
                    )
                }

                if appCore.hasPermission("view_job_financials"), let budget = job.budgetLimit, budget > 0 {
                    progressMetric(
                        title: "Budget",
                        valueText: currency(job.actualCost) + "/" + currency(budget),
                        fraction: min(job.actualCost / budget, 1),
                        tint: job.actualCost > budget ? .red : .green
                    )
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("jobRow_\(job.id)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.jobName), \(job.jobNumber), status \(job.status), priority \(job.priority)")
    }

    private func progressMetric(title: String, valueText: String, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 6)
                Text(valueText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: max(0, min(fraction, 1)))
                .tint(tint)
        }
    }

    private func stageStatuses(for job: JobsService.JobListItem) -> [JobsService.JobStageStatus] {
        guard
            let templateId = job.stageTemplateId,
            let templateStages = stagesByTemplateId[templateId],
            !templateStages.isEmpty
        else { return [] }
        return JobsService.computeStageStatuses(
            allStages: templateStages,
            currentStageId: job.currentStageId,
            jobStatus: job.status
        )
    }

    private func activeStageName(_ stages: [JobsService.JobStageStatus], isContinuous: Bool) -> String {
        if isContinuous { return "Continuous" }
        return stages.first(where: { $0.status == "in_progress" })?.name
            ?? stages.last(where: { $0.status == "completed" })?.name
            ?? "Not Started"
    }

    private func stageProgressFraction(_ stages: [JobsService.JobStageStatus], isContinuous: Bool) -> Double {
        guard !isContinuous, !stages.isEmpty else { return 0 }
        let completed = stages.filter { $0.status == "completed" }.count
        let inProgressCredit = stages.contains { $0.status == "in_progress" } ? 0.5 : 0
        return min((Double(completed) + inProgressCredit) / Double(stages.count), 1)
    }

    private func jobSummary(for job: JobsService.JobListItem, stageName: String, progress: Double, isContinuous: Bool) -> String {
        if let cached = jobSummaryCache[job.id], Date().timeIntervalSince(cached.generatedAt) < 3600 {
            return cached.text
        }
        return makeJobSummary(for: job, stageName: stageName, progress: progress, isContinuous: isContinuous)
    }

    private func makeJobSummary(for job: JobsService.JobListItem, stageName: String, progress: Double, isContinuous: Bool) -> String {
        if isContinuous {
            return "Continuous service route for \(job.customerName ?? job.jobName); recurring work stays outside stage tracking."
        }
        let percent = Int((progress * 100).rounded())
        let teamText = job.teamCount > 0 ? ", \(job.teamCount) assigned" : ""
        return "\(stageName) \(percent)% complete\(teamText); priority \(job.priority.lowercased())."
    }

    private func refreshJobSummaryCache() {
        let now = Date()
        var next = jobSummaryCache
        for job in allJobs {
            let isContinuous = job.jobType == "continuous" || job.status == "continuous"
            let stages = stageStatuses(for: job)
            let stageName = activeStageName(stages, isContinuous: isContinuous)
            let progress = stageProgressFraction(stages, isContinuous: isContinuous)
            if let cached = next[job.id], now.timeIntervalSince(cached.generatedAt) < 3600 { continue }
            next[job.id] = CachedJobSummary(
                text: makeJobSummary(for: job, stageName: stageName, progress: progress, isContinuous: isContinuous),
                generatedAt: now
            )
        }
        next = next.filter { id, _ in allJobs.contains { $0.id == id } }
        jobSummaryCache = next
    }

    private func statusIcon(for status: String, isContinuous: Bool) -> String {
        if isContinuous { return "arrow.clockwise.circle.fill" }
        switch status {
        case "active", "in_progress": return "hammer.circle.fill"
        case "on_hold": return "pause.circle.fill"
        case "payment_hold": return appCore.hasPermission("manage_jobs") ? "dollarsign.circle.fill" : "pause.circle.fill"
        case "completed": return "checkmark.circle.fill"
        case "cancelled": return "xmark.circle.fill"
        case "warranty": return "shield.fill"
        default: return "briefcase.circle.fill"
        }
    }

    private func colorForStatus(_ status: String, isContinuous: Bool) -> Color {
        if isContinuous { return .gray }
        switch status {
        case "active", "in_progress": return .green
        case "on_hold": return .orange
        case "payment_hold": return .red
        case "completed": return .blue
        case "cancelled": return .red.opacity(0.7)
        case "warranty": return .purple
        default: return .secondary
        }
    }

    private func formatNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func currency(_ value: Double) -> String {
        value >= 1_000 ? String(format: "$%.1fk", value / 1_000) : String(format: "$%.0f", value)
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
                            .accessibilityHidden(true)
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

    private func priorityBadge(_ priority: String, dueDate: String? = nil, status: String? = nil) -> some View {
        let isCompleted = status == "completed" || status == "cancelled"
        let color: Color = dueDate != nil
            ? TimelinePriorityColor.color(priority: priority, dueDateString: dueDate, isCompleted: isCompleted)
            : TimelinePriorityColor.fallbackColor(priority: priority)
        return Text(priority.capitalized)
            .font(.caption2)
            .foregroundStyle(color)
    }

    // MARK: - Status Change

    private func updateJobStatus(job: JobsService.JobListItem, newStatus: String) {
        guard let service = appCore.jobsService else { return }
        do {
            try service.updateJob(id: job.id, status: newStatus)
            quickStatusTarget = nil
            loadJobs()
        } catch {
            loadError = "Could not update status: \(error.localizedDescription)"
            quickStatusTarget = nil
        }
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
            stagesByTemplateId = try loadTemplateStageCache(service: service, jobs: allJobs)
            // Build status counts
            var counts: [String: Int] = [:]
            for j in allJobs {
                counts[j.status, default: 0] += 1
            }
            statusCounts = counts
            refreshJobSummaryCache()
            applyFilterAndSort()
        } catch {
            loadError = userFriendlyError(error, context: "load jobs")
        }
        isLoading = false
    }

    private func loadTemplateStageCache(
        service: JobsService,
        jobs: [JobsService.JobListItem]
    ) throws -> [Int64: [JobsService.JobStageStatus]] {
        var cache: [Int64: [JobsService.JobStageStatus]] = [:]
        let templateIds = Set(jobs.compactMap(\.stageTemplateId))
        for templateId in templateIds {
            cache[templateId] = try service.listAllJobStages(templateId: templateId)
        }
        return cache
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
