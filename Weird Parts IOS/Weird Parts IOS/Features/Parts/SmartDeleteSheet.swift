import SwiftUI
import WiredPartCore

/// Smart deletion sheet that checks inventory before deleting.
/// If inventory exists, offers "Empty Shelf Mode" instead of immediate delete.
struct SmartDeleteSheet: View {
    let entityType: String        // "category", "style", "type", etc.
    let entityId: Int64
    let entityName: String
    var onComplete: () async -> Void

    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var inventoryCheck: PartsService.InventoryCheck?
    @State private var isLoading = true
    @State private var isProcessing = false
    @State private var error: String?
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Checking inventory...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let check = inventoryCheck {
                    deleteContent(check)
                }
            }
            .navigationTitle("Delete \(entityName)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await checkInventory() }
        }
        .interactiveDismissDisabled(isProcessing)
    }

    @ViewBuilder
    private func deleteContent(_ check: PartsService.InventoryCheck) -> some View {
        Form {
            if check.hasInventory {
                // Has stock — show Empty Shelf Mode option
                Section {
                    Label("This \(entityType) has \(check.totalStock) items in stock across \(check.partsWithStock.count) part(s).", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                } header: {
                    Text("Inventory Found")
                }

                // Show parts with stock
                Section("Parts with Stock") {
                    ForEach(check.partsWithStock, id: \.partId) { part in
                        HStack {
                            Text(part.partName)
                                .font(.subheadline)
                            Spacer()
                            Text("\(part.stock) in stock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Alternative part recommendations
                if !check.alternativeParts.isEmpty {
                    Section("Recommended Replacements") {
                        ForEach(check.alternativeParts, id: \.partId) { alt in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Switch from **\(alt.partName)**")
                                    .font(.subheadline)
                                Label("Use **\(alt.alternativeName)** instead", systemImage: "arrow.right.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    TextField("Reason for removal (optional)", text: $reason)
                        .frame(minHeight: 44)
                }

                Section {
                    Button {
                        Task { await startEmptyShelfMode() }
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start Empty Shelf Mode")
                                    .fontWeight(.semibold)
                                Text("Stock targets set to 0. Once stock is fully used, a 30-day timer starts. Final approval required.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isProcessing)
                } header: {
                    Text("Action")
                }

            } else {
                // No stock — safe to delete immediately (still confirm)
                Section {
                    Label("No inventory found. Safe to delete.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }

                if !check.alternativeParts.isEmpty {
                    Section("Note: Alternative Parts Exist") {
                        ForEach(check.alternativeParts, id: \.partId) { alt in
                            Text("**\(alt.partName)** has alternative **\(alt.alternativeName)**")
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await deleteImmediately() }
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                            }
                            Text("Delete Now")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isProcessing)
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Actions

    private func checkInventory() async {
        guard let service = appCore.partsService else {
            error = "Parts service not available"
            isLoading = false
            return
        }
        do {
            inventoryCheck = try service.checkInventoryForDeletion(entityType: entityType, entityId: entityId)
        } catch {
            self.error = userFriendlyError(error, context: "delete parts")
        }
        isLoading = false
    }

    private func startEmptyShelfMode() async {
        guard let service = appCore.partsService else {
            error = "Service not available"
            return
        }
        isProcessing = true
        do {
            _ = try service.scheduleEmptyShelfDeletion(
                entityType: entityType, entityId: entityId, entityName: entityName,
                reason: reason.isEmpty ? nil : reason, scheduledBy: nil
            )
            await onComplete()
            dismiss()
        } catch {
            self.error = userFriendlyError(error, context: "delete parts")
        }
        isProcessing = false
    }

    private func deleteImmediately() async {
        guard let service = appCore.partsService else {
            error = "Service not available"
            return
        }
        isProcessing = true
        do {
            // Direct soft-delete via existing service methods
            switch entityType {
            case "category": try service.deleteCategory(id: entityId)
            case "style": try service.deleteStyle(id: entityId)
            case "type": try service.deleteType(id: entityId)
            case "brand": try service.deleteBrand(id: entityId)
            case "color": try service.deleteColor(id: entityId)
            default: break
            }
            await onComplete()
            dismiss()
        } catch {
            self.error = userFriendlyError(error, context: "delete parts")
        }
        isProcessing = false
    }
}
