import SwiftUI
import WiredPartCore

/// Unified approval dashboard for managers.
///
/// Aggregates JPO approvals, scheduled deletions, time-off requests, tool edit
/// verifications, warranty classifications, and flex/schedule approvals into one
/// oldest-first queue.
struct IOSUnifiedApprovalsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var pendingJPOs: [OrdersService.JPOListItem] = []
    @State private var pendingDeletions: [PartsService.ScheduledDeletion] = []
    @State private var pendingTimeOff: [SchedulingService.TimeOffRow] = []
    @State private var pendingToolEdits: [ToolsService.PendingToolEdit] = []
    @State private var pendingWarranty: [NotebooksService.PendingWarrantyClassification] = []
    @State private var pendingScheduleChanges: [SchedulingService.ScheduleChangeApproval] = []

    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var processingId: String?

    @State private var rejectReason = ""
    @State private var showRejectAlert = false
    @State private var rejectingJPOId: Int64?

    @State private var activeFilter: ApprovalType?
    @State private var activeSheet: ActiveSheet?

    init(initialFilter: String? = nil) {
        _activeFilter = State(initialValue: ApprovalType(deepLinkFilter: initialFilter))
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private enum ApprovalType: String, CaseIterable {
        case jpo
        case deletion
        case timeOff
        case toolEdit
        case warranty
        case schedule

        init?(deepLinkFilter: String?) {
            guard let deepLinkFilter else { return nil }
            switch deepLinkFilter.lowercased() {
            case "jpo", "jpos", "orders": self = .jpo
            case "deletion", "deletions": self = .deletion
            case "time-off", "timeoff", "pto": self = .timeOff
            case "tool", "tool-edit", "tool-edits": self = .toolEdit
            case "warranty", "classification": self = .warranty
            case "schedule", "schedule-change", "dispatch", "flex": self = .schedule
            default: return nil
            }
        }

        var label: String {
            switch self {
            case .jpo: return "JPOs"
            case .deletion: return "Deletions"
            case .timeOff: return "Time-Off"
            case .toolEdit: return "Tool Edits"
            case .warranty: return "Warranty"
            case .schedule: return "Schedule"
            }
        }

        var icon: String {
            switch self {
            case .jpo: return "doc.text"
            case .deletion: return "trash"
            case .timeOff: return "calendar.badge.clock"
            case .toolEdit: return "wrench.and.screwdriver"
            case .warranty: return "shield.checkered"
            case .schedule: return "person.badge.clock"
            }
        }

        var color: Color {
            switch self {
            case .jpo: return .blue
            case .deletion: return .orange
            case .timeOff: return .purple
            case .toolEdit: return .teal
            case .warranty: return .indigo
            case .schedule: return .pink
            }
        }
    }

    private enum ApprovalQueueItem: Identifiable {
        case jpo(OrdersService.JPOListItem)
        case deletion(PartsService.ScheduledDeletion)
        case timeOff(SchedulingService.TimeOffRow)
        case toolEdit(ToolsService.PendingToolEdit)
        case warranty(NotebooksService.PendingWarrantyClassification)
        case schedule(SchedulingService.ScheduleChangeApproval)

        var id: String {
            switch self {
            case .jpo(let item): return "jpo-\(item.id)"
            case .deletion(let item): return "deletion-\(item.id)"
            case .timeOff(let item): return "timeoff-\(item.id)"
            case .toolEdit(let item): return "tool-\(item.id)"
            case .warranty(let item): return "warranty-\(item.id)"
            case .schedule(let item): return "schedule-\(item.id)"
            }
        }

        var type: ApprovalType {
            switch self {
            case .jpo: return .jpo
            case .deletion: return .deletion
            case .timeOff: return .timeOff
            case .toolEdit: return .toolEdit
            case .warranty: return .warranty
            case .schedule: return .schedule
            }
        }

        var createdAt: String {
            switch self {
            case .jpo(let item): return item.createdAt ?? ""
            case .deletion(let item): return item.createdAt
            case .timeOff(let item): return item.startDate
            case .toolEdit(let item): return item.changedAt
            case .warranty(let item): return item.createdAt
            case .schedule(let item): return item.createdAt
            }
        }

        func matches(_ query: String) -> Bool {
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            switch self {
            case .jpo(let item):
                return item.jobName.lowercased().contains(q)
                    || item.requestedByName.lowercased().contains(q)
            case .deletion(let item):
                return item.entityName.lowercased().contains(q)
                    || item.entityType.lowercased().contains(q)
                    || (item.reason?.lowercased().contains(q) ?? false)
            case .timeOff(let item):
                return item.userName.lowercased().contains(q)
                    || item.startDate.lowercased().contains(q)
                    || item.endDate.lowercased().contains(q)
                    || (item.reason?.lowercased().contains(q) ?? false)
            case .toolEdit(let item):
                return item.toolName.lowercased().contains(q)
                    || item.changedByName.lowercased().contains(q)
                    || item.fieldName.lowercased().contains(q)
            case .warranty(let item):
                return item.entryTitle.lowercased().contains(q)
                    || item.entryContent.lowercased().contains(q)
                    || item.jobName.lowercased().contains(q)
                    || item.requestedByName.lowercased().contains(q)
                    || item.requestedClassification.lowercased().contains(q)
            case .schedule(let item):
                return item.jobName.lowercased().contains(q)
                    || item.userName.lowercased().contains(q)
                    || item.dispatchDate.lowercased().contains(q)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "office-approvals")
            smartCardFilters
            approvalList
        }
        .navigationTitle("Approvals")
        .searchable(text: $searchText, prompt: "Search pending approvals...")
        .refreshable { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Approvals Help",
                sections: [
                    ("What This Page Does", "Shows every item waiting for manager approval in one oldest-first queue: JPOs, scheduled deletions, time-off, tool edit verifications, warranty classifications, and schedule changes."),
                    ("How to Use It", "Use the filter cards to narrow by approval type without clearing search. Each row exposes the approval actions for that item."),
                    ("Tips", "Pull down to refresh. Items disappear from this page once approved or rejected.")
                ]
            )
        }
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("approvals-view")
        }
        .onAppear { postPageContext() }

        .onDisappear {
            NotificationCenter.default.post(name: .officeApprovalsPageInactive, object: nil)
        }
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
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

    private var allItems: [ApprovalQueueItem] {
        pendingJPOs.map(ApprovalQueueItem.jpo)
            + pendingDeletions.map(ApprovalQueueItem.deletion)
            + pendingTimeOff.map(ApprovalQueueItem.timeOff)
            + pendingToolEdits.map(ApprovalQueueItem.toolEdit)
            + pendingWarranty.map(ApprovalQueueItem.warranty)
            + pendingScheduleChanges.map(ApprovalQueueItem.schedule)
    }

    private var filteredItems: [ApprovalQueueItem] {
        allItems
            .filter { activeFilter == nil || $0.type == activeFilter }
            .filter { $0.matches(searchText) }
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.id < $1.id }
                return $0.createdAt < $1.createdAt
            }
    }

    private var totalCount: Int { allItems.count }

    private var approvalsPageContext: String {
        let pendingSummary = ApprovalType.allCases
            .map { "\($0.label): \(count(for: $0))" }
            .joined(separator: ", ")
        let selectedFilter = activeFilter?.label ?? "All"
        let searchState = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none" : "active"
        return """
        page=Office Approvals; total_pending=\(totalCount); visible_pending=\(filteredItems.count); selected_filter=\(selectedFilter); search=\(searchState); pending_by_type=[\(pendingSummary)]
        """
    }

    private func count(for type: ApprovalType) -> Int {
        switch type {
        case .jpo: return pendingJPOs.count
        case .deletion: return pendingDeletions.count
        case .timeOff: return pendingTimeOff.count
        case .toolEdit: return pendingToolEdits.count
        case .warranty: return pendingWarranty.count
        case .schedule: return pendingScheduleChanges.count
        }
    }

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterCard(label: "All", count: totalCount, type: nil, icon: "tray.full", color: .accentColor)
                ForEach(ApprovalType.allCases, id: \.self) { type in
                    filterCard(label: type.label, count: count(for: type), type: type, icon: type.icon, color: type.color)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func filterCard(label: String, count: Int, type: ApprovalType?, icon: String, color: Color) -> some View {
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
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? color : color.opacity(0.1))
            )
            .foregroundStyle(isActive ? .white : color)
        }
        .buttonStyle(.plain)
    }

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
                message: searchText.isEmpty ? "All items have been reviewed." : "No approvals match your search."
            )
        } else {
            List(filteredItems) { item in
                approvalRow(item)
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func approvalRow(_ item: ApprovalQueueItem) -> some View {
        switch item {
        case .jpo(let jpo): jpoRow(jpo)
        case .deletion(let deletion): deletionRow(deletion)
        case .timeOff(let request): timeOffRow(request)
        case .toolEdit(let edit): toolEditRow(edit)
        case .warranty(let warranty): warrantyRow(warranty)
        case .schedule(let schedule): scheduleRow(schedule)
        }
    }

    private func rowHeader(type: ApprovalType, title: String, subtitle: String, status: String = "pending") -> some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .foregroundStyle(type.color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(type.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            statusBadge(status, color: type.color)
            ActionDot(isOverdue: false)
        }
    }

    private func jpoRow(_ jpo: OrdersService.JPOListItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            rowHeader(
                type: .jpo,
                title: jpo.jobName,
                subtitle: "JPO #\(jpo.id) by \(jpo.requestedByName) - \(jpo.lineCount) lines"
            )
            HStack(spacing: 12) {
                actionButton("Approve", icon: "checkmark.circle.fill", color: .green, processingKey: "jpo-\(jpo.id)") {
                    approveJPO(jpo.id)
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
                .actionRing(.red)
                .disabled(processingId != nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func deletionRow(_ deletion: PartsService.ScheduledDeletion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            rowHeader(
                type: .deletion,
                title: deletion.entityName,
                subtitle: "\(deletion.entityType.capitalized) - stock \(deletion.stockAtSchedule)"
            )
            if let reason = deletion.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                actionButton("Approve", icon: "checkmark.circle.fill", color: .green, processingKey: "del-\(deletion.id)") {
                    approveDeletion(deletion.id)
                }
                actionButton("Reject", icon: "xmark.circle.fill", color: .red, processingKey: "del-\(deletion.id)") {
                    cancelDeletion(deletion.id)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func timeOffRow(_ request: SchedulingService.TimeOffRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            rowHeader(
                type: .timeOff,
                title: request.userName,
                subtitle: request.startDate == request.endDate ? request.startDate : "\(request.startDate) to \(request.endDate)"
            )
            if let reason = request.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                actionButton("Approve", icon: "checkmark.circle.fill", color: .green, processingKey: "pto-\(request.id)") {
                    approveTimeOff(request.id)
                }
                actionButton("Deny", icon: "xmark.circle.fill", color: .red, processingKey: "pto-\(request.id)") {
                    denyTimeOff(request.id)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func toolEditRow(_ edit: ToolsService.PendingToolEdit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            rowHeader(
                type: .toolEdit,
                title: edit.toolName,
                subtitle: "\(edit.fieldName) by \(edit.changedByName)"
            )
            Text((edit.oldValue ?? "Empty") + " -> " + (edit.newValue ?? "Empty"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                actionButton("Approve", icon: "checkmark.circle.fill", color: .green, processingKey: "tool-\(edit.id)") {
                    approveToolEditAction(edit.id)
                }
                actionButton("Reject", icon: "xmark.circle.fill", color: .red, processingKey: "tool-\(edit.id)") {
                    rejectToolEditAction(edit.id)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func warrantyRow(_ item: NotebooksService.PendingWarrantyClassification) -> some View {
        let alternate = item.requestedClassification == "warranty" ? "regular" : "warranty"
        return VStack(alignment: .leading, spacing: 8) {
            rowHeader(
                type: .warranty,
                title: item.entryTitle.isEmpty ? item.entryContent : item.entryTitle,
                subtitle: "\(item.jobName) - \(item.requestedClassification.capitalized) by \(item.requestedByName)"
            )
            HStack(spacing: 12) {
                actionButton("Approve", icon: "checkmark.circle.fill", color: .green, processingKey: "war-\(item.id)") {
                    approveWarrantyClassification(item.id)
                }
                actionButton("Reclassify", icon: "arrow.triangle.2.circlepath", color: .red, processingKey: "war-\(item.id)") {
                    reclassifyWarranty(item.id, as: alternate)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func scheduleRow(_ item: SchedulingService.ScheduleChangeApproval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            rowHeader(
                type: .schedule,
                title: item.jobName,
                subtitle: "\(item.userName) requested \(item.dispatchDate) (\(item.timeSlot))"
            )
            HStack(spacing: 12) {
                actionButton("Approve", icon: "checkmark.circle.fill", color: .green, processingKey: "sch-\(item.id)") {
                    approveScheduleChange(item.id)
                }
                actionButton("Reject", icon: "xmark.circle.fill", color: .red, processingKey: "sch-\(item.id)") {
                    rejectScheduleChange(item.id)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func actionButton(_ title: String, icon: String, color: Color, processingKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .actionRing(color)
        .disabled(processingId != nil)
        .overlay {
            if processingId == processingKey {
                ProgressView()
            }
        }
    }

    private func statusBadge(_ status: String, color: Color) -> some View {
        Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

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
            actionError = userFriendlyError(error, context: "process approval")
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
            actionError = userFriendlyError(error, context: "process approval")
        }
        processingId = nil
    }

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
            actionError = userFriendlyError(error, context: "process approval")
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
            actionError = userFriendlyError(error, context: "process approval")
        }
        processingId = nil
    }

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
            actionError = userFriendlyError(error, context: "process approval")
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
            actionError = userFriendlyError(error, context: "process approval")
        }
        processingId = nil
    }

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
            actionError = userFriendlyError(error, context: "process approval")
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
            actionError = userFriendlyError(error, context: "process approval")
        }
        processingId = nil
    }

    private func approveWarrantyClassification(_ entryId: Int64) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            actionError = "Not logged in"
            return
        }
        processingId = "war-\(entryId)"
        do {
            try service.reviewClassification(entryId: entryId, reviewedBy: userId, approved: true, newClassification: nil)
            pendingWarranty.removeAll { $0.id == entryId }
        } catch {
            actionError = userFriendlyError(error, context: "process approval")
        }
        processingId = nil
    }

    private func reclassifyWarranty(_ entryId: Int64, as newClassification: String) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            actionError = "Not logged in"
            return
        }
        processingId = "war-\(entryId)"
        do {
            try service.reviewClassification(entryId: entryId, reviewedBy: userId, approved: false, newClassification: newClassification)
            pendingWarranty.removeAll { $0.id == entryId }
        } catch {
            actionError = userFriendlyError(error, context: "process approval")
        }
        processingId = nil
    }

    private func approveScheduleChange(_ dispatchId: Int64) {
        guard let service = appCore.schedulingService else {
            actionError = "Scheduling service not available"
            return
        }
        processingId = "sch-\(dispatchId)"
        do {
            try service.approveScheduleChange(dispatchId: dispatchId, approvedBy: appCore.currentUser?.id)
            pendingScheduleChanges.removeAll { $0.id == dispatchId }
        } catch {
            actionError = userFriendlyError(error, context: "process approval")
        }
        processingId = nil
    }

    private func rejectScheduleChange(_ dispatchId: Int64) {
        guard let service = appCore.schedulingService else {
            actionError = "Scheduling service not available"
            return
        }
        processingId = "sch-\(dispatchId)"
        do {
            try service.rejectScheduleChange(dispatchId: dispatchId, rejectedBy: appCore.currentUser?.id)
            pendingScheduleChanges.removeAll { $0.id == dispatchId }
        } catch {
            actionError = userFriendlyError(error, context: "process approval")
        }
        processingId = nil
    }

    private func loadData() {
        isLoading = allItems.isEmpty
        loadError = nil

        if let ordersService = appCore.ordersService {
            do {
                pendingJPOs = try ordersService.listJPOs(status: "pending")
            } catch {
                loadError = userFriendlyError(error, context: "load approvals")
            }
        }

        if let partsService = appCore.partsService {
            do {
                pendingDeletions = try partsService.listScheduledDeletions(status: "pending_approval")
            } catch {
                if loadError == nil { loadError = userFriendlyError(error, context: "load approvals") }
            }
        }

        if let schedulingService = appCore.schedulingService {
            do {
                pendingTimeOff = try schedulingService.listTimeOffRequests(status: "pending")
                pendingScheduleChanges = try schedulingService.listPendingScheduleChangeApprovals()
            } catch {
                if loadError == nil { loadError = userFriendlyError(error, context: "load approvals") }
            }
        }

        if let toolsService = appCore.toolsService {
            do {
                pendingToolEdits = try toolsService.listPendingToolEdits()
            } catch {
                if loadError == nil { loadError = userFriendlyError(error, context: "load approvals") }
            }
        }

        if let notebooksService = appCore.notebooksService {
            do {
                pendingWarranty = try notebooksService.listPendingWarrantyClassifications()
            } catch {
                if loadError == nil { loadError = userFriendlyError(error, context: "load approvals") }
            }
        }

        isLoading = false
        postPageContext()
    }

    private func postPageContext() {
        let filterLabel = activeFilter?.label ?? "All"
        NotificationCenter.default.post(
            name: .officeApprovalsPageActive,
            object: nil,
            userInfo: [
                "context": "Office Approvals: \(totalCount) pending, \(filteredItems.count) visible, filter: \(filterLabel), search active: \(!searchText.isEmpty)."
            ]
        )
    }
}
