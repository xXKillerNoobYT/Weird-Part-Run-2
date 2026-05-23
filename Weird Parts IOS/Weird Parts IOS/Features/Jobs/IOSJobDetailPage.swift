import SwiftUI
import WiredPartCore

/// Job detail page for iOS.
///
/// Presents a dashboard-style view for one job with status, stage progress,
/// quick actions, activity summaries, and detail tabs.
struct IOSJobDetailPage: View {
    @EnvironmentObject private var appCore: AppCore

    let jobId: Int64

    // MARK: - State

    @State private var job: JobsService.JobDetail?
    @State private var teamMembers: [JobsService.TeamMemberRow] = []
    @State private var laborSummary: JobsService.LaborSummary?
    @State private var activeTodos: [JobsService.ClockTodoItem] = []
    @State private var todoSummary: JobsService.JobTodoSummary?
    @State private var stages: [JobsService.JobStageStatus] = []
    @State private var isPaymentHold = false
    @State private var warrantyDaysRemaining: Int?
    @State private var selectedTab: DetailTab = .todos
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?
    private var canViewJobFinancials: Bool { appCore.hasPermission("view_job_financials") }

    private enum DetailTab: String, CaseIterable, Identifiable {
        case todos = "To-Dos"
        case jpos = "JPOs"
        case labor = "Labor"
        case notes = "Notes"
        case financial = "Financial"
        case warranty = "Warranty"

        var id: String { rawValue }
    }

    private enum ActiveSheet: Identifiable {
        case help
        case weeklyReview
        case stageDetails(String)
        case quickAction(String)

        var id: String {
            switch self {
            case .help: "help"
            case .weeklyReview: "weeklyReview"
            case .stageDetails(let name): "stage-\(name)"
            case .quickAction(let name): "action-\(name)"
            }
        }
    }

    private var hasFinancialPermission: Bool {
        appCore.hasPermission("view_job_financials")
    }

