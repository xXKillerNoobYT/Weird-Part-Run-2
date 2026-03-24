# 50B — Unified Approvals Queue

> **Chain position:** 50A → **50B** → 50C
> **Prerequisite:** 50A (attention items model)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read the existing approvals page (IOSApprovalsPage.swift or similar) and relevant services. Build a unified approval queue that combines JPO approvals, deletion approvals, tool edit verifications, warranty classifications, and time-off requests into one page.

## Context

Currently, approvals are scattered: JPOs in one place, deletions in another, tool edits pending verification elsewhere. The unified approvals queue brings everything together. Smart cards at the top show counts by type. Items are sorted by age (oldest first). Each item type has its own inline action buttons. Items remain accessible on their source pages too — this is just a consolidated view.

## Task

### Step 1: Unified Approval Model

```swift
enum ApprovalType: String, CaseIterable, Sendable {
    case jpo = "Job Orders"
    case deletion = "Deletions"
    case toolEdit = "Tool Edits"
    case warranty = "Warranty"
    case timeOff = "Time Off"

    var icon: String {
        switch self {
        case .jpo: return "doc.badge.clock"
        case .deletion: return "trash.circle"
        case .toolEdit: return "wrench.and.screwdriver"
        case .warranty: return "shield.checkered"
        case .timeOff: return "moon.fill"
        }
    }

    var color: Color {
        switch self {
        case .jpo: return .blue
        case .deletion: return .red
        case .toolEdit: return .orange
        case .warranty: return .purple
        case .timeOff: return .green
        }
    }
}

struct ApprovalItem: Identifiable, Sendable {
    let id: String           // "jpo_123", "deletion_45", etc.
    let entityId: Int64
    let type: ApprovalType
    let title: String
    let subtitle: String
    let requestedBy: String
    let requestedAt: Date
    let details: [String: String]  // type-specific details
}
```

### Step 2: Smart Cards by Type

```swift
struct IOSUnifiedApprovalsPage: View {
    @EnvironmentObject var appCore: AppCore
    @State private var items: [ApprovalItem] = []
    @State private var filterType: ApprovalType? = nil
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var actionError: String?

    var body: some View {
        List {
            // Smart cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    SmartCard(title: "All", count: items.count,
                              icon: "tray.full.fill", color: .primary,
                              isActive: filterType == nil) {
                        filterType = nil
                    }
                    ForEach(ApprovalType.allCases, id: \.self) { type in
                        SmartCard(
                            title: type.rawValue,
                            count: items.filter { $0.type == type }.count,
                            icon: type.icon,
                            color: type.color,
                            isActive: filterType == type
                        ) {
                            filterType = filterType == type ? nil : type
                        }
                    }
                }
                .padding(.horizontal)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())

            // Action error banner
            if let error = actionError {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        Text(error).font(.caption)
                        Spacer()
                        Button("Dismiss") { actionError = nil }
                            .font(.caption)
                    }
                }
            }

            // Filtered items
            let filtered = filterType == nil ? items : items.filter { $0.type == filterType }
            if filtered.isEmpty {
                Section {
                    ContentUnavailableView("All Clear",
                        systemImage: "checkmark.circle.fill",
                        description: Text("No pending approvals"))
                }
            } else {
                Section {
                    ForEach(filtered) { item in
                        ApprovalItemRow(item: item,
                                       onApprove: { await handleApprove(item) },
                                       onReject: { reason in await handleReject(item, reason: reason) })
                    }
                } header: {
                    HStack {
                        Text("Pending (\(filtered.count))")
                        Spacer()
                        Text("Oldest first").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Approvals")
        .refreshable { await loadData() }
        .task { await loadData() }
    }
}
```

### Step 3: Approval Item Row with Inline Actions

