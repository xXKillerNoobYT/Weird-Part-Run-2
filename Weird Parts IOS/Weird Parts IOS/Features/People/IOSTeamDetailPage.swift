import SwiftUI
import WiredPartCore

/// Detail page for a single team — shows members, assigned jobs, and edit/delete actions.
struct IOSTeamDetailPage: View {
    let teamId: Int64
    @EnvironmentObject var appCore: AppCore

    @State private var team: PeopleService.TeamDetail?
    @State private var members: [PeopleService.TeamMemberDetail] = []
    @State private var assignedJobs: [PeopleService.TeamJobSummary] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var showDeleteConfirm = false

    private enum ActiveSheet: Identifiable {
        case editTeam
        case addMember
        case help

        var id: String {
            switch self {
            case .editTeam: return "editTeam"
            case .addMember: return "addMember"
            case .help: return "help"
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
            } else {
                ContentUnavailableView("Team Not Found", systemImage: "person.3.fill",
                                       description: Text("This team may have been deleted."))
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
                    Divider()
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete Team", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editTeam:
                if let team {
                    EditTeamSheet(
                        teamId: team.id,
                        currentName: team.name,
                        currentDescription: team.description
                    ) {
                        Task { await loadData() }
                    }
                    .environmentObject(appCore)
                }
            case .addMember:
                AddMemberSheet(teamId: teamId) {
                    Task { await loadData() }
                }
                .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Team Detail Help",
                    sections: [
                        ("Members", "View all team members with their roles and last work date. Swipe left on a member to remove them from the team."),
                        ("Assigned Jobs", "Shows active jobs that team members are working on."),
                        ("Edit Team", "Change the team name or description from the menu button."),
                        ("Delete Team", "Deleting a team removes it from the list but does NOT delete team members' accounts.")
                    ]
                )
            }
        }
        .alert("Delete Team?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await deleteTeam() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the team. Members will not be deleted.")
        }
        .task { await loadData() }
        .refreshable { await loadData() }
    }

    // MARK: - Content

    private func teamContent(_ team: PeopleService.TeamDetail) -> some View {
        List {
            // Error banner
            if let error = actionError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // Team Info
            Section {
                LabeledContent("Name", value: team.name)
                if let description = team.description, !description.isEmpty {
                    LabeledContent("Description", value: description)
                }
                LabeledContent("Members", value: "\(members.count)")
                if let leader = team.leaderName {
                    LabeledContent("Lead", value: leader)
                }
            } header: {
                Text("Team Info")
            }

            // Members
            Section {
                if members.isEmpty {
                    Text("No members yet. Add team members from the menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(members) { member in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name).font(.headline)
                                Text(member.role.capitalized)
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
                                Task { await removeMember(member) }
                            } label: {
                                Label("Remove", systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
            } header: {
                Text("Members (\(members.count))")
            }

            // Assigned Jobs
            Section {
                if assignedJobs.isEmpty {
                    Text("No active jobs assigned to this team.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(assignedJobs) { job in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.jobName).font(.headline)
                                HStack(spacing: 6) {
                                    if !job.jobNumber.isEmpty {
                                        Text("#\(job.jobNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(job.status.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(statusColor(job.status))
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Assigned Jobs")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Status Color

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "active", "in_progress": return .green
        case "pending": return .orange
        case "completed", "closed": return .blue
        default: return .secondary
        }
    }

    // MARK: - Actions

    private func loadData() async {
        guard let service = appCore.peopleService else {
            loadError = "People service unavailable"
            isLoading = false
            return
        }
        isLoading = team == nil && members.isEmpty
        loadError = nil
        do {
            let detail = try service.getTeamDetail(teamId: teamId)
            let memberList = try service.getTeamMembers(teamId: teamId)
            let jobs = try service.getTeamJobs(teamId: teamId)
            team = detail
            members = memberList
            assignedJobs = jobs
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func removeMember(_ member: PeopleService.TeamMemberDetail) async {
        guard let service = appCore.peopleService else { return }
        do {
            try service.removeTeamMember(membershipId: member.membershipId)
            actionError = nil
            await loadData()
        } catch {
            actionError = "Failed to remove member: \(error.localizedDescription)"
        }
    }

    private func deleteTeam() async {
        guard let service = appCore.peopleService else { return }
        do {
            try service.deleteTeam(teamId: teamId)
        } catch {
            actionError = "Failed to delete team: \(error.localizedDescription)"
        }
    }
}

// MARK: - Edit Team Sheet

private struct EditTeamSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let teamId: Int64
    @State var name: String
    @State var description: String
    @State private var errorMessage: String?
    let onSave: () -> Void

    init(teamId: Int64, currentName: String, currentDescription: String?, onSave: @escaping () -> Void) {
        self.teamId = teamId
        self._name = State(initialValue: currentName)
        self._description = State(initialValue: currentDescription ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Team Name", text: $name)
                }
                Section("Optional") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let service = appCore.peopleService else {
            errorMessage = "People service unavailable"
            return
        }
        do {
            try service.updateTeam(
                teamId: teamId,
                name: name.trimmingCharacters(in: .whitespaces),
                description: description.isEmpty ? nil : description
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Add Member Sheet

private struct AddMemberSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let teamId: Int64
    let onAdd: () -> Void

    @State private var employees: [PeopleService.EmployeeListItem] = []
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading employees...")
                } else if filteredEmployees.isEmpty {
                    ContentUnavailableView(
                        "No Available Employees",
                        systemImage: "person.badge.plus",
                        description: Text("All employees are already members of this team.")
                    )
                } else {
                    List(filteredEmployees) { employee in
                        Button {
                            addEmployee(employee)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(employee.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(employee.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search employees...")
            .navigationTitle("Add Team Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { loadEmployees() }
        }
    }

    private var filteredEmployees: [PeopleService.EmployeeListItem] {
        guard !searchText.isEmpty else { return employees }
        let query = searchText.lowercased()
        return employees.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.email.lowercased().contains(query)
        }
    }

    private func loadEmployees() {
        guard let service = appCore.peopleService else {
            isLoading = false
            return
        }
        do {
            employees = try service.getAvailableEmployeesForTeam(teamId: teamId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func addEmployee(_ employee: PeopleService.EmployeeListItem) {
        guard let service = appCore.peopleService else { return }
        do {
            try service.addTeamMember(teamId: teamId, userId: employee.id)
            // Remove from list and refresh
            employees.removeAll { $0.id == employee.id }
            onAdd()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
