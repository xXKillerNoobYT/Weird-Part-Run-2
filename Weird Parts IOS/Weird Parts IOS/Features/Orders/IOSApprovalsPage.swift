import SwiftUI
import WiredPartCore

/// Quick-approval dashboard for managers.
///
/// Aggregates all pending approval types: JPOs, scheduled deletions,
/// and time-off requests. Supports smart card filters by approval type,
/// reject reason requirement, and loading state during actions.
struct IOSApprovalsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var pendingJPOs: [OrdersService.JPOListItem] = []
    @State private var pendingDeletions: [PartsService.ScheduledDeletion] = []
    @State private var pendingTimeOff: [SchedulingService.TimeOffRow] = []
    @State private var pendingToolEdits: [ToolsService.PendingToolEdit] = []

    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var processingId: String?

    // Reject reason
    @State private var rejectReason = ""
    @State private var showRejectAlert = false
    @State private var rejectingJPOId: Int64?

    // Smart card filter
    @State private var activeFilter: ApprovalType?

    private enum ApprovalType: String, CaseIterable {
        case jpo = "JPO Approvals"
        case deletion = "Deletions"
        case timeOff = "Time-Off"
        case toolEdit = "Tool Edits"
    }

    var body: some View {
        VStack(spacing: 0) {
            smartCardFilters
            approvalList
        }
        .navigationTitle("Approvals")
        .searchable(text: $searchText, prompt: "Search pending approvals...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert("Reject JPO?", isPresented: $showRejectAlert) {
            TextField("Reason (required)", text: $rejectReason)
            Button("Cancel", role: .cancel) { rejectReason = "" }
            Button("Reject", role: .destructive) {
                guard !rejectReason.trimmingCharacters(in: .whitespaces).isEmpty else {
                    actionError = "Rejection reason is required."
                    return
                }
                if let id = rejectingJPOId {
                    rejectJPO(id, reason: rejectReason)
                }
                rejectReason = ""
            }
        } message: {
            Text("A reason is required. The requester will be notified.")
        }
    }

    // MARK: - Counts

    private var jpoCount: Int { pendingJPOs.count }
    private var deletionCount: Int { pendingDeletions.count }
    private var timeOffCount: Int { pendingTimeOff.count }
    private var toolEditCount: Int { pendingToolEdits.count }
    private var totalCount: Int { jpoCount + deletionCount + timeOffCount + toolEditCount }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterCard(label: "All", count: totalCount, type: nil,
                           icon: "tray.full", color: .accentColor)
                filterCard(label: "JPOs", count: jpoCount, type: .jpo,
                           icon: "doc.text", color: .blue)
                filterCard(label: "Deletions", count: deletionCount, type: .deletion,
                           icon: "trash", color: .orange)
                filterCard(label: "Time-Off", count: timeOffCount, type: .timeOff,
                           icon: "calendar.badge.clock", color: .purple)
                filterCard(label: "Tool Edits", count: toolEditCount, type: .toolEdit,
                           icon: "wrench.and.screwdriver", color: .teal)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func filterCard(label: String, count: Int, type: ApprovalType?,
                            icon: String, color: Color) -> some View {
        let isActive = activeFilter == type
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeFilter = isActive ? nil : type
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundStyle(isActive ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? color : color.opacity(0.1))
            )
            .foregroundStyle(isActive ? .white : color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Approval List

    @ViewBuilder
    private var approvalList: some View {
        if isLoading {
            ProgressView("Loading approvals...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredItems.isEmpty {
            EmptyStateView(
                icon: "checkmark.seal",
                title: "No Pending Approvals",
                message: searchText.isEmpty
                    ? "All items have been reviewed."
                    : "No approvals match your search."
            )
        } else {
            List {
                // JPOs section
                if showJPOs && !filteredJPOs.isEmpty {
                    Section {
                        ForEach(filteredJPOs, id: \.id) { jpo in
                            jpoRow(jpo)
                        }
                    } header: {
                        Label("JPO Approvals (\(filteredJPOs.count))", systemImage: "doc.text")
                    }
                }

                // Deletions section
                if showDeletions && !filteredDeletions.isEmpty {
                    Section {
                        ForEach(filteredDeletions, id: \.id) { deletion in
                            deletionRow(deletion)
                        }
                    } header: {
                        Label("Scheduled Deletions (\(filteredDeletions.count))", systemImage: "trash")
                    }
                }

                // Time-Off section
                if showTimeOff && !filteredTimeOff.isEmpty {
                    Section {
                        ForEach(filteredTimeOff, id: \.id) { request in
                            timeOffRow(request)
                        }
                    } header: {
                        Label("Time-Off Requests (\(filteredTimeOff.count))", systemImage: "calendar.badge.clock")
                    }
                }

                // Tool Edits section
                if showToolEdits && !filteredToolEdits.isEmpty {
                    Section {
                        ForEach(filteredToolEdits, id: \.id) { edit in
                            toolEditRow(edit)
                        }
                    } header: {
                        Label("Tool Edit Verifications (\(filteredToolEdits.count))", systemImage: "wrench.and.screwdriver")
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Filter Logic

    private var showJPOs: Bool { activeFilter == nil || activeFilter == .jpo }
    private var showDeletions: Bool { activeFilter == nil || activeFilter == .deletion }
    private var showTimeOff: Bool { activeFilter == nil || activeFilter == .timeOff }
    private var showToolEdits: Bool { activeFilter == nil || activeFilter == .toolEdit }

    /// Combined count of visible items (for empty state check)
    private var filteredItems: [AnyHashable] {
        var items: [AnyHashable] = []
        if showJPOs { items.append(contentsOf: filteredJPOs.map { $0.id }) }
        if showDeletions { items.append(contentsOf: filteredDeletions.map { $0.id }) }
        if showTimeOff { items.append(contentsOf: filteredTimeOff.map { $0.id }) }
        if showToolEdits { items.append(contentsOf: filteredToolEdits.map { $0.id }) }
        return items
    }

    private var filteredJPOs: [OrdersService.JPOListItem] {
        guard !searchText.isEmpty else { return pendingJPOs }
        let query = searchText.lowercased()
        return pendingJPOs.filter {
            $0.jobName.lowercased().contains(query) ||
            $0.requestedByName.lowercased().contains(query)
        }
    }

    private var filteredDeletions: [PartsService.ScheduledDeletion] {
        guard !searchText.isEmpty else { return pendingDeletions }
        let query = searchText.lowercased()
        return pendingDeletions.filter {
            $0.entityName.lowercased().contains(query) ||
            $0.entityType.lowercased().contains(query)
        }
    }

    private var filteredTimeOff: [SchedulingService.TimeOffRow] {
        guard !searchText.isEmpty else { return pendingTimeOff }
        let query = searchText.lowercased()
        return pendingTimeOff.filter {
            $0.userName.lowercased().contains(query) ||
            ($0.reason?.lowercased().contains(query) ?? false)
        }
    }

    private var filteredToolEdits: [ToolsService.PendingToolEdit] {
        guard !searchText.isEmpty else { return pendingToolEdits }
        let query = searchText.lowercased()
        return pendingToolEdits.filter {
            $0.toolName.lowercased().contains(query) ||
            $0.changedByName.lowercased().contains(query) ||
            $0.fieldName.lowercased().contains(query)
        }
    }

    // MARK: - JPO Row

    private func jpoRow(_ jpo: OrdersService.JPOListItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        .lineLimit(1)
                    Text("Requested by \(jpo.requestedByName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    statusBadge("pending", color: .orange)
                    Label("\(jpo.lineCount) lines", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    approveJPO(jpo.id)
                } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(processingId != nil)
                .overlay {
                    if processingId == "jpo-\(jpo.id)" {
                        ProgressView()
                    }
                }

                Button {
                    rejectingJPOId = jpo.id
                    showRejectAlert = true
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(processingId != nil)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Deletion Row

    private func deletionRow(_ deletion: PartsService.ScheduledDeletion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deletion.entityType.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(deletion.entityName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let reason = deletion.reason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    statusBadge("pending", color: .orange)
                    Text("Stock: \(deletion.stockAtSchedule)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button {
                    approveDeletion(deletion.id)
                } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(processingId != nil)
                .overlay {
                    if processingId == "del-\(deletion.id)" {
                        ProgressView()
                    }
                }

                Button {
                    cancelDeletion(deletion.id)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(processingId != nil)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Time-Off Row

    private func timeOffRow(_ request: SchedulingService.TimeOffRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.userName)
                        .fontWeight(.medium)
                    Text(request.startDate == request.endDate
                         ? request.startDate
                         : "\(request.startDate) – \(request.endDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let reason = request.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                statusBadge("pending", color: .purple)
            }

            HStack(spacing: 12) {
                Button {
                    approveTimeOff(request.id)
                } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(processingId != nil)
                .overlay {
                    if processingId == "pto-\(request.id)" {
                        ProgressView()
                    }
                }

                Button {
                    denyTimeOff(request.id)
                } label: {
                    Label("Deny", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(processingId != nil)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Tool Edit Row

    private func toolEditRow(_ edit: ToolsService.PendingToolEdit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(edit.toolName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text("Field: \(edit.fieldName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let oldVal = edit.oldValue {
                        Text("\(oldVal) → \(edit.newValue ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("New value: \(edit.newValue ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("By \(edit.changedByName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge("pending", color: .teal)
            }

            HStack(spacing: 12) {
                Button {
                    approveToolEditAction(edit.id)
                } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(processingId != nil)
                .overlay {
                    if processingId == "tool-\(edit.id)" {
                        ProgressView()
                    }
                }

                Button {
                    rejectToolEditAction(edit.id)
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(processingId != nil)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String, color: Color) -> some View {
        Text(status.capitalized)
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
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - JPO Actions

    private func approveJPO(_ id: Int64) {
        guard let service = appCore.ordersService else {
            actionError = "Orders service not available"
            return
        }
        processingId = "jpo-\(id)"
        do {
            try service.updateJPOStatus(id: id, status: "approved")
            pendingJPOs.removeAll { $0.id == id }
        } catch {
            actionError = error.localizedDescription
        }
        processingId = nil
    }

    private func rejectJPO(_ id: Int64, reason: String) {
        guard let service = appCore.ordersService else {
            actionError = "Orders service not available"
            return
        }
        processingId = "jpo-\(id)"
        do {
            try service.updateJPOStatus(id: id, status: "rejected", reason: reason)
            pendingJPOs.removeAll { $0.id == id }
        } catch {
            actionError = error.localizedDescription
        }
        processingId = nil
    }

    // MARK: - Deletion Actions

    private func approveDeletion(_ id: Int64) {
        guard let service = appCore.partsService else {
            actionError = "Parts service not available"
            return
        }
        processingId = "del-\(id)"
        do {
            try service.approveScheduledDeletion(id: id, approvedBy: appCore.currentUser?.id)
            pendingDeletions.removeAll { $0.id == id }
        } catch {
            actionError = error.localizedDescription
        }
        processingId = nil
    }

    private func cancelDeletion(_ id: Int64) {
        guard let service = appCore.partsService else {
            actionError = "Parts service not available"
            return
        }
        processingId = "del-\(id)"
        do {
            try service.cancelScheduledDeletion(id: id)
            pendingDeletions.removeAll { $0.id == id }
        } catch {
            actionError = error.localizedDescription
        }
        processingId = nil
    }

    // MARK: - Time-Off Actions

    private func approveTimeOff(_ id: Int64) {
        guard let service = appCore.schedulingService else {
            actionError = "Scheduling service not available"
            return
        }
        processingId = "pto-\(id)"
        do {
            try service.updateTimeOffStatus(id: id, status: "approved", approvedBy: appCore.currentUser?.id)
            pendingTimeOff.removeAll { $0.id == id }
        } catch {
            actionError = error.localizedDescription
        }
        processingId = nil
    }

    private func denyTimeOff(_ id: Int64) {
        guard let service = appCore.schedulingService else {
            actionError = "Scheduling service not available"
            return
        }
        processingId = "pto-\(id)"
        do {
            try service.updateTimeOffStatus(id: id, status: "denied", approvedBy: appCore.currentUser?.id)
            pendingTimeOff.removeAll { $0.id == id }
        } catch {
            actionError = error.localizedDescription
        }
        processingId = nil
    }

    // MARK: - Tool Edit Actions

    private func approveToolEditAction(_ editId: Int64) {
        guard let service = appCore.toolsService else {
            actionError = "Tools service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            actionError = "Not logged in"
            return
        }
        processingId = "tool-\(editId)"
        do {
            try service.approveToolEdit(editId: editId, approverId: userId)
            pendingToolEdits.removeAll { $0.id == editId }
        } catch {
            actionError = error.localizedDescription
        }
        processingId = nil
    }

    private func rejectToolEditAction(_ editId: Int64) {
        guard let service = appCore.toolsService else {
            actionError = "Tools service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            actionError = "Not logged in"
            return
        }
        processingId = "tool-\(editId)"
        do {
            try service.rejectToolEdit(editId: editId, rejectedBy: userId)
            pendingToolEdits.removeAll { $0.id == editId }
        } catch {
            actionError = error.localizedDescription
        }
        processingId = nil
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoading = pendingJPOs.isEmpty && pendingDeletions.isEmpty && pendingTimeOff.isEmpty && pendingToolEdits.isEmpty
        loadError = nil

        // Load JPOs
        if let ordersService = appCore.ordersService {
            do {
                pendingJPOs = try ordersService.listJPOs(status: "pending")
            } catch {
                loadError = error.localizedDescription
            }
        }

        // Load scheduled deletions
        if let partsService = appCore.partsService {
            do {
                pendingDeletions = try partsService.listScheduledDeletions(status: "pending_approval")
            } catch {
                if loadError == nil { loadError = error.localizedDescription }
            }
        }

        // Load time-off requests
        if let schedulingService = appCore.schedulingService {
            do {
                pendingTimeOff = try schedulingService.listTimeOffRequests(status: "pending")
            } catch {
                if loadError == nil { loadError = error.localizedDescription }
            }
        }

        // Load pending tool edit verifications
        if let toolsService = appCore.toolsService {
            do {
                pendingToolEdits = try toolsService.listPendingToolEdits()
            } catch {
                if loadError == nil { loadError = error.localizedDescription }
            }
        }

        isLoading = false
    }
}
