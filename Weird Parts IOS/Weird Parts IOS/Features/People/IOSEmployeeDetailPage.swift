import SwiftUI
import WiredPartCore

/// Employee detail page with tabs for profile, hats, teams, and activity.
struct IOSEmployeeDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let employeeId: Int64

    @State private var employee: PeopleService.EmployeeDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedTab = "profile"

    // Hat management
    @State private var allHats: [(hat: PeopleService.HatInfo, isAssigned: Bool)] = []
    @State private var canManageHats = false
    @State private var combinedPermissions: [String] = []

    private enum ActiveSheet: String, Identifiable {
        case editContact
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    private let tabs = ["profile", "hats", "teams"]

    var body: some View {
        VStack(spacing: 0) {
            tabPicker

            if isLoading {
                ProgressView("Loading employee...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let emp = employee {
                tabContent(emp)
            }
        }
        .navigationTitle(employee?.displayName ?? "Employee")
        .refreshable { loadData() }
        .task { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { activeSheet = .editContact }
                    .disabled(employee == nil)
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
            case .editContact:
                if let emp = employee {
                    EditEmployeeContactSheet(
                        displayName: emp.displayName,
                        email: emp.email,
                        phone: emp.phone ?? ""
                    ) { name, email, phone in
                        guard let service = appCore.peopleService else {
                            loadError = "People service not available"
                            struct ServiceUnavailableError: Error {}
                            throw ServiceUnavailableError()
                        }
                        try service.updateEmployeeContact(
                            employeeId: emp.id,
                            displayName: name,
                            phone: phone.isEmpty ? nil : phone,
                            email: email.isEmpty ? nil : email
                        )
                        loadData()
                    }
                }
            case .help:
                PageHelpSheet(
                    title: "Employee Detail Help",
                    sections: [
                        ("What This Page Does", "View and edit a single employee's profile, hat assignments, and team memberships. Use the tabs to switch between Profile, Hats, and Teams views."),
                        ("Profile Tab", "Shows the employee's basic info: name, email, phone, role, status, and important dates. Tap Edit in the toolbar to update their contact information."),
                        ("Hats Tab", "Displays all available hats (roles) and which ones are assigned to this employee. If you have manage_people permission, you can toggle hats on and off directly. Each hat grants a set of permissions."),
                        ("Teams Tab", "Shows which teams this employee belongs to, their role within each team, and when they joined."),
                        ("Tips", "Pull down to refresh all data. Only managers and admins can toggle hat assignments. The Edit button updates contact info only — use the Hats tab for role changes.")
                    ]
                )
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.capitalized)
                            .font(.caption)
                            .fontWeight(selectedTab == tab ? .bold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selectedTab == tab ? Color.accentColor : Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(_ emp: PeopleService.EmployeeDetail) -> some View {
        switch selectedTab {
        case "profile":
            profileTab(emp)
        case "hats":
            hatsTab(emp)
        case "teams":
            teamsTab(emp)
        default:
            Text("Unknown tab")
        }
    }

    // MARK: - Profile

    private func profileTab(_ emp: PeopleService.EmployeeDetail) -> some View {
        List {
            Section("Basic Info") {
                detailRow("Name", emp.displayName)
                detailRow("Email", emp.email)
                if let phone = emp.phone, !phone.isEmpty {
                    detailRow("Phone", phone)
                }
                detailRow("Role", emp.role.capitalized)
                detailRow("Status", emp.status.capitalized)
            }

            Section("Dates") {
                if let created = emp.createdAt {
                    detailRow("Added", String(created.prefix(10)))
                }
                if let updated = emp.updatedAt {
                    detailRow("Updated", String(updated.prefix(10)))
                }
            }
        }
        // Fix #149: dismiss keyboard when scrolling employee detail lists
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
    }

    // MARK: - Hats

    private func hatsTab(_ emp: PeopleService.EmployeeDetail) -> some View {
        List {
            if allHats.isEmpty {
                Section {
                    Text("No hats available")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(allHats, id: \.hat.id) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "graduationcap.fill")
                                .foregroundStyle(item.isAssigned ? Color.accentColor : .gray)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.hat.name)
                                    .fontWeight(.medium)
                                if let desc = item.hat.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if canManageHats {
                                Toggle("", isOn: Binding<Bool>(
                                    get: { item.isAssigned },
                                    set: { newValue in
                                        toggleHat(hatId: item.hat.id, assign: newValue)
                                    }
                                ))
                                .labelsHidden()
                            } else if item.isAssigned {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                } header: {
                    Text("Hats & Roles (\(allHats.filter(\.isAssigned).count) assigned)")
                } footer: {
                    if !canManageHats {
                        Text("Contact a manager to change hat assignments")
                    }
                }
            }

            // Permissions Granted section
            Section {
                if combinedPermissions.isEmpty {
                    if allHats.filter(\.isAssigned).isEmpty && !allHats.isEmpty {
                        Text("Assign hats above to grant permissions")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        Text("No permissions granted")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    ForEach(combinedPermissions, id: \.self) { perm in
                        Label(permissionLabel(perm), systemImage: "checkmark.shield")
                            .font(.subheadline)
                            .accessibilityLabel(permissionLabel(perm))
                    }
                }
            } header: {
                Text("Permissions Granted (\(combinedPermissions.count))")
            } footer: {
                if !combinedPermissions.isEmpty {
                    Text("These permissions come from all assigned hats.")
                }
            }
        }
        // Fix #149: dismiss keyboard when scrolling employee detail lists
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
    }

    // MARK: - Teams

    private func teamsTab(_ emp: PeopleService.EmployeeDetail) -> some View {
        List {
            if emp.teams.isEmpty {
                Section {
                    Text("Not a member of any teams")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Teams (\(emp.teams.count))") {
                    ForEach(emp.teams) { membership in
                        HStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(membership.teamName)
                                    .fontWeight(.medium)
                                Text("Role: \(membership.role.capitalized)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let joined = membership.joinedAt {
                                    Text("Joined: \(String(joined.prefix(10)))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        // Fix #149: dismiss keyboard when scrolling employee detail lists
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func permissionLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func toggleHat(hatId: Int64, assign: Bool) {
        guard let service = appCore.peopleService else {
            loadError = "Service not available"
            return
        }
        do {
            try service.toggleHatAssignment(employeeId: employeeId, hatId: hatId, assign: assign)
            // Reload hats
            allHats = (try? service.getAllHatsWithAssignment(employeeId: employeeId)) ?? []
        } catch {
            loadError = userFriendlyError(error, context: "update hat")
        }
    }

    private func loadData() {
        guard let service = appCore.peopleService else {
            isLoading = false
            loadError = "People service unavailable"
            return
        }
        isLoading = employee == nil
        loadError = nil
        do {
            employee = try service.getEmployeeDetail(id: employeeId)
            allHats = try service.getAllHatsWithAssignment(employeeId: employeeId)
            canManageHats = appCore.hasPermission("manage_people")

            // Collect combined permissions from all assigned hats
            var allPerms = Set<String>()
            if let auth = appCore.authService {
                for item in allHats where item.isAssigned {
                    let hatPerms = (try? auth.getHatPermissions(item.hat.id)) ?? []
                    allPerms.formUnion(hatPerms)
                }
            }
            combinedPermissions = allPerms.sorted()
        } catch {
            loadError = userFriendlyError(error, context: "load employee details")
        }
        isLoading = false
    }
}

// MARK: - Edit Employee Contact Sheet

private struct EditEmployeeContactSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var displayName: String
    @State var email: String
    @State var phone: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    let onSave: (String, String, String) throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
                Section("Contact Info") {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)
                        .onChange(of: displayName) { _, _ in isDirty = true }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .onChange(of: email) { _, _ in isDirty = true }
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .onChange(of: phone) { _, _ in isDirty = true }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Contact Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
        .interactiveDismissDisabled(isDirty)
    }

    private func save() {
        isSaving = true
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        do {
            try onSave(trimmedName, email, phone)
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "load employee")
        }
        isSaving = false
    }
}

