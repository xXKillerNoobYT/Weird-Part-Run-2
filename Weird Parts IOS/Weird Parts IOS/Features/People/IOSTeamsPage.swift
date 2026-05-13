import SwiftUI
import WiredPartCore

/// Team management page for iOS.
///
/// Displays a searchable list of teams with smart card filters,
/// member counts, and navigation to team detail pages.
struct IOSTeamsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var teams: [PeopleService.TeamListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var filter: TeamFilter = .all

    private enum TeamFilter {
        case all, active, mine
    }

    private enum ActiveSheet: String, Identifiable {
        case addTeam
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        teamList
            .navigationTitle("Teams")
            .searchable(text: $searchText, prompt: "Search teams...")
            .refreshable { loadData() }
            .task { loadData() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .addTeam } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add team")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addTeam:
                    AddTeamSheet { loadData() }
                        .environmentObject(appCore)
                case .help:
                    PageHelpSheet(
                        title: "Teams Help",
                        sections: [
                            ("What This Page Does", "View and manage teams. Teams group employees together for job assignments and scheduling. Each row shows the team name, description, leader, and member count."),
                            ("Smart Card Filters", "Tap the filter cards at the top to narrow the list: All shows every team, Active shows teams with at least one member, and My Teams shows teams you belong to."),
                            ("How to Use It", "Use the search bar to find teams by name, description, or leader. Tap a team to see its members, assigned jobs, and management options. Tap the + button to create a new team."),
                            ("Tips", "Pull down to refresh. The member count badge on each row shows how many employees are in that team. Teams with a star icon indicate the team leader.")
                        ]
                    )
                }
            }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                smartCard("All", count: teams.count, icon: "person.3", filterType: .all, color: .accentColor)
                smartCard("Active", count: activeTeams.count, icon: "checkmark.circle", filterType: .active, color: .green)
                smartCard("My Teams", count: myTeams.count, icon: "person.crop.circle", filterType: .mine, color: .blue)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func smartCard(_ label: String, count: Int, icon: String, filterType: TeamFilter, color: Color) -> some View {
        let isActive = filter == filterType
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                filter = isActive ? .all : filterType
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text("\(count)")
                        .font(.system(.title3, weight: .bold))
                        .monospacedDigit()
                }
                Text(label)
                    .font(.caption2)
            }
            .frame(minWidth: 80)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? color.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isActive ? color : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter Helpers

    private var activeTeams: [PeopleService.TeamListItem] {
        teams.filter { $0.memberCount > 0 }
    }

    private var myTeams: [PeopleService.TeamListItem] {
        // For now, show all teams — would need current user's team membership to filter
        // This is a placeholder; ideally we'd filter by current user's teams
        teams
    }

    private var filteredTeams: [PeopleService.TeamListItem] {
        var result: [PeopleService.TeamListItem]
        switch filter {
        case .all: result = teams
        case .active: result = activeTeams
        case .mine: result = myTeams
        }

        guard !searchText.isEmpty else { return result }
        let query = searchText.lowercased()
        return result.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) ?? false) ||
            ($0.leaderName?.lowercased().contains(query) ?? false)
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
        } else if teams.isEmpty {
            EmptyStateView(
                icon: "person.3.fill",
                title: "No Teams Yet",
                message: "Teams are built from employees. Create your employees first, then organize them into teams here.",
                actionLabel: "Add Team",
                helpLabel: "Learn how teams work",
                helpAction: { activeSheet = .help },
                action: { activeSheet = .addTeam }
            )
        } else if filteredTeams.isEmpty {
            EmptyStateView(
                icon: "line.3.horizontal.decrease.circle",
                title: "No Matching Teams",
                message: "No teams match your current search and filter.",
                helpLabel: "Learn how teams work",
                helpAction: { activeSheet = .help }
            )
        } else {
            List {
                Section {
                    smartCardFilters
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                ForEach(filteredTeams, id: \.id) { team in
                    NavigationLink(value: team.id) {
                        teamRow(team)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationDestination(for: Int64.self) { teamId in
                IOSTeamDetailPage(teamId: teamId)
            }
        }
    }

    private func teamRow(_ team: PeopleService.TeamListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.title3)
                .foregroundStyle(Color.blue)
                .frame(width: 32)
                .accessibilityHidden(true)

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
                .accessibilityHidden(true)
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
            loadError = userFriendlyError(error, context: "load teams")
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
    @State private var isSaving = false
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Team Name", text: $teamName)
                        .onChange(of: teamName) { _, _ in isDirty = true }
                }
                Section("Optional") {
                    TextField("Description", text: $teamDescription, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: teamDescription) { _, _ in isDirty = true }
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CreationFormActions(
                    isEditing: false,
                    isSaving: isSaving,
                    isValid: !teamName.trimmingCharacters(in: .whitespaces).isEmpty,
                    onCancel: {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    },
                    onSaveAndExit: { save(shouldDismiss: true) },
                    onSaveAndAddAnother: { save(shouldDismiss: false) }
                )
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
        .interactiveDismissDisabled(isDirty || isSaving)
    }

    private func save(shouldDismiss: Bool) {
        guard let service = appCore.peopleService else {
            errorMessage = "People service unavailable"
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            try service.createTeam(
                name: teamName.trimmingCharacters(in: .whitespaces),
                description: teamDescription.isEmpty ? nil : teamDescription
            )
            if shouldDismiss {
                dismiss()
            } else {
                resetForm()
            }
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "load teams")
        }
        isSaving = false
    }

    private func resetForm() {
        teamName = ""
        teamDescription = ""
        isDirty = false
    }
}
