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
    @State private var addressLine2: String
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
        _addressLine2 = State(initialValue: job.addressLine2 ?? "")
        _city = State(initialValue: job.city ?? "")
        _state = State(initialValue: job.state ?? "")
        _zip = State(initialValue: job.zip ?? "")
        _jobType = State(initialValue: job.jobType)
        _priority = State(initialValue: job.priority)
        _status = State(initialValue: job.status)
        _notes = State(initialValue: job.notes ?? "")
        _budgetLimit = State(initialValue: job.budgetLimit.map { String($0) } ?? "")
        _estimatedHours = State(initialValue: job.estimatedHours.map { String($0) } ?? "")
        // Baseline mirrors the job's saved workflow — including nil for jobs
        // without one. The picker is the only thing that mutates this, so a
        // template change is persisted only when the user explicitly picks a
        // different option (issue #1105: never draft the default template).
        _selectedStageTemplateId = State(initialValue: job.stageTemplateId)
    }

    private var isValid: Bool {
        !jobName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && estimatedHoursValidationMessage == nil
            && budgetLimitValidationMessage == nil
    }

    /// Live validation so negative or malformed numeric drafts disable Save
    /// instead of persisting (or only failing at save time).
    private var estimatedHoursValidationMessage: String? {
        numericValidationMessage(for: estimatedHours, label: "Estimated Hours")
    }

    private var budgetLimitValidationMessage: String? {
        numericValidationMessage(for: budgetLimit, label: "Budget Limit")
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
                    TextField("Address Line 2", text: $addressLine2)
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
                    if let message = estimatedHoursValidationMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    TextField("Budget Limit ($)", text: $budgetLimit)
                        .keyboardType(.decimalPad)
                    if let message = budgetLimitValidationMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section("Stage Template") {
                    if stageTemplates.isEmpty {
                        Text("No stage templates available. Create one in Settings → Job Stage Templates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Workflow", selection: $selectedStageTemplateId) {
                            // Jobs without a workflow get an explicit "No Workflow"
                            // choice so opening the editor never pre-drafts the
                            // default template (issue #1105). Jobs that already
                            // have a workflow keep the template-only list — the
                            // service has no unassign path, so removal stays
                            // unsupported here.
                            if job.stageTemplateId == nil {
                                Text("No Workflow").tag(Int64?.none)
                            }
                            ForEach(stageTemplates.filter { $0.stageCount > 0 }) { template in
                                Text(template.name).tag(Int64?.some(template.id))
                            }
                        }
                        if selectedStageTemplateId != job.stageTemplateId {
                            Text(job.stageTemplateId == nil
                                ? "Saving will confirm assigning this workflow. The job will start at the workflow's first stage."
                                : "Saving will preview and confirm the template change so the current stage is preserved when possible.")
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
                job.stageTemplateId == nil ? "Assign workflow?" : "Change stage template?",
                isPresented: $showingTemplateChangeConfirmation,
                titleVisibility: .visible
            ) {
                Button(job.stageTemplateId == nil ? "Assign Workflow" : "Change Template") {
                    saveJob(applyTemplateChange: true)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(job.stageTemplateId == nil
                    ? "This job currently has no workflow. It will be assigned the selected workflow and start at its first stage."
                    : "The job will move to the selected workflow. If its current stage is not in that template, it will move to the first stage in the new template.")
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
            // Deliberately no default here: selectedStageTemplateId keeps the
            // baseline set in init (nil for workflow-less jobs), so saving an
            // unrelated edit never assigns the default/first template (#1105).
        } catch {
            errorMessage = userFriendlyError(error, context: "load stage templates")
        }
    }

    private func saveJob(applyTemplateChange: Bool = false) {
        guard let service = appCore.jobsService else {
            errorMessage = "Service not available"
            return
        }
        guard validateNumericFields() else { return }
        errorMessage = nil
        if selectedStageTemplateId != job.stageTemplateId && !applyTemplateChange {
            showingTemplateChangeConfirmation = true
            return
        }
        isSaving = true

        do {
            try service.updateJob(
                id: job.id,
                jobName: changedRequiredText(jobName, original: job.jobName),
                customerName: changedOptionalText(customerName, original: job.customerName),
                addressLine1: changedOptionalText(addressLine1, original: job.addressLine1),
                addressLine2: changedOptionalText(addressLine2, original: job.addressLine2),
                city: changedOptionalText(city, original: job.city),
                state: changedOptionalText(state, original: job.state),
                zip: changedOptionalText(zip, original: job.zip),
                status: changedRequiredText(status, original: job.status),
                priority: changedRequiredText(priority, original: job.priority),
                jobType: changedRequiredText(jobType, original: job.jobType),
                estimatedHours: changedDouble(estimatedHours, original: job.estimatedHours),
                notes: changedOptionalText(notes, original: job.notes),
                budgetLimit: changedDouble(budgetLimit, original: job.budgetLimit),
                clearEstimatedHours: shouldClearDouble(estimatedHours, original: job.estimatedHours),
                clearBudgetLimit: shouldClearDouble(budgetLimit, original: job.budgetLimit)
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

    private func changedRequiredText(_ value: String, original: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == original ? nil : trimmed
    }

    private func changedOptionalText(_ value: String, original: String?) -> String? {
        value == (original ?? "") ? nil : value
    }

    private func changedDouble(_ value: String, original: Double?) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalValue = original.map { String($0) } ?? ""
        if trimmed == originalValue || trimmed.isEmpty {
            return nil
        }
        return Double(trimmed)
    }

    private func shouldClearDouble(_ value: String, original: Double?) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && original != nil
    }

    private func validateNumericFields() -> Bool {
        if let message = numericValidationMessage(for: estimatedHours, label: "Estimated Hours") {
            errorMessage = message
            return false
        }
        if let message = numericValidationMessage(for: budgetLimit, label: "Budget Limit") {
            errorMessage = message
            return false
        }
        return true
    }

    private func numericValidationMessage(for value: String, label: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let number = Double(trimmed), number.isFinite else {
            return "\(label) must be a plain number, like 8 or 8.5. Clear the field to remove it."
        }
        guard number > 0 else {
            return "\(label) must be greater than zero. Clear the field to remove it."
        }
        return nil
    }
}