```swift
struct ApprovalItemRow: View {
    let item: ApprovalItem
    let onApprove: () async -> Void
    let onReject: (String?) async -> Void
    @State private var showRejectReason = false
    @State private var rejectReason = ""
    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: item.type.icon)
                    .foregroundStyle(item.type.color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.subheadline).fontWeight(.medium)
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                Text(item.requestedAt, format: .relative(presentation: .numeric))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // Requested by
            Text("By \(item.requestedBy)")
                .font(.caption2).foregroundStyle(.secondary)

            // Type-specific details
            ForEach(Array(item.details.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                HStack {
                    Text(key).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(value).font(.caption)
                }
            }

            // Action buttons
            if showRejectReason {
                VStack(spacing: 8) {
                    TextField("Reason for rejection", text: $rejectReason)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    HStack {
                        Button("Cancel") {
                            showRejectReason = false
                            rejectReason = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button("Confirm Reject") {
                            isProcessing = true
                            Task {
                                await onReject(rejectReason.isEmpty ? nil : rejectReason)
                                isProcessing = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        .disabled(isProcessing)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        showRejectReason = true
                    } label: {
                        Label("Reject", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)

                    Spacer()

                    Button {
                        isProcessing = true
                        Task {
                            await onApprove()
                            isProcessing = false
                        }
                    } label: {
                        Label("Approve", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isProcessing)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

### Step 4: Service Method

```swift
// MARK: - Unified Approvals

func getUnifiedApprovals() async throws -> [ApprovalItem] {
    try await db.read { db in
        var items: [ApprovalItem] = []

        // JPO approvals
        let jpos = try Row.fetchAll(db, sql: """
            SELECT jpo.id, jpo.created_at, j.name as job_name,
                   u.first_name || ' ' || u.last_name as requester,
                   (SELECT COUNT(*) FROM jpo_line_items WHERE jpo_id = jpo.id) as line_count
            FROM job_part_orders jpo
            JOIN jobs j ON jpo.job_id = j.id
            JOIN users u ON jpo.created_by = u.id
            WHERE jpo.status = 'pending_approval'
            """)
        for row in jpos {
            items.append(ApprovalItem(
                id: "jpo_\(row["id"] as Int64)",
                entityId: row["id"],
                type: .jpo,
                title: row["job_name"],
                subtitle: "\(row["line_count"] as Int) items",
                requestedBy: row["requester"],
                requestedAt: row["created_at"],
                details: ["Items": "\(row["line_count"] as Int)"]
            ))
        }

        // Deletion approvals
        let deletions = try Row.fetchAll(db, sql: """
            SELECT sd.id, sd.created_at, sd.entity_type, sd.entity_name,
                   u.first_name || ' ' || u.last_name as requester
            FROM scheduled_deletions sd
            JOIN users u ON sd.requested_by = u.id
            WHERE sd.status = 'pending_approval'
            """)
        for row in deletions {
            items.append(ApprovalItem(
                id: "deletion_\(row["id"] as Int64)",
                entityId: row["id"],
                type: .deletion,
                title: "Delete: \(row["entity_name"] as String)",
                subtitle: row["entity_type"],
                requestedBy: row["requester"],
                requestedAt: row["created_at"],
                details: ["Type": row["entity_type"]]
            ))
        }

        // Tool edit verifications
        let toolEdits = try Row.fetchAll(db, sql: """
            SELECT pcl.id, pcl.changed_at, pcl.entity_id, pcl.field_name,
                   pcl.new_value, t.name as tool_name,
                   u.first_name || ' ' || u.last_name as editor
            FROM part_change_log pcl
            JOIN tools t ON pcl.entity_id = t.id
            JOIN users u ON pcl.changed_by = u.id
            WHERE pcl.entity_type = 'tool' AND pcl.verification_status = 'pending_verification'
            """)
        for row in toolEdits {
            items.append(ApprovalItem(
                id: "tool_edit_\(row["id"] as Int64)",
                entityId: row["id"],
                type: .toolEdit,
                title: "Edit: \(row["tool_name"] as String)",
                subtitle: "\(row["field_name"] as String) → \(row["new_value"] as String)",
                requestedBy: row["editor"],
                requestedAt: row["changed_at"],
                details: ["Field": row["field_name"], "New Value": row["new_value"]]
            ))
        }

        // Time-off requests
        let timeOff = try Row.fetchAll(db, sql: """
            SELECT tor.id, tor.created_at, tor.start_date, tor.end_date, tor.reason,
                   u.first_name || ' ' || u.last_name as employee
            FROM time_off_requests tor
            JOIN users u ON tor.employee_id = u.id
            WHERE tor.status = 'pending'
            """)
        for row in timeOff {
            items.append(ApprovalItem(
                id: "timeoff_\(row["id"] as Int64)",
                entityId: row["id"],
                type: .timeOff,
                title: "Time Off: \(row["employee"] as String)",
                subtitle: "\(row["start_date"] as String) — \(row["end_date"] as String)",
                requestedBy: row["employee"],
                requestedAt: row["created_at"],
                details: ["Start": row["start_date"], "End": row["end_date"],
                          "Reason": row["reason"] ?? "None"]
            ))
        }

        // Sort by age (oldest first)
        items.sort { $0.requestedAt < $1.requestedAt }
        return items
    }
}
```

### Step 5: Handle Approve/Reject

```swift
func handleApprove(_ item: ApprovalItem) async {
    actionError = nil
    do {
        switch item.type {
        case .jpo:
            try await appCore.ordersService?.approveJPO(jpoId: item.entityId, approvedBy: appCore.currentUserId)
        case .deletion:
            try await appCore.partsService?.approveScheduledDeletion(deletionId: item.entityId, approvedBy: appCore.currentUserId)
        case .toolEdit:
            try await appCore.toolsService?.approveToolEdit(editId: item.entityId, approverId: appCore.currentUserId)
        case .timeOff:
            try await appCore.schedulingService?.approveTimeOff(requestId: item.entityId, approvedBy: appCore.currentUserId)
        case .warranty:
            break // handled separately
        }
        // Refresh list
        await loadData()
    } catch {
        actionError = error.localizedDescription
    }
}

