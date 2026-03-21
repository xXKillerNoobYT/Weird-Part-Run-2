# Fix Prompt 12E: Enhanced Daily Report — Command Center

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.
>
> **DEPENDS ON:** Prompt 12A must be completed (routing). Independent of 12C/12D.

---

## What the User Wants

The Daily Report page currently shows: pending actions, today's activity, expected deliveries, and budget alerts. The user wants THREE new sections added, plus a Fast Actions bar at the top.

**New sections:**
1. **My Hours Today** — personal clock status, hours worked, jobs touched, breaks taken
2. **Who's Clocked In** — team-wide view (managers only), all currently clocked-in employees
3. **Fast Actions Bar** — horizontal scroll of quick action buttons at the top

---

## File To Edit

**`Weird Parts IOS/Features/Dashboard/DashboardDailyReportPage.swift`**

### Step 1: Add New State Variables

Add after the existing state declarations:

```swift
// My Hours
@State private var myTodayHours: Double = 0
@State private var myClockInTime: String?
@State private var myCurrentJob: String?
@State private var myBreakMinutes: Int = 0
@State private var myJobBreakdown: [JobTimeEntry] = []

// Team (managers only)
@State private var teamClockedIn: [TeamMemberStatus] = []

// Fast action state
@State private var showReportProblem = false
@State private var showSubmitReport = false

struct JobTimeEntry: Identifiable {
    let id: String
    let jobName: String
    let hours: Double
}

struct TeamMemberStatus: Identifiable {
    let id: Int64
    let displayName: String
    let jobName: String
    let clockInTime: String
    let durationText: String
}
```

### Step 2: Add Fast Actions Bar

Insert at the TOP of the content VStack (before the overdue alert banner, around line 39):

```swift
// Fast Actions Bar
fastActionsBar
    .padding(.horizontal, DS.Space.lg)
```

Create the fast actions view:

```swift
@ViewBuilder
private var fastActionsBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: DS.Space.md) {
            // Lunch
            DSQuickActionButton(title: "Lunch", icon: "fork.knife", color: .green) {
                startLunch()
            }
            // Break
            DSQuickActionButton(title: "Break", icon: "cup.and.saucer.fill", color: .purple) {
                startBreak()
            }
            // Report Problem
            DSQuickActionButton(title: "Problem", icon: "exclamationmark.triangle.fill", color: .red) {
                showReportProblem = true
            }
            // Submit Report
            DSQuickActionButton(title: "Day Report", icon: "doc.text.fill", color: .indigo) {
                showSubmitReport = true
            }
            // Supply Run
            DSQuickActionButton(title: "Supply Run", icon: "truck.box.fill", color: .blue) {
                startSupplyRun()
            }
        }
    }
}

private func startLunch() {
    guard let service = appCore.jobsService,
          let userId = appCore.currentUser?.id else { return }
    do {
        try service.clockOut(userId: userId, latitude: nil, longitude: nil)
        // TODO: Set reminder to clock back in after 30 min
        Task { await loadData() }
    } catch {
        loadError = error.localizedDescription
    }
}

private func startBreak() {
    guard let service = appCore.jobsService,
          let userId = appCore.currentUser?.id else { return }
    do {
        try service.clockOut(userId: userId, latitude: nil, longitude: nil)
        Task { await loadData() }
    } catch {
        loadError = error.localizedDescription
    }
}

private func startSupplyRun() {
    // TODO: Record supply run start event
    // For now, this is a placeholder. Geofencing (12D) handles supply runs automatically.
}
```

### Step 3: Add "My Hours Today" Section

Insert after the overdue alert banner, before pending actions:

```swift
// My Hours Today
myHoursTodayCard
    .padding(.horizontal, DS.Space.lg)
```

```swift
@ViewBuilder
private var myHoursTodayCard: some View {
    VStack(alignment: .leading, spacing: DS.Space.md) {
        HStack {
            Text("My Hours Today")
                .dsStyle(.sectionTitle)
            Spacer()
            Text(String(format: "%.1fh", myTodayHours))
                .dsStyle(.kpiValue)
                .foregroundStyle(.blue)
        }

        // Current status
        HStack(spacing: DS.Space.md) {
            if let clockIn = myClockInTime, let job = myCurrentJob {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clocked in since \(clockIn)")
                        .dsStyle(.detail)
                    Text(job)
                        .dsStyle(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "clock")
                    .foregroundStyle(.gray)
                Text("Not currently clocked in")
                    .dsStyle(.detail)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }

        // Job breakdown
        if !myJobBreakdown.isEmpty {
            Divider()
            VStack(spacing: DS.Space.xs) {
                ForEach(myJobBreakdown) { entry in
                    HStack {
                        Text(entry.jobName)
                            .dsStyle(.detail)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1fh", entry.hours))
                            .dsStyle(.detail)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                }
            }
        }

        if myBreakMinutes > 0 {
            HStack {
                Text("Break time")
                    .dsStyle(.detail)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(myBreakMinutes)m")
                    .dsStyle(.detail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
    .padding(DS.Space.lg)
    .dsCard()
}
```

### Step 4: Add "Who's Clocked In" Section (Managers Only)

Insert after today's activity card:

```swift
// Who's Clocked In (managers only)
if appCore.hasPermission("view_labor") && !teamClockedIn.isEmpty {
    teamClockedInCard
        .padding(.horizontal, DS.Space.lg)
}
```

