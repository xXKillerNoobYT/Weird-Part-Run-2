import SwiftUI
import WiredPartCore

/// Sheet for creating a new purchase order.
///
/// Lets the user pick a supplier, enter a PO number (auto-generated default),
/// optional notes, and save. Calls `OrdersService.createPurchaseOrder`.
struct CreatePOSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    var onSave: () -> Void

    @State private var poNumber = ""
    @State private var selectedSupplierId: Int64?
    @State private var notes = ""
    @State private var suppliers: [PartsService.SupplierWithCount] = []
    @State private var supplierSearch = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("PO Number") {
                    TextField("e.g. PO-00042", text: $poNumber)
                        .font(.system(.body, design: .monospaced))
                }

                Section("Supplier") {
                    TextField("Search suppliers...", text: $supplierSearch)
                        .onChange(of: supplierSearch) { loadSuppliers() }

                    if suppliers.isEmpty {
                        Text("No suppliers found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(suppliers, id: \.supplier.id) { item in
                            Button {
                                selectedSupplierId = item.supplier.id
                            } label: {
                                HStack {
                                    Text(item.supplier.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedSupplierId == item.supplier.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Purchase Order")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { savePO() }
                        .disabled(poNumber.isEmpty || selectedSupplierId == nil || isSaving)
                        .fontWeight(.semibold)
                }
            }
            .task {
                generatePONumber()
                loadSuppliers()
            }
        }
    }

    private func generatePONumber() {
        guard let service = appCore.ordersService else { return }
        do {
            let existing = try service.listPurchaseOrders(status: nil)
            poNumber = String(format: "PO-%05d", existing.count + 1)
        } catch {
            poNumber = "PO-NEW"
        }
    }

    private func loadSuppliers() {
        guard let service = appCore.partsService else { return }
        do {
            suppliers = try service.listSuppliers(
                search: supplierSearch.isEmpty ? nil : supplierSearch
            )
        } catch {
            print("[CreatePOSheet] Load suppliers error: \(error)")
        }
    }

    private func savePO() {
        guard let service = appCore.ordersService,
              let supplierId = selectedSupplierId else { return }
        isSaving = true
        saveError = nil
        do {
            _ = try service.createPurchaseOrder(
                poNumber: poNumber,
                supplierId: supplierId,
                notes: notes.isEmpty ? nil : notes
            )
            onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
