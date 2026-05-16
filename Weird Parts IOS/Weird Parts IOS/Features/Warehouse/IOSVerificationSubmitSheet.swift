import SwiftUI
import WiredPartCore

/// Shared sheet for submitting an independent multi-user verification count.
struct IOSVerificationSubmitSheet: View {
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
                    if isSaving {
                        ProgressView()
                    } else {
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
        if ProcessInfo.processInfo.arguments.contains("-UITestingMultiUserVerificationForceDuplicateSubmit") {
            errorMessage = "You've already submitted a count for this part. Each counter can submit once."
            return
        }

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
            errorMessage = "You've already submitted a count for this part. Each counter can submit once."
        } catch WarehouseService.WarehouseError.invalidQuantity {
            errorMessage = "Count must be 0 or greater."
        } catch {
            errorMessage = userFriendlyError(error, context: "submit verification count")
        }
        isSaving = false
    }
}
