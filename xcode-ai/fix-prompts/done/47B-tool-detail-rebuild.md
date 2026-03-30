# 47B — Tool Detail Rebuild

> **Chain position:** 47A → **47B** → 47C
> **Prerequisite:** 47A (dashboard service methods)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read the existing tool detail page and `ToolsService.swift`. Rebuild with full contents checklist, mandatory condition check on checkout/return, 2-year version history, and edit-without-permission pattern.

## Context

Tool detail needs to show everything about a tool: its contents (for kits — tools + consumables with quantity bars), checkout/return with REQUIRED condition checking (not optional — you MUST record condition), a 2-year version history showing who changed what, and an edit pattern where any user can edit but edits from users without the right hat go into a "pending verification" state that a manager must QR-scan-approve.

## Task

### Step 1: Contents Checklist (for Kits)

```swift
@State private var kitContents: [KitContentItem] = []

struct KitContentItem: Identifiable, Sendable {
    let id: Int64
    let name: String
    let itemType: String  // "tool" or "consumable"
    let requiredQty: Int
    let currentQty: Int
    let status: String    // "present", "missing", "damaged", "low"
    let lastChecked: Date?
}

// Contents checklist section (only for kits)
if tool.isKit {
    Section {
        ForEach(kitContents) { item in
            HStack {
                // Status icon
                Image(systemName: statusIcon(item.status))
                    .foregroundStyle(statusColor(item.status))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.subheadline)
                    Text(item.itemType.capitalized)
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Spacer()

                // Quantity bar for consumables
                if item.itemType == "consumable" {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(item.currentQty)/\(item.requiredQty)")
                            .font(.caption).monospacedDigit()
                        ProgressView(value: Double(item.currentQty),
                                     total: Double(max(item.requiredQty, 1)))
                            .tint(item.currentQty < item.requiredQty ? .orange : .green)
                            .frame(width: 60)
                    }
                } else {
                    // Tool: present/missing badge
                    Text(item.status.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(statusColor(item.status).opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    } header: {
        HStack {
            Text("Contents")
            Spacer()
            let missing = kitContents.filter { $0.status == "missing" }.count
            if missing > 0 {
                Text("\(missing) missing").font(.caption).foregroundStyle(.red)
            }
        }
    }
}
```

### Step 2: Checkout/Return with REQUIRED Condition Check

```swift
enum ActiveSheet: Identifiable {
    case checkout
    case returnTool
    case reportIssue
    case editTool
    case versionHistory
    case pendingVerification(editId: Int64)

    var id: String { String(describing: self) }
}

// Checkout sheet — condition is REQUIRED
struct ToolCheckoutSheet: View {
    let tool: ToolDetail
    let onComplete: () -> Void
    @EnvironmentObject var appCore: AppCore
    @State private var condition: ToolCondition = .good
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    enum ToolCondition: String, CaseIterable {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case damaged = "Damaged"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tool.name).font(.headline)
                    if let serial = tool.serialNumber {
                        Text("S/N: \(serial)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                // REQUIRED condition check
                Section {
                    Picker("Condition", selection: $condition) {
                        ForEach(ToolCondition.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Condition Check (Required)")
                } footer: {
                    Text("You must record the tool's condition before checkout.")
                }

                if let error = saveError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Checkout Tool")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Checkout") {
                        Task { await performCheckout() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    func performCheckout() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        do {
            try await service.checkoutTool(
                toolId: tool.id,
                userId: appCore.currentUserId,
                condition: condition.rawValue,
                notes: notes.isEmpty ? nil : notes
            )
            onComplete()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

// Return sheet — also requires condition check
struct ToolReturnSheet: View {
    let tool: ToolDetail
    let onComplete: () -> Void
    @EnvironmentObject var appCore: AppCore
    @State private var condition: ToolCheckoutSheet.ToolCondition = .good
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tool.name).font(.headline)
                }

                Section {
                    Picker("Return Condition", selection: $condition) {
                        ForEach(ToolCheckoutSheet.ToolCondition.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Return notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Return Condition Check (Required)")
                }

                // Show condition change warning
                if condition.rawValue != tool.lastKnownCondition {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Condition changed from \(tool.lastKnownCondition ?? "Unknown") to \(condition.rawValue)")
                                .font(.caption)
                        }
                    }
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Return Tool")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Return") {
                        Task { await performReturn() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    func performReturn() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        do {
            try await service.returnTool(
                toolId: tool.id,
                userId: appCore.currentUserId,
                condition: condition.rawValue,
                notes: notes.isEmpty ? nil : notes
            )
            onComplete()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
```

### Step 3: Version History (2 Years)

