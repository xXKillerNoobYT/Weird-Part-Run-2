import SwiftUI
import WiredPartCore

/// Teams list page.
///
/// Displays a sortable table of all teams with name, description,
/// leader, and member count columns. Supports searching by team name
/// or leader name.
struct TeamsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var teams: [PeopleService.TeamListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\PeopleService.TeamListItem.name)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { load() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Teams")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(teams.count) team\(teams.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search teams...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { load() }

            Button {
                load()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading teams...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if teams.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.3.sequence")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No teams found")
                    .font(.headline)
                Text("Create a team to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedTeams, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { team in
                    Text(team.name)
                        .fontWeight(.medium)
                }
                .width(min: 120, ideal: 180)

                TableColumn("Description") { (team: PeopleService.TeamListItem) in
                    Text(team.description ?? "-")
                        .lineLimit(1)
                        .foregroundStyle(team.description != nil ? .primary : .secondary)
                }
                .width(min: 160, ideal: 260)

                TableColumn("Leader") { (team: PeopleService.TeamListItem) in
                    Text(team.leaderName ?? "-")
                        .foregroundStyle(team.leaderName != nil ? .primary : .secondary)
                }
                .width(min: 100, ideal: 150)

                TableColumn("Members", value: \.memberCount) { team in
                    Text("\(team.memberCount)")
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 60, ideal: 80)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedTeams: [PeopleService.TeamListItem] {
        teams.sorted(using: sortOrder)
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = PeopleService(db: db)
        isLoading = true
        do {
            let allTeams = try service.listTeams()
            // Client-side search filter
            if searchText.isEmpty {
                teams = allTeams
            } else {
                let query = searchText.lowercased()
                teams = allTeams.filter {
                    $0.name.lowercased().contains(query) ||
                    ($0.leaderName?.lowercased().contains(query) ?? false) ||
                    ($0.description?.lowercased().contains(query) ?? false)
                }
            }
        } catch {
            print("[TeamsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
