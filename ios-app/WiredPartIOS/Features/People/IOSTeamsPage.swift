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

    var body: some View {
        NavigationStack {
            teamList
                .navigationTitle("Teams")
                .searchable(text: $searchText, prompt: "Search teams...")
                .onChange(of: searchText) { /* local filter only */ }
                .refreshable { loadData() }
                .task { loadData() }
        }
    }

    // MARK: - Team List

    @ViewBuilder
    private var teamList: some View {
        if isLoading {
            ProgressView("Loading teams...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
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
        guard let service = appCore.peopleService else { return }
        isLoading = teams.isEmpty
        do {
            teams = try service.listTeams()
        } catch {
            print("[IOSTeamsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
