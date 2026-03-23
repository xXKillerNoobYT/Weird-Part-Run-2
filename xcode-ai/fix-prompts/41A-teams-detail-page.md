# 41A — Teams Detail Page

> **Chain position:** **41A** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. All navigation uses NavigationLink with value-based navigation

## Instructions

**IMPORTANT:** Before implementing, read `IOSTeamsPage.swift` and `PeopleService.swift` to understand the current team data model and list page. Then create a full detail page with member management and enhance the list page with smart cards.

## Context

The Teams page currently shows a flat list with no detail view. Teams are a key organizing concept — workers are assigned to teams, teams are assigned to jobs. Managers need to see who's on each team, what they're working on, and when they last worked. The list page needs smart cards for quick filtering.

## Task

### Step 1: Create IOSTeamDetailPage.swift

Create `Weird Parts IOS/Weird Parts IOS/Features/People/IOSTeamDetailPage.swift`:

```swift
import SwiftUI

struct IOSTeamDetailPage: View {
    let teamId: Int64
    @EnvironmentObject var appCore: AppCore

    @State private var team: Team?
    @State private var members: [TeamMemberInfo] = []
    @State private var assignedJobs: [JobSummary] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case editTeam
        case addMember

        var id: String {
            switch self {
            case .editTeam: return "editTeam"
            case .addMember: return "addMember"
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading team...")
            } else if let error = loadError {
                ErrorStateView(message: error, retryAction: { Task { await loadData() } })
            } else if let team = team {
                teamContent(team)
            }
        }
        .navigationTitle(team?.name ?? "Team")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { activeSheet = .addMember } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                    }
                    Button { activeSheet = .editTeam } label: {
                        Label("Edit Team", systemImage: "pencil")
                    }
                    Button(role: .destructive) { /* deleteTeam() */ } label: {
                        Label("Delete Team", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editTeam:
                // Edit team name/description sheet
                EmptyView() // Implement
            case .addMember:
                // Employee picker sheet
                EmptyView() // Implement
            }
        }
        .task { await loadData() }
    }
}
```

**Team Content Sections:**

```swift
func teamContent(_ team: Team) -> some View {
    List {
        // Error banner
        if let error = actionError {
            Section {
                Text(error).foregroundStyle(.red)
            }
        }

        // Team Info
        Section {
            LabeledContent("Name", value: team.name)
            if let description = team.description {
                LabeledContent("Description", value: description)
            }
            LabeledContent("Members", value: "\(members.count)")
        } header: {
            Text("Team Info")
        }

        // Members with roles and last work date
        Section {
            ForEach(members) { member in
                HStack {
                    VStack(alignment: .leading) {
                        Text(member.name).font(.headline)
                        Text(member.role ?? "Member")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let lastWork = member.lastWorkDate {
                        Text(lastWork, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No activity")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await removeMember(member.id) }
                    } label: {
                        Label("Remove", systemImage: "person.badge.minus")
                    }
                }
            }
        } header: {
            Text("Members (\(members.count))")
        }

        // Assigned Jobs
        Section {
            if assignedJobs.isEmpty {
                Text("No active jobs").foregroundStyle(.secondary)
            } else {
                ForEach(assignedJobs) { job in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(job.name).font(.headline)
                            Text(job.status.capitalized)
                                .font(.caption)
                                .foregroundStyle(statusColor(job.status))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Assigned Jobs")
        }
    }
}
```

### Step 2: Add Service Methods

In `PeopleService.swift` or `JobsService.swift`:

```swift
struct TeamMemberInfo: Identifiable, Sendable {
    let id: Int64
    let name: String
    let role: String?
    let lastWorkDate: Date?
}

/// Get team members with their last work date
func getTeamMembersWithActivity(teamId: Int64) async throws -> [TeamMemberInfo]

/// Get jobs assigned to a team
func getTeamJobs(teamId: Int64) async throws -> [JobSummary]

/// Add employee to team
func addTeamMember(teamId: Int64, employeeId: Int64, role: String?) async throws

/// Remove employee from team
func removeTeamMember(teamId: Int64, employeeId: Int64) async throws

/// Update team details
func updateTeam(teamId: Int64, name: String, description: String?) async throws

/// Delete team (soft delete)
func deleteTeam(teamId: Int64) async throws
```

### Step 3: Update IOSTeamsPage.swift

Add smart cards and navigation to detail:

```swift
// Smart cards at top
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 10) {
        SmartCard(title: "All", count: allTeams.count, isActive: filter == .all) {
            filter = .all
        }
        SmartCard(title: "Active", count: activeTeams.count, isActive: filter == .active) {
            filter = .active
        }
        SmartCard(title: "My Teams", count: myTeams.count, isActive: filter == .mine) {
            filter = .mine
        }
    }
    .padding(.horizontal)
}

// Team rows with NavigationLink
ForEach(filteredTeams) { team in
    NavigationLink(value: team.id) {
        TeamRow(team: team, memberCount: memberCounts[team.id] ?? 0)
    }
}
.navigationDestination(for: Int64.self) { teamId in
    IOSTeamDetailPage(teamId: teamId)
}
```

### Step 4: Add Edit/Delete with Confirmation

```swift
// Delete confirmation alert
.alert("Delete Team?", isPresented: $showDeleteConfirm) {
    Button("Delete", role: .destructive) {
        Task { await deleteTeam() }
    }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This will remove the team. Members will not be deleted.")
}
```

## Important Notes
- Team deletion is soft delete — members are NOT deleted, just unlinked
- Last work date comes from the most recent clock_entries for that employee
- NavigationLink should use value-based navigation (`.navigationDestination`)
- The team detail page should work with the existing PeopleRouter navigation stack

## Success Criteria
- [ ] IOSTeamDetailPage.swift created with full layout
- [ ] Team members shown with roles and last work dates
- [ ] Assigned jobs shown with status
- [ ] Add/remove member functionality
- [ ] Edit team name/description
- [ ] Delete team with confirmation
- [ ] Smart cards on IOSTeamsPage (All, Active, My Teams)
- [ ] NavigationLink from list to detail page
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 41A Results (YYYY-MM-DD)
- Created IOSTeamDetailPage.swift
- X service methods added
- Smart cards + navigation on IOSTeamsPage
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
