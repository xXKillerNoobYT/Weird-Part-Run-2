import SwiftUI
import WiredPartCore

/// Dashboard-first job detail view.
///
/// The overview is the command center; legacy tabs remain available as deep sections.
struct IOSJobDetailTabView: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let jobId: Int64

    @State private var job: JobsService.JobDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedTab = "overview"
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case editJob
        case help
        case createSupplierChannel
        var id: String { String(describing: self) }
    }
    @State private var jobJPOs: [OrdersService.JPOListItem] = []
    @State private var jobQAThreads: [ChatService.QAThreadRow] = []
    @State private var oneTimeQuestions: [JobsService.OneTimeQuestionRow] = []
    @State private var activeTodos: [JobsService.ClockTodoItem] = []
    @State private var todoSummary = JobsService.JobTodoSummary(totalTodos: 0, completedTodos: 0)
    @State private var laborSummary: JobsService.LaborSummary?
    @State private var teamMembers: [JobsService.TeamMemberRow] = []
    @State private var jobParts: [JobsService.JobPartRow] = []
    @State private var jobSupplierChannels: [ChatService.SupplierChannelRow] = []
    @State private var tabError: String?
    @State private var dashboardSectionErrors: [String: String] = [:]
    /// Job stages with computed statuses (Rough-in, Prep/Makeup, Trim-out).
    @State private var jobStages: [JobsService.JobStageStatus] = []

    // Flex Pool
    @State private var isInFlexPool = false
    @State private var showFlexPoolConfirm = false
    @State private var flexPoolError: String?

    // AI Summary
    @State private var aiSummary: String?
    @State private var aiSummaryLoadedAt: Date?
    @State private var isLoadingAISummary = false
    private let aiService = FoundationModelsService()

    private let tabs: [(id: String, label: String, icon: String)] = [
        ("overview", "Overview", "doc.text"),
        ("team", "Team", "person.2"),
        ("labor", "Labor", "clock"),
        ("parts", "Parts", "wrench.and.screwdriver"),
        ("orders", "Orders", "cart"),
        ("notebooks", "Notebooks", "note.text"),
        ("chat", "Chat", "bubble.left"),
        ("qa", "Q&A", "questionmark.circle"),
        ("costs", "Costs", "dollarsign.circle"),
        ("estimate", "Estimate", "chart.bar.doc.horizontal"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            if selectedTab != "overview" {
                tabPicker
            }

            // Tab error banner
            if let tabError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(tabError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        self.tabError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
            }

            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let job {
                tabContent(job)
            }
        }
        .navigationTitle(job?.jobName ?? "Job Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(tabs, id: \.id) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab.id
                            }
                        } label: {
                            Label(tab.label, systemImage: tab.icon)
                        }
                        .accessibilityIdentifier("jobDetailToolbarSection_\(tab.id)")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More job sections")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .editJob
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit job")
                .requiresPermission("manage_jobs")
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
                    title: "Job Detail Help",
                    sections: [
                        ("Tabs", "Use the scrollable tab bar to switch between Overview, Team, Labor, Parts, Orders, Notebooks, Chat, Q&A, and Costs."),
                        ("Editing", "Tap the pencil icon to edit job details like name, status, priority, and address."),
                        ("Collaboration", "The Chat and Q&A tabs let you communicate with your team. Notebooks track notes and to-dos for this job.")
                    ]
                )
            case .editJob:
                if let job {
                    IOSEditJobSheet(job: job) { loadData() }
                        .environmentObject(appCore)
                }
            case .createSupplierChannel:
                CreateJobSupplierChannelSheet(jobId: jobId, onCreated: { loadJobSupplierChannels() })
                    .environmentObject(appCore)
            }
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 8) {
            if horizontalSizeClass == .compact, let estimateTab = tabs.first(where: { $0.id == "estimate" }) {
                jobDetailTabButton(estimateTab)
                    .padding(.leading, 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(scrollableTabs, id: \.id) { tab in
                        jobDetailTabButton(tab)
                    }
                }
                .padding(.leading)
                .padding(.vertical, 8)
            }

            if horizontalSizeClass == .compact {
                Menu {
                    ForEach(tabs, id: \.id) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab.id
                            }
                        } label: {
                            Label(tab.label, systemImage: tab.icon)
                        }
                        .accessibilityIdentifier("jobDetailTabMenu_\(tab.id)")
                    }
                } label: {
                    Label("Tabs", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("jobDetailTabMenu")
                .accessibilityLabel("Job detail tabs")
                .padding(.trailing, 8)
            }
        }
    }

    private var scrollableTabs: [(id: String, label: String, icon: String)] {
        guard horizontalSizeClass == .compact else { return tabs }
        return tabs.filter { $0.id != "estimate" }
    }

    private func jobDetailTabButton(_ tab: (id: String, label: String, icon: String)) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab.id
            }
        } label: {
            Label(tab.label, systemImage: tab.icon)
                .font(.caption)
                .fontWeight(selectedTab == tab.id ? .bold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(selectedTab == tab.id ? Color.accentColor : Color.secondary.opacity(0.15))
                )
                .foregroundStyle(selectedTab == tab.id ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("jobDetailTab_\(tab.id)")
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(_ job: JobsService.JobDetail) -> some View {
        switch selectedTab {
        case "overview":
            dashboardOverview(job)
        case "team":
            ScrollView {
                teamTab(job)
            }
        case "labor":
            ScrollView {
                laborTab(job)
            }
        case "parts":
            ScrollView {
                partsTab(job)
            }
        case "orders":
            ScrollView {
                ordersTab(job)
            }
        case "notebooks":
            ScrollView {
                notebooksTab(job)
            }
        case "chat":
            ScrollView {
                chatTab(job)
            }
        case "qa":
            ScrollView {
                qaTab(job)
            }
        case "costs":
            ScrollView {
                costsTab(job)
            }
        case "estimate":
            ScrollView {
                estimateTab(job)
            }
        default:
            Text("Unknown tab")
        }
    }

    // MARK: - Dashboard Overview

    private func dashboardOverview(_ job: JobsService.JobDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                jobHeaderCard(job)
                blockerStrip(job)
                actionSummaryGrid(job)
                highUseRoutes(job)
                workProgressSection(job)
                peopleLaborFinancialSection(job)
                notesAndProvenanceSection(job)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .accessibilityIdentifier("jobDetailDashboard")
    }

    private func jobHeaderCard(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.jobName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(job.jobNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: job.status.replacingOccurrences(of: "_", with: " ").capitalized, color: statusColor(job.status))
            }

            HStack(spacing: 8) {
                StatusBadge(text: job.priority.capitalized, color: priorityColor(job.priority))
                StatusBadge(text: job.jobType.capitalized, color: .secondary)
            }

            dashboardInfoRow(icon: "person.crop.circle", title: "Customer", value: emptyFallback(job.customerName, fallback: "No customer set"))
            dashboardInfoRow(icon: "mappin.and.ellipse", title: "Address", value: formattedAddress(job))
            dashboardInfoRow(icon: "person.badge.key", title: "Lead", value: emptyFallback(job.leadUserName, fallback: "No lead assigned"))
            if let due = job.dueDate, !due.isEmpty {
                dashboardInfoRow(icon: "calendar", title: "Due", value: due)
            }
        }
        .padding()
        .dsCard()
    }

    private func blockerStrip(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status")
                .font(.headline)

            if job.status == "payment_hold" {
                dashboardAlertRow(
                    severity: .error,
                    icon: "exclamationmark.octagon.fill",
                    title: "Payment hold. Clock-in blocked.",
                    message: "Resolve billing status before crews add labor.",
                    destinationTab: "labor"
                )
            }

            let openQA = jobQAThreads.filter { $0.status != "answered" }.count + oneTimeQuestions.filter { $0.status != "answered" }.count
            if openQA > 0 {
                dashboardAlertRow(
                    severity: .warning,
                    icon: "questionmark.bubble.fill",
                    title: "\(openQA) open questions.",
                    message: "Review job Q&A before work continues.",
                    destinationTab: "qa"
                )
            }

            let waitingRFIs = jobSupplierChannels.filter { $0.unreadCount > 0 }.count
            if waitingRFIs > 0 {
                dashboardAlertRow(
                    severity: .warning,
                    icon: "envelope.badge.fill",
                    title: "\(waitingRFIs) RFIs need attention.",
                    message: "Supplier channels have unread activity.",
                    destinationTab: "chat"
                )
            }

            let openTodos = max(todoSummary.totalTodos - todoSummary.completedTodos, activeTodos.count)
            if openTodos > 0 {
                dashboardAlertRow(
                    severity: .warning,
                    icon: "checklist.unchecked",
                    title: "\(openTodos) open todos.",
                    message: "Open the job todo list for the next work items.",
                    destinationTab: "notebooks"
                )
            }

            if job.status != "payment_hold" && openQA == 0 && waitingRFIs == 0 && openTodos == 0 {
                dashboardAlertRow(
                    severity: .info,
                    icon: "checkmark.seal.fill",
                    title: "No open blockers found.",
                    message: "Dashboard modules loaded without active holds."
                )
            }
        }
    }

    private func actionSummaryGrid(_ job: JobsService.JobDetail) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            DashboardMetricCard(title: "Todos", value: "\(max(todoSummary.totalTodos - todoSummary.completedTodos, activeTodos.count)) open", subtitle: "\(todoSummary.totalTodos) total", icon: "checklist", color: .orange) {
                selectedTab = "notebooks"
            }

            DashboardMetricCard(title: "Q&A", value: "\(jobQAThreads.filter { $0.status != "answered" }.count + oneTimeQuestions.filter { $0.status != "answered" }.count) open", subtitle: "Job questions", icon: "questionmark.circle", color: .purple) {
                selectedTab = "qa"
            }

            DashboardMetricCard(title: "RFIs", value: "\(jobSupplierChannels.filter { $0.unreadCount > 0 }.count) waiting", subtitle: "\(jobSupplierChannels.count) supplier channels", icon: "envelope.badge", color: .blue) {
                selectedTab = "chat"
            }

            DashboardMetricCard(title: "Notebook", value: activeTodos.isEmpty ? "No open todos" : "Has todos", subtitle: "Open job notes", icon: "note.text", color: .green) {
                selectedTab = "notebooks"
            }

            DashboardMetricCard(title: "Parts/orders", value: "\(jobJPOs.count) orders", subtitle: "\(jobParts.count) parts", icon: "shippingbox", color: .indigo) {
                selectedTab = "orders"
            }

            DashboardMetricCard(title: "Trailer", value: "No trailer onsite", subtitle: "Inventory unavailable", icon: "truck.box", color: .teal) {
                selectedTab = "overview"
            }
        }
    }

    private func highUseRoutes(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Routes")
                .font(.headline)

            dashboardRouteRow(icon: "questionmark.circle", title: "Job Q&A", subtitle: qASummaryText, tab: "qa", accessibilityIdentifier: "jobDetailQALink")
            dashboardRouteRow(icon: "checklist", title: "Job todo list", subtitle: todoSummaryText, tab: "notebooks", accessibilityIdentifier: "jobDetailTodosLink")
            dashboardRouteRow(icon: "note.text", title: "Job notebook", subtitle: "Open notes and job todos.", tab: "notebooks", accessibilityIdentifier: "jobDetailNotebookLink")
            dashboardRouteRow(icon: "envelope.badge", title: "Requests for info", subtitle: rfiSummaryText, tab: "chat", accessibilityIdentifier: "jobDetailRFILink")
            dashboardRouteRow(icon: "truck.box", title: "Trailer inventory", subtitle: "No trailer onsite for this job.", tab: "overview", accessibilityIdentifier: "jobDetailTrailerInventoryLink")
            dashboardRouteRow(icon: "clock", title: "Labor and clock entries", subtitle: laborSummaryText(job), tab: "labor")
            dashboardRouteRow(icon: "shippingbox", title: "Parts and orders", subtitle: "\(jobParts.count) parts, \(jobJPOs.count) purchase orders.", tab: "orders")

            NavigationLink {
                IOSEstimationReviewPage(jobId: jobId)
                    .environmentObject(appCore)
            } label: {
                routeRowLabel(icon: "chart.line.uptrend.xyaxis", title: "Estimate reviews and actuals", subtitle: "Review estimate stages and actual work.")
            }
            .buttonStyle(.plain)

            NavigationLink {
                IOSDailyReportsPage()
                    .environmentObject(appCore)
            } label: {
                routeRowLabel(icon: "doc.text.magnifyingglass", title: "Daily reports", subtitle: "Open daily job reporting.")
            }
            .buttonStyle(.plain)

            dashboardRouteRow(icon: "person.2", title: "Team", subtitle: "\(teamMembers.count) loaded team members.", tab: "team")
        }
    }

    private func workProgressSection(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Work Progress")
                .font(.headline)

            stageProgressionBar(currentStage: job.status)
                .padding(.vertical, 4)

            if !jobStages.isEmpty {
                JobStageProgressBar(stages: jobStages, compact: false)
            }

            if let est = job.estimatedHours, est > 0 {
                progressRow(title: "Hours", value: "\(String(format: "%.1f", job.laborHours))/\(String(format: "%.1f", est))h", progress: min(job.laborHours / est, 1.0), tint: job.laborHours > est ? .red : .blue)
            }

            if appCore.hasPermission("view_job_financials"), let budget = job.budgetLimit, budget > 0 {
                progressRow(title: "Budget", value: "\(formatCurrency(job.partsCost))/\(formatCurrency(budget))", progress: min(job.partsCost / budget, 1.0), tint: job.partsCost > budget ? .red : .green)
            }
        }
        .padding()
        .dsCard()
    }

    private func peopleLaborFinancialSection(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("People and Labor")
                .font(.headline)

            dashboardInfoRow(icon: "person.2", title: "Team", value: "\(job.teamCount) assigned, \(teamMembers.count) loaded")
            dashboardInfoRow(icon: "clock", title: "Labor", value: laborSummaryText(job))

            if appCore.hasPermission("view_job_financials") {
                let laborCost = job.laborHours * (job.billingRate ?? 0)
                dashboardInfoRow(icon: "dollarsign.circle", title: "Costs", value: "\(formatCurrency(laborCost + job.partsCost)) total")
            }

            if job.status == "warranty" {
                dashboardInfoRow(icon: "shield.checkered", title: "Warranty", value: warrantySummary(job))
            }

            if appCore.hasPermission("manage_flex_pool") {
                dashboardInfoRow(icon: "person.badge.clock", title: "Flex pool", value: isInFlexPool ? "In pool" : "Not in pool")
            }
        }
        .padding()
        .dsCard()
    }

    private func notesAndProvenanceSection(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)

            if let notes = job.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .lineLimit(4)
            } else {
                Text("No job notes yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !dashboardSectionErrors.isEmpty {
                ForEach(dashboardSectionErrors.sorted(by: { $0.key < $1.key }), id: \.key) { key, message in
                    dashboardInfoRow(icon: "exclamationmark.triangle", title: "\(key) unavailable", value: message)
                }
            }

            if let updated = job.updatedAt {
                Text("Updated \(updated)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if isLoadingAISummary {
                Label("Generating summary...", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let summary = aiSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let loadedAt = aiSummaryLoadedAt {
                    Text("Generated \(loadedAt, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Button {
                    Task { await loadAISummary(job) }
                } label: {
                    Label("Generate AI summary", systemImage: "sparkles")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .dsCard()
    }

    // MARK: - Overview Tab

    private func overviewTab(_ job: JobsService.JobDetail) -> some View {
        List {
            // Payment Hold Banner
            if job.status == "payment_hold" {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Payment Hold")
                                .font(.headline)
                                .foregroundStyle(.red)
                            Text("This job is on payment hold. Clock-in is blocked for all workers.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Status & Job Info
            Section {
                HStack(spacing: 8) {
                    StatusBadge(
                        text: job.status.replacingOccurrences(of: "_", with: " ").capitalized,
                        color: statusColor(job.status)
                    )
                    StatusBadge(
                        text: job.priority.capitalized,
                        color: priorityColor(job.priority)
                    )
                    StatusBadge(text: job.jobType.capitalized, color: .secondary)
                    Spacer()
                }

                DetailRow(label: "Job Number", value: job.jobNumber)

                if let customer = job.customerName, !customer.isEmpty {
                    DetailRow(label: "Customer", value: customer)
                }

                if let addr = job.addressLine1, !addr.isEmpty {
                    let fullAddr = [addr, job.city, job.state, job.zip]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")
                    DetailRow(label: "Address", value: fullAddr)
                }

                if let lead = job.leadUserName, !lead.isEmpty {
                    DetailRow(label: "Lead", value: lead)
                }
            }

            // Work Stage Progression (Rough-in / Prep/Makeup / Trim-out)
            if !jobStages.isEmpty {
                Section {
                    JobStageProgressBar(stages: jobStages, compact: false)
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Work Stage")
                }
            }

            // Lifecycle Progression (Lead -> Estimated -> Scheduled -> etc.)
            Section {
                stageProgressionBar(currentStage: job.status)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Lifecycle")
            }

            // Smart Metric Cards
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        MetricCard(title: "Hours", value: String(format: "%.1f", job.laborHours),
                                   subtitle: job.estimatedHours.map { "of \(Int($0))" },
                                   color: .blue, icon: "clock")
                        if appCore.hasPermission("view_job_financials"), let budget = job.budgetLimit {
                            MetricCard(title: "Budget", value: formatCurrency(job.partsCost),
                                       subtitle: "of \(formatCurrency(budget))",
                                       color: .green, icon: "dollarsign.circle")
                        }
                        MetricCard(title: "Team", value: "\(job.teamCount)",
                                   subtitle: "members",
                                   color: .orange, icon: "person.2")
                        MetricCard(title: "Parts", value: formatCurrency(job.partsCost),
                                   subtitle: "cost",
                                   color: .purple, icon: "wrench.and.screwdriver")
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // AI Summary
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if isLoadingAISummary {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating summary...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let summary = aiSummary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        if let loadedAt = aiSummaryLoadedAt {
                            Text("Generated \(loadedAt, style: .relative) ago")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Button {
                            Task { await loadAISummary(job) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                                    .accessibilityHidden(true)
                                Text("Tap to generate AI summary")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                        .accessibilityHidden(true)
                    Text("AI Summary")
                }
            }

            // Progress Bars
            if job.estimatedHours != nil || (appCore.hasPermission("view_job_financials") && job.budgetLimit != nil) {
                Section {
                    if let est = job.estimatedHours, est > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Hours Progress")
                                Spacer()
                                Text("\(String(format: "%.1f", job.laborHours))/\(Int(est))h")
                                    .font(.caption).monospacedDigit()
                            }
                            ProgressView(value: min(job.laborHours / est, 1.0))
                                .tint(job.laborHours > est ? .red : .blue)
                        }
                    }
                    if appCore.hasPermission("view_job_financials"),
                       let budget = job.budgetLimit, budget > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Budget Progress")
                                Spacer()
                                Text("\(formatCurrency(job.partsCost))/\(formatCurrency(budget))")
                                    .font(.caption).monospacedDigit()
                            }
                            ProgressView(value: min(job.partsCost / budget, 1.0))
                                .tint(job.partsCost > budget ? .red : .green)
                        }
                    }
                } header: {
                    Text("Progress")
                }
            }

            // Dates
            Section {
                if let start = job.startDate {
                    DetailRow(label: "Start Date", value: start)
                }
                if let due = job.dueDate {
                    DetailRow(label: "Due Date", value: due)
                }
                if let completed = job.completedDate {
                    DetailRow(label: "Completed", value: completed)
                }
            } header: {
                Text("Dates")
            }

            // Quick Actions (3-column grid)
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    quickAction("Clock In", icon: "clock.badge.checkmark", color: .green) {
                        selectedTab = "labor"
                    }
                    quickAction("Order Parts", icon: "cart.badge.plus", color: .blue) {
                        selectedTab = "orders"
                    }
                    quickAction("Add Note", icon: "note.text.badge.plus", color: .orange) {
                        selectedTab = "notebooks"
                    }
                    quickAction("Ask Q&A", icon: "questionmark.bubble", color: .purple) {
                        selectedTab = "qa"
                    }
                    quickAction("View Costs", icon: "dollarsign.circle", color: .green) {
                        selectedTab = "costs"
                    }
                    quickAction("Team", icon: "person.2", color: .indigo) {
                        selectedTab = "team"
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Quick Actions")
            }

            // Warranty Info (if warranty status)
            if job.status == "warranty" {
                Section {
                    if let start = job.warrantyStartDate {
                        DetailRow(label: "Warranty Start", value: start)
                    }
                    if let end = job.warrantyEndDate {
                        DetailRow(label: "Warranty End", value: end)
                    }
                    // Calculate days remaining
                    if let endStr = job.warrantyEndDate {
                        if let endDate = Formatters.iso8601Basic.date(from: endStr)
                            ?? Formatters.iso8601Fractional.date(from: endStr) {
                            let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
                            HStack {
                                Text("Days Remaining")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(days)")
                                    .font(.body)
                                    .foregroundStyle(days < 30 ? .red : .primary)
                            }
                        }
                    }
                } header: {
                    Label("Warranty", systemImage: "shield.checkered")
                }
            }

            // Financial Summary (hat-gated)
            if appCore.hasPermission("view_job_financials") {
                Section {
                    let laborCost = job.laborHours * (job.billingRate ?? 0)

                    LabeledContent("Parts Cost", value: formatCurrency(job.partsCost))
                    LabeledContent("Labor Cost", value: formatCurrency(laborCost))

                    Divider()

                    LabeledContent {
                        Text(formatCurrency(laborCost + job.partsCost))
                            .fontWeight(.semibold)
                    } label: {
                        Text("Total Cost")
                            .fontWeight(.semibold)
                    }

                    // Budget Usage progress bar
                    if let budget = job.budgetLimit, budget > 0 {
                        let totalCost = laborCost + job.partsCost
                        let usageRatio = totalCost / budget
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Budget Usage")
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(min(usageRatio, 1.0) * 100))%")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(usageRatio > 1.0 ? .red : .primary)
                            }
                            ProgressView(value: min(usageRatio, 1.0))
                                .tint(usageRatio > 1.0 ? .red : usageRatio > 0.8 ? .orange : .green)
                        }
                    }
                } header: {
                    Text("Financial Summary")
                }
            }

            // Flex Pool (manager-only)
            if appCore.hasPermission("manage_flex_pool") {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Status")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: isInFlexPool ? "checkmark.circle.fill" : "minus.circle")
                                    .foregroundStyle(isInFlexPool ? .green : .secondary)
                                    .accessibilityHidden(true)
                                Text(isInFlexPool ? "In Pool" : "Not in Pool")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(isInFlexPool ? .green : .secondary)
                            }
                        }
                        Spacer()
                        Button {
                            showFlexPoolConfirm = true
                        } label: {
                            Text(isInFlexPool ? "Remove from Pool" : "Add to Flex Pool")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isInFlexPool ? .red : .accentColor)
                    }

                    if let error = flexPoolError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Label("Flex Pool", systemImage: "person.badge.clock")
                }
                .confirmationDialog(
                    isInFlexPool ? "Remove from Flex Pool?" : "Add to Flex Pool?",
                    isPresented: $showFlexPoolConfirm,
                    titleVisibility: .visible
                ) {
                    if isInFlexPool {
                        Button("Remove from Pool", role: .destructive) {
                            toggleFlexPool(job: job)
                        }
                    } else {
                        Button("Add to Pool") {
                            toggleFlexPool(job: job)
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text(isInFlexPool
                         ? "Workers will no longer be able to self-claim this job."
                         : "All qualified workers will be able to see and claim this job.")
                }
            }

            // Notes
            if let notes = job.notes, !notes.isEmpty {
                Section {
                    Text(notes)
                        .font(.body)
                } header: {
                    Text("Notes")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Team Tab

    private func teamTab(_ job: JobsService.JobDetail) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("Team Members")
                    .font(.headline)
                Spacer()
                Text("\(teamMembers.count) members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if teamMembers.isEmpty {
                EmptyStateView(
                    icon: "person.2",
                    title: "No Team Members",
                    message: "Assign team members to this job."
                )
                .frame(height: 200)
            } else {
                ForEach(teamMembers) { member in
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.userName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(member.role.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let date = member.joinedAt {
                            Text(date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .dsCard()
                }
            }
        }
        .padding()
        .task { loadTeamMembers() }
    }

    // MARK: - Labor Tab

    private func laborTab(_ job: JobsService.JobDetail) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("Labor Summary")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 24) {
                VStack {
                    Text(String(format: "%.1f", job.laborHours))
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Total Hours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let estimated = job.estimatedHours {
                    VStack {
                        Text(String(format: "%.1f", estimated))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Text("Estimated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack {
                        let pct = estimated > 0 ? (job.laborHours / estimated) * 100 : 0
                        Text(String(format: "%.0f%%", pct))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(pct > 100 ? .red : .green)
                        Text("Used")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .dsCard()
        }
        .padding()
    }

    // MARK: - Parts Tab

    private func partsTab(_ job: JobsService.JobDetail) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("Job Parts")
                    .font(.headline)
                Spacer()
                Text(formatCurrency(job.partsCost))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .hideWithoutPermission("show_dollar_values")
            }

            if jobParts.isEmpty {
                EmptyStateView(
                    icon: "wrench.and.screwdriver",
                    title: "No Parts",
                    message: "Parts used on this job will appear here."
                )
                .frame(height: 200)
            } else {
                ForEach(jobParts) { part in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.partName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let code = part.partCode, !code.isEmpty {
                                Text(code)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Qty: \(part.qtyConsumed)")
                                .font(.caption)
                            if part.qtyReturned > 0 {
                                Text("Returned: \(part.qtyReturned)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        if let cost = part.unitCost {
                            Text(formatCurrency(cost * Double(part.qtyConsumed)))
                                .font(.caption)
                                .fontWeight(.medium)
                                .hideWithoutPermission("show_dollar_values")
                        }
                    }
                    .padding(10)
                    .dsCard()
                }
            }
        }
        .padding()
        .task { loadJobParts() }
    }

    // MARK: - Costs Tab

    private func costsTab(_ job: JobsService.JobDetail) -> some View {
        VStack(spacing: 16) {
            Text("Cost Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                CostRow(label: "Parts", value: formatCurrency(job.partsCost))
                CostRow(label: "Labor Hours", value: String(format: "%.1f hrs", job.laborHours))
                if let budget = job.budgetLimit {
                    Divider()
                    CostRow(label: "Budget Limit", value: formatCurrency(budget))
                }
            }
            .padding()
            .dsCard()
        }
        .padding()
        .hideWithoutPermission("show_dollar_values")
    }

    // MARK: - Estimate Tab

    private func estimateTab(_ job: JobsService.JobDetail) -> some View {
        VStack(spacing: 16) {
            Text("Job Estimation")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stage selector — navigate to questionnaire for each stage
            let stages: [(id: String, label: String, icon: String)] = [
                ("bid", "Bid", "doc.text.magnifyingglass"),
                ("pre_start", "Pre-Start", "checklist"),
                ("during", "During Job", "hammer"),
                ("before_trim", "Before Trim", "ruler"),
                ("punch_list", "Punch List", "checkmark.circle"),
            ]

            ForEach(stages, id: \.id) { stage in
                NavigationLink {
                    IOSEstimationQuestionnairePage(jobId: jobId, stage: stage.id)
                        .environmentObject(appCore)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: stage.icon)
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text(stage.label)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(12)
                    .dsCard()
                }
                .buttonStyle(.plain)
            }

            // Reviews link
            NavigationLink {
                IOSEstimationReviewPage(jobId: jobId)
                    .environmentObject(appCore)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.green)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text("Reviews & Actuals")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(12)
                .dsCard()
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Orders Tab

    private func ordersTab(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Job Purchase Orders")
                    .font(.headline)
                Spacer()
            }

            if jobJPOs.isEmpty {
                EmptyStateView(
                    icon: "cart",
                    title: "No Orders",
                    message: "No purchase orders have been created for this job."
                )
                .frame(height: 200)
            } else {
                ForEach(jobJPOs) { jpo in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("JPO #\(jpo.id)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("by \(jpo.requestedByName)")
                                .font(.caption)
                        }
                        Spacer()
                        StatusBadge(text: jpo.status.capitalized, color: jpo.status == "approved" ? .green : .orange)
                        Text("\(jpo.lineCount) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .dsCard()
                }
            }
        }
        .padding()
        .task { loadJobOrders() }
    }

    // MARK: - Notebooks Tab

    private func notebooksTab(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Job Notebooks")
                    .font(.headline)
                Spacer()
            }

            Text("Notebooks for \(job.jobName) can be viewed in the Notebooks module.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                NotificationCenter.default.post(
                    name: .navigateToModule,
                    object: nil,
                    userInfo: ["moduleId": "notebooks", "tabId": "notebooks-job-notebooks"]
                )
            } label: {
                Label("Open Job Notebooks", systemImage: "note.text")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Chat Tab

    private func chatTab(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Job Chat")
                    .font(.headline)
                Spacer()
            }

            Text("Chat for \(job.jobName) is in the Chat module.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                NotificationCenter.default.post(
                    name: .navigateToModule,
                    object: nil,
                    userInfo: ["moduleId": "chat", "tabId": "chat-channels"]
                )
            } label: {
                Label("Open Chat", systemImage: "bubble.left.fill")
            }
            .buttonStyle(.bordered)

            // Supplier Channels for this job
            supplierChannelsSection
        }
        .padding()
        .task { loadJobSupplierChannels() }
    }

    // MARK: - Supplier Channels Section

    private var supplierChannelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supplier Channels")
                .font(.headline)

            if jobSupplierChannels.isEmpty {
                Button {
                    activeSheet = .createSupplierChannel
                } label: {
                    Label("Add Supplier Channel", systemImage: "plus.bubble")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
            } else {
                ForEach(jobSupplierChannels, id: \.channelId) { channel in
                    NavigationLink {
                        IOSMessageThreadView(
                            channelId: channel.channelId,
                            channelName: channel.channelName
                        )
                        .environmentObject(appCore)
                    } label: {
                        HStack {
                            Image(systemName: "building.2")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.supplierName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let role = channel.role {
                                    Text(role)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if channel.unreadCount > 0 {
                                Text("\(channel.unreadCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }

                Button {
                    activeSheet = .createSupplierChannel
                } label: {
                    Label("Add Another", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Dashboard Components

    private func dashboardInfoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func dashboardAlertRow(
        severity: DSAlertSeverity,
        icon: String,
        title: String,
        message: String,
        destinationTab: String? = nil,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        Button {
            if let destinationTab {
                selectedTab = destinationTab
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(severity.color)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if destinationTab != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .dsAlertCard(severity)
        }
        .buttonStyle(.plain)
        .disabled(destinationTab == nil)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private func dashboardRouteRow(icon: String, title: String, subtitle: String, tab: String, accessibilityIdentifier: String? = nil) -> some View {
        Button {
            selectedTab = tab
        } label: {
            routeRowLabel(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private func routeRowLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .combine)
    }

    private func progressRow(title: String, value: String, progress: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(value)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(tint)
        }
    }

    private var qASummaryText: String {
        let openCount = jobQAThreads.filter { $0.status != "answered" }.count + oneTimeQuestions.filter { $0.status != "answered" }.count
        return openCount == 0 ? "No open job questions." : "\(openCount) open job questions."
    }

    private var todoSummaryText: String {
        let openCount = max(todoSummary.totalTodos - todoSummary.completedTodos, activeTodos.count)
        return openCount == 0 ? "No open todos for this job." : "\(openCount) open / \(todoSummary.totalTodos) total."
    }

    private var rfiSummaryText: String {
        let waitingCount = jobSupplierChannels.filter { $0.unreadCount > 0 }.count
        if waitingCount > 0 { return "\(waitingCount) supplier channels waiting." }
        return jobSupplierChannels.isEmpty ? "No open requests for info." : "\(jobSupplierChannels.count) supplier channels."
    }

    private func laborSummaryText(_ job: JobsService.JobDetail) -> String {
        if let laborSummary {
            let total = laborSummary.totalRegularHours + laborSummary.totalOvertimeHours
            return "\(String(format: "%.1f", total)) hours from \(laborSummary.uniqueWorkers) workers."
        }
        return "\(String(format: "%.1f", job.laborHours)) total hours."
    }

    private func emptyFallback(_ value: String?, fallback: String) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return value
    }

    private func formattedAddress(_ job: JobsService.JobDetail) -> String {
        let parts = [job.addressLine1, job.city, job.state, job.zip]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "No address set" : parts.joined(separator: ", ")
    }

    private func warrantySummary(_ job: JobsService.JobDetail) -> String {
        switch (job.warrantyStartDate, job.warrantyEndDate) {
        case let (start?, end?):
            return "\(start) to \(end)"
        case let (_, end?):
            return "Ends \(end)"
        default:
            return "Warranty active"
        }
    }

    // MARK: - Q&A Tab

    private func qaTab(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Questions & Answers")
                    .font(.headline)
                Spacer()
            }

            if jobQAThreads.isEmpty {
                EmptyStateView(
                    icon: "questionmark.circle",
                    title: "No Questions",
                    message: "No Q&A threads for this job yet."
                )
                .frame(height: 200)
            } else {
                ForEach(jobQAThreads) { thread in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            StatusBadge(
                                text: thread.status.capitalized,
                                color: thread.status == "answered" ? .green : .orange
                            )
                            Spacer()
                            Text("by \(thread.askedByName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(thread.question)
                            .font(.subheadline)
                            .lineLimit(2)
                        if let answer = thread.answer {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                    .accessibilityHidden(true)
                                Text(answer)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(10)
                    .dsCard()
                }
            }
        }
        .padding()
        .task { loadJobQA() }
    }

    // MARK: - Data

    private func loadData() {
        guard let service = appCore.jobsService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = job == nil
        loadError = nil
        do {
            job = try service.getJob(id: jobId)
            // Load job stages with computed statuses
            jobStages = try service.listJobStages(forJobId: jobId)
            loadDashboardSections()
            // Load flex pool status for managers
            if appCore.hasPermission("manage_flex_pool"),
               let svc = appCore.schedulingService {
                isInFlexPool = (try? svc.isJobInFlexPool(jobId: jobId)) ?? false
            }
        } catch {
            loadError = userFriendlyError(error, context: "load job data")
        }
        isLoading = false
    }

    private func loadDashboardSections() {
        dashboardSectionErrors = [:]
        loadTodoDashboardData()
        loadJobQuestionsDashboardData()
        loadTeamMembers()
        loadJobParts()
        loadJobOrders()
        loadJobQA()
        loadJobSupplierChannels()
        loadLaborSummary()
    }

    private func toggleFlexPool(job: JobsService.JobDetail) {
        guard let service = appCore.schedulingService else {
            flexPoolError = "Scheduling service not available"
            return
        }
        flexPoolError = nil
        do {
            try service.markJobFlexPool(jobId: job.id, isFlexPool: !isInFlexPool)
            isInFlexPool.toggle()
        } catch {
            flexPoolError = userFriendlyError(error, context: "update flex pool status")
        }
    }

    private func loadTeamMembers() {
        guard let service = appCore.jobsService else {
            setDashboardSectionError("Team", "Service not available")
            return
        }
        do {
            teamMembers = try service.getTeamMembers(jobId: jobId)
            clearDashboardSectionError("Team")
        } catch {
            let message = userFriendlyError(error, context: "load job details")
            tabError = message
            setDashboardSectionError("Team", message)
        }
    }

    private func loadJobParts() {
        guard let service = appCore.jobsService else {
            setDashboardSectionError("Parts", "Service not available")
            return
        }
        do {
            jobParts = try service.getJobParts(jobId: jobId)
            clearDashboardSectionError("Parts")
        } catch {
            let message = userFriendlyError(error, context: "load job details")
            tabError = message
            setDashboardSectionError("Parts", message)
        }
    }

    private func loadJobOrders() {
        guard let service = appCore.ordersService else {
            setDashboardSectionError("Orders", "Service not available")
            return
        }
        do {
            jobJPOs = try service.listJPOs(jobId: jobId)
            clearDashboardSectionError("Orders")
        } catch {
            let message = userFriendlyError(error, context: "load job details")
            tabError = message
            setDashboardSectionError("Orders", message)
        }
    }

    private func loadJobQA() {
        guard let service = appCore.chatService else {
            setDashboardSectionError("Q&A", "Service not available")
            return
        }
        do {
            jobQAThreads = try service.listQAThreads(jobId: jobId)
            clearDashboardSectionError("Q&A")
        } catch {
            let message = userFriendlyError(error, context: "load job details")
            tabError = message
            setDashboardSectionError("Q&A", message)
        }
    }

    private func loadJobSupplierChannels() {
        guard let service = appCore.chatService else {
            setDashboardSectionError("RFIs", "Service not available")
            return
        }
        guard let userId = appCore.currentUser?.id else {
            setDashboardSectionError("RFIs", "Not logged in")
            return
        }
        do {
            jobSupplierChannels = try service.listSupplierChannelsForJob(jobId: jobId, userId: userId)
            clearDashboardSectionError("RFIs")
        } catch {
            let message = userFriendlyError(error, context: "load job details")
            tabError = message
            setDashboardSectionError("RFIs", message)
        }
    }

    private func loadTodoDashboardData() {
        guard let service = appCore.jobsService else {
            setDashboardSectionError("Todos", "Service not available")
            return
        }
        do {
            todoSummary = try service.getJobTodoSummary(jobId: jobId)
            activeTodos = try service.getActiveJobTodos(jobId: jobId)
            clearDashboardSectionError("Todos")
        } catch {
            setDashboardSectionError("Todos", userFriendlyError(error, context: "load job todos"))
        }
    }

    private func loadJobQuestionsDashboardData() {
        guard let service = appCore.jobsService else {
            setDashboardSectionError("Questions", "Service not available")
            return
        }
        do {
            oneTimeQuestions = try service.getQuestionsForJob(jobId: jobId)
            clearDashboardSectionError("Questions")
        } catch {
            setDashboardSectionError("Questions", userFriendlyError(error, context: "load job questions"))
        }
    }

    private func loadLaborSummary() {
        guard let service = appCore.jobsService else {
            setDashboardSectionError("Labor", "Service not available")
            return
        }
        do {
            laborSummary = try service.getLaborSummary(jobId: jobId)
            clearDashboardSectionError("Labor")
        } catch {
            setDashboardSectionError("Labor", userFriendlyError(error, context: "load labor summary"))
        }
    }

    private func setDashboardSectionError(_ section: String, _ message: String) {
        dashboardSectionErrors[section] = message
    }

    private func clearDashboardSectionError(_ section: String) {
        dashboardSectionErrors.removeValue(forKey: section)
    }

    // MARK: - Overview Helpers

    /// Stage progression bar with dot indicators for each lifecycle stage.
    private func stageProgressionBar(currentStage: String) -> some View {
        let stages: [(id: String, label: String)] = [
            ("lead", "Lead"),
            ("estimated", "Estimated"),
            ("scheduled", "Scheduled"),
            ("in_progress", "In Progress"),
            ("complete", "Complete"),
            ("invoiced", "Invoiced"),
            ("paid", "Paid"),
        ]

        // Map job status to the closest stage for progression
        let stageMapping: [String: String] = [
            "lead": "lead",
            "estimated": "estimated",
            "scheduled": "scheduled",
            "active": "in_progress",
            "in_progress": "in_progress",
            "completed": "complete",
            "complete": "complete",
            "invoiced": "invoiced",
            "paid": "paid",
            // Non-linear statuses map to their last known progression
            "on_hold": "in_progress",
            "payment_hold": "complete",
            "warranty": "complete",
            "cancelled": "lead",
            "continuous": "in_progress",
        ]

        let mappedStage = stageMapping[currentStage] ?? "lead"
        let currentIndex = stages.firstIndex(where: { $0.id == mappedStage }) ?? 0

        return VStack(spacing: 6) {
            // Progress bar with dots
            GeometryReader { geo in
                let dotCount = stages.count
                // Guard against single-stage (or empty) scenario to prevent division by zero.
                let spacing = dotCount > 1 ? geo.size.width / CGFloat(dotCount - 1) : geo.size.width

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)

                    // Filled track
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: spacing * CGFloat(currentIndex), height: 4)

                    // Dot indicators
                    ForEach(0..<dotCount, id: \.self) { i in
                        let isCompleted = i <= currentIndex
                        let isCurrent = i == currentIndex

                        Circle()
                            .fill(isCompleted ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: isCurrent ? 14 : 10, height: isCurrent ? 14 : 10)
                            .overlay {
                                if isCurrent {
                                    Circle()
                                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                                        .frame(width: 18, height: 18)
                                }
                            }
                            .position(x: spacing * CGFloat(i), y: 2)
                    }
                }
            }
            .frame(height: 20)

            // Stage labels
            HStack {
                ForEach(Array(stages.enumerated()), id: \.element.id) { i, stage in
                    Text(stage.label)
                        .font(.caption2)
                        .foregroundStyle(i <= currentIndex ? .primary : .tertiary)
                        .fontWeight(i == currentIndex ? .bold : .regular)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    /// Quick action button for the 3-column grid.
    private func quickAction(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12))
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    /// Load an AI-generated summary for the job overview, cached for 1 hour.
    private func loadAISummary(_ job: JobsService.JobDetail) async {
        // Check cache: reuse if loaded within the last hour
        if let loadedAt = aiSummaryLoadedAt,
           Date().timeIntervalSince(loadedAt) < 3600,
           aiSummary != nil {
            return
        }

        isLoadingAISummary = true

        var context: [String: String] = [
            "job_name": job.jobName,
            "job_number": job.jobNumber,
            "status": job.status,
            "priority": job.priority,
            "type": job.jobType,
            "customer": job.customerName ?? "N/A",
            "team_size": "\(job.teamCount) members",
            "labor_hours": String(format: "%.1f hours", job.laborHours),
            "estimated_hours": job.estimatedHours.map { String(format: "%.1f hours", $0) } ?? "N/A",
            "lead": job.leadUserName ?? "Unassigned",
            "start_date": job.startDate ?? "Not set",
            "due_date": job.dueDate ?? "Not set",
            "notes": job.notes ?? "",
        ]
        if appCore.hasPermission("view_job_financials") || appCore.hasPermission("show_dollar_values") {
            context["parts_cost"] = formatCurrency(job.partsCost)
            context["budget"] = job.budgetLimit.map { formatCurrency($0) } ?? "No budget set"
        }

        let result = await aiService.generatePreFill(
            fieldType: "brief job overview summary (2-3 sentences covering status, progress, and anything notable)",
            contextData: context
        )

        await MainActor.run {
            isLoadingAISummary = false
            if result.success, let text = result.text, !text.isEmpty {
                aiSummary = text
                aiSummaryLoadedAt = Date()
            } else {
                aiSummary = "Unable to generate summary. AI may not be available on this device."
                aiSummaryLoadedAt = Date()
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": .green
        case "completed": .blue
        case "on_hold": .orange
        case "cancelled": .red
        case "warranty": .purple
        case "payment_hold": .red
        case "continuous": .gray
        default: .secondary
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        let isCompleted = job?.status == "completed" || job?.status == "cancelled"
        return TimelinePriorityColor.color(priority: priority, dueDateString: job?.dueDate, isCompleted: isCompleted)
    }

    private func formatCurrency(_ value: Double) -> String {
        Formatters.formatCurrency(value)
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2).bold()
            if let sub = subtitle {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(minWidth: 100)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

// MARK: - Cost Row

private struct CostRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Create Job Supplier Channel Sheet

private struct CreateJobSupplierChannelSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let jobId: Int64
    let onCreated: () -> Void

    @State private var suppliers: [PartsService.SupplierWithCount] = []
    @State private var selectedSupplierId: Int64 = 0
    @State private var channelName = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Supplier") {
                    if suppliers.isEmpty {
                        Text("No suppliers available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Select Supplier", selection: $selectedSupplierId) {
                            Text("Choose...").tag(Int64(0))
                            ForEach(suppliers, id: \.supplier.id) { item in
                                Text(item.supplier.name)
                                    .tag(item.supplier.id ?? Int64(0))
                            }
                        }
                    }
                }
                Section("Channel Name (Optional)") {
                    TextField("Auto-generated if empty", text: $channelName)
                }
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Supplier Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .disabled(selectedSupplierId == 0 || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { loadSuppliers() }
        }
    }

    private func loadSuppliers() {
        guard let service = appCore.partsService else {
            errorMessage = "Service not available"
            return
        }
        do {
            suppliers = try service.listSuppliers()
        } catch {
            errorMessage = "Failed to load suppliers."
        }
    }

    private func save() {
        guard let service = appCore.chatService else {
            errorMessage = "Chat service unavailable"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            errorMessage = "Not logged in"
            return
        }
        guard selectedSupplierId > 0 else {
            errorMessage = "Please select a supplier."
            return
        }

        isSaving = true
        errorMessage = nil

        let supplier = suppliers.first(where: { ($0.supplier.id ?? 0) == selectedSupplierId })
        let displayName = supplier?.supplier.contactName ?? supplier?.supplier.name ?? "Supplier"
        let name = channelName.isEmpty ? "Channel: \(supplier?.supplier.name ?? "Supplier")" : channelName

        do {
            _ = try service.createSupplierChannel(
                name: name,
                supplierId: selectedSupplierId,
                supplierDisplayName: displayName,
                contactId: nil,
                role: nil,
                createdBy: userId,
                jobId: jobId
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "load job details")
        }
        isSaving = false
    }
}
