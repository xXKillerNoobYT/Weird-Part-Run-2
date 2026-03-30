# 50A — Office Dashboard

> **Chain position:** **50A** → 50B → 50C → 50D
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read the existing Office router and pages. Build an Office Dashboard with daily briefing, AI summary (cached 1hr, 7AM push notification), "Needs Your Attention" with priority colors, today's schedule, financial snapshot with comparison, and background task status.

## Context

The Office Dashboard is the manager's morning starting point. It answers: "What do I need to know right now?" A cached AI summary of overnight activity refreshes every hour and pushes at 7AM. The "Needs Your Attention" section shows actionable items sorted by urgency — color-coded green (no rush), yellow (4 days), orange (24 hours), red (overdue). Today's schedule, a quick financial snapshot comparing this week vs last, and any background tasks (sync, report generation) round out the view.

## Task

### Step 1: Dashboard Structure

```swift
struct IOSOfficeDashboardPage: View {
    @EnvironmentObject var appCore: AppCore
    @State private var briefing: OfficeBriefing?
    @State private var attentionItems: [AttentionItem] = []
    @State private var todaySchedule: [ScheduleItem] = []
    @State private var financialSnapshot: FinancialSnapshot?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section { ProgressView() }
            } else if let error = loadError {
                Section { Text(error).foregroundStyle(.red) }
            } else {
                aiSummarySection
                attentionSection
                scheduleSection
                if appCore.hasPermission("view_financials") {
                    financialSection
                }
                backgroundTasksSection
            }
        }
        .navigationTitle("Office Dashboard")
        .refreshable { await loadData() }
        .task { await loadData() }
    }
}
```

### Step 2: AI Summary (Cached 1hr)

```swift
struct OfficeBriefing: Sendable {
    let summary: String
    let generatedAt: Date
    let highlights: [String]  // bullet points
    let alertCount: Int
}

var aiSummarySection: some View {
    Section {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                Text("Daily Briefing").font(.headline)
                Spacer()
                if let briefing = briefing {
                    Text(briefing.generatedAt, format: .dateTime.hour().minute())
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if let briefing = briefing {
                Text(briefing.summary)
                    .font(.subheadline).foregroundStyle(.secondary)

                ForEach(briefing.highlights, id: \.self) { highlight in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(.blue).frame(width: 6, height: 6).padding(.top, 5)
                        Text(highlight).font(.caption)
                    }
                }
            } else {
                Text("Generating briefing...")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// Service: cached AI summary
func getOfficeBriefing(userId: Int64) async throws -> OfficeBriefing {
    // Check cache (1hr TTL)
    let cacheKey = "office_briefing_\(userId)"
    if let cached = getCachedBriefing(key: cacheKey),
       Date().timeIntervalSince(cached.generatedAt) < 3600 {
        return cached
    }

    // Generate new briefing from overnight data
    let briefing = try await generateBriefing(userId: userId)
    cacheBriefing(key: cacheKey, briefing: briefing)
    return briefing
}

private func generateBriefing(userId: Int64) async throws -> OfficeBriefing {
    try await db.read { db in
        // Gather overnight activity
        let newJPOs = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM job_part_orders
            WHERE created_at >= datetime('now', '-12 hours')
            """) ?? 0

        let pendingApprovals = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM job_part_orders WHERE status = 'pending_approval'
            """) ?? 0

        let clockedInToday = try Int.fetchOne(db, sql: """
            SELECT COUNT(DISTINCT user_id) FROM clock_entries
            WHERE clock_in >= date('now') AND clock_out IS NULL
            """) ?? 0

        let overdueItems = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM purchase_orders
            WHERE expected_delivery_date < date('now') AND status = 'ordered'
            """) ?? 0

        var highlights: [String] = []
        if newJPOs > 0 { highlights.append("\(newJPOs) new job part orders overnight") }
        if pendingApprovals > 0 { highlights.append("\(pendingApprovals) approvals waiting") }
        if clockedInToday > 0 { highlights.append("\(clockedInToday) workers clocked in") }
        if overdueItems > 0 { highlights.append("\(overdueItems) overdue deliveries") }

        let summary = "Good morning. \(pendingApprovals) items need approval, \(clockedInToday) workers are active, and \(overdueItems > 0 ? "\(overdueItems) deliveries are overdue." : "all deliveries on track.")"

        return OfficeBriefing(
            summary: summary,
            generatedAt: Date(),
            highlights: highlights,
            alertCount: pendingApprovals + overdueItems
        )
    }
}
```