func handleReject(_ item: ApprovalItem, reason: String?) async {
    actionError = nil
    do {
        switch item.type {
        case .jpo:
            try await appCore.ordersService?.rejectJPO(jpoId: item.entityId, rejectedBy: appCore.currentUserId, reason: reason)
        case .deletion:
            try await appCore.partsService?.cancelScheduledDeletion(deletionId: item.entityId)
        case .toolEdit:
            // Reject tool edit — mark as rejected
            break
        case .timeOff:
            try await appCore.schedulingService?.rejectTimeOff(requestId: item.entityId, rejectedBy: appCore.currentUserId, reason: reason)
        case .warranty:
            break
        }
        await loadData()
    } catch {
        actionError = error.localizedDescription
    }
}
```

## Important Notes
- Smart cards act as toggle filters — tap to filter, tap again to show all
- Items sorted by age (oldest first) to encourage timely processing
- Each item type has its own approve/reject logic calling the appropriate service
- Reject requires a reason (text field expands inline, not a separate sheet)
- Items remain accessible on source pages — this is a consolidated view, not the only way to approve
- Action errors show as a banner that can be dismissed

## Success Criteria
- [ ] Unified queue combining 5 approval types
- [ ] Smart cards with counts per type (act as filters)
- [ ] Inline approve/reject buttons per item
- [ ] Reject with reason (inline text field)
- [ ] Sorted by age (oldest first)
- [ ] Service: getUnifiedApprovals
- [ ] Approve/reject handlers calling correct services
- [ ] Action error banner
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 50B Results (YYYY-MM-DD)
- Unified approvals: 5 types in one queue
- Smart card filters, inline actions
- Reject with reason
- Service: unified query across 4+ tables
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 50C.**
