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
    private enum ActiveSheet: Identifiable {
        case addHat
        case help
        case hatDetail(PeopleService.HatListItem)
        var id: String {
            switch self {
            case .addHat: return "addHat"
            case .help: return "help"
            case .hatDetail(let h): return "hat-\(h.id)"
            }
        }
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
                Group {
                    switch sheet {
                    case .addHat:
                        AddHatSheet { loadData() }
                            .environmentObject(appCore)
                    case .help:
                        PageHelpSheet(
                            title: "Hats & Roles Help",
                            sections: [
                                ("What This Page Does", "Manage hats (roles) that can be assigned to employees. Hats define what an employee is responsible for and control their permissions in the system. Each hat shows its name, description, and how many employees currently wear it."),
                                ("How to Use It", "Search by hat name or description. Tap a hat to see its members and permissions. Tap the + button to create a new hat. Swipe left on any hat to delete it."),
                                ("Assigning Hats", "Hats are assigned to employees from the Employee Detail page's Hats tab. Each hat grants a set of permissions — configure those on the Permissions page."),
                                ("Deleting a Hat", "Swipe left and tap Delete to remove a hat. This removes the role and all its permission assignments permanently. Employees who had this hat will lose those permissions."),
                                ("Tips", "Pull down to refresh. The badge on each hat shows how many employees are assigned to it. Common hats include Foreman, Electrician, Apprentice, Office Manager, etc.")
                            ]
                        )
                    case .hatDetail(let hat):
                        HatDetailSheet(hat: hat) { loadData() }
                            .environmentObject(appCore)
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
            EmptyStateView(
                icon: "graduationcap",
                title: "No Hats",
                message: searchText.isEmpty ? "No roles have been created yet." : "No roles match your current search.",
                actionLabel: "Add Hat",
                helpLabel: "Learn how hats work",
                helpAction: { activeSheet = .help },
                action: { activeSheet = .addHat }
            )
        } else {
            List(filteredHats, id: \.id) { hat in
                Button {
                    activeSheet = .hatDetail(hat)
                } label: {
                    hatRow(hat)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(hat.name), \(hat.userCount) members")
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
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Hat Name", text: $hatName)
                        .onChange(of: hatName) { _, _ in isDirty = true }
                }
                Section("Optional") {
                    TextField("Description", text: $hatDescription, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: hatDescription) { _, _ in isDirty = true }
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Hat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(hatName.trimmingCharacters(in: .whitespaces).isEmpty)
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
        guard let service = appCore.peopleService else {
            errorMessage = "People service unavailable"
            return
        }
        do {
            try service.createHat(
                name: hatName.trimmingCharacters(in: .whitespaces),
                description: hatDescription.isEmpty ? nil : hatDescription
            )
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "load hats")
        }
    }
}
// MARK: - Hat Detail Sheet

private struct HatDetailSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let hat: PeopleService.HatListItem
    let onDismiss: () -> Void

    @State private var members: [PeopleService.HatMember] = []
    @State private var permissions: [String] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var canManageHats = false
    @State private var showAddEmployee = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ErrorStateView(message: error) { loadData() }
                } else {
                    detailContent
                }
            }
            .navigationTitle(hat.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
                if canManageHats {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAddEmployee = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                        .accessibilityLabel("Add employee to hat")
                    }
                }
            }
            .task { loadData() }
            .sheet(isPresented: $showAddEmployee) {
                AddEmployeeToHatSheet(hatId: hat.id, existingMemberIds: Set(members.map(\.id))) {
                    loadData()
                }
                .environmentObject(appCore)
            }
        }
    }

    private var detailContent: some View {
        List {
            membersSection
            permissionsSection
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var membersSection: some View {
        Section {
            if members.isEmpty {
                Text("No employees assigned to this hat")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else if canManageHats {
                ForEach(members) { member in
                    memberRow(member)
                }
                .onDelete(perform: removeMember)
            } else {
                ForEach(members) { member in
                    memberRow(member)
                }
            }
        } header: {
            Text("Members (\(members.count))")
        }
    }

    private func memberRow(_ member: PeopleService.HatMember) -> some View {
        NavigationLink(destination: IOSEmployeeDetailPage(employeeId: member.id).environmentObject(appCore)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .fontWeight(.medium)
                if let date = member.assignedAt {
                    Text("Since \(String(date.prefix(10)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var permissionsSection: some View {
        Section {
            if permissions.isEmpty {
                Text("No permissions configured")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(Array(permissions.prefix(5)), id: \.self) { perm in
                    Label(permissionLabel(perm), systemImage: "checkmark.shield")
                        .font(.subheadline)
                }
                if permissions.count > 5 {
                    Text("+\(permissions.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink(destination: IOSPermissionsPage().environmentObject(appCore)) {
                Label("Edit Permissions", systemImage: "lock.shield")
            }
            .frame(minHeight: 44)
        } header: {
            Text("Permissions (\(permissions.count))")
        }
    }

    private func removeMember(at offsets: IndexSet) {
        guard let service = appCore.peopleService else { return }
        for index in offsets {
            let member = members[index]
            do {
                try service.toggleHatAssignment(employeeId: member.id, hatId: hat.id, assign: false)
            } catch {
                loadError = userFriendlyError(error, context: "remove member")
            }
        }
        loadData()
    }

    private func loadData() {
        guard let people = appCore.peopleService else {
            isLoading = false
            loadError = "People service unavailable"
            return
        }
        isLoading = members.isEmpty
        loadError = nil
        do {
            members = try people.getHatMembers(hatId: hat.id)
            permissions = (try? appCore.authService?.getHatPermissions(hat.id)) ?? []
            canManageHats = appCore.hasPermission("manage_people")
        } catch {
            loadError = userFriendlyError(error, context: "load hat details")
        }
        isLoading = false
    }

    private func permissionLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Add Employee to Hat Sheet

private struct AddEmployeeToHatSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let hatId: Int64
    let existingMemberIds: Set<Int64>
    let onSave: () -> Void

    @State private var employees: [PeopleService.EmployeeListItem] = []
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            Group {
                if let error = loadError {
                    ErrorStateView(message: error) { loadEmployees() }
                } else if availableEmployees.isEmpty {
                    EmptyStateView(
                        icon: "person.slash",
                        title: "No Employees Available",
                        message: "All employees are already assigned to this hat.",
                        helpLabel: "Learn how hats work",
                        helpAction: { showHelp = true }
                    )
                } else {
                    List(availableEmployees) { emp in
                        Button {
                            assignEmployee(emp.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(emp.displayName)
                                        .fontWeight(.medium)
                                    Text(emp.role.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Add Employee")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search employees...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showHelp = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .sheet(isPresented: $showHelp) {
                PageHelpSheet(
                    title: "Add Employee to Hat Help",
                    sections: [
                        ("What This Sheet Does", "Lists employees who are not already assigned to the selected hat."),
                        ("How to Use It", "Search for an employee, then tap a row to assign that employee to the hat. Employees already wearing the hat are hidden from this list.")
                    ]
                )
            }
            .task { loadEmployees() }
        }
    }

    private var availableEmployees: [PeopleService.EmployeeListItem] {
        let filtered = employees.filter { !existingMemberIds.contains($0.id) }
        guard !searchText.isEmpty else { return filtered }
        let query = searchText.lowercased()
        return filtered.filter { $0.displayName.lowercased().contains(query) }
    }

    private func loadEmployees() {
        guard let service = appCore.peopleService else {
            loadError = "People service unavailable"
            return
        }
        do {
            employees = try service.listEmployees()
            loadError = nil
        } catch {
            loadError = userFriendlyError(error, context: "load employees")
        }
    }

    private func assignEmployee(_ employeeId: Int64) {
        guard let service = appCore.peopleService else { return }
        do {
            try service.toggleHatAssignment(employeeId: employeeId, hatId: hatId, assign: true)
            dismiss()
            onSave()
        } catch {
            loadError = userFriendlyError(error, context: "assign hat")
        }
    }
}
