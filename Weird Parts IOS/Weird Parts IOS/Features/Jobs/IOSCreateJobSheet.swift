import SwiftUI
import WiredPartCore

/// Job creation form presented as a sheet.
///
/// Collects job number, name, customer, address, type, priority,
/// dates, notes, and budget. On save, creates the job via JobsService.
struct IOSCreateJobSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    var onCreated: (() -> Void)?

    // Required
    @State private var jobNumber = ""
    @State private var jobName = ""

    // Customer & Address
    @State private var customerName = ""
    @State private var addressLine1 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""

    // Classification
    @State private var jobType = "service"
    @State private var jobClassification = "standard"
    @State private var priority = "normal"
    @State private var status = "active"

    // Dates
    @State private var startDate = Date()
    @State private var hasStartDate = false
    @State private var dueDate = Date()
    @State private var hasDueDate = false

    // Budget
    @State private var budgetLimit = ""
    @State private var estimatedHours = ""

    // Notes
    @State private var notes = ""

    // UI
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var stageTemplates: [JobsService.JobStageTemplate] = []
    @State private var selectedStageTemplateId: Int64?

    private let jobTypes = ["service", "installation", "maintenance", "inspection", "emergency", "warranty"]
    private let jobClassifications = ["standard", "continuous", "convention"]
    private let priorities = ["low", "normal", "high", "urgent"]

    private var isValid: Bool {
        !jobNumber.trimmingCharacters(in: .whitespaces).isEmpty
            && !jobName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info
                Section("Job Information") {
                    TextField("Job Number", text: $jobNumber)
                        .textContentType(.none)
                    TextField("Job Name", text: $jobName)
                    Picker("Type", selection: $jobType) {
                        ForEach(jobTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    Picker("Classification", selection: $jobClassification) {
                        ForEach(jobClassifications, id: \.self) { c in
                            Text(c.capitalized).tag(c)
                        }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { p in
                            Text(p.capitalized).tag(p)
                        }
                    }
                }

                // Customer
                Section("Customer") {
                    TextField("Customer Name", text: $customerName)
                        .textContentType(.organizationName)
                    TextField("Address", text: $addressLine1)
                        .textContentType(.streetAddressLine1)
                    HStack(spacing: 8) {
                        TextField("City", text: $city)
                            .textContentType(.addressCity)
                        TextField("State", text: $state)
                            .textContentType(.addressState)
                            .frame(width: 60)
                        TextField("ZIP", text: $zip)
                            .textContentType(.postalCode)
                            .keyboardType(.numberPad)
                            .frame(width: 70)
                    }
                }

                // Stage template
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
                        if let selected = stageTemplates.first(where: { $0.id == selectedStageTemplateId }) {
                            Text("\(selected.stageCount) stage workflow")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Dates
                Section("Schedule") {
                    Toggle("Start Date", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }

                // Budget
                Section("Budget") {
                    TextField("Estimated Hours", text: $estimatedHours)
                        .keyboardType(.decimalPad)
                    TextField("Budget Limit ($)", text: $budgetLimit)
                        .keyboardType(.decimalPad)
                }

                // Notes
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                // Error
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Create Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createJob() }
                        .fontWeight(.semibold)
                        .disabled(!isValid || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { loadStageTemplates() }
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
                selectedStageTemplateId = stageTemplates.first(where: { $0.isDefault })?.id ?? stageTemplates.first?.id
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "load stage templates")
        }
    }

    private func createJob() {
        guard let service = appCore.jobsService else {
            errorMessage = "Service not available"
            return
        }
        isSaving = true
        errorMessage = nil

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        do {
            let jobId = try service.createJob(
                jobNumber: jobNumber.trimmingCharacters(in: .whitespaces),
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
                startDate: hasStartDate ? dateFormatter.string(from: startDate) : nil,
                dueDate: hasDueDate ? dateFormatter.string(from: dueDate) : nil,
                notes: notes.isEmpty ? nil : notes,
                budgetLimit: Double(budgetLimit),
                createdBy: appCore.currentUser?.id,
                jobClassification: jobClassification
            )
            if let selectedStageTemplateId {
                try service.assignJobStageTemplate(jobId: jobId, templateId: selectedStageTemplateId)
            }
            appCore.onboardingManager?.markCompleted("jobs-create")
            onCreated?()
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "create job")
        }
        isSaving = false
    }
}
