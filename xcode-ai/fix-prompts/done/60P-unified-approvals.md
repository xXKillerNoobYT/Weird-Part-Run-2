# 60P — Unified Approvals Page

> **Chain position:** Standalone
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

Approvals are currently scattered across separate pages: JPO approvals in Orders, deletion approvals in Office, tool edit verifications in Tools, warranty classifications in Jobs. Create a single `IOSUnifiedApprovalsPage` that queries ALL approval types and shows them in one consolidated list sorted by age.

**Read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSDeletionApprovalsPage.swift` — see existing deletion approvals pattern
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/OrdersRouter.swift` — see `"orders-approvals"` routing to `IOSApprovalsPage`
- `Weird Parts IOS/Weird Parts IOS/App/AppCore.swift` — see available services: `ordersService`, `partsService`, `toolsService`, `jobsService`, `schedulingService`

## Task

### Step 1: Create the unified approval model

At the top of the new page file (or in a shared location), define:

```swift
enum ApprovalType: String, CaseIterable, Identifiable {
    case jpo = "Job Orders"
    case deletion = "Deletions"
    case toolEdit = "Tool Edits"
    case warranty = "Warranty"
    case timeOff = "Time Off"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .jpo: "doc.badge.clock"
        case .deletion: "trash.circle"
        case .toolEdit: "wrench.and.screwdriver"
        case .warranty: "shield.checkered"
        case .timeOff: "moon.fill"
        }
    }

    var color: Color {
        switch self {
        case .jpo: .blue
        case .deletion: .red
        case .toolEdit: .orange
        case .warranty: .purple
        case .timeOff: .green
        }
    }
}

struct ApprovalItem: Identifiable {
    let id: String           // "jpo_123", "deletion_45", etc.
    let entityId: Int64
    let type: ApprovalType
    let title: String
    let subtitle: String
    let requestedBy: String
    let requestedAt: Date
    let urgency: String      // "urgent", "normal", "low"
}
```

### Step 2: Create IOSUnifiedApprovalsPage

Create `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSUnifiedApprovalsPage.swift`:

```swift
struct IOSUnifiedApprovalsPage: View {
    @EnvironmentObject var appCore: AppCore
    @State private var items: [ApprovalItem] = []
    @State private var filterType: ApprovalType? = nil
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String {
            switch self {
            case .help: "help"
            }
        }
    }

    var filteredItems: [ApprovalItem] {
        guard let filter = filterType else { return items }
        return items.filter { $0.type == filter }
    }

    var body: some View {
        List {
            // Smart cards section — one card per type showing count
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        smartCard(type: nil, label: "All", count: items.count, color: .primary)
                        ForEach(ApprovalType.allCases) { type in
                            let count = items.filter { $0.type == type }.count
                            if count > 0 {
                                smartCard(type: type, label: type.rawValue, count: count, color: type.color)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Approval items sorted oldest first
            if filteredItems.isEmpty {
                // Use EmptyStateView
            } else {
                ForEach(filteredItems) { item in
                    approvalRow(item)
                }
            }
        }
        .navigationTitle("Approvals")
        .refreshable { await loadAllApprovals() }
        .task { await loadAllApprovals() }
    }
}
```

### Step 3: Load approvals from ALL sources

In the `loadAllApprovals()` method, query each service:

```swift
private func loadAllApprovals() async {
    isLoading = true
    defer { isLoading = false }

    var allItems: [ApprovalItem] = []

    // 1. JPO approvals — pending JPOs awaiting office approval
    if let ordersService = appCore.ordersService {
        do {
            let pendingJPOs = try ordersService.listJPOs(status: "pending_approval")
            for jpo in pendingJPOs {
                allItems.append(ApprovalItem(
                    id: "jpo_\(jpo.id)",
                    entityId: jpo.id,
                    type: .jpo,
                    title: "JPO #\(jpo.id)",
                    subtitle: jpo.jobName ?? "No job",
                    requestedBy: jpo.createdByName ?? "Unknown",
                    requestedAt: /* parse jpo.createdAt */,
                    urgency: "normal"
                ))
            }
        } catch {
            // Log but don't fail — show what we can
        }
    }

    // 2. Deletion approvals — parts/items pending deletion approval
    if let partsService = appCore.partsService {
        do {
            let pendingDeletions = try partsService.listPendingDeletions()
            // Map to ApprovalItem with type: .deletion
        } catch { }
    }

    // 3. Tool edit verifications
    if let toolsService = appCore.toolsService {
        do {
            // Query tools with pending_verification status
            // Map to ApprovalItem with type: .toolEdit
        } catch { }
    }

    // 4. Warranty classifications
    if let jobsService = appCore.jobsService {
        do {
            // Query jobs with pending warranty classification
            // Map to ApprovalItem with type: .warranty
        } catch { }
    }

    // 5. Time-off requests
    if let schedulingService = appCore.schedulingService {
        do {
            let pendingTimeOff = try schedulingService.listTimeOffRequests(status: "pending")
            // Map to ApprovalItem with type: .timeOff
        } catch { }
    }

    // Sort by age — oldest first
    items = allItems.sorted { $0.requestedAt < $1.requestedAt }
}
```

**IMPORTANT:** Read each service file to find the actual method names. The method names above (like `listJPOs(status:)`, `listPendingDeletions()`) are approximate. Look up the real methods. If a method doesn't exist, query the database directly using the service's db connection pattern, or skip that approval type and leave a `// TODO:` comment.

### Step 4: Wire into OfficeRouter

In the `OfficeRouter` (or wherever the office module routes), update the approvals tab to use `IOSUnifiedApprovalsPage` instead of the current split page:

Find the case that handles `"office-approvals"` and change it to:
```swift
case "office-approvals": IOSUnifiedApprovalsPage()
```

Also update `OrdersRouter` so `"orders-approvals"` points to the same unified page:
```swift
case "orders-approvals": IOSUnifiedApprovalsPage()
```

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSUnifiedApprovalsPage.swift` — CREATE new file
- `Weird Parts IOS/Weird Parts IOS/Features/Office/OfficeRouter.swift` (or wherever office routes live) — update approvals routing
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/OrdersRouter.swift` — update orders-approvals to unified page

## Success Criteria

- [ ] IOSUnifiedApprovalsPage queries at least 3 different services for approval items
- [ ] Smart cards at top show counts per approval type
- [ ] Tapping a smart card filters to that type
- [ ] Items sorted by age (oldest first)
- [ ] Each item shows type icon, title, subtitle, requester, and age
- [ ] Both OfficeRouter and OrdersRouter route to IOSUnifiedApprovalsPage
- [ ] Uses ActiveSheet pattern, EmptyStateView, .refreshable
- [ ] No force unwraps, no empty catch blocks
- [ ] Builds without errors
