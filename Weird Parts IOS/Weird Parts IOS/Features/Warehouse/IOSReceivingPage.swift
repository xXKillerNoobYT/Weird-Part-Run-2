import SwiftUI
import WiredPartCore

/// Sorting/Receiving incoming shipments and job returns page for iOS.
///
/// Shows active and recent sorting sessions for purchase orders and job returns.
/// Displays PO ID, started-by name, mode, status, and item count.
/// Supports pull-to-refresh, smart card filters by status,
/// start new session, and continue active sessions.
struct IOSReceivingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var sessions: [WarehouseService.ReceivingSessionInfo] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var selectedFilter: StatusFilter?
    @State private var jobReturnItems: [WarehouseService.JobReturnHoldingItem] = []

    private enum ActiveSheet: Identifiable {
        case chooseEntry
        case poIncoming
        case jobReturn
        case continueSession(Int64)
        case help

        var id: String { String(describing: self) }
    }

    private enum StatusFilter: String, CaseIterable {
        case active = "Active"
        case completed = "Completed"
        case cancelled = "Cancelled"

        var matchStatuses: [String] {
            switch self {
            case .active: ["in_progress", "active"]
            case .completed: ["completed"]
            case .cancelled: ["cancelled"]
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "warehouse-receiving")

            entryActions

            // Smart card filters
            if !sessions.isEmpty || !jobReturnGroups.isEmpty {
                smartCardFilters
            }

            sessionList
        }
        .task { appCore.onboardingManager?.markCompleted("wh-receiving-view") }
        .navigationTitle("Sorting/Receiving")
        .searchable(text: $searchText, prompt: "Search sorting sessions...")
        .refreshable { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .chooseEntry } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Start sorting or receiving session")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .task { loadData() }
        .onDisappear {
            NotificationCenter.default.post(name: .warehouseReceivingPageInactive, object: nil)
        }
        .onChange(of: searchText) { _, _ in postAIContext() }
        .onChange(of: selectedFilter) { _, _ in postAIContext() }
        .onChange(of: activeSheet?.id) { _, _ in postAIContext() }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .chooseEntry:
            NavigationStack {
                entryChoiceSheet
                    .navigationTitle("New Sorting/Receiving")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { activeSheet = nil }
                        }
                    }
            }
        case .poIncoming:
            NavigationStack {
                IOSReceiveShipmentPage()
                    .environmentObject(appCore)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { activeSheet = nil }
                        }
                    }
            }
        case .jobReturn:
            NavigationStack {
                IOSJobReturnSortingPage()
                    .environmentObject(appCore)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { activeSheet = nil }
                        }
                    }
            }
        case .continueSession(let sessionId):
            NavigationStack {
                IOSReceiveShipmentPage(sessionId: sessionId)
                    .environmentObject(appCore)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { activeSheet = nil }
                        }
                    }
            }
        case .help:
            PageHelpSheet(
                title: "Sorting/Receiving Help",
                sections: [
                    ("Overview", "Use PO Incoming for supplier shipments and Job Return for material coming back from jobs."),
                    ("PO Incoming", "PO Incoming keeps the purchase order receiving checklist, including quantity checks and visible price verification."),
                    ("Job Return", "Job Return records the job, source, returned-by user, notes, parts, quantities, and sorting outcome without PO price verification.")
                ]
            )
        }
    }

    private var entryActions: some View {
        HStack(spacing: 12) {
            Button { activeSheet = .poIncoming } label: {
                Label("PO Incoming", systemImage: "shippingbox.and.arrow.backward")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Scan PO")

            Button { activeSheet = .jobReturn } label: {
                Label("Job Return", systemImage: "arrow.uturn.backward.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var entryChoiceSheet: some View {
        List {
            Section {
                Button { activeSheet = .poIncoming } label: {
                    entryChoiceRow(
                        icon: "shippingbox.and.arrow.backward.fill",
                        title: "PO Incoming",
                        subtitle: "Receive supplier shipments against purchase orders and verify receipt prices."
                    )
                }
                .accessibilityLabel("Scan PO")

                Button { activeSheet = .jobReturn } label: {
                    entryChoiceRow(
                        icon: "arrow.uturn.backward.circle.fill",
                        title: "Job Return",
                        subtitle: "Sort parts returned from a job into holding, shelf, staging, write-off, or review."
                    )
                }
            }
        }
    }

    private func entryChoiceRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 36, height: 36)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(StatusFilter.allCases, id: \.self) { filter in
                    let count = countForFilter(filter)
                    smartCard(filter: filter, count: count)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func countForFilter(_ filter: StatusFilter) -> Int {
        let poCount = sessions.filter { session in
            filter.matchStatuses.contains(session.status)
        }.count
        let jobReturnCount = filter == .active ? jobReturnGroups.filter { $0.totalQty > 0 }.count : 0
        return poCount + jobReturnCount
    }

    private func smartCard(filter: StatusFilter, count: Int) -> some View {
        let isSelected = selectedFilter == filter
        let color = filterColor(filter)

        return Button {
            selectedFilter = isSelected ? nil : filter
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: filterIcon(filter))
                        .font(.caption)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(filter.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 90)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }

    private func filterIcon(_ filter: StatusFilter) -> String {
        switch filter {
        case .active: "arrow.down.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private func filterColor(_ filter: StatusFilter) -> Color {
        switch filter {
        case .active: .blue
        case .completed: .green
        case .cancelled: .red
        }
    }

    // MARK: - Session List

    @ViewBuilder
    private var sessionList: some View {
        if isLoading {
            ProgressView("Loading sorting sessions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredSessions.isEmpty && filteredJobReturnGroups.isEmpty {
            if searchText.isEmpty && selectedFilter == nil {
                EmptyStateView(
                    icon: "shippingbox.and.arrow.backward",
                    title: "No Sorting Sessions",
                    message: "Start with PO Incoming for purchase orders or Job Return for material coming back from a job."
                )
            } else {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: "No receiving sessions match your current filters."
                )
            }
        } else {
            List {
                if !filteredSessions.isEmpty {
                    Section("PO Incoming") {
                        ForEach(filteredSessions, id: \.id) { session in
                            let isActive = session.status == "in_progress" || session.status == "active"
                            if isActive {
                                Button {
                                    activeSheet = .continueSession(session.id)
                                } label: {
                                    sessionRow(session)
                                }
                                .buttonStyle(.plain)
                            } else {
                                sessionRow(session)
                            }
                        }
                    }
                }

                if !filteredJobReturnGroups.isEmpty {
                    Section("Job Return") {
                        ForEach(filteredJobReturnGroups) { group in
                            jobReturnGroupRow(group)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private struct JobReturnGroup: Identifiable {
        let id: Int64
        let sourceJobName: String
        let itemCount: Int
        let totalQty: Int
        let statuses: [String]
        let createdAt: String
    }

    private var jobReturnGroups: [JobReturnGroup] {
        Dictionary(grouping: jobReturnItems, by: \.intakeId)
            .map { intakeId, items in
                let first = items.first
                return JobReturnGroup(
                    id: intakeId,
                    sourceJobName: first?.sourceJobName ?? "Unknown Job",
                    itemCount: items.count,
                    totalQty: items.reduce(0) { $0 + $1.qtyRemaining },
                    statuses: Array(Set(items.map(\.status))).sorted(),
                    createdAt: first?.createdAt ?? ""
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredJobReturnGroups: [JobReturnGroup] {
        var result = jobReturnGroups

        if let filter = selectedFilter {
            result = result.filter { group in
                filter.matchStatuses.contains("in_progress") && group.totalQty > 0
            }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.sourceJobName.lowercased().contains(query) ||
                $0.statuses.joined(separator: " ").lowercased().contains(query)
            }
        }

        return result
    }

    private func jobReturnGroupRow(_ group: JobReturnGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Job Return")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    sourceBadge("Job Return")
                }
                Text(group.sourceJobName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(formatDate(group.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge("in_progress")
                Label("\(group.itemCount) items", systemImage: "cube.box")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(group.totalQty) in holding/review")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private var filteredSessions: [WarehouseService.ReceivingSessionInfo] {
        var result = sessions

        // Status filter
        if let filter = selectedFilter {
            result = result.filter { session in
                filter.matchStatuses.contains(session.status)
            }
        }

        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.startedByName.lowercased().contains(query) ||
                $0.mode.lowercased().contains(query) ||
                String($0.poId).contains(query)
            }
        }

        return result
    }

    private func sessionRow(_ session: WarehouseService.ReceivingSessionInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(statusColor(session.status))
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
                .background(statusColor(session.status).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("PO #\(session.poId)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    sourceBadge("PO Incoming")
                    modeBadge(session.mode)
                }
                Text("Started by \(session.startedByName)")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(formatDate(session.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(session.status)
                Label("\(session.itemCount) items", systemImage: "cube.box")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if session.status == "in_progress" || session.status == "active" {
                    Text("Tap to continue")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }

            if session.status == "in_progress" || session.status == "active" {
                ActionDot(isOverdue: false)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color = statusColor(status)
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "in_progress", "active": .blue
        case "completed": .green
        case "cancelled": .red
        default: .secondary
        }
    }

    private func modeBadge(_ mode: String) -> some View {
        Text(mode.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2)
            .foregroundStyle(.purple)
    }

    private func sourceBadge(_ source: String) -> some View {
        Text(source)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.blue.opacity(0.12)))
            .foregroundStyle(.blue)
    }

    // MARK: - Helpers

    private func formatDate(_ dateStr: String) -> String {
        if dateStr.count >= 10 { return String(dateStr.prefix(10)) }
        return dateStr
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = sessions.isEmpty
        loadError = nil
        do {
            sessions = try service.getActiveSessions()
            jobReturnItems = try service.getJobReturnHoldingItems(includeRouted: false)
            postAIContext()
        } catch {
            loadError = userFriendlyError(error, context: "load sorting data")
        }
        isLoading = false
    }

    private func postAIContext() {
        let statusCounts = Dictionary(grouping: sessions, by: \.status)
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let context = """
        Warehouse Sorting/Receiving page. Read-only context.
        Loaded PO incoming sessions: \(sessions.count), active Job Return groups: \(jobReturnGroups.count), visible after filters: \(filteredSessions.count + filteredJobReturnGroups.count), selected filter: \(selectedFilter?.rawValue ?? "none"), search active: \(!searchText.isEmpty).
        Session statuses: \(statusCounts.isEmpty ? "none" : statusCounts).
        Available read-only guidance: explain PO Incoming vs Job Return entry points, active/completed/cancelled filters, search, continuing active sessions, and source badges. Do not start or continue a session directly.
        """
        NotificationCenter.default.post(
            name: .warehouseReceivingPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }
}

// MARK: - Job Return Sorting

private struct IOSJobReturnSortingPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var selectedJob: JobsService.JobListItem?
    @State private var jobSearchText = ""
    @State private var returnSource = "Crew truck"
    @State private var notes = ""
    @State private var partSearchText = ""
    @State private var partResults: [Part] = []
    @State private var lines: [JobReturnDraftLine] = []
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var completionMessage: String?
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var isShowingCompletionReview = false
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case partScanner
        case help
        var id: String { String(describing: self) }
    }

    private enum ReturnCondition: String, CaseIterable, Identifiable {
        case usable = "Usable"
        case damaged = "Damaged"
        case wrongPart = "Wrong Part"

        var id: String { rawValue }
        var serviceValue: String {
            switch self {
            case .usable: "usable"
            case .damaged: "damaged"
            case .wrongPart: "wrong_part"
            }
        }
    }

    private enum SortAction: String, CaseIterable, Identifiable {
        case holding = "Holding"
        case shelf = "Shelf"
        case stage = "Stage"
        case writeOff = "Write-off"
        case supplierReview = "Supplier/Damage Review"
        case wrongPart = "Wrong Part"

        var id: String { rawValue }
    }

    private struct JobReturnDraftLine: Identifiable, Equatable {
        let id = UUID()
        let partId: Int64
        let partName: String
        let partCode: String?
        var qty: Int = 1
        var condition: ReturnCondition = .usable
        var sortAction: SortAction = .holding
        var notes: String = ""
    }

    var body: some View {
        List {
            if let error = loadError {
                Section {
                    ErrorStateView(message: error) { loadData() }
                }
            }

            Section("Return Details") {
                jobPicker

                Picker("Return Source", selection: $returnSource) {
                    Text("Crew truck").tag("Crew truck")
                    Text("Job box").tag("Job box")
                    Text("Customer site").tag("Customer site")
                    Text("Other").tag("Other")
                }

                HStack {
                    Text("Returned By")
                    Spacer()
                    Text(appCore.currentUser?.displayName ?? "Current user")
                        .foregroundStyle(.secondary)
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("Add Returned Parts") {
                HStack {
                    TextField("Search parts", text: $partSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { searchParts() }
                    Button { searchParts() } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search returned parts")
                    Button { activeSheet = .partScanner } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Scan returned part")
                }

                ForEach(partResults.prefix(8), id: \.id) { part in
                    Button { addPart(part) } label: {
                        partResultRow(part)
                    }
                }
            }

            if !lines.isEmpty {
                Section("Returned Lines") {
                    ForEach($lines) { $line in
                        draftLineRow($line)
                    }
                    .onDelete { offsets in
                        lines.remove(atOffsets: offsets)
                    }
                }

                Section("Completion Preview") {
                    completionPreview
                }
            }

            Section {
                Button {
                    isShowingCompletionReview = true
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Label("Review Job Return", systemImage: "checkmark.circle.fill")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .frame(minHeight: 44)
                .disabled(!canSubmit || isSubmitting)
            }

            if let error = actionError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Job Return")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadData() }
        .onChange(of: jobSearchText) { _, _ in filterSelectedJobIfNeeded() }
        .onChange(of: partSearchText) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                searchParts()
            }
        }
        .alert("Job Return Complete", isPresented: Binding(
            get: { completionMessage != nil },
            set: { if !$0 { completionMessage = nil } }
        )) {
            Button("OK") {
                completionMessage = nil
                resetForm()
            }
        } message: {
            Text(completionMessage ?? "")
        }
        .alert("Complete Job Return?", isPresented: $isShowingCompletionReview) {
            Button("Cancel", role: .cancel) {}
            Button("Complete Job Return") {
                Task { await submitJobReturn() }
            }
            .disabled(isSubmitting)
        } message: {
            Text(completionReviewMessage)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .partScanner:
                QRScanSheet(expectedType: .part) { result in
                    handleScannedPart(code: result.code)
                }
                .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Job Return Help",
                    sections: [
                        ("Sorting", "Choose Holding when the item should stay out of shelf inventory until later review."),
                        ("Shelf", "Shelf adds usable returned material back to warehouse inventory."),
                        ("Review", "Damaged, supplier review, and wrong part outcomes keep the material out of shelf stock.")
                    ]
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
    }

    private var canSubmit: Bool {
        selectedJob != nil &&
        appCore.currentUser?.id != nil &&
        !returnSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        lines.contains { $0.qty > 0 }
    }

    private var completionReviewMessage: String {
        let groups = completionGroups(for: lines)
        let routedSummary = ["Shelved", "Staged", "Write-off", "Supplier/Damage Review", "Wrong Part", "Holding"]
            .compactMap { label -> String? in
                let qty = groups[label, default: 0]
                return qty > 0 ? "\(label): \(qty)" : nil
            }
            .joined(separator: "\n")
        let jobName = selectedJob?.jobName ?? "selected job"
        let base = routedSummary.isEmpty ? "No return lines are ready." : routedSummary
        return """
        Review the sorting outcomes for \(jobName) before committing this return.

        \(base)

        Holding, review, staged, and write-off items stay out of shelf inventory unless explicitly shelved.
        """
    }

    private var filteredJobs: [JobsService.JobListItem] {
        let query = jobSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return jobs }
        return jobs.filter {
            $0.jobName.lowercased().contains(query) ||
            $0.jobNumber.lowercased().contains(query) ||
            ($0.customerName ?? "").lowercased().contains(query)
        }
    }

    private var jobPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search jobs", text: $jobSearchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Picker("Job", selection: Binding(
                get: { selectedJob?.id },
                set: { id in selectedJob = jobs.first { $0.id == id } }
            )) {
                Text("Select a job").tag(Int64?.none)
                ForEach(filteredJobs.prefix(50), id: \.id) { job in
                    Text("\(job.jobNumber) - \(job.jobName)").tag(Optional(job.id))
                }
            }
        }
    }

    private func partResultRow(_ part: Part) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(part.name)
                    .foregroundStyle(.primary)
                if let code = part.code {
                    Text(code)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)
        }
    }

    private func draftLineRow(_ line: Binding<JobReturnDraftLine>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.wrappedValue.partName)
                        .font(.headline)
                    if let code = line.wrappedValue.partCode {
                        Text(code)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                quantityStepper(line)
            }

            Picker("Condition", selection: line.condition) {
                ForEach(ReturnCondition.allCases) { condition in
                    Text(condition.rawValue).tag(condition)
                }
            }
            .pickerStyle(.segmented)

            Picker("Sort Action", selection: line.sortAction) {
                ForEach(SortAction.allCases) { action in
                    Text(action.rawValue).tag(action)
                }
            }

            Text(routingCopy(for: line.wrappedValue.sortAction))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Line notes", text: line.notes, axis: .vertical)
                .lineLimit(1...3)
        }
        .padding(.vertical, 4)
    }

    private func quantityStepper(_ line: Binding<JobReturnDraftLine>) -> some View {
        HStack(spacing: 12) {
            Button {
                line.qty.wrappedValue = max(1, line.qty.wrappedValue - 1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease returned quantity")

            Text("\(line.qty.wrappedValue)")
                .font(.title3.weight(.semibold))
                .frame(minWidth: 44)
                .multilineTextAlignment(.center)

            Button {
                line.qty.wrappedValue += 1
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase returned quantity")
        }
        .frame(minHeight: 44)
    }

    private var completionPreview: some View {
        let groups = completionGroups(for: lines)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(["Shelved", "Staged", "Write-off", "Supplier/Damage Review", "Wrong Part", "Holding"], id: \.self) { label in
                HStack {
                    Text(label)
                    Spacer()
                    Text("\(groups[label, default: 0])")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            if groups["Holding", default: 0] > 0 {
                Label("Unsorted Job Return items stay in holding and do not count as shelf inventory.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func routingCopy(for action: SortAction) -> String {
        switch action {
        case .holding:
            "Hold for later sorting. This does not add shelf inventory."
        case .shelf:
            "Return usable material to shelf inventory."
        case .stage:
            "Stage the returned item back to the selected job without changing shelf stock."
        case .writeOff:
            "Write off unusable returned material with audit history."
        case .supplierReview:
            "Keep damaged or supplier-returnable material out of shelf stock for review."
        case .wrongPart:
            "Flag as wrong part and keep it out of shelf inventory."
        }
    }

    private func completionGroups(for lines: [JobReturnDraftLine]) -> [String: Int] {
        var groups: [String: Int] = [:]
        for line in lines where line.qty > 0 {
            switch line.sortAction {
            case .shelf:
                groups["Shelved", default: 0] += line.qty
            case .stage:
                groups["Staged", default: 0] += line.qty
            case .writeOff:
                groups["Write-off", default: 0] += line.qty
            case .supplierReview:
                groups["Supplier/Damage Review", default: 0] += line.qty
            case .wrongPart:
                groups["Wrong Part", default: 0] += line.qty
            case .holding:
                groups["Holding", default: 0] += line.qty
            }
        }
        return groups
    }

    private func loadData() {
        isLoading = true
        loadError = nil
        do {
            guard let jobsService = appCore.jobsService else {
                loadError = "Jobs service not available"
                isLoading = false
                return
            }
            jobs = try jobsService.listJobs(status: "active", limit: 200)
            if selectedJob == nil {
                selectedJob = jobs.first
            }
        } catch {
            loadError = userFriendlyError(error, context: "load active jobs")
        }
        isLoading = false
    }

    private func searchParts() {
        guard let service = appCore.partsService else {
            actionError = "Parts service not available"
            return
        }
        let query = partSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            partResults = []
            return
        }
        do {
            partResults = try service.searchParts(query: query, limit: 12)
        } catch {
            actionError = userFriendlyError(error, context: "search parts")
        }
    }

    private func addPart(_ part: Part) {
        guard let partId = part.id else { return }
        if let index = lines.firstIndex(where: { $0.partId == partId }) {
            lines[index].qty += 1
        } else {
            lines.append(JobReturnDraftLine(partId: partId, partName: part.name, partCode: part.code))
        }
        partSearchText = ""
        partResults = []
    }

    private func handleScannedPart(code: String) {
        partSearchText = code
        searchParts()
        if partResults.count == 1, let part = partResults.first {
            addPart(part)
        }
    }

    private func filterSelectedJobIfNeeded() {
        if let selectedJob, !filteredJobs.contains(where: { $0.id == selectedJob.id }) {
            self.selectedJob = filteredJobs.first
        }
    }

    private func submitJobReturn() async {
        guard let warehouseService = appCore.warehouseService else {
            actionError = "Warehouse service not available"
            return
        }
        guard let job = selectedJob else {
            actionError = "Select a job before completing the return."
            return
        }
        guard let userId = appCore.currentUser?.id else {
            actionError = "Not logged in. Please log in and try again."
            return
        }

        isSubmitting = true
        actionError = nil

        do {
            let lineInputs = lines.filter { $0.qty > 0 }.map { line in
                WarehouseService.JobReturnLineInput(
                    partId: line.partId,
                    qty: line.qty,
                    condition: conditionForSubmit(line),
                    notes: line.notes.isEmpty ? nil : line.notes
                )
            }
            let intakeId = try warehouseService.createJobReturnIntake(
                sourceJobId: job.id,
                returnSource: returnSource,
                returnedBy: userId,
                lines: lineInputs,
                notes: notes.isEmpty ? nil : notes
            )

            let holdingItems = try warehouseService.getJobReturnHoldingItems(jobId: job.id, includeRouted: false)
                .filter { $0.intakeId == intakeId }
            try applyImmediateRoutes(holdingItems: holdingItems, userId: userId, jobId: job.id)

            await MainActor.run {
                completionMessage = completionSummary()
                isSubmitting = false
            }
        } catch {
            await MainActor.run {
                actionError = userFriendlyError(error, context: "complete job return")
                isSubmitting = false
            }
        }
    }

    private func conditionForSubmit(_ line: JobReturnDraftLine) -> String {
        switch line.sortAction {
        case .supplierReview:
            "damaged"
        case .wrongPart:
            "wrong_part"
        default:
            line.condition.serviceValue
        }
    }

    private func applyImmediateRoutes(
        holdingItems: [WarehouseService.JobReturnHoldingItem],
        userId: Int64,
        jobId: Int64
    ) throws {
        guard let warehouseService = appCore.warehouseService else { return }
        var remainingItems = holdingItems
        for line in lines where line.qty > 0 {
            guard let itemIndex = remainingItems.firstIndex(where: { $0.partId == line.partId }) else { continue }
            let item = remainingItems.remove(at: itemIndex)
            switch line.sortAction {
            case .shelf:
                try warehouseService.confirmJobReturnShelfRoute(
                    intakeItemId: item.id,
                    qty: line.qty,
                    performedBy: userId,
                    notes: line.notes.isEmpty ? nil : line.notes
                )
            case .stage:
                try warehouseService.confirmJobReturnStagingRoute(
                    intakeItemId: item.id,
                    qty: line.qty,
                    jobId: jobId,
                    performedBy: userId,
                    notes: line.notes.isEmpty ? nil : line.notes
                )
            case .writeOff:
                try warehouseService.writeOffJobReturnItem(
                    intakeItemId: item.id,
                    qty: line.qty,
                    reason: "Job return write-off",
                    performedBy: userId,
                    notes: line.notes.isEmpty ? nil : line.notes
                )
            case .holding, .supplierReview, .wrongPart:
                break
            }
        }
    }

    private func completionSummary() -> String {
        let groups = completionGroups(for: lines)
        var parts: [String] = []
        if groups["Shelved", default: 0] > 0 { parts.append("\(groups["Shelved", default: 0]) shelved") }
        if groups["Staged", default: 0] > 0 { parts.append("\(groups["Staged", default: 0]) staged") }
        if groups["Write-off", default: 0] > 0 { parts.append("\(groups["Write-off", default: 0]) written off") }
        if groups["Supplier/Damage Review", default: 0] > 0 { parts.append("\(groups["Supplier/Damage Review", default: 0]) in supplier/damage review") }
        if groups["Wrong Part", default: 0] > 0 { parts.append("\(groups["Wrong Part", default: 0]) wrong part") }
        if groups["Holding", default: 0] > 0 { parts.append("\(groups["Holding", default: 0]) holding") }
        let base = parts.isEmpty ? "Job Return complete." : "Job Return complete: \(parts.joined(separator: ", "))."
        if groups["Holding", default: 0] > 0 {
            return "\(base) Holding items do not count as shelf inventory until sorted."
        }
        return base
    }

    private func resetForm() {
        lines = []
        notes = ""
        partSearchText = ""
        partResults = []
    }
}
