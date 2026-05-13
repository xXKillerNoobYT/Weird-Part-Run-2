import SwiftUI
import WiredPartCore

/// Sheet for creating a new schedule entry with half-day support.
struct CreateScheduleEntrySheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let date: String
    var onSave: () -> Void

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var selectedJobId: Int64?
    @State private var entryDate = Date()
    @State private var timeSlot = "full"
    @State private var startTime = ""
    @State private var endTime = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isDirty = false
    @State private var showDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    if jobs.isEmpty {
                        Text("No active jobs")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Job", selection: $selectedJobId) {
                            Text("Select a job...").tag(nil as Int64?)
                            ForEach(jobs, id: \.id) { job in
                                Text(job.jobName).tag(job.id as Int64?)
                            }
                        }
                        .onChange(of: selectedJobId) { _, _ in isDirty = true }
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                        .onChange(of: entryDate) { _, _ in isDirty = true }
                }

                Section("Time Slot") {
                    Picker("Time Slot", selection: $timeSlot) {
                        Text("Full Day").tag("full")
                        Text("AM Only").tag("am")
                        Text("PM Only").tag("pm")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: timeSlot) { _, _ in isDirty = true }
                }

                Section("Time (Optional)") {
                    TextField("Start time (e.g. 07:00)", text: $startTime)
                        .onChange(of: startTime) { _, _ in isDirty = true }
                    TextField("End time (e.g. 15:30)", text: $endTime)
                        .onChange(of: endTime) { _, _ in isDirty = true }
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                        .onChange(of: notes) { _, _ in isDirty = true }
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            // Fix #149: dismiss keyboard when scrolling through entry form
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Schedule Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardConfirmation = true } else { dismiss() }
                    }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create") { saveEntry() }
                            .disabled(selectedJobId == nil)
                            .fontWeight(.semibold)
                    }
                }
            }
            .interactiveDismissDisabled(isDirty || isSaving)
            .confirmationDialog(
                "Discard changes?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved schedule entry changes will be lost.")
            }
            .task { loadJobs() }
        }
    }

    private func loadJobs() {
        guard let service = appCore.jobsService else {
            saveError = "Jobs service not available"
            return
        }
        jobs = (try? service.listJobs(status: "active", limit: 200)) ?? []
    }

    private func saveEntry() {
        guard let service = appCore.schedulingService,
              let jobId = selectedJobId,
              let userId = appCore.currentUser?.id else {
            saveError = "Service not available"
            return
        }
        isSaving = true
        saveError = nil
        do {
            _ = try service.createScheduleEntry(
                userId: userId,
                jobId: jobId,
                date: Formatters.localDateFormatter.string(from: entryDate),
                startTime: startTime.isEmpty ? nil : startTime,
                endTime: endTime.isEmpty ? nil : endTime,
                notes: notes.isEmpty ? nil : notes,
                timeSlot: timeSlot
            )
            isDirty = false
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}
