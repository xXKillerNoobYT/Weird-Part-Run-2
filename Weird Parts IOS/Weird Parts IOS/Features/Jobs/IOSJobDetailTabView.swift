import SwiftUI
import WiredPartCore

/// 9-tab job detail view.
///
/// Tabs: Overview, Team, Labor, Parts, Orders, Notebooks, Chat, Q&A, Costs.
/// Each tab is a separate section that loads data for the given job.
struct IOSJobDetailTabView: View {
    @EnvironmentObject private var appCore: AppCore

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
    @State private var teamMembers: [JobsService.TeamMemberRow] = []
    @State private var jobParts: [JobsService.JobPartRow] = []
    @State private var jobSupplierChannels: [ChatService.SupplierChannelRow] = []
    @State private var tabError: String?
    /// Job stages with computed statuses (Rough-in, Prep/Makeup, Trim-out).
    @State private var jobStages: [JobsService.JobStageStatus] = []

    // Job notebook recovery/opening state
    @State private var jobNotebook: NotebooksService.NotebookListItem?
    @State private var jobNotebookTemplate: NotebooksService.NotebookTemplateItem?
    @State private var isLoadingJobNotebook = false
    @State private var isCreatingJobNotebook = false
    @State private var jobNotebookError: String?

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
            tabPicker

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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs, id: \.id) { tab in
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
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(_ job: JobsService.JobDetail) -> some View {
        ScrollView {
            switch selectedTab {
            case "overview":
                overviewTab(job)
            case "team":
                teamTab(job)
            case "labor":
                laborTab(job)
            case "parts":
                partsTab(job)
            case "orders":
                ordersTab(job)
            case "notebooks":
                notebooksTab(job)
            case "chat":
                chatTab(job)
            case "qa":
                qaTab(job)
            case "costs":
                costsTab(job)
            case "estimate":
                estimateTab(job)
            default:
                Text("Unknown tab")
            }
        }
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
                Text("Job Notebook")
                    .font(.headline)
                Spacer()
                Button {
                    loadJobNotebook(for: job)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh job notebook")
            }

            Text("Each job should have one linked notebook. New and recovered notebooks start from the best matching job-type starter template.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isLoadingJobNotebook {
                ProgressView("Checking job notebook...")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .dsCard()
            } else if let error = jobNotebookError {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Could not load this job notebook", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadJobNotebook(for: job) }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .dsCard()
            } else if let notebook = jobNotebook {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(notebook.title)
                                .font(.headline)
                            Text("Linked to \(job.jobName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                StatusBadge(text: "Job Notebook", color: .blue)
                                StatusBadge(text: "Job Type: \(formattedJobType(job.jobType))", color: .secondary)
                                if let template = jobNotebookTemplate {
                                    StatusBadge(text: "Starter: \(template.name)", color: .green)
                                }
                            }
                        }
                        Spacer()
                    }

                    LabeledContent("Entries", value: "\(notebook.entryCount)")
                    LabeledContent("Status", value: notebook.status.capitalized)

                    NavigationLink {
                        IOSNotebookDetailPage(notebookId: notebook.id)
                            .environmentObject(appCore)
                    } label: {
                        Label("Open Job Notebook", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .dsCard()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("This older job does not have a notebook yet", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Create one now using the \(formattedJobType(job.jobType)) job-type starter template rules. Recovery is duplicate-safe, so tapping this will reuse an existing linked notebook if one appears during refresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        createMissingJobNotebook(for: job)
                    } label: {
                        if isCreatingJobNotebook {
                            ProgressView()
                        } else {
                            Label("Create Job Notebook", systemImage: "plus.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreatingJobNotebook)
                }
                .padding()
                .dsCard()
            }
        }
        .padding()
        .task(id: job.id) { loadJobNotebook(for: job) }
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
            tabError = "Service not available"
            return
        }
        do {
            teamMembers = try service.getTeamMembers(jobId: jobId)
        } catch {
            tabError = userFriendlyError(error, context: "load job details")
        }
    }

    private func loadJobParts() {
        guard let service = appCore.jobsService else {
            tabError = "Service not available"
            return
        }
        do {
            jobParts = try service.getJobParts(jobId: jobId)
        } catch {
            tabError = userFriendlyError(error, context: "load job details")
        }
    }

    private func loadJobOrders() {
        guard let service = appCore.ordersService else {
            tabError = "Service not available"
            return
        }
        do {
            jobJPOs = try service.listJPOs(jobId: jobId)
        } catch {
            tabError = userFriendlyError(error, context: "load job details")
        }
    }

    private func loadJobNotebook(for job: JobsService.JobDetail) {
        guard let service = appCore.notebooksService else {
            jobNotebookError = "Notebooks service not available"
            return
        }
        isLoadingJobNotebook = true
        jobNotebookError = nil
        do {
            jobNotebook = try service.listNotebooks(notebookType: "job", jobId: job.id).first
            jobNotebookTemplate = try service.findBestJobTemplate(jobType: job.jobType)
        } catch {
            jobNotebookError = userFriendlyError(error, context: "load job notebook")
        }
        isLoadingJobNotebook = false
    }

    private func createMissingJobNotebook(for job: JobsService.JobDetail) {
        guard let service = appCore.notebooksService,
              let userId = appCore.currentUser?.id else {
            jobNotebookError = "Notebooks service unavailable or user not logged in"
            return
        }
        isCreatingJobNotebook = true
        jobNotebookError = nil
        do {
            _ = try service.ensureJobNotebook(
                jobId: job.id,
                jobName: job.jobName,
                jobType: job.jobType,
                createdBy: userId
            )
            jobNotebook = try service.listNotebooks(notebookType: "job", jobId: job.id).first
            jobNotebookTemplate = try service.findBestJobTemplate(jobType: job.jobType)
        } catch {
            jobNotebookError = userFriendlyError(error, context: "create job notebook")
        }
        isCreatingJobNotebook = false
    }

    private func formattedJobType(_ jobType: String) -> String {
        jobType
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func loadJobQA() {
        guard let service = appCore.chatService else {
            tabError = "Service not available"
            return
        }
        do {
            jobQAThreads = try service.listQAThreads(jobId: jobId)
        } catch {
            tabError = userFriendlyError(error, context: "load job details")
        }
    }

    private func loadJobSupplierChannels() {
        guard let service = appCore.chatService else {
            tabError = "Service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            tabError = "Not logged in"
            return
        }
        do {
            jobSupplierChannels = try service.listSupplierChannelsForJob(jobId: jobId, userId: userId)
        } catch {
            tabError = userFriendlyError(error, context: "load job details")
        }
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

        let context: [String: String] = [
            "job_name": job.jobName,
            "job_number": job.jobNumber,
            "status": job.status,
            "priority": job.priority,
            "type": job.jobType,
            "customer": job.customerName ?? "N/A",
            "team_size": "\(job.teamCount) members",
            "labor_hours": String(format: "%.1f hours", job.laborHours),
            "estimated_hours": job.estimatedHours.map { String(format: "%.1f hours", $0) } ?? "N/A",
            "parts_cost": formatCurrency(job.partsCost),
            "budget": job.budgetLimit.map { formatCurrency($0) } ?? "No budget set",
            "lead": job.leadUserName ?? "Unassigned",
            "start_date": job.startDate ?? "Not set",
            "due_date": job.dueDate ?? "Not set",
            "notes": job.notes ?? "",
        ]

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
