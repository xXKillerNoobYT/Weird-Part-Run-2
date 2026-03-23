# 44A — People Dashboard

> **Chain position:** **44A** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `PeopleRouter.swift` and `PeopleService.swift`. Create a new People Dashboard tab showing live workforce status, who's off, expiring certifications, and team assignments.

## Context

The People module currently has list pages but no dashboard overview. Managers need a single view showing: who's working right now (live from clock data), who's off today, certifications expiring soon (safety compliance), and team assignments for today. Smart cards provide quick access to key metrics.

## Task

### Step 1: Create IOSPeopleDashboardPage.swift

Create `Weird Parts IOS/Weird Parts IOS/Features/People/IOSPeopleDashboardPage.swift`:

```swift
import SwiftUI

struct IOSPeopleDashboardPage: View {
    @EnvironmentObject var appCore: AppCore
    @State private var workingNow: [WorkerStatus] = []
    @State private var offToday: [EmployeeSummary] = []
    @State private var expiringCerts: [CertificationAlert] = []
    @State private var teamAssignments: [TeamAssignment] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if let error = loadError {
                ErrorStateView(message: error, retryAction: { Task { await loadData() } })
            } else {
                dashboardContent
            }
        }
        .navigationTitle("People")
        .task { await loadData() }
        .refreshable { await loadData() }
    }

    var dashboardContent: some View {
        List {
            // Smart cards
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        SmartCard(title: "Working Now", count: workingNow.count, color: .green)
                        SmartCard(title: "Off Today", count: offToday.count, color: .orange)
                        SmartCard(title: "Cert. Expiring", count: expiringCerts.count,
                                  color: expiringCerts.isEmpty ? .gray : .red)
                        SmartCard(title: "Teams Active", count: teamAssignments.count, color: .blue)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Working Now (live)
            Section {
                if workingNow.isEmpty {
                    Text("No one clocked in").foregroundStyle(.secondary)
                } else {
                    ForEach(workingNow) { worker in
                        HStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading) {
                                Text(worker.name).font(.headline)
                                Text(worker.jobName ?? "No job")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(worker.elapsedTime)
                                    .font(.caption).monospacedDigit()
                                if let todo = worker.currentTodo {
                                    Text(todo).font(.caption2).foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Working Now")
                    Spacer()
                    Text("\(workingNow.count) people")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Off Today
            Section {
                if offToday.isEmpty {
                    Text("Everyone available").foregroundStyle(.secondary)
                } else {
                    ForEach(offToday) { employee in
                        HStack {
                            Text(employee.name)
                            Spacer()
                            Text(employee.offReason ?? "Time Off")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } header: {
                Text("Off Today")
            }

            // Expiring Certifications
            if !expiringCerts.isEmpty {
                Section {
                    ForEach(expiringCerts) { cert in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(cert.employeeName).font(.headline)
                                Text(cert.certName).font(.caption)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Expires")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(cert.expiryDate, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(cert.daysUntilExpiry < 14 ? .red : .orange)
                            }
                        }
                    }
                } header: {
                    Text("Certifications Expiring Soon")
                }
            }

            // Team Assignments Today
            Section {
                ForEach(teamAssignments) { assignment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(assignment.teamName).font(.headline)
                        Text(assignment.jobName).font(.caption).foregroundStyle(.blue)
                        Text("\(assignment.memberCount) members assigned")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Team Assignments Today")
            }
        }
    }

    func loadData() async {
        guard let service = appCore.peopleService else {
            loadError = "People service unavailable"
            isLoading = false
            return
        }
        do {
            async let workers = service.getWorkersCurrentlyClocked()
            async let off = service.getEmployeesOffToday()
            async let certs = service.getExpiringCertifications(withinDays: 30)
            async let teams = service.getTodaysTeamAssignments()

            workingNow = try await workers
            offToday = try await off
            expiringCerts = try await certs
            teamAssignments = try await teams
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}
```

### Step 2: Service Methods in PeopleService

```swift
struct WorkerStatus: Identifiable, Sendable {
    let id: Int64
    let name: String
    let jobName: String?
    let clockInTime: Date
    let currentTodo: String?
    var elapsedTime: String {
        let elapsed = Date().timeIntervalSince(clockInTime)
        return "\(Int(elapsed) / 3600)h \((Int(elapsed) % 3600) / 60)m"
    }
}

struct EmployeeSummary: Identifiable, Sendable {
    let id: Int64
    let name: String
    let offReason: String?
}

struct CertificationAlert: Identifiable, Sendable {
    let id: Int64
    let employeeName: String
    let certName: String
    let expiryDate: Date
    var daysUntilExpiry: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
    }
}

struct TeamAssignment: Identifiable, Sendable {
    let id: Int64
    let teamName: String
    let jobName: String
    let memberCount: Int
}

func getWorkersCurrentlyClocked() async throws -> [WorkerStatus]
func getEmployeesOffToday() async throws -> [EmployeeSummary]
func getExpiringCertifications(withinDays: Int) async throws -> [CertificationAlert]
func getTodaysTeamAssignments() async throws -> [TeamAssignment]
```

### Step 3: Update PeopleRouter.swift

Add the dashboard as the first tab:

```swift
// Add "Dashboard" as first tab in People module
TabView {
    IOSPeopleDashboardPage()
        .tabItem { Label("Dashboard", systemImage: "person.3") }
    // ... existing tabs
}
```

## Important Notes
- "Working Now" data comes from active clock_entries (no clock_out time)
- "Off Today" comes from time_off_requests for today's date
- Certifications expiring within 30 days — red if <14 days, orange otherwise
- Team assignments come from schedule_entries for today + team_members
- Use `async let` for parallel loading of all 4 data sources
- Dashboard should auto-refresh on appear (`.task` modifier)

## Success Criteria
- [ ] IOSPeopleDashboardPage.swift created
- [ ] Smart cards: Working Now, Off Today, Cert. Expiring, Teams Active
- [ ] Live worker status with job name and elapsed time
- [ ] Off today list with reason
- [ ] Expiring certifications with color-coded urgency
- [ ] Team assignments for today
- [ ] 4 service methods added
- [ ] Added as first tab in PeopleRouter
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 44A Results (YYYY-MM-DD)
- Created IOSPeopleDashboardPage.swift
- PeopleService: 4 dashboard methods
- PeopleRouter: dashboard as first tab
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
