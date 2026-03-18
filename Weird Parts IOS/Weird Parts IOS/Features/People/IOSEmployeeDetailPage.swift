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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
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
        guard let service = appCore.peopleService else { return }
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
