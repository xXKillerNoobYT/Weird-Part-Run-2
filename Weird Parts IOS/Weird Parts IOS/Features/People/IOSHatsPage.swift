import SwiftUI
import WiredPartCore

/// Employee hats (roles) management page for iOS.
///
/// Displays a searchable list of hats with name, description, and the count
/// of employees currently assigned to each hat. Supports pull-to-refresh.
struct IOSHatsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var hats: [PeopleService.HatListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var hatToDelete: PeopleService.HatListItem?
    private enum ActiveSheet: String, Identifiable {
        case addHat
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "people-hats")
            hatList
        }
            .task { appCore.onboardingManager?.markCompleted("hats-view") }
            .navigationTitle("Hats & Roles")
            .searchable(text: $searchText, prompt: "Search hats...")
            .onChange(of: searchText) { /* local filter only */ }
            .refreshable { loadData() }
            .task { loadData() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .addHat } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add hat")
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
                case .addHat:
                    AddHatSheet { loadData() }
                        .environmentObject(appCore)
                case .help:
                    PageHelpSheet(
                        title: "Hats & Roles Help",
                        sections: [
                            ("What This Page Does", "Manage hats (roles) that can be assigned to employees. Hats define what an employee is responsible for and control their permissions in the system. Each hat shows its name, description, and how many employees currently wear it."),
                            ("How to Use It", "Search by hat name or description. Tap the + button to create a new hat with a name and optional description. Swipe left on any hat to delete it."),
                            ("Assigning Hats", "Hats are assigned to employees from the Employee Detail page's Hats tab. Each hat grants a set of permissions — configure those on the Permissions page."),
                            ("Deleting a Hat", "Swipe left and tap Delete to remove a hat. This removes the role and all its permission assignments permanently. Employees who had this hat will lose those permissions."),
                            ("Tips", "Pull down to refresh. The badge on each hat shows how many employees are assigned to it. Common hats include Foreman, Electrician, Apprentice, Office Manager, etc.")
                        ]
                    )
                }
            }
            .alert(
                "Delete Hat?",
                isPresented: Binding(
                    get: { hatToDelete != nil },
                    set: { if !$0 { hatToDelete = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { hatToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let hat = hatToDelete {
                        deleteHat(hat)
                        hatToDelete = nil
                    }
                }
            } message: {
                Text("This will remove the role and all its permissions. This cannot be undone.")
            }
    }

    // MARK: - Hat List

    @ViewBuilder
    private var hatList: some View {
        if isLoading {
            ProgressView("Loading hats...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredHats.isEmpty {
            ContentUnavailableView {
                Label("No Hats", systemImage: "graduationcap")
            } description: {
                Text("No roles have been created yet.")
            }
        } else {
            List(filteredHats, id: \.id) { hat in
                hatRow(hat)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            hatToDelete = hat
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredHats: [PeopleService.HatListItem] {
        guard !searchText.isEmpty else { return hats }
        let query = searchText.lowercased()
        return hats.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) ?? false)
        }
    }

    private func hatRow(_ hat: PeopleService.HatListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.title3)
                .foregroundStyle(Color.purple)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(hat.name)
                    .fontWeight(.medium)
                if let desc = hat.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                assignedBadge(hat.userCount)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func assignedBadge(_ count: Int) -> some View {
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

    private func deleteHat(_ hat: PeopleService.HatListItem) {
        guard let service = appCore.peopleService else {
            loadError = "Service not available"
            return
        }
        do {
            try service.deleteHat(id: hat.id)
            loadData()
        } catch {
            loadError = userFriendlyError(error, context: "load roles")
        }
    }

    private func loadData() {
        guard let service = appCore.peopleService else {
            isLoading = false
            loadError = "People service unavailable"
            return
        }
        isLoading = hats.isEmpty
        loadError = nil
        do {
            hats = try service.listHats()
        } catch {
            loadError = userFriendlyError(error, context: "load roles")
        }
        isLoading = false
    }
}

// MARK: - Add Hat Sheet

private struct AddHatSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var hatName = ""
    @State private var hatDescription = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Hat Name", text: $hatName)
                }
                Section("Optional") {
                    TextField("Description", text: $hatDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add Hat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(hatName.trimmingCharacters(in: .whitespaces).isEmpty)
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
            try service.createHat(
                name: hatName.trimmingCharacters(in: .whitespaces),
                description: hatDescription.isEmpty ? nil : hatDescription
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "load hats")
        }
    }
}