### Step 3: "Needs Your Attention" with Priority Colors

```swift
struct AttentionItem: Identifiable, Sendable {
    let id: Int64
    let title: String
    let subtitle: String
    let itemType: String  // "jpo_approval", "deletion_approval", "time_off", etc.
    let createdAt: Date
    let priority: AttentionPriority
    let actionRoute: String  // navigation destination
}

enum AttentionPriority: Sendable {
    case low       // green — no rush
    case medium    // yellow — within 4 days
    case high      // orange — within 24 hours
    case overdue   // red — past due

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .overdue: return .red
        }
    }

    var icon: String {
        switch self {
        case .low: return "circle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .overdue: return "flame.fill"
        }
    }

    static func from(age: TimeInterval) -> AttentionPriority {
        let days = age / 86400
        if days > 4 { return .overdue }       // red: overdue
        if days > 1 { return .high }          // orange: within 24hr of deadline
        if days > 0 { return .medium }        // yellow: same day
        return .low                            // green: just created
    }
}

var attentionSection: some View {
    Section {
        if attentionItems.isEmpty {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("All caught up!").foregroundStyle(.secondary)
            }
        } else {
            ForEach(attentionItems) { item in
                HStack(spacing: 10) {
                    // Priority indicator
                    Image(systemName: item.priority.icon)
                        .foregroundStyle(item.priority.color)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline)
                        Text(item.subtitle)
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(item.createdAt, format: .relative(presentation: .numeric))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    } header: {
        HStack {
            Text("Needs Your Attention")
            Spacer()
            if !attentionItems.isEmpty {
                Text("\(attentionItems.count)")
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.red)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }
}
```

### Step 4: Today's Schedule

```swift
var scheduleSection: some View {
    Section("Today's Schedule") {
        if todaySchedule.isEmpty {
            Text("Nothing scheduled for today").foregroundStyle(.secondary)
        } else {
            ForEach(todaySchedule) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline)
                        Text(item.jobName ?? "No job").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.time, format: .dateTime.hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

### Step 5: Financial Snapshot (Hat-Gated)

```swift
struct FinancialSnapshot: Sendable {
    let revenueThisWeek: Double
    let revenueLastWeek: Double
    let spendingThisMonth: Double
    let spendingLastMonth: Double
    let outstandingInvoices: Double
}

