import SwiftUI
import WiredPartCore

/// Sheet for creating a new dispatch entry.
struct CreateDispatchSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let date: String
    var onSave: () -> Void

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var employees: [AuthService.UserListItem] = []
    @State private var selectedJobId: Int64?
    @State private var selectedUserId: Int64?
    @State private var notes = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Employee") {
                    if employees.isEmpty {
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
                    if jobs.isEmpty {
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
            .navigationTitle("New Dispatch")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { saveDispatch() }
                        .disabled(selectedJobId == nil || selectedUserId == nil || isSaving)
                        .fontWeight(.semibold)
                }
            }
            .task { loadData() }
        }
    }

    private func loadData() {
        if let jobService = appCore.jobsService {
            jobs = (try? jobService.listJobs(status: "active", limit: 200)) ?? []
        }
        if let authService = appCore.authService {
            employees = (try? authService.listUsers()) ?? []
        }
    }

    private func saveDispatch() {
        guard let service = appCore.schedulingService,
              let jobId = selectedJobId,
              let userId = selectedUserId else { return }
        isSaving = true
        saveError = nil
        do {
            _ = try service.createDispatch(
                jobId: jobId,
                userId: userId,
                date: date,
                notes: notes.isEmpty ? nil : notes
            )
            onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
