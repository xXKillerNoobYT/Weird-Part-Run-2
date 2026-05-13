import SwiftUI
import WiredPartCore

/// Formal RFI (Request for Information) workflow for office/management.
///
/// Uses `ChatService.RFIRecord` directly instead of routing creation through the
/// generic Q&A form. RFIs still create backing Q&A threads for inbox visibility.
struct IOSRFIListPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var rfis: [ChatService.RFIRecord] = []
    @State private var jobsById: [Int64: JobsService.JobListItem] = [:]
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter: RFIFilter = .all
    @State private var loadError: String?

    private enum ActiveSheet: String, Identifiable {
        case createRFI
        case help
        var id: String { rawValue }
    }

    @State private var activeSheet: ActiveSheet?

    enum RFIFilter: String, CaseIterable {
        case all = "All"
        case pending = "Pending"
        case overdue = "Overdue"
        case responded = "Responded"
        case closed = "Closed"
    }

    var body: some View {
        VStack(spacing: 0) {
            smartCardBar
            rfiList
        }
        .navigationTitle("RFIs")
        .searchable(text: $searchText, prompt: "Search RFIs...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .createRFI } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create new RFI")
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
            case .createRFI:
                IOSFormalRFIForm(onSubmitted: { loadData() })
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "RFI Help",
                    sections: [
                        ("What This Page Does", "RFIs are formal requests sent to outside parties for job information, decisions, or clarification. This page tracks due dates, recipients, sent dates, responses, and closure status."),
                        ("How to Use It", "Use the filter cards to view pending, overdue, responded, or closed RFIs. Tap an RFI to review its full detail, mark it sent, record a response, or close it."),
                        ("Creating an RFI", "Tap the + button, choose the job, enter the subject/body, pick the directed-to party, set priority, and add a due date when needed."),
                        ("Tips", "Overdue RFIs are based on due dates before today and statuses that have not responded or closed. RFIs also create backing Q&A threads so they remain visible in the unified inbox.")
                    ]
                )
            }
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Smart Card Filters

    private var smartCardBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(RFIFilter.allCases, id: \.self) { filter in
                    smartCard(
                        filter.rawValue,
                        count: countFor(filter),
                        icon: iconFor(filter),
                        isActive: statusFilter == filter,
                        color: colorFor(filter)
                    ) {
                        statusFilter = filter
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func countFor(_ filter: RFIFilter) -> Int {
        rfis.filter { matches($0, filter: filter) }.count
    }

    private func iconFor(_ filter: RFIFilter) -> String {
        switch filter {
        case .all: return "doc.text"
        case .pending: return "clock"
        case .overdue: return "exclamationmark.triangle"
        case .responded: return "arrowshape.turn.up.left"
        case .closed: return "checkmark.circle"
        }
    }

    private func colorFor(_ filter: RFIFilter) -> Color {
        switch filter {
        case .all: return .blue
        case .pending: return .orange
        case .overdue: return .red
        case .responded: return .green
        case .closed: return .secondary
        }
    }

    private func smartCard(_ label: String, count: Int, icon: String, isActive: Bool,
                           color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text("\(count)")
                        .font(.system(.title3, weight: .bold))
                        .monospacedDigit()
                }
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? .white : color)
            .frame(minWidth: 76)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? color : color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - RFI List

    @ViewBuilder
    private var rfiList: some View {
        if isLoading {
            ProgressView("Loading RFIs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredRFIs.isEmpty {
            EmptyStateView(
                icon: "doc.questionmark",
                title: "No RFIs",
                message: statusFilter == .all ? "No formal RFIs have been created yet." : "No RFIs match this filter."
            )
        } else {
            List(filteredRFIs) { rfi in
                NavigationLink {
                    IOSRFIDetailPage(rfiId: rfi.id)
                        .environmentObject(appCore)
                        .navigationTitle(rfi.rfiNumber)
                } label: {
                    rfiRow(rfi)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredRFIs: [ChatService.RFIRecord] {
        var items = rfis.filter { matches($0, filter: statusFilter) }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter {
                $0.rfiNumber.lowercased().contains(query) ||
                $0.subject.lowercased().contains(query) ||
                $0.body.lowercased().contains(query) ||
                $0.directedToName.lowercased().contains(query) ||
                jobName(for: $0).lowercased().contains(query)
            }
        }

        return items
    }

    private func matches(_ rfi: ChatService.RFIRecord, filter: RFIFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .pending:
            return ["open", "submitted", "pending_response"].contains(rfi.status)
        case .overdue:
            return isOverdue(rfi)
        case .responded:
            return rfi.status == "responded"
        case .closed:
            return rfi.status == "closed"
        }
    }

    private func rfiRow(_ rfi: ChatService.RFIRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(rfi.rfiNumber)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.blue)
                    .clipShape(Capsule())
                StatusBadge(text: displayStatus(rfi), color: statusColor(rfi))
                StatusBadge(text: rfi.priority.capitalized, color: priorityColor(rfi))
                Spacer()
            }

            Text(rfi.subject)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            HStack(spacing: 8) {
                Label(jobName(for: rfi), systemImage: "briefcase")
                Label(rfi.directedToName, systemImage: "person.crop.rectangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: 10) {
                if let dueDate = rfi.dueDate, !dueDate.isEmpty {
                    Label("Due \(Formatters.formatDateString(dueDate))", systemImage: "calendar")
                        .foregroundStyle(isOverdue(rfi) ? .red : .secondary)
                }
                if let sentAt = rfi.sentAt {
                    Label("Sent \(Formatters.formatDateString(sentAt))", systemImage: "paperplane")
                }
                if let respondedAt = rfi.respondedAt {
                    Label("Responded \(Formatters.formatDateString(respondedAt))", systemImage: "arrowshape.turn.up.left")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func displayStatus(_ rfi: ChatService.RFIRecord) -> String {
        if isOverdue(rfi) { return "Overdue" }
        return rfi.status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func statusColor(_ rfi: ChatService.RFIRecord) -> Color {
        if isOverdue(rfi) { return .red }
        switch rfi.status {
        case "open", "submitted", "pending_response": return .orange
        case "responded": return .green
        case "closed": return .secondary
        default: return .blue
        }
    }

    private func priorityColor(_ rfi: ChatService.RFIRecord) -> Color {
        TimelinePriorityColor.color(priority: rfi.priority, dueDateString: rfi.dueDate, isCompleted: rfi.status == "closed")
    }

    private func isOverdue(_ rfi: ChatService.RFIRecord) -> Bool {
        guard !["responded", "closed"].contains(rfi.status),
              let dueDate = rfi.dueDate,
              let due = Formatters.localDateFormatter.date(from: String(dueDate.prefix(10))) else {
            return false
        }
        let today = Calendar.current.startOfDay(for: Date())
        return due < today
    }

    private func jobName(for rfi: ChatService.RFIRecord) -> String {
        jobsById[rfi.jobId]?.jobName ?? "Job #\(rfi.jobId)"
    }

    // MARK: - Data

    private func loadData() {
        guard let service = appCore.chatService else {
            loadError = "Chat service unavailable"
            isLoading = false
            return
        }
        isLoading = rfis.isEmpty
        loadError = nil
        do {
            rfis = try service.listFormalRFIs()
            loadJobs()
        } catch {
            loadError = userFriendlyError(error, context: "load RFIs")
        }
        isLoading = false
    }

    private func loadJobs() {
        guard let jobsService = appCore.jobsService else { return }
        let jobs = (try? jobsService.listJobs(limit: 500)) ?? []
        jobsById = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
    }
}

private struct IOSFormalRFIForm: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    var onSubmitted: (() -> Void)?

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var contacts: [PeopleService.ContactListItem] = []
    @State private var selectedJobId: Int64?
    @State private var selectedContactId: Int64?
    @State private var directedToType = "gc"
    @State private var directedToName = ""
    @State private var subject = ""
    @State private var rfiBody = ""
    @State private var priority = "normal"
    @State private var hasDueDate = true
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let priorities = ["low", "normal", "high", "urgent"]
    private let directedTypes = ["gc", "owner", "architect", "engineer", "supplier", "external"]

    private var isValid: Bool {
        selectedJobId != nil &&
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !rfiBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !directedToName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    if jobs.isEmpty {
                        Text("No active jobs available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Job", selection: $selectedJobId) {
                            Text("Select a job...").tag(nil as Int64?)
                            ForEach(jobs, id: \.id) { job in
                                Text(job.jobName).tag(job.id as Int64?)
                            }
                        }
                    }
                }

                Section("Directed To") {
                    Picker("Party Type", selection: $directedToType) {
                        ForEach(directedTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }

                    if !contacts.isEmpty {
                        Picker("Known Contact", selection: $selectedContactId) {
                            Text("Manual entry").tag(nil as Int64?)
                            ForEach(contacts, id: \.id) { contact in
                                Text(contactDisplayName(contact)).tag(contact.id as Int64?)
                            }
                        }
                        .onChange(of: selectedContactId) { _, newValue in
                            guard let newValue,
                                  let contact = contacts.first(where: { $0.id == newValue }) else { return }
                            directedToName = contactDisplayName(contact)
                            if let type = contact.contactType, !type.isEmpty {
                                directedToType = type
                            }
                        }
                    }

                    TextField("Name or company", text: $directedToName)
                        .textInputAutocapitalization(.words)
                }

                Section("RFI") {
                    TextField("Subject", text: $subject)
                    TextEditor(text: $rfiBody)
                        .frame(minHeight: 120)
                }

                Section("Priority & Due Date") {
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { p in
                            Text(p.capitalized).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New RFI")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .interactiveDismissDisabled(hasUnsavedChanges && !isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createRFI() }
                        .fontWeight(.semibold)
                        .disabled(!isValid || isSaving)
                }
            }
            .task { loadFormData() }
        }
    }

    private var hasUnsavedChanges: Bool {
        selectedJobId != nil ||
        !directedToName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !rfiBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadFormData() {
        if let jobsService = appCore.jobsService {
            jobs = (try? jobsService.listJobs(status: "active", limit: 200)) ?? []
        }
        if let peopleService = appCore.peopleService {
            contacts = (try? peopleService.listContacts()) ?? []
        }
    }

    private func createRFI() {
        guard let jobId = selectedJobId else { return }
        guard let userId = appCore.currentUser?.id else {
            errorMessage = "Not logged in"
            return
        }
        guard let chatService = appCore.chatService else {
            errorMessage = "Chat service not available"
            return
        }

        isSaving = true
        errorMessage = nil
        do {
            try chatService.createFormalRFI(
                jobId: jobId,
                createdBy: userId,
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                body: rfiBody.trimmingCharacters(in: .whitespacesAndNewlines),
                directedToName: directedToName.trimmingCharacters(in: .whitespacesAndNewlines),
                directedToType: directedToType,
                directedToContactId: selectedContactId,
                priority: priority,
                dueDate: hasDueDate ? Formatters.localDateFormatter.string(from: dueDate) : nil
            )
            isSaving = false
            onSubmitted?()
            dismiss()
        } catch {
            isSaving = false
            errorMessage = userFriendlyError(error, context: "create RFI")
        }
    }

    private func contactDisplayName(_ contact: PeopleService.ContactListItem) -> String {
        let fullName = "\(contact.firstName) \(contact.lastName)".trimmingCharacters(in: .whitespaces)
        if !fullName.isEmpty { return fullName }
        return contact.company ?? "Contact #\(contact.id)"
    }
}

private struct IOSRFIDetailPage: View {
    @EnvironmentObject private var appCore: AppCore

    let rfiId: Int64

    @State private var rfi: ChatService.RFIRecord?
    @State private var jobName = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var responseText = ""
    @State private var responseFrom = ""
    @State private var isSaving = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading RFI...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { loadData() }
            } else if let rfi {
                List {
                    summarySection(rfi)
                    bodySection(rfi)
                    responseSection(rfi)
                    actionsSection(rfi)
                }
                .listStyle(.insetGrouped)
            } else {
                EmptyStateView(icon: "doc.questionmark", title: "RFI Not Found", message: "This RFI could not be loaded.")
            }
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    private func summarySection(_ rfi: ChatService.RFIRecord) -> some View {
        Section("Summary") {
            detailRow("RFI Number", rfi.rfiNumber, icon: "number")
            detailRow("Status", rfi.status.replacingOccurrences(of: "_", with: " ").capitalized, icon: "tag")
            detailRow("Job", jobName.isEmpty ? "Job #\(rfi.jobId)" : jobName, icon: "briefcase")
            detailRow("Directed To", rfi.directedToName, icon: "person.crop.rectangle")
            detailRow("Party Type", rfi.directedToType.capitalized, icon: "building.2")
            detailRow("Priority", rfi.priority.capitalized, icon: "flag")
            if let dueDate = rfi.dueDate {
                detailRow("Due Date", Formatters.formatDateString(dueDate), icon: "calendar")
            }
            if let sentAt = rfi.sentAt {
                detailRow("Sent", Formatters.formatDateString(sentAt), icon: "paperplane")
            }
            if let respondedAt = rfi.respondedAt {
                detailRow("Responded", Formatters.formatDateString(respondedAt), icon: "arrowshape.turn.up.left")
            }
        }
    }

    private func bodySection(_ rfi: ChatService.RFIRecord) -> some View {
        Section("Request") {
            Text(rfi.subject)
                .font(.headline)
            Text(rfi.body)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func responseSection(_ rfi: ChatService.RFIRecord) -> some View {
        Section("Response") {
            if let response = rfi.responseText, !response.isEmpty {
                if let from = rfi.responseReceivedFrom, !from.isEmpty {
                    detailRow("From", from, icon: "person")
                }
                Text(response)
                    .textSelection(.enabled)
            } else {
                TextField("Received from", text: $responseFrom)
                    .textInputAutocapitalization(.words)
                TextEditor(text: $responseText)
                    .frame(minHeight: 100)
                Button {
                    recordResponse()
                } label: {
                    Label("Record Response", systemImage: "arrowshape.turn.up.left")
                }
                .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
    }

    private func actionsSection(_ rfi: ChatService.RFIRecord) -> some View {
        Section("Actions") {
            if rfi.sentAt == nil {
                Button {
                    updateRFI(markSent: true, status: "submitted")
                } label: {
                    Label("Mark Sent", systemImage: "paperplane")
                }
                .disabled(isSaving)
            }

            if rfi.status != "closed" {
                Button {
                    updateRFI(status: "closed")
                } label: {
                    Label("Close RFI", systemImage: "checkmark.circle")
                }
                .disabled(isSaving)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadData() {
        guard let service = appCore.chatService else {
            errorMessage = "Chat service unavailable"
            isLoading = false
            return
        }
        isLoading = rfi == nil
        errorMessage = nil
        do {
            rfi = try service.listFormalRFIs().first(where: { $0.id == rfiId })
            if let jobId = rfi?.jobId, let job = try? appCore.jobsService?.getJob(id: jobId) {
                jobName = job.jobName
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "load RFI")
        }
        isLoading = false
    }

    private func updateRFI(markSent: Bool = false, status: String? = nil) {
        guard let service = appCore.chatService else { return }
        isSaving = true
        do {
            try service.updateFormalRFI(rfiId: rfiId, status: status, markSent: markSent)
            isSaving = false
            loadData()
        } catch {
            isSaving = false
            errorMessage = userFriendlyError(error, context: "update RFI")
        }
    }

    private func recordResponse() {
        guard let service = appCore.chatService else { return }
        isSaving = true
        do {
            try service.recordRFIResponse(
                rfiId: rfiId,
                responseText: responseText.trimmingCharacters(in: .whitespacesAndNewlines),
                receivedFrom: responseFrom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : responseFrom.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            responseText = ""
            responseFrom = ""
            isSaving = false
            loadData()
        } catch {
            isSaving = false
            errorMessage = userFriendlyError(error, context: "record RFI response")
        }
    }
}