var financialSection: some View {
    Section("Financial Snapshot") {
        if let snapshot = financialSnapshot {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This Week").font(.caption).foregroundStyle(.secondary)
                    Text("$\(Int(snapshot.revenueThisWeek))")
                        .font(.title3).fontWeight(.semibold)
                    let diff = snapshot.revenueThisWeek - snapshot.revenueLastWeek
                    Text("\(diff >= 0 ? "+" : "")\(Int(diff)) vs last week")
                        .font(.caption2)
                        .foregroundStyle(diff >= 0 ? .green : .red)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("This Month").font(.caption).foregroundStyle(.secondary)
                    Text("$\(Int(snapshot.spendingThisMonth))")
                        .font(.title3).fontWeight(.semibold)
                    let diff = snapshot.spendingThisMonth - snapshot.spendingLastMonth
                    Text("\(diff >= 0 ? "+" : "")\(Int(diff)) vs last month")
                        .font(.caption2)
                        .foregroundStyle(diff <= 0 ? .green : .red)  // spending up = red
                }
            }

            if snapshot.outstandingInvoices > 0 {
                HStack {
                    Image(systemName: "dollarsign.circle.fill").foregroundStyle(.orange)
                    Text("Outstanding: $\(Int(snapshot.outstandingInvoices))")
                        .font(.caption)
                }
            }
        }
    }
}
```

### Step 6: Background Tasks

```swift
var backgroundTasksSection: some View {
    Section("Background") {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.blue)
            Text("Last sync: Never (sync not available)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

### Step 7: Service Method

```swift
func getAttentionItems(userId: Int64) async throws -> [AttentionItem] {
    try await db.read { db in
        var items: [AttentionItem] = []

        // JPO approvals
        let jpos = try Row.fetchAll(db, sql: """
            SELECT jpo.id, jpo.created_at, j.name as job_name,
                   u.first_name || ' ' || u.last_name as requester
            FROM job_part_orders jpo
            JOIN jobs j ON jpo.job_id = j.id
            JOIN users u ON jpo.created_by = u.id
            WHERE jpo.status = 'pending_approval'
            ORDER BY jpo.created_at ASC
            """)
        for row in jpos {
            let age = Date().timeIntervalSince(row["created_at"] as Date)
            items.append(AttentionItem(
                id: row["id"],
                title: "JPO Approval: \(row["job_name"] as String)",
                subtitle: "Requested by \(row["requester"] as String)",
                itemType: "jpo_approval",
                createdAt: row["created_at"],
                priority: .from(age: age),
                actionRoute: "jpo_detail"
            ))
        }

        // Time-off requests
        let timeOff = try Row.fetchAll(db, sql: """
            SELECT tor.id, tor.created_at,
                   u.first_name || ' ' || u.last_name as employee_name,
                   tor.start_date, tor.end_date
            FROM time_off_requests tor
            JOIN users u ON tor.employee_id = u.id
            WHERE tor.status = 'pending'
            ORDER BY tor.created_at ASC
            """)
        for row in timeOff {
            let age = Date().timeIntervalSince(row["created_at"] as Date)
            items.append(AttentionItem(
                id: row["id"],
                title: "Time Off: \(row["employee_name"] as String)",
                subtitle: "\(row["start_date"] as String) - \(row["end_date"] as String)",
                itemType: "time_off",
                createdAt: row["created_at"],
                priority: .from(age: age),
                actionRoute: "time_off_detail"
            ))
        }

        // Sort by priority (overdue first), then by age (oldest first)
        items.sort { a, b in
            if a.priority != b.priority {
                return priorityWeight(a.priority) > priorityWeight(b.priority)
            }
            return a.createdAt < b.createdAt
        }

        return items
    }
}

private func priorityWeight(_ priority: AttentionPriority) -> Int {
    switch priority {
    case .overdue: return 4
    case .high: return 3
    case .medium: return 2
    case .low: return 1
    }
}
```

## Important Notes
- AI briefing is cached for 1 hour — don't regenerate on every visit
- Push notification at 7AM (set up via UNUserNotificationCenter — schedule local notification)
- Priority colors: green (no rush), yellow (4 days), orange (24 hours), red (overdue)
- Financial snapshot only visible with view_financials permission
- "Needs Your Attention" items sorted: overdue first, then by age (oldest first)
- Background tasks section shows sync status (currently placeholder)

## Success Criteria
- [ ] AI daily briefing with highlights (cached 1hr)
- [ ] "Needs Your Attention" with priority colors (green/yellow/orange/red)
- [ ] Attention items sorted by urgency then age
- [ ] Today's schedule section
- [ ] Financial snapshot with week/month comparison (hat-gated)
- [ ] Background tasks section
- [ ] Service: getOfficeBriefing, getAttentionItems, getFinancialSnapshot
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 50A Results (YYYY-MM-DD)
- Office dashboard: AI briefing, attention items, schedule, financials
- Priority colors: 4-level urgency system
- Cached briefing (1hr)
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 50B.**
