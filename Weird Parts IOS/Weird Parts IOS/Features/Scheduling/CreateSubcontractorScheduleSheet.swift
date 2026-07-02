import SwiftUI
import WiredPartCore

/// Sheet for creating or editing a subcontractor schedule arrival.
///
/// Uses the SchedulingService write APIs so scheduled subcontractor dates stay as
/// exact local date-only values (`yyyy-MM-dd`) instead of being buried in notes.
struct CreateSubcontractorScheduleSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let existing: SchedulingService.SubScheduleRow?
    var onSave: () -> Void

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var contractors: [PeopleService.ContractorListItem] = []
    @State private var selectedJobId: Int64?
    @State private var selectedContractorId: Int64?
    @State private var scheduledDate = Date()
    @State private var arrivalTime = ""
    @State private var departureTime = ""
    @State private var scopeOfWork = ""
    @State private var status = "scheduled"
    @State private var notes = ""
    @State private var isSaving = false
    @State private var saveError: String?
    /// Load-error states for the prerequisite pickers (#1177) — a failed job
    /// or contractor list load must never render as an empty picker with a
    /// disabled Create/Save button. Tracked separately so the operator knows
    /// which prerequisite failed.
    @State private var jobsLoadError: String?
    @State private var contractorsLoadError: String?

    private let statuses = ["scheduled", "confirmed", "completed"]

    init(
        initialDate: Date,
        existing: SchedulingService.SubScheduleRow? = nil,
        onSave: @escaping () -> Void
    ) {
        self.initialDate = initialDate
        self.existing = existing
        self.onSave = onSave
        _scheduledDate = State(initialValue: initialDate)
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    if let error = jobsLoadError {
                        // Inline load error with retry (#1177) — distinguishes
                        // "failed to load jobs" from "no active jobs exist".
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Button {
                                loadJobList()
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .accessibilityLabel("Retry loading jobs")
                        }
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

                Section("Subcontractor") {
                    if let error = contractorsLoadError {
                        // Inline load error with retry (#1177) — distinguishes
                        // "failed to load subcontractors" from "none exist".
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Button {
                                loadContractorList()
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .accessibilityLabel("Retry loading subcontractors")
                        }
                    } else if contractors.isEmpty {
                        Text("No active subcontractors")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Subcontractor", selection: $selectedContractorId) {
                            Text("Select a subcontractor...").tag(nil as Int64?)
                            ForEach(contractors, id: \.id) { contractor in
                                Text(contractorDisplayName(contractor)).tag(contractor.id as Int64?)
                            }
                        }
                    }
                }

                Section("Scheduled Date") {
                    DatePicker("Date", selection: $scheduledDate, displayedComponents: .date)
                }

                Section("Arrival Window (Optional)") {
                    TextField("Arrival time (e.g. 07:30)", text: $arrivalTime)
                        .textInputAutocapitalization(.never)
                    TextField("Departure time (e.g. 15:30)", text: $departureTime)
                        .textInputAutocapitalization(.never)
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { value in
                            Text(value.capitalized).tag(value)
                        }
                    }
                }

                Section("Scope of Work (Optional)") {
                    TextEditor(text: $scopeOfWork)
                        .frame(minHeight: 70)
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 70)
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Sub Schedule" : "Add Sub Schedule")
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
                        Button(isEditing ? "Save" : "Create") { saveSchedule() }
                            .disabled(selectedJobId == nil || selectedContractorId == nil)
                            .fontWeight(.semibold)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { loadData() }
        }
    }

    private func loadData() {
        if let existing {
            selectedJobId = existing.jobId == 0 ? nil : existing.jobId
            selectedContractorId = existing.gcId == 0 ? nil : existing.gcId
            if let date = Formatters.localDateFormatter.date(from: String(existing.scheduleDate.prefix(10))) {
                scheduledDate = date
            }
            arrivalTime = existing.arrivalTime ?? ""
            departureTime = existing.departureTime ?? ""
            scopeOfWork = existing.scopeOfWork ?? ""
            status = existing.status
            notes = existing.notes ?? ""
        }

        loadJobList()
        loadContractorList()
    }

    /// Loads the active-job picker list with explicit error surfacing (#1177).
    /// Kept separate from `loadData()` so Retry re-fetches only the list and
    /// never re-applies `existing` values over in-progress user edits.
    private func loadJobList() {
        guard let jobsService = appCore.jobsService else {
            jobsLoadError = "Jobs service not available. Try again after app services finish loading."
            return
        }
        do {
            jobs = try jobsService.listJobs(status: "active", limit: 300)
            jobsLoadError = nil
        } catch {
            jobsLoadError = userFriendlyError(error, context: "load active jobs")
        }
    }

    /// Loads the subcontractor picker list with explicit error surfacing (#1177).
    private func loadContractorList() {
        guard let peopleService = appCore.peopleService else {
            contractorsLoadError = "People service not available. Try again after app services finish loading."
            return
        }
        do {
            contractors = try peopleService.listContractors()
            contractorsLoadError = nil
        } catch {
            contractorsLoadError = userFriendlyError(error, context: "load subcontractors")
        }
    }

    private func saveSchedule() {
        guard let service = appCore.schedulingService,
              let jobId = selectedJobId,
              let contractorId = selectedContractorId else {
            saveError = "Service not available"
            return
        }

        isSaving = true
        saveError = nil
        do {
            let scheduledDateString = Formatters.localDateFormatter.string(from: scheduledDate)
            if let existing {
                try service.updateSubcontractorSchedule(
                    id: existing.id,
                    jobId: jobId,
                    gcId: contractorId,
                    scheduledDate: scheduledDateString,
                    arrivalTime: optionalText(arrivalTime),
                    departureTime: optionalText(departureTime),
                    scopeOfWork: optionalText(scopeOfWork),
                    status: status,
                    notes: optionalText(notes)
                )
            } else {
                _ = try service.createSubcontractorSchedule(
                    jobId: jobId,
                    gcId: contractorId,
                    scheduledDate: scheduledDateString,
                    arrivalTime: optionalText(arrivalTime),
                    departureTime: optionalText(departureTime),
                    scopeOfWork: optionalText(scopeOfWork),
                    status: status,
                    notes: optionalText(notes),
                    createdBy: appCore.currentUser?.id
                )
            }
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: isEditing ? "update sub schedule" : "create sub schedule")
        }
        isSaving = false
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func contractorDisplayName(_ contractor: PeopleService.ContractorListItem) -> String {
        let personName = [contractor.firstName, contractor.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if let company = contractor.company?.trimmingCharacters(in: .whitespacesAndNewlines), !company.isEmpty {
            return personName.isEmpty ? company : "\(company) — \(personName)"
        }
        return personName.isEmpty ? "Subcontractor #\(contractor.id)" : personName
    }
}
