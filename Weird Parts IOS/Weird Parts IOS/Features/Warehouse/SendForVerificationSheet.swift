import SwiftUI
import WiredPartCore

/// Flags a discrepancy for independent multi-user verification.
struct SendForVerificationSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let discrepancy: WarehouseService.AuditDiscrepancy
    let sessionId: Int64
    let onSent: () -> Void

    @State private var requiredCounts = 2
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Part") {
                    LabeledContent("Part", value: discrepancy.partName)
                    if let code = discrepancy.partCode, !code.isEmpty {
                        LabeledContent("Code", value: code)
                    }
                    LabeledContent("Location", value: "\(discrepancy.locationType.capitalized) #\(discrepancy.locationId)")
                }

                Section("Verification") {
                    Stepper("Required counters: \(requiredCounts)", value: $requiredCounts, in: 2...3)
                    Text("The current operator is excluded from assignments.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Send for Verification")
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
                        Button("Send") { submit() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func submit() {
        if ProcessInfo.processInfo.arguments.contains("-UITestingMultiUserVerificationForceNoEligibleUsers") {
            errorMessage = "No eligible active users are available to assign verification counts."
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestingMultiUserVerificationForceAlreadyFlagged") {
            errorMessage = "This part is already flagged for verification in the current audit session."
            return
        }

        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id else {
            errorMessage = "Service or user unavailable"
            return
        }

        isSaving = true
        errorMessage = nil
        do {
            _ = try service.flagForMultiUserAudit(
                partId: discrepancy.partId,
                expectedQty: discrepancy.systemQty,
                sessionId: sessionId,
                flaggedBy: userId,
                requiredCounts: requiredCounts
            )
            onSent()
            dismiss()
        } catch WarehouseService.WarehouseError.noEligibleVerificationCounters {
            errorMessage = "No eligible active users are available to assign verification counts."
        } catch WarehouseService.WarehouseError.partAlreadyFlaggedForVerification {
            errorMessage = "This part is already flagged for verification in the current audit session."
        } catch WarehouseService.WarehouseError.invalidQuantity {
            errorMessage = "Invalid count value. Try again with a non-negative quantity."
        } catch {
            errorMessage = userFriendlyError(error, context: "send for multi-user verification")
        }
        isSaving = false
    }
}
