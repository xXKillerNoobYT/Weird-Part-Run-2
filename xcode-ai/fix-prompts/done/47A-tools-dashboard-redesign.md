# 47A — Tools Dashboard Redesign

> **Chain position:** **47A** → 47B → 47C → 47D → 47E → 47F
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read `IOSToolsDashboardPage.swift` and `ToolsService.swift`. Redesign the dashboard with smart cards, QR-first quick actions, recent checkouts, and maintenance due sections.

## Context

The tools dashboard needs smart stat cards showing fleet-wide tool health at a glance, QR-first quick actions (scan a tool to immediately checkout/return/report), and two activity sections — recent checkouts and upcoming maintenance. This is the landing page for the Tools module, so it must be fast and action-oriented.

## Task

### Step 1: Smart Cards

```swift
@State private var stats: ToolsDashboardStats?
@State private var loadError: String?
@State private var isLoading = true

struct ToolsDashboardStats: Sendable {
    let totalTools: Int
    let checkedOut: Int
    let maintenanceDue: Int
    let missingParts: Int  // kits with missing components
}

// Smart cards row
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 12) {
        SmartCard(title: "Total Tools", count: stats?.totalTools ?? 0,
                  icon: "wrench.and.screwdriver.fill", color: .blue)
        SmartCard(title: "Checked Out", count: stats?.checkedOut ?? 0,
                  icon: "person.fill.checkmark", color: .orange)
        SmartCard(title: "Maintenance Due", count: stats?.maintenanceDue ?? 0,
                  icon: "exclamationmark.triangle.fill", color: .red)
        SmartCard(title: "Missing Parts", count: stats?.missingParts ?? 0,
                  icon: "xmark.circle.fill", color: .purple)
    }
    .padding(.horizontal)
}
```

### Step 2: Add Service Methods

```swift
// MARK: - Dashboard Stats

func getToolsDashboardStats() async throws -> ToolsDashboardStats {
    try await db.read { db in
        let totalTools = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM tools WHERE status != 'retired'
            """) ?? 0

        let checkedOut = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM tool_checkouts
            WHERE returned_at IS NULL
            """) ?? 0

        let maintenanceDue = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM tools
            WHERE next_maintenance_date <= date('now', '+7 days')
            AND status != 'retired'
            """) ?? 0

        let missingParts = try Int.fetchOne(db, sql: """
            SELECT COUNT(DISTINCT kit_id) FROM kit_items ki
            JOIN tools t ON ki.tool_id = t.id
            WHERE t.status = 'missing' OR t.status = 'lost'
            """) ?? 0

        return ToolsDashboardStats(
            totalTools: totalTools,
            checkedOut: checkedOut,
            maintenanceDue: maintenanceDue,
            missingParts: missingParts
        )
    }
}

func getRecentCheckouts(limit: Int = 10) async throws -> [ToolCheckoutInfo] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT tc.id, tc.tool_id, t.name as tool_name, t.serial_number,
                   tc.checked_out_by, u.first_name || ' ' || u.last_name as user_name,
                   tc.checked_out_at, tc.expected_return_date,
                   tc.condition_at_checkout
            FROM tool_checkouts tc
            JOIN tools t ON tc.tool_id = t.id
            JOIN users u ON tc.checked_out_by = u.id
            WHERE tc.returned_at IS NULL
            ORDER BY tc.checked_out_at DESC
            LIMIT ?
            """, arguments: [limit])
        .map { row in
            ToolCheckoutInfo(
                id: row["id"],
                toolId: row["tool_id"],
                toolName: row["tool_name"],
                serialNumber: row["serial_number"],
                userId: row["checked_out_by"],
                userName: row["user_name"],
                checkedOutAt: row["checked_out_at"],
                expectedReturnDate: row["expected_return_date"],
                conditionAtCheckout: row["condition_at_checkout"]
            )
        }
    }
}

func getMaintenanceDueTools(limit: Int = 10) async throws -> [ToolMaintenanceInfo] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT t.id, t.name, t.serial_number, t.next_maintenance_date,
                   t.maintenance_type, t.status,
                   julianday(t.next_maintenance_date) - julianday('now') as days_until
            FROM tools t
            WHERE t.next_maintenance_date IS NOT NULL
            AND t.status != 'retired'
            ORDER BY t.next_maintenance_date ASC
            LIMIT ?
            """, arguments: [limit])
        .map { row in
            ToolMaintenanceInfo(
                id: row["id"],
                name: row["name"],
                serialNumber: row["serial_number"],
                nextMaintenanceDate: row["next_maintenance_date"],
                maintenanceType: row["maintenance_type"],
                status: row["status"],
                daysUntil: row["days_until"]
            )
        }
    }
}
```

### Step 3: Quick Actions (QR-First)

