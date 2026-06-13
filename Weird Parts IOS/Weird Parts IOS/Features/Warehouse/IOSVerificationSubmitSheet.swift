import SwiftUI
import WiredPartCore

/// Sheet that lets an assigned counter submit their physical count for a
/// multi-user verification assignment.
///
/// Used from both `IOSMyVerificationsPage` and the `IOSAuditPage`
/// "My Verification Assignments" entry point.
///
/// When the counter tries to submit a second time the service throws
/// `WarehouseService.WarehouseError.sessionAlreadyCompleted`; this sheet
/// surfaces the GH#486 QA acceptance copy for that case.
struct IOSVerificationSubmitSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let assignment: MultiUserAuditAssignment
    let onSubmitted: () -> Void

    @State private var countInput = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Part") {
                    LabeledContent("Part", value: assignment.partName)
                    if let bin = assignment.binLocation, !bin.isEmpty {
                        LabeledContent("Location", value: bin)
                    }
                }

                Section("Your Count") {
                    TextField("Enter quantity", text: $countInput)
                        .keyboardType(.numberPad)
                }

                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Notes")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Submit Count")
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
                            .disabled(countInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func submit() {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id,
              let assignmentId = assignment.id,
              let qty = Int(countInput.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = "Enter a valid count before submitting."
            return
        }

        isSaving = true
        errorMessage = nil
        do {
            try service.submitMultiUserCount(
                assignmentId: assignmentId,
                quantity: qty,
                userId: userId,
                notes: notes.isEmpty ? nil : notes
            )
            onSubmitted()
            dismiss()
        } catch {
            errorMessage = VerificationSubmitSheetDuplicateSubmitCopy.message(for: error)
                ?? userFriendlyError(error, context: "submit verification count")
        }
        isSaving = false
    }
}

enum VerificationSubmitSheetDuplicateSubmitCopy {
    static let exactCopy = "You've already submitted a count for this part. Each counter can submit once."

    static func message(for error: Error) -> String? {
        guard case WarehouseService.WarehouseError.sessionAlreadyCompleted = error else {
            return nil
        }
        return exactCopy
    }
}
