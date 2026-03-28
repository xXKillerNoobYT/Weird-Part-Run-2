import SwiftUI
import WiredPartCore

/// Q&A question submission form.
///
/// Allows users to submit questions with priority and job association.
/// Questions enter the escalation chain and are routed to the appropriate responder.
struct IOSQAQuestionForm: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    var onSubmitted: (() -> Void)?

    @State private var question = ""
    @State private var selectedJobId: Int64?
    @State private var priority = "normal"
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var jobs: [JobsService.JobListItem] = []
    @State private var wasAutoFilled = false

    private let priorities = ["low", "normal", "high", "urgent"]

    private var isValid: Bool {
        !question.trimmingCharacters(in: .whitespaces).isEmpty && selectedJobId != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if jobs.isEmpty {
                        Text("No jobs available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Job", selection: $selectedJobId) {
                            Text("Select a job…").tag(nil as Int64?)
                            ForEach(jobs, id: \.id) { job in
                                Text(job.jobName).tag(job.id as Int64?)
                            }
                        }
                        .onChange(of: selectedJobId) { _, _ in
                            wasAutoFilled = false
                        }
                    }
                } header: {
                    Text("Job")
                } footer: {
                    if wasAutoFilled {
                        Text("Auto-filled from your active clock entry")
                    }
                }

                Section("Your Question") {
                    TextEditor(text: $question)
                        .frame(minHeight: 100)
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { p in
                            Text(p.capitalized).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Ask a Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submitQuestion() }
                        .fontWeight(.semibold)
                        .disabled(!isValid || isSaving)
                }
            }
            .task {
                loadJobs()
                autoFillFromClockEntry()
            }
        }
    }

    // MARK: - Data

    private func loadJobs() {
        guard let service = appCore.jobsService else {
            errorMessage = "Service not available"
            return
        }
        do {
            jobs = try service.listJobs(status: "active", limit: 200)
        } catch {
            errorMessage = userFriendlyError(error, context: "load jobs")
        }
    }

    private func autoFillFromClockEntry() {
        guard selectedJobId == nil,
              let service = appCore.jobsService,
              let userId = appCore.currentUser?.id else { return }
        do {
            if let activeEntry = try service.getActiveClockEntry(userId: userId) {
                selectedJobId = activeEntry.jobId
                wasAutoFilled = true
            }
        } catch {
            // Non-fatal — user can still select manually
        }
    }

    // MARK: - Actions

    private func submitQuestion() {
        guard let jobId = selectedJobId else { return }
        isSaving = true
        errorMessage = nil

        guard let service = appCore.chatService else {
            isSaving = false
            errorMessage = "Chat service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            isSaving = false
            errorMessage = "Not logged in"
            return
        }
        do {
            try service.createQAThread(
                jobId: jobId,
                askedBy: userId,
                subject: question.trimmingCharacters(in: .whitespaces),
                priority: priority
            )
            isSaving = false
            onSubmitted?()
            dismiss()
        } catch {
            isSaving = false
            errorMessage = userFriendlyError(error, context: "load messages")
        }
    }
}