    var body: some View {
        detailContent
            .navigationTitle(job?.jobName ?? "Job Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button { activeSheet = .weeklyReview } label: {
                            Image(systemName: "calendar.badge.clock")
                        }
                        .accessibilityLabel("Open weekly review")
                        Button { activeSheet = .help } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel("Help")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .help:
                    PageHelpSheet(
                        title: "Job Detail Help",
                        sections: [
                            ("Dashboard", "Review status, stage progress, smart cards, AI summary, today’s activity, and quick actions from the top of the page."),
                            ("Tabs", "Use To-Dos, JPOs, Labor, Notes, Financial, and Warranty tabs to focus the detail area."),
                            ("Payment Holds", "A red banner appears when a job is on payment hold. Workers can still view details, but clock-in remains blocked by the Jobs service."),
                            ("Weekly Review", "Tap the calendar icon to submit a weekly work review for this job.")
                        ]
                    )
                case .weeklyReview:
                    IOSWeeklyReviewSheet(
                        jobId: jobId,
                        jobName: job?.jobName ?? "Job \(jobId)"
                    )
                case .stageDetails(let stageName):
                    informationalSheet(
                        title: stageName,
                        message: "Stage details are read-only from this dashboard for now. Use the stage workflow pages to change progression."
                    )
                case .quickAction(let action):
                    informationalSheet(
                        title: action,
                        message: quickActionMessage(action)
                    )
                }
            }
            .refreshable { loadData() }
            .task { loadData() }
            .task { appCore.onboardingManager?.markCompleted("jobs-tap-detail") }
            .onDisappear {
                NotificationCenter.default.post(name: .jobDetailPageInactive, object: nil)
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var detailContent: some View {
        if isLoading {
            ProgressView("Loading job...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if let job {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isPaymentHold {
                        paymentHoldBanner
                    }

                    dashboardHeader(job)
                    stageProgressSection
                    smartCards(job)
                    aiSummaryCard(job)
                    todayActivityCard
                    quickActionsGrid
                    tabbedDetailSection(job)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
        } else {
            EmptyStateView(
                icon: "hammer",
                title: "Job Not Found",
                message: "The requested job could not be loaded."
            )
        }
    }

    private var paymentHoldBanner: some View {
        dashboardCard(background: Color.red.opacity(0.12)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Payment Hold")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("Workers can view this job, but clock-in is blocked until a manager resumes the job.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dashboardHeader(_ job: JobsService.JobDetail) -> some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.jobNumber)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(job.jobName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        statusBadge(job.status)
                        priorityBadge(job.priority)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    summaryPill(icon: "wrench.and.screwdriver", title: "Type", value: job.jobType.capitalized)
                    summaryPill(icon: "person.crop.circle", title: "Customer", value: job.customerName.nilIfEmpty ?? "Not set")
                }
                HStack(spacing: 12) {
                    summaryPill(icon: "person.2.fill", title: "Team", value: "\(teamMembers.count) assigned")
                    summaryPill(icon: "calendar", title: "Due", value: job.dueDate.map(formatDate) ?? "No due date")
                }
            }
        }
    }

    private var stageProgressSection: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Stage Progress", systemImage: "point.3.connected.trianglepath.dotted")
                if stages.isEmpty {
                    placeholderRow("No job stages configured yet.", systemImage: "circle.dashed")
                } else {
                    JobStageProgressBar(stages: stages, compact: false)
                        .padding(.vertical, 4)
                    HStack {
                        ForEach(stages) { stage in
                            Button {
                                activeSheet = .stageDetails(stage.name)
                            } label: {
                                Text(stage.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(stageTint(stage).opacity(0.15)))
                                    .foregroundStyle(stageTint(stage))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .accessibilityLabel("Tap a stage name for details")
                }
            }
        }
    }

    private func smartCards(_ job: JobsService.JobDetail) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            smartCard(
                title: "Hours",
                value: totalHoursText,
                subtitle: "\(laborSummary?.uniqueWorkers ?? 0) workers",
                icon: "clock.fill",
                tint: .blue
            ) { selectedTab = .labor }
            if hasFinancialPermission {
                smartCard(
                    title: "Budget",
                    value: budgetValue(job),
                    subtitle: budgetSubtitle(job),
                    icon: "chart.pie.fill",
                    tint: .green
                ) { selectedTab = .financial }
            } else {
                smartCard(
                    title: "Budget",
                    value: "Locked",
                    subtitle: "Requires financial permission",
                    icon: "lock.fill",
                    tint: .secondary
                )
            }
            smartCard(
                title: "JPOs",
                value: "—",
                subtitle: "Linked orders tab",
                icon: "doc.text.fill",
                tint: .orange
            ) { selectedTab = .jpos }
            smartCard(
                title: "To-Dos",
                value: todoValue,
                subtitle: "\(activeTodos.count) active",
                icon: "checklist.checked",
                tint: .purple
            ) { selectedTab = .todos }
        }
    }

    private func aiSummaryCard(_ job: JobsService.JobDetail) -> some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("AI Summary", systemImage: "sparkles")
                Text(aiSummary(job))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    postAIContext(job)
                } label: {
                    Label("Refresh AI context", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var todayActivityCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Today’s Activity", systemImage: "calendar.badge.clock")
                HStack(spacing: 12) {
                    activityMetric("Workers", "\(laborSummary?.uniqueWorkers ?? 0)")
                    activityMetric("Hours", totalHoursText)
                    activityMetric("Open To-Dos", "\(activeTodos.count)")
                }
                Text("Detailed per-person activity and parts-used feeds will appear here as those event streams are wired into the dashboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickActionsGrid: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Quick Actions", systemImage: "bolt.fill")
                let actions: [(String, String, Bool)] = [
                    ("Clock In", "clock.badge.checkmark", !isPaymentHold),
                    ("Add To-Do", "checklist.unchecked", true),
                    ("Create JPO", "doc.badge.plus", true),
                    ("Add Note", "note.text.badge.plus", true),
                    ("Change Status", "arrow.triangle.2.circlepath", true),
                    ("Job QR", "qrcode", true),
                ]
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(actions.indices, id: \.self) { index in
                        let action = actions[index]
                        Button {
                            activeSheet = .quickAction(action.0)
                        } label: {
                            Label(action.0, systemImage: action.1)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!action.2)
                        .accessibilityHint(action.2 ? "Opens \(action.0) workflow" : "Disabled while payment hold is active")
                    }
                }
            }
        }
    }

    private func tabbedDetailSection(_ job: JobsService.JobDetail) -> some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Detail Tab", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedTab {
                case .todos:
                    todosTab
                case .jpos:
                    placeholderTab(
                        title: "Linked JPOs",
                        message: "Linked purchase orders will be listed here once the order relationship is exposed to the job detail dashboard.",
                        icon: "doc.text"
                    )
                case .labor:
                    laborTab
                case .notes:
                    notesTab(job)
                case .financial:
                    if hasFinancialPermission {
                        financialTab(job)
                    } else {
                        financialLockedTab
                    }
                case .warranty:
                    warrantyTab(job)
                }
            }
        }
    }

    private var todosTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("To-Dos", systemImage: "checklist")
            if activeTodos.isEmpty {
                placeholderRow("No active to-dos found for this job.", systemImage: "checkmark.circle")
            } else {
                ForEach(activeTodos) { todo in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(todo.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let content = todo.content, !content.isEmpty {
                                Text(content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var laborTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Labor", systemImage: "person.2.fill")
            if let labor = laborSummary {
                labelRow("Regular", value: String(format: "%.1f hrs", labor.totalRegularHours), icon: "clock")
                labelRow("Overtime", value: String(format: "%.1f hrs", labor.totalOvertimeHours), icon: "clock.badge.exclamationmark")
                labelRow("Workers", value: "\(labor.uniqueWorkers)", icon: "person.2")
                labelRow("Entries", value: "\(labor.totalEntries)", icon: "list.bullet.rectangle")
            } else {
                placeholderRow("No labor has been logged yet.", systemImage: "clock")
            }
        }
    }

    private func notesTab(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Notes", systemImage: "note.text")
            if let notes = job.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                placeholderRow("No notes saved for this job yet.", systemImage: "note.text")
            }
        }
    }

    private func financialTab(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Financial", systemImage: "dollarsign.circle")
            if canViewJobFinancials {
                labelRow("Billing Rate", value: job.billingRate.map { formatCurrency($0) } ?? "Not set", icon: "dollarsign.circle")
                labelRow("Estimated Hours", value: job.estimatedHours.map { String(format: "%.0f hrs", $0) } ?? "Not set", icon: "clock")
                labelRow("Parts Cost", value: formatCurrency(job.partsCost), icon: "shippingbox")
                labelRow("Budget Limit", value: job.budgetLimit.map { formatCurrency($0) } ?? "Not set", icon: "creditcard")
                Text("Labor cost, FIFO parts layers, subcontractor cost, and margin should remain hat-gated as those cost feeds are added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                placeholderRow("You do not have permission to view job financial details.", systemImage: "lock.fill")
            }
        }
    }

    private var financialLockedTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Financial", systemImage: "lock.fill")
            placeholderRow("You need the appropriate financial permission to view budget details for this job.", systemImage: "lock.fill")
        }
    }

    private func warrantyTab(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Warranty", systemImage: "shield.checkered")
            labelRow("Warranty Start", value: job.warrantyStartDate.map(formatDate) ?? "Not set", icon: "calendar")
            labelRow("Warranty End", value: job.warrantyEndDate.map(formatDate) ?? "Not set", icon: "calendar.badge.clock")
            labelRow("Days Remaining", value: warrantyDaysRemaining.map(String.init) ?? "Not active", icon: "timer")
            Text("Continuous-job per-to-do warranty classification is managed through the notebook approval flow and will surface here when linked to job to-dos.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func placeholderTab(title: String, message: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title, systemImage: icon)
            placeholderRow(message, systemImage: icon)
        }
    }

    // MARK: - Components

    private func dashboardCard<Content: View>(
        background: Color = Color(.secondarySystemGroupedBackground),
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(background)
            )
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func summaryPill(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemGroupedBackground)))
    }

    private func smartCard(title: String, value: String, subtitle: String, icon: String, tint: Color, action: (() -> Void)? = nil) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    smartCardBody(title: title, value: value, subtitle: subtitle, icon: icon, tint: tint, showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Switches to the \(title) detail tab")
            } else {
                smartCardBody(title: title, value: value, subtitle: subtitle, icon: icon, tint: tint, showsChevron: false)
            }
        }
    }

    private func smartCardBody(title: String, value: String, subtitle: String, icon: String, tint: Color, showsChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func activityMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholderRow(_ message: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func informationalSheet(title: String, message: String) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func labelRow(_ label: String, value: String?, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "completed": .blue
        case "on_hold", "payment_hold": .orange
        case "cancelled": .red
        case "warranty": .indigo
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
        let isCompleted = job?.status == "completed" || job?.status == "cancelled"
        let color: Color = TimelinePriorityColor.color(priority: priority, dueDateString: job?.dueDate, isCompleted: isCompleted)
        return Text(priority.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    private var totalHoursText: String {
        let labor = laborSummary
        let total = (labor?.totalRegularHours ?? 0) + (labor?.totalOvertimeHours ?? 0)
        return String(format: "%.1f hrs", total)
    }

    private var todoValue: String {
        guard let todoSummary else { return "\(activeTodos.count)" }
        return "\(todoSummary.completedTodos)/\(todoSummary.totalTodos)"
    }

    private func budgetValue(_ job: JobsService.JobDetail) -> String {
        if let budget = job.budgetLimit {
            return formatCurrency(budget)
        }
        if let rate = job.billingRate, let hours = job.estimatedHours {
            return formatCurrency(rate * hours)
        }
        return "Not set"
    }

    private func budgetSubtitle(_ job: JobsService.JobDetail) -> String {
        if let rate = job.billingRate, let hours = job.estimatedHours {
            return "\(String(format: "%.0f", hours)) hrs @ \(formatCurrency(rate))"
        }
        return "Estimate pending"
    }

    private func aiSummary(_ job: JobsService.JobDetail) -> String {
        let stageName = stages.first(where: { $0.status == "in_progress" })?.name ?? "stage not set"
        let holdText = isPaymentHold ? " Payment hold is active, so clock-in should remain blocked until resolved." : ""
        let warrantyText = warrantyDaysRemaining.map { " Warranty has \($0) days remaining." } ?? " Warranty is not currently active."
        return "\(job.jobName) is \(job.status.replacingOccurrences(of: "_", with: " ")) with \(teamMembers.count) assigned team members and \(totalHoursText) logged. Current stage: \(stageName). Active to-dos: \(activeTodos.count).\(holdText)\(warrantyText)"
    }

    private func quickActionMessage(_ action: String) -> String {
        switch action {
        case "Clock In" where isPaymentHold:
            return "Clock-in is disabled while this job is on payment hold. A manager with payment-hold permissions must resume the job first."
        case "Clock In":
            return "Open the Clock page to clock into this job. The Jobs service still validates status, payment hold, and existing active clock entries."
        case "Add To-Do":
            return "Add to-dos from the job notebook flow. Future work can deep-link this button directly into the add-to-do sheet."
        case "Create JPO":
            return "Create a job purchase order from the JPO workflow. Future work can preselect this job from the action."
        case "Add Note":
            return "Add notes from the job notebook. Future work can deep-link this button directly to the notebook entry composer."
        case "Change Status":
            return "Change status from the manager job workflow. This dashboard keeps the action visible but avoids bypassing role checks."
        case "Job QR":
            return "Job-site QR signage generation is queued for this dashboard. The action is reserved here so crews know where it will live."
        default:
            return "This action is available from the related job workflow."
        }
    }

    private func stageTint(_ stage: JobsService.JobStageStatus) -> Color {
        switch stage.status {
        case "completed": .green
        case "in_progress": .blue
        default: .secondary
        }
    }

    private func formatDate(_ iso: String) -> String {
        String(iso.prefix(10))
    }

    private func formatCurrency(_ value: Double) -> String {
        Formatters.formatCurrency(value)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.jobsService else {
            isLoading = false
            loadError = "Jobs service unavailable"
            return
        }
        isLoading = job == nil
        loadError = nil
        do {
            job = try service.getJob(id: jobId)
            teamMembers = try service.getTeamMembers(jobId: jobId)
            laborSummary = try service.getLaborSummary(jobId: jobId)
            activeTodos = try service.getActiveJobTodos(jobId: jobId)
            todoSummary = try service.getJobTodoSummary(jobId: jobId)
            stages = try service.listJobStages(forJobId: jobId)
            isPaymentHold = try service.isJobOnPaymentHold(jobId: jobId)
            warrantyDaysRemaining = try service.warrantyDaysRemaining(jobId: jobId)
            if let job {
                postAIContext(job)
            }
        } catch {
            loadError = userFriendlyError(error, context: "load job details")
        }
        isLoading = false
    }

    private func postAIContext(_ job: JobsService.JobDetail) {
        let labor = laborSummary
        let context = """
        Job Detail dashboard. Read-only context.
        Job: \(job.jobNumber) - \(job.jobName) (id \(job.id)), status: \(job.status), priority: \(job.priority), type: \(job.jobType).
        Customer: \(job.customerName ?? "not set"), lead: \(job.leadUserName ?? "not set"), team members loaded: \(teamMembers.count).
        Dates: start \(job.startDate ?? "not set"), due \(job.dueDate ?? "not set"), completed \(job.completedDate ?? "not set").
        Stage count: \(stages.count), current stage: \(stages.first(where: { $0.status == "in_progress" })?.name ?? "not set").
        Payment hold active: \(isPaymentHold). Active to-dos: \(activeTodos.count), todo summary: \(todoValue).
        Labor summary: regular \(String(format: "%.1f", labor?.totalRegularHours ?? 0)) hrs, overtime \(String(format: "%.1f", labor?.totalOvertimeHours ?? 0)) hrs, workers \(labor?.uniqueWorkers ?? 0), entries \(labor?.totalEntries ?? 0).
        Budget: \(hasFinancialPermission ? "estimated hours \(String(format: "%.0f", job.estimatedHours ?? 0)), parts cost \(Formatters.formatCurrency(job.partsCost)), budget limit \(job.budgetLimit.map { Formatters.formatCurrency($0) } ?? "not set")" : "restricted for current user").
        Warranty: start \(job.warrantyStartDate ?? "not set"), end \(job.warrantyEndDate ?? "not set"), days remaining \(warrantyDaysRemaining.map { String($0) } ?? "not active").
        Available guidance: explain job status, stage progress, smart cards, quick actions, tabs, payment hold restrictions, warranty, \(hasFinancialPermission ? "budget fields, and " : "")weekly review entry point. Do not edit the job directly.
        """
        NotificationCenter.default.post(
            name: .jobDetailPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self, !value.isEmpty else { return nil }
        return value
    }
}