```swift
enum ActiveSheet: Identifiable {
    case qrCheckout
    case qrReturn
    case qrReportIssue
    case manualCheckout
    case manualReturn

    var id: String { String(describing: self) }
}

@State private var activeSheet: ActiveSheet?

// Quick Actions section
Section {
    HStack(spacing: 12) {
        QuickActionButton(
            title: "Checkout",
            icon: "qrcode.viewfinder",
            color: .blue
        ) {
            activeSheet = .qrCheckout
        }

        QuickActionButton(
            title: "Return",
            icon: "qrcode.viewfinder",
            color: .green
        ) {
            activeSheet = .qrReturn
        }

        QuickActionButton(
            title: "Report Issue",
            icon: "exclamationmark.bubble.fill",
            color: .red
        ) {
            activeSheet = .qrReportIssue
        }
    }
} header: {
    Text("Quick Actions")
}

// QR scan sheets — camera opens first, fallback to manual ID entry
.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .qrCheckout:
        QRScanSheet(title: "Scan Tool to Checkout") { toolId in
            activeSheet = nil
            // navigate to checkout flow with scanned tool
            handleCheckout(toolId: toolId)
        } onManualEntry: {
            activeSheet = .manualCheckout
        }
    case .qrReturn:
        QRScanSheet(title: "Scan Tool to Return") { toolId in
            activeSheet = nil
            handleReturn(toolId: toolId)
        } onManualEntry: {
            activeSheet = .manualReturn
        }
    case .qrReportIssue:
        QRScanSheet(title: "Scan Tool to Report Issue") { toolId in
            activeSheet = nil
            handleReportIssue(toolId: toolId)
        }
    case .manualCheckout:
        ToolIdEntrySheet { toolId in
            activeSheet = nil
            handleCheckout(toolId: toolId)
        }
    case .manualReturn:
        ToolIdEntrySheet { toolId in
            activeSheet = nil
            handleReturn(toolId: toolId)
        }
    }
}
```

### Step 4: Recent Checkouts Section

```swift
@State private var recentCheckouts: [ToolCheckoutInfo] = []

Section {
    if recentCheckouts.isEmpty {
        Text("No active checkouts").foregroundStyle(.secondary)
    } else {
        ForEach(recentCheckouts) { checkout in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(checkout.toolName).font(.subheadline).fontWeight(.medium)
                    Text(checkout.userName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(checkout.checkedOutAt, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                    if let returnDate = checkout.expectedReturnDate {
                        let overdue = returnDate < Date()
                        Text(overdue ? "Overdue" : "Due \(returnDate, format: .dateTime.month(.abbreviated).day())")
                            .font(.caption2)
                            .foregroundStyle(overdue ? .red : .secondary)
                    }
                }
            }
        }
    }
} header: {
    HStack {
        Text("Recent Checkouts")
        Spacer()
        Text("\(recentCheckouts.count)").foregroundStyle(.secondary)
    }
}
```

### Step 5: Maintenance Due Section

```swift
@State private var maintenanceDue: [ToolMaintenanceInfo] = []

Section {
    if maintenanceDue.isEmpty {
        Text("No upcoming maintenance").foregroundStyle(.secondary)
    } else {
        ForEach(maintenanceDue) { tool in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name).font(.subheadline).fontWeight(.medium)
                    if let serial = tool.serialNumber {
                        Text("S/N: \(serial)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    let days = Int(tool.daysUntil ?? 0)
                    if days < 0 {
                        Text("Overdue \(abs(days))d")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.red)
                    } else if days == 0 {
                        Text("Due Today")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.orange)
                    } else {
                        Text("In \(days)d")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let type = tool.maintenanceType {
                        Text(type.capitalized)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
} header: {
    HStack {
        Text("Maintenance Due")
        Spacer()
        Text("\(maintenanceDue.count)").foregroundStyle(.secondary)
    }
}
```

### Step 6: Load Data

```swift
func loadData() async {
    isLoading = true
    loadError = nil
    guard let service = appCore.toolsService else {
        loadError = "Tools service not available"
        isLoading = false
        return
    }
    do {
        stats = try await service.getToolsDashboardStats()
        recentCheckouts = try await service.getRecentCheckouts()
        maintenanceDue = try await service.getMaintenanceDueTools()
    } catch {
        loadError = error.localizedDescription
    }
    isLoading = false
}
```

## Important Notes
- Smart cards are horizontally scrollable — do NOT wrap them
- QR scan opens the camera FIRST — manual ID entry is a fallback button inside the scan sheet
- Maintenance "due" means within the next 7 days
- Overdue items show in red, today in orange, future in gray
- Recent checkouts show the 10 most recent active (unreturned) checkouts
- All data loads in a single loadData() call on .task

## Success Criteria
- [ ] 4 smart cards: Total Tools, Checked Out, Maintenance Due, Missing Parts
- [ ] Quick actions with QR-first pattern (camera → manual fallback)
- [ ] Recent checkouts section with overdue indicators
- [ ] Maintenance due section with days-until countdown
- [ ] Service methods for dashboard stats, checkouts, maintenance
- [ ] All errors show in UI (loadError state)
- [ ] ActiveSheet enum for all sheets
- [ ] No GRDB imports in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 47A Results (YYYY-MM-DD)
- Smart cards: 4 KPI stats
- Quick actions: QR-first checkout/return/report
- Recent checkouts + maintenance due sections
- Service: 3 new dashboard methods
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 47B.**
