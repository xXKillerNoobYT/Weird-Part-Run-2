import SwiftUI
import GRDB
import WiredPartCore


/// Employee detail page with tabs for profile, hats, teams, and activity.
struct IOSEmployeeDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let employeeId: Int64

    @State private var employee: PeopleService.EmployeeDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedTab = "profile"
    private enum ActiveSheet: String, Identifiable {
        case editEmployee
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
                Button("Edit") { activeSheet = .editEmployee }
                    .disabled(employee == nil)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editEmployee:
                if let emp = employee {
                    EditEmployeeSheet(employee: emp) { loadData() }
                        .environmentObject(appCore)
                }
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
        .listStyle(.insetGrouped)
    }

    // MARK: - Hats

    private func hatsTab(_ emp: PeopleService.EmployeeDetail) -> some View {
        List {
            if emp.hats.isEmpty {
                Section {
                    Text("No hats assigned")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Assigned Hats (\(emp.hats.count))") {
                    ForEach(emp.hats) { hat in
                        HStack(spacing: 12) {
                            Image(systemName: "graduationcap.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hat.name)
                                    .fontWeight(.medium)
                                if let desc = hat.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
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
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
// MARK: - Edit Employee Sheet

private struct EditEmployeeSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let employee: PeopleService.EmployeeDetail
    let onSave: () -> Void

    @State private var displayName: String
    @State private var email: String
    @State private var phone: String
    @State private var errorMessage: String?

    init(employee: PeopleService.EmployeeDetail, onSave: @escaping () -> Void) {
        self.employee = employee
        self.onSave = onSave
        _displayName = State(initialValue: employee.displayName)
        _email = State(initialValue: employee.email)
        _phone = State(initialValue: employee.phone ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Employee Info") {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Employee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let db = appCore.db else {
            errorMessage = "Database unavailable"
            return
        }
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        do {
            try db.writer.write { dbConn in
                try dbConn.execute(
                    sql: """
                        UPDATE users SET display_name = ?, email = ?, phone = ?, updated_at = datetime('now')
                        WHERE id = ?
                        """,
                    arguments: [trimmedName, email.isEmpty ? nil : email, phone.isEmpty ? nil : phone, employee.id]
                )
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

