import SwiftUI
import WiredPartCore

/// Sheet for creating a new schedule entry with half-day support.
struct CreateScheduleEntrySheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let date: String
    var initialJobId: Int64? = nil
    var initialJobName: String? = nil
    var onSave: () -> Void

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var selectedJobId: Int64?
    @State private var entryDate = Date()
    @State private var timeSlot = "full"
    @State private var startTime = ""
    @State private var endTime = ""
    @State private var notes = ""
    @State private var assignmentDetail: SchedulingService.JobDayAssignmentDetail?
    @State private var isLoadingAssignmentDetail = false
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    if let initialJobId {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(initialJobName ?? selectedJobName(for: initialJobId))
                                    .foregroundStyle(.primary)
                                Text("Opened from this job's calendar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Selected job, \(initialJobName ?? selectedJobName(for: initialJobId))")
                    } else if jobs.isEmpty {
                        Text("No active jobs")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Job", selection: $selectedJobId) {
                            Text("Select a job...").tag(nil as Int64?)
                            ForEach(jobs, id: \.id) { job in
                                Text(job.jobName).tag(job.id as Int64?)
                            }
                        }
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                }

                if initialJobId != nil || selectedJobId != nil {
                    dayAssignmentsSection
                }

                Section("Time Slot") {
                    Picker("Time Slot", selection: $timeSlot) {
                        Text("Full Day").tag("full")
                        Text("AM Only").tag("am")
                        Text("PM Only").tag("pm")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Time (Optional)") {
                    TextField("Start time (e.g. 07:00)", text: $startTime)
                    TextField("End time (e.g. 15:30)", text: $endTime)
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
            // Fix #149: dismiss keyboard when scrolling through entry form
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Schedule Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
            .interactiveDismissDisabled(isSaving)
            .task { loadJobs() }
            .onAppear {
                selectedJobId = initialJobId
                loadAssignmentDetail()
            }
            .onChange(of: entryDate) { _ in loadAssignmentDetail() }
            .onChange(of: selectedJobId) { _ in loadAssignmentDetail() }
        }
    }

    @ViewBuilder
    private var dayAssignmentsSection: some View {
        Section("Day Assignments") {
            if isLoadingAssignmentDetail {
                ProgressView("Checking crew availability...")
            } else if let detail = assignmentDetail {
                if detail.assignedToJob.isEmpty,
                   detail.assignedToOtherJobs.isEmpty,
                   detail.timeOffWorkers.isEmpty {
                    Text("No crew assignments or approved time off found for this date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if !detail.assignedToJob.isEmpty {
                        assignmentGroup(
                            title: "Assigned to this job",
                            rows: detail.assignedToJob,
                            color: .green,
                            systemImage: "checkmark.circle.fill"
                        )
                    }
                    if !detail.assignedToOtherJobs.isEmpty {
                        assignmentGroup(
                            title: "Assigned to other jobs",
                            rows: detail.assignedToOtherJobs,
                            color: .orange,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                    }
                    if !detail.timeOffWorkers.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Approved time off", systemImage: "person.crop.circle.badge.xmark")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                            ForEach(detail.timeOffWorkers) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.userName)
                                        .font(.caption)
                                    if let reason = row.reason, !reason.isEmpty {
                                        Text(reason)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Pick a job to see who is assigned, busy elsewhere, or off on this date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func assignmentGroup(
        title: String,
        rows: [SchedulingService.JobDayAssignmentRow],
        color: Color,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.userName)
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text(row.timeSlot.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(row.jobName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let notes = row.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var selectedDateString: String {
        Formatters.localDateFormatter.string(from: entryDate)
    }

    private func selectedJobName(for jobId: Int64) -> String {
        jobs.first(where: { $0.id == jobId })?.jobName ?? "Selected Job"
    }

    private func loadJobs() {
        guard let service = appCore.jobsService else {
            saveError = "Jobs service not available"
            return
        }
        jobs = (try? service.listJobs(status: "active", limit: 200)) ?? []
        if let initialJobId {
            selectedJobId = initialJobId
        }
        loadAssignmentDetail()
    }

    private func loadAssignmentDetail() {
        guard let service = appCore.schedulingService,
              let jobId = selectedJobId else {
            assignmentDetail = nil
            return
        }

        isLoadingAssignmentDetail = true
        do {
            assignmentDetail = try service.getJobDayAssignmentDetail(
                jobId: jobId,
                date: selectedDateString
            )
        } catch {
            assignmentDetail = nil
            saveError = userFriendlyError(error, context: "load day assignments")
        }
        isLoadingAssignmentDetail = false
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
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}
