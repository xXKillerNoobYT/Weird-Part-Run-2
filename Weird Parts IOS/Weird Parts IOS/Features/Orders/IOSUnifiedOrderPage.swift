import SwiftUI
import WiredPartCore

/// Unified order creation form.
///
/// Combines job selection, part search, and cart into a single flow
/// for creating new Job Purchase Orders.
struct IOSUnifiedOrderPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var selectedJobId: Int64?
    @State private var priority = "normal"
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var loadError: String?

    private let priorities = ["low", "normal", "high", "urgent"]

    var body: some View {
        NavigationStack {
            Form {
                // Job Selection
                Section("Select Job") {
                    if jobs.isEmpty {
                        Text("Loading jobs...")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Job", selection: $selectedJobId) {
                            Text("Select a job...").tag(nil as Int64?)
                            ForEach(jobs, id: \.id) { job in
                                Text("\(job.jobNumber) — \(job.jobName)").tag(job.id as Int64?)
                            }
                        }
                    }
                }

                // Priority
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { p in
                            Text(p.capitalized).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Notes
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                // Info
                Section {
                    Text("After creating the order request, you can add line items from the JPO detail page.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Order Request")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createOrder() }
                        .fontWeight(.semibold)
                        .disabled(selectedJobId == nil || isSaving)
                }
            }
            .task { loadJobs() }
        }
    }

    // MARK: - Actions

    private func loadJobs() {
        guard let service = appCore.jobsService else { return }
        do {
            jobs = try service.listJobs(status: "active")
        } catch {
            print("[IOSUnifiedOrderPage] Load jobs error: \(error)")
            loadError = error.localizedDescription
        }
    }

    private func createOrder() {
        guard let service = appCore.ordersService,
              let jobId = selectedJobId,
              let userId = appCore.currentUser?.id else { return }
        isSaving = true
        errorMessage = nil

        do {
            _ = try service.createJPO(
                jobId: jobId,
                requestedBy: userId,
                priority: priority,
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
