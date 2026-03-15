import SwiftUI
import WiredPartCore

/// Employees list page for iOS.
///
/// Displays a searchable list of employees with name, email, role,
/// status badge, and hats. Supports pull-to-refresh and status-based filtering.
struct IOSEmployeesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var employees: [PeopleService.EmployeeListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"

    private let statusOptions = ["all", "active", "inactive", "suspended"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusPicker
                employeeList
            }
            .navigationTitle("Employees")
            .searchable(text: $searchText, prompt: "Search employees...")
            .onChange(of: searchText) { loadData() }
            .refreshable { loadData() }
            .task { loadData() }
        }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    Button {
                        statusFilter = status
                        loadData()
                    } label: {
                        Text(status == "all" ? "All" : status.capitalized)
                            .font(.caption)
                            .fontWeight(statusFilter == status ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(statusFilter == status ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(statusFilter == status ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Employee List

    @ViewBuilder
    private var employeeList: some View {
        if isLoading {
            ProgressView("Loading employees...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredEmployees.isEmpty {
            ContentUnavailableView {
                Label("No Employees", systemImage: "person.3")
            } description: {
                Text("No employees match your criteria.")
            }
        } else {
            List(filteredEmployees, id: \.id) { employee in
                employeeRow(employee)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredEmployees: [PeopleService.EmployeeListItem] {
        guard !searchText.isEmpty else { return employees }
        let query = searchText.lowercased()
        return employees.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.email.lowercased().contains(query) ||
            ($0.phone?.lowercased().contains(query) ?? false) ||
            ($0.hatNames?.lowercased().contains(query) ?? false)
        }
    }

    private func employeeRow(_ employee: PeopleService.EmployeeListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(employee.displayName)
                    .fontWeight(.medium)
                Text(employee.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let hats = employee.hatNames, !hats.isEmpty {
                    Text(hats)
                        .font(.caption2)
                        .foregroundStyle(.purple)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(employee.status)
                roleBadge(employee.role)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "inactive": .secondary
        case "suspended": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func roleBadge(_ role: String) -> some View {
        let color: Color = switch role {
        case "admin": .red
        case "manager": .orange
        case "supervisor": .purple
        default: .blue
        }
        return Text(role.capitalized)
            .font(.caption2)
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.peopleService else { return }
        isLoading = employees.isEmpty
        do {
            employees = try service.listEmployees(
                search: searchText.isEmpty ? nil : searchText,
                status: statusFilter == "all" ? nil : statusFilter
            )
        } catch {
            print("[IOSEmployeesPage] Load error: \(error)")
        }
        isLoading = false
    }
}
