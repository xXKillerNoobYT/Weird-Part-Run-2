import SwiftUI
import WiredPartCore

/// Job Purchase Orders list page for iOS.
///
/// Displays a searchable list of JPOs with job name, requester,
/// status badge, priority badge, and line count. Supports pull-to-refresh,
/// status-based filtering with count badges, QR scanning, and Create JPO
/// with auto-fill from the user's current clock-in.
struct IOSJPOsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var allJPOs: [OrdersService.JPOListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private let statusOptions = ["all", "draft", "pending", "submitted", "approved", "rejected"]

    private enum ActiveSheet: Identifiable {
        case createJPO
        case qrScanner
        case scannedJPODetail(Int64)

        var id: String {
            switch self {
            case .createJPO: "createJPO"
            case .qrScanner: "qrScanner"
            case .scannedJPODetail(let id): "scannedJPO-\(id)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            statusPicker

            // Pending KPI line
            if pendingCount > 0 {
                HStack {
                    Label("\(pendingCount) pending approval", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            jpoList
        }
        .navigationTitle("Job Purchase Orders")
        .searchable(text: $searchText, prompt: "Search JPOs...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { activeSheet = .qrScanner } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                Button { activeSheet = .createJPO } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .task { loadData() }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .createJPO:
            CreateJPOSheet(onSave: { loadData() })
                .environmentObject(appCore)
        case .qrScanner:
            QRScanSheet(expectedType: .po) { result in
                if result.entityId != nil, result.isFound {
                    // PO scanned — show JPO detail for the linked JPO
                    // For now, dismiss and reload; a future prompt can wire PO→JPO navigation
                    activeSheet = nil
                }
            }
            .environmentObject(appCore)
        case .scannedJPODetail(let jpoId):
            NavigationStack {
                IOSJPODetailPage(jpoId: jpoId)
                    .environmentObject(appCore)
            }
        }
    }

    // MARK: - Counts

    private var pendingCount: Int {
        allJPOs.filter { $0.status == "pending" }.count
    }

    private func countForStatus(_ status: String) -> Int {
        if status == "all" { return allJPOs.count }
        return allJPOs.filter { $0.status == status }.count
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    Button {
                        statusFilter = status
                    } label: {
                        Text("\(status == "all" ? "All" : status.capitalized) (\(countForStatus(status)))")
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

    // MARK: - JPO List

    @ViewBuilder
    private var jpoList: some View {
        if isLoading {
            ProgressView("Loading JPOs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if displayedJPOs.isEmpty {
            EmptyStateView(
                icon: "doc.text",
                title: "No JPOs",
                message: searchText.isEmpty ? "No job purchase orders yet." : "No JPOs match your criteria."
            )
        } else {
            List(displayedJPOs, id: \.id) { jpo in
                NavigationLink {
                    IOSJPODetailPage(jpoId: jpo.id)
                        .environmentObject(appCore)
                } label: {
                    jpoRow(jpo)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// JPOs filtered by status and search text.
    private var displayedJPOs: [OrdersService.JPOListItem] {
        var result = allJPOs
        // Status filter
        if statusFilter != "all" {
            result = result.filter { $0.status == statusFilter }
        }
        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.jobName.lowercased().contains(query) ||
                $0.requestedByName.lowercased().contains(query)
            }
        }
        return result
    }

    private func jpoRow(_ jpo: OrdersService.JPOListItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("JPO #\(jpo.id)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    priorityBadge(jpo.priority)
                }
                Text(jpo.jobName)
                    .fontWeight(.medium)
                Text("Requested by \(jpo.requestedByName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(jpo.status)
                Label("\(jpo.lineCount) lines", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if jpo.holdCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "message.badge")
                            .foregroundStyle(.yellow)
                        Text("\(jpo.holdCount) question\(jpo.holdCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("JPO number \(jpo.id), \(jpo.jobName), status \(jpo.status), \(jpo.lineCount) line items, \(jpo.holdCount) on hold")
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "draft": .secondary
        case "pending", "submitted": .orange
        case "approved": .green
        case "rejected": .red
        default: .secondary
        }
        return Text(status.capitalized)
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

    private func loadData() {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
        isLoading = allJPOs.isEmpty
        loadError = nil
        do {
            // Load all JPOs for counts, then filter in-memory
            allJPOs = try service.listJPOs(status: nil, limit: 500)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Create JPO Sheet

private struct CreateJPOSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void

    @State private var selectedJobId: Int64?
    @State private var priority = "normal"
    @State private var notes = ""
    @State private var jobs: [JobsService.JobListItem] = []
    @State private var errorMessage: String?
    @State private var clockedInJobId: Int64?
    @State private var clockedInJobName: String?

    var body: some View {
        NavigationStack {
            Form {
                // Job selection
                Section("Job") {
                    if let clockedJob = clockedInJobName, selectedJobId == clockedInJobId {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(clockedJob)
                                    .fontWeight(.medium)
                                Text("Clocked in")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Button("Change") {
                                selectedJobId = nil
                                clockedInJobName = nil
                            }
                            .font(.caption)
                        }
                    } else {
                        Picker("Select Job", selection: $selectedJobId) {
                            Text("Select a job...").tag(nil as Int64?)
                            ForEach(jobs, id: \.id) { job in
                                Text(job.jobName).tag(job.id as Int64?)
                            }
                        }
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("Normal").tag("normal")
                        Text("High").tag("high")
                        Text("Urgent").tag("urgent")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New JPO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createJPO() }
                        .disabled(selectedJobId == nil)
                }
            }
            .task { await loadJobContext() }
        }
    }

    private func loadJobContext() async {
        guard let jobsService = appCore.jobsService else {
            errorMessage = "Jobs service not available"
            return
        }
        // Load active jobs
        do {
            jobs = try jobsService.listJobs(status: "active", limit: 100)
        } catch {
            errorMessage = error.localizedDescription
        }

        // Check if user is clocked in
        guard let userId = appCore.currentUser?.id else {
            // User not logged in
            return
        }
        do {
            if let activeEntry = try jobsService.getActiveClockEntry(userId: userId) {
                clockedInJobId = activeEntry.jobId
                clockedInJobName = activeEntry.jobName
                selectedJobId = activeEntry.jobId
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createJPO() {
        guard let service = appCore.ordersService else {
            errorMessage = "Orders service not available"
            return
        }
        guard let jobId = selectedJobId else {
            errorMessage = "Please select a job"
            return
        }
        let userId = appCore.currentUser?.id ?? 0
        do {
            _ = try service.createJPO(
                jobId: jobId,
                requestedBy: userId,
                priority: priority,
                notes: notes.isEmpty ? nil : notes
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
