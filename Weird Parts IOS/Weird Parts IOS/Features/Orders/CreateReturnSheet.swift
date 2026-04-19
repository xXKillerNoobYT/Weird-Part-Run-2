import SwiftUI
import WiredPartCore

/// Sheet for creating a new return.
///
/// Lets the user pick a return type, enter a reason, optionally select a
/// supplier, and save. Calls `OrdersService.createReturn`.
struct CreateReturnSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    var onSave: () -> Void

    @State private var returnType = "defective"
    @State private var reason = ""
    @State private var selectedSupplierId: Int64?
    @State private var suppliers: [PartsService.SupplierWithCount] = []
    @State private var isSaving = false
    @State private var saveError: String?

    private let returnTypes = ["defective", "wrong_item", "overstock", "warranty", "other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Return Type") {
                    Picker("Type", selection: $returnType) {
                        ForEach(returnTypes, id: \.self) { type in
                            Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Reason") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 80)
                }

                Section("Supplier (Optional)") {
                    if suppliers.isEmpty {
                        Text("No suppliers available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Supplier", selection: $selectedSupplierId) {
                            Text("None").tag(nil as Int64?)
                            ForEach(suppliers, id: \.supplier.id) { item in
                                Text(item.supplier.name).tag(item.supplier.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Return")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create") { saveReturn() }
                            .disabled(reason.isEmpty)
                            .fontWeight(.semibold)
                    }
                }
            }
            .task { loadSuppliers() }
        }
    }

    private func loadSuppliers() {
        guard let service = appCore.partsService else {
            saveError = "Parts service not available"
            return
        }
        do {
            suppliers = try service.listSuppliers()
        } catch {
            saveError = userFriendlyError(error, context: "load suppliers")
        }
    }

    private func saveReturn() {
        guard let service = appCore.ordersService else {
            saveError = "Orders service not available"
            return
        }
        isSaving = true
        saveError = nil
        do {
            _ = try service.createReturn(
                returnType: returnType,
                reason: reason,
                supplierId: selectedSupplierId
            )
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "create return")
        }
        isSaving = false
    }
}
