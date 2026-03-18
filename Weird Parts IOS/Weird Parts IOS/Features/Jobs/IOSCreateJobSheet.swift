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

    private let jobTypes = ["service", "installation", "maintenance", "inspection", "emergency", "warranty"]
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
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .frame(width: 70)
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
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Budget Limit ($)", text: $budgetLimit)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
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
            .navigationTitle("Create Job")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        }
    }

    // MARK: - Actions

    private func createJob() {
        guard let service = appCore.jobsService else { return }
        isSaving = true
        errorMessage = nil

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        do {
            try service.createJob(
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
                createdBy: appCore.currentUser?.id
            )
            onCreated?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