```swift
// Service method
func getToolVersionHistory(toolId: Int64, months: Int = 24) async throws -> [ToolChangeRecord] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT pcl.id, pcl.changed_by, pcl.field_name, pcl.old_value, pcl.new_value,
                   pcl.changed_at, pcl.change_type,
                   u.first_name || ' ' || u.last_name as changed_by_name
            FROM part_change_log pcl
            LEFT JOIN users u ON pcl.changed_by = u.id
            WHERE pcl.entity_type = 'tool' AND pcl.entity_id = ?
            AND pcl.changed_at >= date('now', '-' || ? || ' months')
            ORDER BY pcl.changed_at DESC
            """, arguments: [toolId, months])
        .map { row in
            ToolChangeRecord(
                id: row["id"],
                changedBy: row["changed_by"],
                changedByName: row["changed_by_name"],
                fieldName: row["field_name"],
                oldValue: row["old_value"],
                newValue: row["new_value"],
                changedAt: row["changed_at"],
                changeType: row["change_type"]
            )
        }
    }
}

// UI
Section {
    ForEach(versionHistory.prefix(5)) { record in
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(record.changedByName ?? "Unknown")
                    .font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(record.changedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text("\(record.fieldName): \(record.oldValue ?? "—") → \(record.newValue ?? "—")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    if versionHistory.count > 5 {
        Button("View All History (\(versionHistory.count))") {
            activeSheet = .versionHistory
        }
    }
} header: {
    Text("Recent Changes")
}
```

### Step 4: Edit-Without-Permission Pattern

```swift
// Service: save edit with verification status
func editToolWithVerification(
    toolId: Int64, userId: Int64, changes: [String: String],
    hasPermission: Bool
) async throws -> ToolEditResult {
    let status = hasPermission ? "approved" : "pending_verification"

    return try await db.write { db in
        // Apply changes
        for (field, value) in changes {
            // Log change
            try db.execute(sql: """
                INSERT INTO part_change_log
                (entity_type, entity_id, field_name, old_value, new_value,
                 changed_by, changed_at, change_type, verification_status)
                VALUES ('tool', ?, ?, (SELECT \(field) FROM tools WHERE id = ?), ?,
                        ?, datetime('now'), 'edit', ?)
                """, arguments: [toolId, field, toolId, value, userId, status])

            if hasPermission {
                // Direct update
                try db.execute(sql: """
                    UPDATE tools SET \(field) = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [value, toolId])
            }
        }

        return ToolEditResult(
            status: status,
            requiresVerification: !hasPermission
        )
    }
}

// Verification approval (manager scans QR)
func approveToolEdit(editId: Int64, approverId: Int64) async throws {
    try await db.write { db in
        let row = try Row.fetchOne(db, sql: """
            SELECT entity_id, field_name, new_value FROM part_change_log
            WHERE id = ? AND verification_status = 'pending_verification'
            """, arguments: [editId])

        guard let row = row else {
            throw ToolsServiceError.editNotFound
        }

        let toolId: Int64 = row["entity_id"]
        let field: String = row["field_name"]
        let value: String = row["new_value"]

        // Apply the edit
        try db.execute(sql: """
            UPDATE tools SET \(field) = ?, updated_at = datetime('now')
            WHERE id = ?
            """, arguments: [value, toolId])

        // Mark as approved
        try db.execute(sql: """
            UPDATE part_change_log SET verification_status = 'approved',
            verified_by = ?, verified_at = datetime('now')
            WHERE id = ?
            """, arguments: [approverId, editId])
    }
}

// UI: edit button with verification feedback
Button {
    Task { await saveEdit() }
} label: {
    Text(hasManagePermission ? "Save" : "Submit for Verification")
}

// After save:
if result.requiresVerification {
    // Show banner
    Text("Edit submitted. A manager must scan this tool's QR code to approve.")
        .font(.caption).foregroundStyle(.orange)
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
}
```

## Important Notes
- Condition check is REQUIRED on both checkout AND return — no skip button
- Condition options: Excellent, Good, Fair, Poor, Damaged (5 levels)
- Version history defaults to 2 years of changes
- Edit-without-permission: ANY user can edit, but without manage_tools hat the edit is "pending_verification"
- Manager approves by scanning the tool's QR code (physical presence required)
- Kit contents show quantity bars for consumables and present/missing badges for tools
- Condition change on return triggers a visual warning

## Success Criteria
- [ ] Kit contents checklist with qty bars (consumables) and status badges (tools)
- [ ] Checkout with REQUIRED condition check (5 levels)
- [ ] Return with REQUIRED condition check + condition change warning
- [ ] 2-year version history with who-changed-what
- [ ] Edit-without-permission pattern (any user edits, pending if no hat)
- [ ] Manager QR-scan approval for pending edits
- [ ] ActiveSheet enum for all sheets
- [ ] Service methods for history, edit verification, approval
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 47B Results (YYYY-MM-DD)
- Contents checklist: tools + consumables with qty bars
- Checkout/return: REQUIRED condition check
- Version history: 2 years
- Edit-without-permission: pending verification pattern
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 47C.**
