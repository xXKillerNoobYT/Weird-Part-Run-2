import SwiftUI
import WiredPartCore

/// Job edit form presented as a sheet.
///
/// Pre-populated with existing job data. On save, updates via JobsService.
struct IOSEditJobSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let job: JobsService.JobDetail
    var onUpdated: (() -> Void)?

    @State private var jobName: String
    @State private var customerName: String
    @State private var addressLine1: String
    @State private var city: String
    @State private var state: String
    @State private var zip: String
    @State private var jobType: String
    @State private var priority: String
    @State private var status: String
    @State private var notes: String
    @State private var budgetLimit: String
    @State private var estimatedHours: String

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var stageTemplates: [JobsService.JobStageTemplate] = []
    @State private var selectedStageTemplateId: Int64?
    @State private var showingTemplateChangeConfirmation = false

    private let jobTypes = ["service", "installation", "maintenance", "inspection", "emergency", "warranty"]
    private let priorities = ["low", "normal", "high", "urgent"]
    private let statuses = ["active", "completed", "on_hold", "cancelled"]

    init(job: JobsService.JobDetail, onUpdated: (() -> Void)? = nil) {
        self.job = job
        self.onUpdated = onUpdated
        _jobName = State(initialValue: job.jobName)
        _customerName = State(initialValue: job.customerName ?? "")
        _addressLine1 = State(initialValue: job.addressLine1 ?? "")
        _city = State(initialValue: job.city ?? "")
        _state = State(initialValue: job.state ?? "")
        _zip = State(initialValue: job.zip ?? "")
        _jobType = State(initialValue: job.jobType)
        _priority = State(initialValue: job.priority)
        _status = State(initialValue: job.status)
        _notes = State(initialValue: job.notes ?? "")
        _budgetLimit = State(initialValue: job.budgetLimit.map { String($0) } ?? "")
        _estimatedHours = State(initialValue: job.estimatedHours.map { String($0) } ?? "")
    }

    private var isValid: Bool {
        !jobName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job Information") {
                    TextField("Job Name", text: $jobName)
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { s in
                            Text(s.replacingOccurrences(of: "_", with: " ").capitalized).tag(s)
                        }
                    }
                    Picker("Type", selection: $jobType) {
                        ForEach(jobTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { p in
                            Text(p.capitalized).tag(p)
                        }
                    }
                }

                Section("Customer") {
                    TextField("Customer Name", text: $customerName)
                    TextField("Address", text: $addressLine1)
                    HStack(spacing: 8) {
                        TextField("City", text: $city)
                        TextField("State", text: $state)
                            .frame(width: 60)
                        TextField("ZIP", text: $zip)
                            .keyboardType(.numberPad)
                            .frame(width: 70)
                    }
                }

                Section("Budget") {
                    TextField("Estimated Hours", text: $estimatedHours)
                        .keyboardType(.decimalPad)
                    TextField("Budget Limit ($)", text: $budgetLimit)
                        .keyboardType(.decimalPad)
                }

                Section("Stage Template") {
                    if stageTemplates.isEmpty {
                        Text("No stage templates available. Create one in Settings → Job Stage Templates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Workflow", selection: Binding(
                            get: { selectedStageTemplateId ?? stageTemplates.first?.id ?? 0 },
                            set: { selectedStageTemplateId = $0 }
                        )) {
                            ForEach(stageTemplates.filter { $0.stageCount > 0 }) { template in
                                Text(template.name).tag(template.id)
                            }
                        }
                        if selectedStageTemplateId != job.stageTemplateId {
                            Text("Saving will preview and confirm the template change so the current stage is preserved when possible.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
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
            .navigationTitle("Edit Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveJob() }
                        .fontWeight(.semibold)
                        .disabled(!isValid || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { loadStageTemplates() }
            .confirmationDialog(
                "Change stage template?",
                isPresented: $showingTemplateChangeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Change Template") { saveJob(applyTemplateChange: true) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The job will move to the selected workflow. If its current stage is not in that template, it will move to the first stage in the new template.")
            }
        }
    }

    // MARK: - Actions

    private func loadStageTemplates() {
        guard let service = appCore.jobsService else {
            errorMessage = "Jobs service unavailable"
            return
        }
        do {
            stageTemplates = try service.listJobStageTemplates().filter { $0.stageCount > 0 }
            if selectedStageTemplateId == nil {
                selectedStageTemplateId = job.stageTemplateId ?? stageTemplates.first(where: { $0.isDefault })?.id ?? stageTemplates.first?.id
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "load stage templates")
        }
    }

    private func saveJob(applyTemplateChange: Bool = false) {
        guard let service = appCore.jobsService else {
            errorMessage = "Service not available"
            return
        }
        if selectedStageTemplateId != job.stageTemplateId && !applyTemplateChange {
            showingTemplateChangeConfirmation = true
            return
        }
        isSaving = true
        errorMessage = nil

        do {
            try service.updateJob(
                id: job.id,
                jobName: jobName.trimmingCharacters(in: .whitespaces),
                customerName: customerName.isEmpty ? nil : customerName,
                addressLine1: addressLine1.isEmpty ? nil : addressLine1,
                city: city.isEmpty ? nil : city,
                state: state.isEmpty ? nil : state,
                zip: zip.isEmpty ? nil : zip,
                status: status,
                priority: priority,
                jobType: jobType,
                estimatedHours: Double(estimatedHours),
                notes: notes.isEmpty ? nil : notes,
                budgetLimit: Double(budgetLimit)
            )
            if applyTemplateChange, let selectedStageTemplateId, selectedStageTemplateId != job.stageTemplateId {
                let preview = try service.previewJobStageTemplateAssignment(jobId: job.id, templateId: selectedStageTemplateId)
                try service.assignJobStageTemplate(jobId: job.id, templateId: selectedStageTemplateId, currentStageId: preview.replacementStageId)
            }
            onUpdated?()
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "save job")
        }
        isSaving = false
    }
}
