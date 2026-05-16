import SwiftUI
import WiredPartCore

/// Operator inbox for pending multi-user verification assignments.
struct IOSMyVerificationsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var assignments: [MultiUserAuditAssignment] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedAssignment: MultiUserAuditAssignment?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading assignments...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ErrorStateView(message: loadError) { loadData() }
            } else if assignments.isEmpty {
                ContentUnavailableView(
                    "No Pending Verifications",
                    systemImage: "checkmark.seal",
                    description: Text("You have no multi-user verification assignments right now.")
                )
            } else {
                List(assignments, id: \.id) { assignment in
                    Button {
                        selectedAssignment = assignment
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.badge.gearshape")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(assignment.partName)
                                    .fontWeight(.medium)
                                if let bin = assignment.binLocation, !bin.isEmpty {
                                    Text(bin)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospaced()
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.insetGrouped)
                .refreshable { loadData() }
            }
        }
        .navigationTitle("My Verifications")
        .sheet(item: $selectedAssignment) { assignment in
            MyVerificationSubmitSheet(assignment: assignment) {
                selectedAssignment = nil
                loadData()
            }
            .environmentObject(appCore)
        }
        .task { loadData() }
    }

    private func loadData() {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id else {
            isLoading = false
            loadError = "Service or user unavailable"
            return
        }

        isLoading = assignments.isEmpty
        loadError = nil
        do {
            assignments = try service.getMyMultiUserAuditAssignments(userId: userId)
        } catch {
            loadError = userFriendlyError(error, context: "load verification assignments")
        }
        isLoading = false
    }
}

private struct MyVerificationSubmitSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let assignment: MultiUserAuditAssignment
    let onSubmitted: () -> Void

    @State private var countedQuantity = 0
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Assignment") {
                    LabeledContent("Part", value: assignment.partName)
                    if let bin = assignment.binLocation, !bin.isEmpty {
                        LabeledContent("Location", value: bin)
                    }
                }
                Section("Your Count") {
                    Stepper("Counted quantity: \(countedQuantity)", value: $countedQuantity, in: 0...9999)
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Submit Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button("Submit") { submit() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                countedQuantity = assignment.countedQuantity ?? 0
                notes = assignment.notes ?? ""
            }
        }
    }

    private func submit() {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id,
              let assignmentId = assignment.id else {
            errorMessage = "Assignment unavailable. Reload and try again."
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            try service.submitMultiUserCount(
                assignmentId: assignmentId,
                quantity: countedQuantity,
                userId: userId,
                notes: notes.isEmpty ? nil : notes
            )
            onSubmitted()
            dismiss()
        } catch WarehouseService.WarehouseError.sessionNotFound {
            errorMessage = "This verification assignment is no longer available."
        } catch WarehouseService.WarehouseError.sessionAlreadyCompleted {
            errorMessage = "This verification assignment was already submitted."
        } catch WarehouseService.WarehouseError.invalidQuantity {
            errorMessage = "Count must be 0 or greater."
        } catch {
            errorMessage = userFriendlyError(error, context: "submit verification count")
        }
        isSaving = false
    }
}
