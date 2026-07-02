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
    @State private var statusCounts: [String: Int] = [:]
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case addEmployee
        case badgeScanner
        case help

        var id: String {
            switch self {
            case .addEmployee: "addEmployee"
            case .badgeScanner: "badgeScanner"
            case .help: "help"
            }
        }
    }

    private let statusOptions = ["all", "active", "inactive", "suspended"]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "people-employees")
            SkippedModuleHint(moduleId: "people")
            statusPicker
            employeeList
        }
        .task { appCore.onboardingManager?.markCompleted("people-view") }
        .navigationTitle("Employees")
        .searchable(text: $searchText, prompt: "Search employees...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
        .onAppear {
            NotificationCenter.default.post(
                name: .employeesPageActive,
                object: nil,
                userInfo: [
                    "context": "Employees Page: \(employees.count) employees, filter: \(statusFilter)."
                ]
            )
        }
        .onDisappear {
            NotificationCenter.default.post(name: .employeesPageInactive, object: nil)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { activeSheet = .badgeScanner } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .accessibilityLabel("Scan employee badge")
                Button { activeSheet = .addEmployee } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add employee")
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
            case .addEmployee:
                AddEmployeeSheet { loadData() }
                    .environmentObject(appCore)
            case .badgeScanner:
                QRScanSheet(expectedType: .employee) { result in
                    if result.isFound {
                        searchText = result.fields["display_name"] ?? result.code
                    }
                }
                .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Employees Help",
                    sections: [
                        ("What This Page Does", "View and manage all employees in the system. Each row shows the employee's name, email, assigned hats (roles), status, and role level."),
                        ("How to Use It", "Use the status filter chips at the top to show only Active, Inactive, or Suspended employees. Type in the search bar to filter by name, email, phone, or hat. Tap an employee to view their full profile. Tap the + button to add a new employee."),
                        ("Badge Scanner", "Tap the QR scanner icon to scan an employee badge. If the badge is found, the employee's name fills the search bar automatically."),
                        ("Tips", "Pull down to refresh the list. Status badges are color-coded: green for active, red for suspended, gray for inactive. Role badges show the employee's access level (admin, manager, supervisor, or worker).")
                    ]
                )
            }
        }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let total = statusCounts.values.reduce(0, +)
                SmartFilterCard(
                    title: "All",
                    count: total,
                    isSelected: statusFilter == "all",
                    action: { statusFilter = "all"; loadData() }
                )
                ForEach(statusOptions.dropFirst(), id: \.self) { status in
                    SmartFilterCard(
                        title: status.capitalized,
                        count: statusCounts[status] ?? 0,
                        isSelected: statusFilter == status,
                        action: { statusFilter = status; loadData() }
                    )
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
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredEmployees.isEmpty {
            EmptyStateView(
                icon: "person.3",
                title: "No Employees",
                message: searchText.isEmpty ? "No employees have been added yet." : "No employees match your criteria."
            )
        } else {
            List(filteredEmployees, id: \.id) { employee in
                NavigationLink(destination: IOSEmployeeDetailPage(employeeId: employee.id)) {
                    employeeRow(employee)
                }
            }
            .listStyle(.insetGrouped)
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
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(employee.displayName), \(employee.email), role \(employee.role), status \(employee.status)")
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
        guard let service = appCore.peopleService else {
            isLoading = false
            loadError = "People service is not available."
            return
        }
        isLoading = employees.isEmpty
        loadError = nil
        do {
            employees = try service.listEmployees(
                search: searchText.isEmpty ? nil : searchText,
                status: statusFilter == "all" ? nil : statusFilter
            )
            // Load status counts for SmartFilterCard
            if statusCounts.isEmpty {
                let allEmployees = try service.listEmployees(search: nil, status: nil)
                var counts: [String: Int] = [:]
                for emp in allEmployees {
                    counts[emp.status, default: 0] += 1
                }
                statusCounts = counts
            }
        } catch {
            loadError = userFriendlyError(error, context: "load employees")
        }
        isLoading = false
    }
}

// MARK: - Add Employee Sheet

private struct AddEmployeeSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var displayName = ""
    @State private var pin = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var errorMessage: String?
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)
                        .onChange(of: displayName) { _, _ in isDirty = true }
                    SecureField("PIN (min 4 digits)", text: $pin)
                        .keyboardType(.numberPad)
                        .onChange(of: pin) { _, _ in isDirty = true }
                }
                Section("Optional") {
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
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Employee")
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
                        .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pin.count < 4)
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
        guard let authService = appCore.authService else {
            errorMessage = "Auth service unavailable"
            return
        }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required."
            return
        }
        guard pin.count >= 4 else {
            errorMessage = "PIN must be at least 4 digits."
            return
        }
        do {
            try authService.createUser(
                displayName: trimmedName,
                pin: pin,
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone
            )
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "load employees")
        }
    }
}
