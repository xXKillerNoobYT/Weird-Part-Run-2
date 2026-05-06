import SwiftUI
import WiredPartCore

/// Sheet for assigning a driver to a vehicle.
///
/// Lists available employees and allows selecting one to assign
/// as the primary or secondary driver of a vehicle.
struct IOSAssignDriverSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let vehicleId: Int64

    @State private var employees: [PeopleService.EmployeeListItem] = []
    @State private var selectedEmployeeId: Int64?
    @State private var assignmentType = "primary"
    @State private var isTakeHome = false
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError: String?

    private let assignmentTypes = ["primary", "secondary", "temporary"]

    var body: some View {
        NavigationStack {
            Form {
                assignmentTypeSection
                driverListSection
            }
            .navigationTitle("Assign Driver")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search employees...")
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") { assignDriver() }
                        .disabled(isSaving || selectedEmployeeId == nil)
                        .fontWeight(.semibold)
                        .requiresPermission("manage_fleet")
                }
            }
            .task { loadEmployees() }
            .alert("Assignment Failed", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(actionError ?? "Unknown error")
            }
            .alert("Error", isPresented: Binding<Bool>(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("OK") { loadError = nil }
            } message: {
                Text(loadError ?? "")
            }
        }
    }

    // MARK: - Sections

    private var assignmentTypeSection: some View {
        Section("Assignment Type") {
            Picker("Type", selection: $assignmentType) {
                ForEach(assignmentTypes, id: \.self) { type in
                    Text(type.capitalized).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Take-Home Vehicle", isOn: $isTakeHome)
        }
    }

    private var driverListSection: some View {
        Section("Select Driver") {
            if isLoading {
                ProgressView()
            } else if filteredEmployees.isEmpty {
                Text("No employees found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredEmployees) { employee in
                    employeeRow(employee)
                }
            }
        }
    }

    private func employeeRow(_ employee: PeopleService.EmployeeListItem) -> some View {
        Button {
            selectedEmployeeId = employee.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(employee.displayName)
                        .foregroundStyle(.primary)
                        .fontWeight(selectedEmployeeId == employee.id ? .semibold : .regular)
                    if let hats = employee.hatNames, !hats.isEmpty {
                        Text(hats)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selectedEmployeeId == employee.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: - Filtering

    private var filteredEmployees: [PeopleService.EmployeeListItem] {
        guard !searchText.isEmpty else { return employees }
        let query = searchText.lowercased()
        return employees.filter {
            $0.displayName.lowercased().contains(query)
        }
    }

    // MARK: - Data

    private func loadEmployees() {
        guard let service = appCore.peopleService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = true
        do {
            employees = try service.listEmployees()
        } catch {
            loadError = userFriendlyError(error, context: "load driver data")
        }
        isLoading = false
    }

    @State private var actionError: String?
    var onSaved: (() -> Void)?

    private func assignDriver() {
        guard let fleet = appCore.fleetService else {
            actionError = "Service not available"
            return
        }
        guard let employeeId = selectedEmployeeId else { return }
        isSaving = true
        actionError = nil

        do {
            try fleet.assignDriver(
                actorId: appCore.currentUser?.id ?? 0,
                vehicleId: vehicleId,
                userId: employeeId,
                assignmentType: assignmentType,
                isTakeHome: isTakeHome
            )
            onSaved?()
            dismiss()
        } catch {
            actionError = userFriendlyError(error, context: "assign driver")
        }
        isSaving = false
    }
}