```swift
@ViewBuilder
private var teamClockedInCard: some View {
    VStack(alignment: .leading, spacing: 0) {
        HStack {
            Text("Who's Clocked In")
                .dsStyle(.sectionTitle)
            Spacer()
            Text("\(teamClockedIn.count)")
                .dsStyle(.label)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, DS.Space.xxxs + 1)
                .background(Capsule().fill(DS.SemanticColor.tint(.green)))
                .foregroundStyle(.green)
        }
        .padding(DS.Space.lg)

        VStack(spacing: DS.Space.sm) {
            ForEach(teamClockedIn) { member in
                HStack(spacing: DS.Space.md) {
                    // Avatar circle with initials
                    Text(String(member.displayName.prefix(1)))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.blue))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName)
                            .dsStyle(.detail)
                            .fontWeight(.medium)
                        Text(member.jobName)
                            .dsStyle(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(member.durationText)
                        .dsStyle(.detail)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, DS.Space.md)
    }
    .dsCard()
}
```

### Step 5: Load the New Data

In the existing `loadData()`, inside the `db.writer.read` closure, add queries for the new sections.

**My Hours Today** (after the existing queries):

```swift
let currentUserId = appCore.currentUser?.id

// My hours today
var myHours: Double = 0
var myClockIn: String?
var myJob: String?
var myBreaks: Int = 0
var jobBreakdown: [JobTimeEntry] = []

if let userId = currentUserId {
    // Total hours today
    myHours = try Double.fetchOne(conn, sql: """
        SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
        FROM labor_entries
        WHERE user_id = ? AND date(clock_in) = date('now') AND deleted_at IS NULL
        """, arguments: [userId]) ?? 0

    // Current active clock-in
    if let activeRow = try Row.fetchOne(conn, sql: """
        SELECT le.clock_in, j.job_name
        FROM labor_entries le
        LEFT JOIN jobs j ON j.id = le.job_id
        WHERE le.user_id = ? AND le.clock_out IS NULL AND le.deleted_at IS NULL
        ORDER BY le.clock_in DESC LIMIT 1
        """, arguments: [userId]) {
        myClockIn = activeRow["clock_in"] as String?
        myJob = activeRow["job_name"] as String?

        // Add active session time to total
        if let clockInStr = myClockIn {
            // Parse and add elapsed time
        }
    }

    // Job breakdown
    let breakdownRows = try Row.fetchAll(conn, sql: """
        SELECT COALESCE(j.job_name, 'Shop / Warehouse') AS job_name,
               SUM(regular_hours + overtime_hours) AS total_hours
        FROM labor_entries le
        LEFT JOIN jobs j ON j.id = le.job_id
        WHERE le.user_id = ? AND date(le.clock_in) = date('now') AND le.deleted_at IS NULL
        GROUP BY le.job_id
        ORDER BY total_hours DESC
        """, arguments: [userId])
    jobBreakdown = breakdownRows.map { row in
        JobTimeEntry(
            id: row["job_name"] ?? "unknown",
            jobName: row["job_name"] ?? "Shop / Warehouse",
            hours: row["total_hours"] ?? 0
        )
    }
}
```

**Who's Clocked In** (team data — load for all users):

```swift
let teamRows = try Row.fetchAll(conn, sql: """
    SELECT u.id, u.display_name,
           COALESCE(j.job_name, 'Shop / Warehouse') AS job_name,
           le.clock_in
    FROM labor_entries le
    JOIN users u ON u.id = le.user_id
    LEFT JOIN jobs j ON j.id = le.job_id
    WHERE le.clock_out IS NULL AND le.deleted_at IS NULL AND u.deleted_at IS NULL
    ORDER BY le.clock_in ASC
    """)
let team = teamRows.map { row in
    let clockIn = row["clock_in"] as String? ?? ""
    // Calculate duration from clock_in to now
    let duration = "—" // Calculate from clockIn timestamp
    return TeamMemberStatus(
        id: row["id"] ?? 0,
        displayName: row["display_name"] ?? "",
        jobName: row["job_name"] ?? "",
        clockInTime: String(clockIn.suffix(8).prefix(5)),
        durationText: duration
    )
}
```

Add these to the `DailyReportData` struct and apply in the `MainActor.run` block.

### Step 6: Add Report Problem Sheet

Add a `.sheet` for the problem report form:

```swift
.sheet(isPresented: $showReportProblem) {
    ReportProblemSheet()
}
.sheet(isPresented: $showSubmitReport) {
    SubmitDailyReportSheet()
}
```

Create minimal forms inside the same file:

```swift
private struct ReportProblemSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedJobId: Int64?
    @State private var description = ""
    @State private var jobs: [Row] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    // Job picker — load active jobs
                    Picker("Job", selection: $selectedJobId) {
                        Text("Select a job").tag(nil as Int64?)
                        // ForEach active jobs
                    }
                }
                Section("Problem Description") {
                    TextField("Describe the problem...", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Report Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        // TODO: Create notebook entry tagged as 'problem'
                        dismiss()
                    }
                    .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private struct SubmitDailyReportSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var accomplishments = ""
    @State private var issues = ""
    @State private var tomorrowNotes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("What was accomplished today?") {
                    TextField("Work completed...", text: $accomplishments, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Issues encountered") {
                    TextField("Any problems or blockers...", text: $issues, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Notes for tomorrow") {
                    TextField("What needs to happen next...", text: $tomorrowNotes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Daily Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        // TODO: Save daily report via JobsService
                        dismiss()
                    }
                    .disabled(accomplishments.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
```

---

## Success Criteria

1. Fast Actions bar shows at top: Lunch, Break, Problem, Day Report, Supply Run
2. "My Hours Today" card shows personal hours, current clock status, job breakdown
3. "Who's Clocked In" section shows team members (managers only — gated by `view_labor` permission)
4. Report Problem sheet opens and has job picker + description
5. Submit Daily Report sheet opens with accomplishments / issues / notes fields
6. Lunch/Break buttons clock the user out
7. Page still auto-refreshes every 60 seconds

---

## When Done

Read and implement **prompt 12F-fast-qr-scanner.md** next.
