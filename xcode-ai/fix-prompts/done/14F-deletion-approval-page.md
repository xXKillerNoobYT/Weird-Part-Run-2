# Prompt 14F — Deletion Approval Page in Office

> Read `xcode-ai/xcode.md` first for project conventions.

## Goal

Add a "Deletion Approvals" section to the Office area where scheduled deletions that have completed their 30-day drain period can be approved or rejected. This integrates with the `scheduled_deletions` table created in Prompt 14E.

## Files to Modify / Create

1. `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSDeletionApprovalsPage.swift` — **NEW FILE**
2. `Weird Parts IOS/Weird Parts IOS/Features/Office/OfficeRouter.swift` — add route
3. `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` — add tab config

## Step 1: Create the Deletion Approvals Page

**Create new file:** `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSDeletionApprovalsPage.swift`

```swift
import SwiftUI
import WiredPartCore

/// Office page for reviewing and approving scheduled part/category deletions.
///
/// Shows items in "pending_approval" status (stock reached 0, 30-day timer expired)
/// and "draining" status (still has stock, waiting to reach 0).
struct IOSDeletionApprovalsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var pendingApprovals: [PartsService.ScheduledDeletion] = []
    @State private var drainingItems: [PartsService.ScheduledDeletion] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var processingId: Int64?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading deletion queue...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else if pendingApprovals.isEmpty && drainingItems.isEmpty {
                ContentUnavailableView {
                    Label("No Pending Deletions", systemImage: "checkmark.seal")
                } description: {
                    Text("All deletion requests have been processed.")
                }
            } else {
                deletionList
            }
        }
        .navigationTitle("Deletion Approvals")
        .refreshable { await loadData() }
        .task { await loadData() }
    }

    // MARK: - List

    @ViewBuilder
    private var deletionList: some View {
        List {
            // Pending Approval section (ready to delete)
            if !pendingApprovals.isEmpty {
                Section {
                    ForEach(pendingApprovals) { item in
                        approvalRow(item)
                    }
                } header: {
                    Label("Ready for Approval (\(pendingApprovals.count))", systemImage: "clock.badge.checkmark")
                } footer: {
                    Text("These items have had zero stock for 30+ days.")
                }
            }

            // Draining section (still has stock)
            if !drainingItems.isEmpty {
                Section {
                    ForEach(drainingItems) { item in
                        drainingRow(item)
                    }
                } header: {
                    Label("Draining — Empty Shelf Mode (\(drainingItems.count))", systemImage: "arrow.down.to.line")
                } footer: {
                    Text("Stock targets set to 0. Once stock reaches 0, a 30-day timer will start.")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Approval Row (ready to delete)

    private func approvalRow(_ item: PartsService.ScheduledDeletion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.entityType.capitalized)
                            .font(.system(.caption2, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                        Text(item.entityName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    if let reason = item.reason {
                        Text("Reason: \(reason)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let deleteAfter = item.deleteAfter {
                        Text("Timer expired: \(deleteAfter)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // Alternative part recommendation
            if let altName = item.alternativePartName {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Replacement: **\(altName)**")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    Task { await approve(item) }
                } label: {
                    Label("Approve Delete", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(processingId == item.id)

                Button {
                    Task { await cancel(item) }
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
                .disabled(processingId == item.id)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Draining Row (still has stock)

    private func drainingRow(_ item: PartsService.ScheduledDeletion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(item.entityType.capitalized)
                    .font(.system(.caption2, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                    .foregroundStyle(.blue)
                Text(item.entityName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("Started with \(item.stockAtSchedule)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let altName = item.alternativePartName {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Switch to: \(altName)")
                        .font(.caption)
                }
            }

            // Cancel button only (can't approve while still draining)
            Button {
                Task { await cancel(item) }
            } label: {
                Label("Cancel Empty Shelf Mode", systemImage: "arrow.uturn.backward")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(processingId == item.id)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func approve(_ item: PartsService.ScheduledDeletion) async {
        guard let service = appCore.partsService else { return }
        processingId = item.id
        do {
            try service.approveScheduledDeletion(id: item.id, approvedBy: nil)
            pendingApprovals.removeAll { $0.id == item.id }
        } catch {
            loadError = error.localizedDescription
        }
        processingId = nil
    }

    private func cancel(_ item: PartsService.ScheduledDeletion) async {
        guard let service = appCore.partsService else { return }
        processingId = item.id
        do {
            try service.cancelScheduledDeletion(id: item.id)
            pendingApprovals.removeAll { $0.id == item.id }
            drainingItems.removeAll { $0.id == item.id }
        } catch {
            loadError = error.localizedDescription
        }
        processingId = nil
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        do {
            pendingApprovals = try service.listScheduledDeletions(status: "pending_approval")
            drainingItems = try service.listScheduledDeletions(status: "draining")
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
```

## Step 2: Add Route to Office Router

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Office/OfficeRouter.swift`

Add a new case in the `switch tabId` block, under the "Operations" section:

```swift
case "office-deletion-approvals":
    IOSDeletionApprovalsPage()
```

## Step 3: Add Tab to Navigation Config

**File:** `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift`

Find where Office tabs are defined and add a new entry. Look for the array of tab configs for the Office section and add:

```swift
// Under Operations section, after existing entries:
TabConfig(id: "office-deletion-approvals", label: "Deletion Approvals", icon: "trash.circle", section: "Operations")
```

Use whatever pattern the existing tab configs follow — match the struct name, ordering, and section grouping.

## Success Criteria

- [ ] Build succeeds with no errors
- [ ] "Deletion Approvals" tab appears in Office section
- [ ] Page shows "Ready for Approval" items (pending_approval status) with Approve/Cancel buttons
- [ ] Page shows "Draining" items (still has stock) with Cancel button only
- [ ] Approve performs the soft delete and removes from list
- [ ] Cancel restores parts (removes deprecation) and removes from list
- [ ] Alternative part names shown where available
- [ ] Empty state when no pending deletions
- [ ] Pull-to-refresh works

## Next

When all criteria are met, read and implement `xcode-ai/fix-prompts/14G-categories-help-guidance.md`.
