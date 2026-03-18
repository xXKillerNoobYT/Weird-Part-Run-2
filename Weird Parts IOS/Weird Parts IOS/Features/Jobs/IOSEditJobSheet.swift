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
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .frame(width: 70)
                    }
                }

                Section("Budget") {
                    TextField("Estimated Hours", text: $estimatedHours)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Budget Limit ($)", text: $budgetLimit)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
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
            .navigationTitle("Edit Job")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        }
    }

    // MARK: - Actions

    private func saveJob() {
        guard let service = appCore.jobsService else { return }
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
            onUpdated?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
