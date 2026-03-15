import SwiftUI
import WiredPartCore

/// Employees list page.
///
/// Displays a searchable, sortable table of all employees with name, email,
/// role, status, and hats columns. Supports searching by name or email.
struct EmployeesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var employees: [PeopleService.EmployeeListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\PeopleService.EmployeeListItem.displayName)]

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
                Text("Employees")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(employees.count) employee\(employees.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search employees...", text: $searchText)
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
            ProgressView("Loading employees...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if employees.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.3")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No employees found")
                    .font(.headline)
                Text("Employees will appear here once added.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedEmployees, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.displayName) { emp in
                    Text(emp.displayName)
                        .fontWeight(.medium)
                }
                .width(min: 140, ideal: 200)

                TableColumn("Email", value: \.email) { emp in
                    Text(emp.email)
                        .font(.callout)
                }
                .width(min: 160, ideal: 220)

                TableColumn("Role", value: \.role) { emp in
                    Text(emp.role.capitalized)
                        .font(.callout)
                }
                .width(min: 70, ideal: 100)

                TableColumn("Status", value: \.status) { emp in
                    statusBadge(emp.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Hats") { (emp: PeopleService.EmployeeListItem) in
                    Text(emp.hatNames ?? "-")
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(emp.hatNames != nil ? .primary : .secondary)
                }
                .width(min: 100, ideal: 180)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedEmployees: [PeopleService.EmployeeListItem] {
        employees.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "inactive": .red
        case "on_leave": .orange
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = PeopleService(db: db)
        isLoading = true
        do {
            let allEmployees = try service.listEmployees()
            // Client-side search filter
            if searchText.isEmpty {
                employees = allEmployees
            } else {
                let query = searchText.lowercased()
                employees = allEmployees.filter {
                    $0.displayName.lowercased().contains(query) ||
                    $0.email.lowercased().contains(query)
                }
            }
        } catch {
            print("[EmployeesPage] Load error: \(error)")
        }
        isLoading = false
    }
}
