import SwiftUI
import WiredPartCore

/// Team management page for iOS.
///
/// Displays a searchable list of teams with team name, member count,
/// and lead name. Supports pull-to-refresh and search filtering.
struct IOSTeamsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var teams: [PeopleService.TeamListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    private enum ActiveSheet: String, Identifiable {
        case addTeam
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        teamList
            .navigationTitle("Teams")
            .searchable(text: $searchText, prompt: "Search teams...")
            .onChange(of: searchText) { /* local filter only */ }
            .refreshable { loadData() }
            .task { loadData() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .addTeam } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addTeam:
                    AddTeamSheet { loadData() }
                        .environmentObject(appCore)
                }
            }
    }

    // MARK: - Team List

    @ViewBuilder
    private var teamList: some View {
        if isLoading {
            ProgressView("Loading teams...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredTeams.isEmpty {
            ContentUnavailableView {
                Label("No Teams", systemImage: "person.3")
            } description: {
                Text("No teams have been created yet.")
            }
        } else {
            List(filteredTeams, id: \.id) { team in
                teamRow(team)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredTeams: [PeopleService.TeamListItem] {
        guard !searchText.isEmpty else { return teams }
        let query = searchText.lowercased()
        return teams.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) ?? false) ||
            ($0.leaderName?.lowercased().contains(query) ?? false)
        }
    }

    private func teamRow(_ team: PeopleService.TeamListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.title3)
                .foregroundStyle(Color.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(team.name)
                    .fontWeight(.medium)
                if let desc = team.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let leader = team.leaderName {
                    Label(leader, systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            membersBadge(team.memberCount)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func membersBadge(_ count: Int) -> some View {
        let color: Color = count > 0 ? .blue : .secondary
        return HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.caption2)
            Text("\(count)")
                .font(.system(.caption2, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.15)))
        .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.peopleService else {
            isLoading = false
            loadError = "People service unavailable"
            return
        }
        isLoading = teams.isEmpty
        loadError = nil
        do {
            teams = try service.listTeams()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Add Team Sheet

private struct AddTeamSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var teamName = ""
    @State private var teamDescription = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Team Name", text: $teamName)
                }
                Section("Optional") {
                    TextField("Description", text: $teamDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(teamName.trimmingCharacters(in: .whitespaces).isEmpty)
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
            try service.createTeam(
                name: teamName.trimmingCharacters(in: .whitespaces),
                description: teamDescription.isEmpty ? nil : teamDescription
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
