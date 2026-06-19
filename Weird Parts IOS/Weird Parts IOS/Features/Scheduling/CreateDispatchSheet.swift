import SwiftUI
import WiredPartCore

public struct DispatchSheetLoadData {
    public let jobs: [JobsService.JobListItem]
    public let employees: [PeopleService.EmployeeListItem]
    public let jobLoadError: String?
    public let employeeLoadError: String?

    public var hasLoadFailure: Bool {
        jobLoadError != nil || employeeLoadError != nil
    }

    public static func load(
        jobsProvider: () throws -> [JobsService.JobListItem],
        employeesProvider: () throws -> [PeopleService.EmployeeListItem],
        errorFormatter: (Error, String) -> String
    ) -> DispatchSheetLoadData {
        var loadedJobs: [JobsService.JobListItem] = []
        var loadedEmployees: [PeopleService.EmployeeListItem] = []
        var jobError: String?
        var employeeError: String?

        do {
            loadedJobs = try jobsProvider()
        } catch {
            jobError = errorFormatter(error, "load active jobs")
        }

        do {
            loadedEmployees = try employeesProvider()
        } catch {
            employeeError = errorFormatter(error, "load employees")
        }

        return DispatchSheetLoadData(
            jobs: loadedJobs,
            employees: loadedEmployees,
            jobLoadError: jobError,
            employeeLoadError: employeeError
        )
    }
}

/// Sheet for creating a new dispatch entry.
struct CreateDispatchSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let date: String
    var onSave: () -> Void

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var employees: [PeopleService.EmployeeListItem] = []
    @State private var selectedJobId: Int64?
    @State private var selectedUserId: Int64?
    @State private var notes = ""
    @State private var isSaving = false
    @State private var isLoadingData = false
    @State private var saveError: String?
    @State private var jobLoadError: String?
    @State private var employeeLoadError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Employee") {
                    if let employeeLoadError {
                        loadFailureRow(message: employeeLoadError, retryLabel: "Retry loading employees")
                    } else if employees.isEmpty {
                        Text("No employees found")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Employee", selection: $selectedUserId) {
                            Text("Select...").tag(nil as Int64?)
                            ForEach(employees, id: \.id) { emp in
                                Text(emp.displayName).tag(emp.id as Int64?)
                            }
                        }
                    }
                }

                Section("Job") {
                    if let jobLoadError {
                        loadFailureRow(message: jobLoadError, retryLabel: "Retry loading jobs")
                    } else if jobs.isEmpty {
                        Text("No active jobs")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Job", selection: $selectedJobId) {
                            Text("Select...").tag(nil as Int64?)
                            ForEach(jobs, id: \.id) { job in
                                Text(job.jobName).tag(job.id as Int64?)
                            }
                        }
                    }
                }

                Section("Date") {
                    Text(date)
                        .foregroundStyle(.secondary)
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            // Fix #149: dismiss keyboard when scrolling dispatch form
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Dispatch")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { saveDispatch() }
                        .disabled(selectedJobId == nil || selectedUserId == nil || isSaving || isLoadingData)
                        .fontWeight(.semibold)
                }
            }
            .task { loadData() }
        }
    }

    @ViewBuilder
    private func loadFailureRow(message: String, retryLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Unable to load", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .accessibilityElement(children: .combine)

            Button {
                loadData()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(retryLabel)
        }
    }

    private func loadData() {
        isLoadingData = true
        defer { isLoadingData = false }

        let result = DispatchSheetLoadData.load(
            jobsProvider: {
                guard let jobService = appCore.jobsService else {
                    throw DispatchLoadServiceError.jobsUnavailable
                }
                return try jobService.listJobs(status: "active", limit: 200)
            },
            employeesProvider: {
                guard let peopleService = appCore.peopleService else {
                    throw DispatchLoadServiceError.peopleUnavailable
                }
                return try peopleService.listEmployees()
            },
            errorFormatter: { error, context in
                userFriendlyError(error, context: context)
            }
        )

        jobs = result.jobs
        employees = result.employees
        jobLoadError = result.jobLoadError
        employeeLoadError = result.employeeLoadError

        if let selectedJobId, !jobs.contains(where: { $0.id == selectedJobId }) {
            self.selectedJobId = nil
        }
        if let selectedUserId, !employees.contains(where: { $0.id == selectedUserId }) {
            self.selectedUserId = nil
        }
    }

    private func saveDispatch() {
        guard let service = appCore.schedulingService,
              let jobId = selectedJobId,
              let userId = selectedUserId else {
            saveError = "Scheduling service not available"
            return
        }
        isSaving = true
        saveError = nil
        do {
            _ = try service.createDispatch(
                jobId: jobId,
                userId: userId,
                date: date,
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}

private enum DispatchLoadServiceError: LocalizedError {
    case jobsUnavailable
    case peopleUnavailable

    var errorDescription: String? {
        switch self {
        case .jobsUnavailable:
            return "Job service is not available"
        case .peopleUnavailable:
            return "People service is not available"
        }
    }
}
