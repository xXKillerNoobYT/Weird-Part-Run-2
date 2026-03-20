import SwiftUI
import WiredPartCore

/// Sheet for creating a new notebook.
struct CreateNotebookSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    var onSave: () -> Void

    @State private var title = ""
    @State private var notebookType = "general"
    @State private var selectedJobId: Int64?
    @State private var jobs: [JobsService.JobListItem] = []
    @State private var isSaving = false
    @State private var saveError: String?

    private let typeOptions = ["general", "job", "daily_report", "checklist"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Notebook title", text: $title)
                }

                Section("Type") {
                    Picker("Type", selection: $notebookType) {
                        ForEach(typeOptions, id: \.self) { type in
                            Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if notebookType == "job" {
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
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Notebook")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { saveNotebook() }
                        .disabled(title.isEmpty || isSaving)
                        .fontWeight(.semibold)
                }
            }
            .task { loadJobs() }
        }
    }

    private func loadJobs() {
        guard let service = appCore.jobsService else { return }
        jobs = (try? service.listJobs(status: "active", limit: 200)) ?? []
    }

    private func saveNotebook() {
        guard let service = appCore.notebooksService,
              let userId = appCore.currentUser?.id else { return }
        isSaving = true
        saveError = nil
        do {
            _ = try service.createNotebook(
                title: title,
                notebookType: notebookType,
                jobId: notebookType == "job" ? selectedJobId : nil,
                createdBy: userId
            )
            onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
