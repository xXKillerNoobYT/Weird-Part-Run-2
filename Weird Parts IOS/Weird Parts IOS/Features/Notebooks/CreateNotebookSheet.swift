import SwiftUI
import WiredPartCore

/// Sheet for creating a new notebook, optionally from a template.
struct CreateNotebookSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    var templateId: Int64? = nil
    var onSave: () -> Void

    @State private var title = ""
    @State private var notebookType = "general"
    @State private var selectedJobId: Int64?
    @State private var selectedTemplateId: Int64?
    @State private var jobs: [JobsService.JobListItem] = []
    @State private var templates: [NotebooksService.NotebookTemplateItem] = []
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

                // Template picker
                if !templates.isEmpty {
                    Section {
                        Picker("Start from Template", selection: $selectedTemplateId) {
                            Text("Blank Notebook").tag(nil as Int64?)
                            ForEach(templates) { template in
                                Text(template.name).tag(template.id as Int64?)
                            }
                        }
                    } header: {
                        Text("Template")
                    } footer: {
                        Text("Templates create pre-built sections and pages for you")
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
            .navigationBarTitleDisplayMode(.inline)
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
            .task {
                loadJobs()
                loadTemplates()
                if let tid = templateId {
                    selectedTemplateId = tid
                }
            }
        }
    }

    private func loadJobs() {
        guard let service = appCore.jobsService else {
            saveError = "Jobs service not available"
            return
        }
        jobs = (try? service.listJobs(status: "active", limit: 200)) ?? []
    }

    private func loadTemplates() {
        guard let service = appCore.notebooksService else {
            // Service not ready
            return
        }
        templates = (try? service.getTemplates(templateType: "job")) ?? []
    }

    private func saveNotebook() {
        guard let service = appCore.notebooksService,
              let userId = appCore.currentUser?.id else {
            saveError = "Service not available"
            return
        }
        isSaving = true
        saveError = nil
        do {
            let nbId = try service.createNotebook(
                title: title,
                notebookType: notebookType,
                jobId: notebookType == "job" ? selectedJobId : nil,
                createdBy: userId
            )

            // Apply template if selected
            if let tid = selectedTemplateId {
                try service.applyJobTemplate(templateId: tid, notebookId: nbId, createdBy: userId)
            }

            onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
