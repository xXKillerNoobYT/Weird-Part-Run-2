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
    @State private var showEditSheet = false
    @State private var showHelp = false
    @State private var jobJPOs: [OrdersService.JPOListItem] = []
    @State private var jobQAThreads: [ChatService.QAThreadRow] = []
    @State private var teamMembers: [JobsService.TeamMemberRow] = []
    @State private var jobParts: [JobsService.JobPartRow] = []
    @State private var jobSupplierChannels: [ChatService.SupplierChannelRow] = []
    @State private var showCreateSupplierChannel = false

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
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            tabPicker

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
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .requiresPermission("manage_jobs")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $showHelp) {
            PageHelpSheet(
                title: "Job Detail Help",
                sections: [
                    ("Tabs", "Use the scrollable tab bar to switch between Overview, Team, Labor, Parts, Orders, Notebooks, Chat, Q&A, and Costs."),
                    ("Editing", "Tap the pencil icon to edit job details like name, status, priority, and address."),
                    ("Collaboration", "The Chat and Q&A tabs let you communicate with your team. Notebooks track notes and to-dos for this job.")
                ]
            )
        }
        .sheet(isPresented: $showEditSheet) {
            if let job {
                IOSEditJobSheet(job: job) { loadData() }
                    .environmentObject(appCore)
            }
        }
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
            default:
                Text("Unknown tab")
            }
        }
    }

    // MARK: - Overview Tab

    private func overviewTab(_ job: JobsService.JobDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status & Priority
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

            // Job Number
            DetailRow(label: "Job Number", value: job.jobNumber)

            // Customer
            if let customer = job.customerName, !customer.isEmpty {
                DetailRow(label: "Customer", value: customer)
            }

            // Address
            if let addr = job.addressLine1, !addr.isEmpty {
                let fullAddr = [addr, job.city, job.state, job.zip]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                DetailRow(label: "Address", value: fullAddr)
            }

            // Lead
            if let lead = job.leadUserName, !lead.isEmpty {
                DetailRow(label: "Lead", value: lead)
            }

            // Dates
            if let start = job.startDate {
                DetailRow(label: "Start Date", value: start)
            }
            if let due = job.dueDate {
                DetailRow(label: "Due Date", value: due)
            }

            // Notes
            if let notes = job.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(notes)
                        .font(.body)
                }
            }
        }
        .padding()
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
                    showCreateSupplierChannel = true
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
                    showCreateSupplierChannel = true
                } label: {
                    Label("Add Another", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
        }
        .sheet(isPresented: $showCreateSupplierChannel) {
            CreateJobSupplierChannelSheet(jobId: jobId, onCreated: { loadJobSupplierChannels() })
                .environmentObject(appCore)
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

    // MARK: - Placeholder Tab

    private func placeholderTab(_ title: String, icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Data

    private func loadData() {
        guard let service = appCore.jobsService else { return }
        isLoading = job == nil
        loadError = nil
        do {
            job = try service.getJob(id: jobId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadTeamMembers() {
        guard let service = appCore.jobsService else { return }
        do {
            teamMembers = try service.getTeamMembers(jobId: jobId)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadJobParts() {
        guard let service = appCore.jobsService else { return }
        do {
            jobParts = try service.getJobParts(jobId: jobId)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadJobOrders() {
        guard let service = appCore.ordersService else { return }
        do {
            let all = try service.listJPOs(status: nil)
            jobJPOs = all.filter { $0.jobId == jobId }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadJobQA() {
        guard let service = appCore.chatService else { return }
        do {
            let all = try service.listQAThreads(status: nil)
            jobQAThreads = all.filter { $0.jobId == jobId }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadJobSupplierChannels() {
        guard let service = appCore.chatService else { return }
        guard let userId = appCore.currentUser?.id else { return }
        do {
            jobSupplierChannels = try service.listSupplierChannelsForJob(jobId: jobId, userId: userId)
        } catch {
            loadError = error.localizedDescription
        }
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

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
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
            .navigationTitle("Supplier Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .disabled(selectedSupplierId == 0 || isSaving)
                }
            }
            .task { loadSuppliers() }
        }
    }

    private func loadSuppliers() {
        guard let service = appCore.partsService else { return }
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
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
