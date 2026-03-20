import SwiftUI
import WiredPartCore

/// Sheet for picking a supplier to generate a PO from a JPO.
///
/// Displays a searchable list of suppliers. On selection, calls
/// `OrdersService.generatePOFromJPO(jpoId:supplierId:)` and dismisses.
struct SupplierPickerSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let jpoId: Int64
    var onGenerated: () -> Void

    @State private var suppliers: [PartsService.SupplierWithCount] = []
    @State private var searchText = ""
    @State private var isGenerating = false
    @State private var generateError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if suppliers.isEmpty {
                    ContentUnavailableView {
                        Label("No Suppliers", systemImage: "building.2")
                    } description: {
                        Text("Add suppliers in the Parts section first.")
                    }
                } else {
                    List(filteredSuppliers, id: \.supplier.id) { item in
                        Button {
                            generatePO(supplierId: item.supplier.id!)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.supplier.name)
                                        .foregroundStyle(.primary)
                                        .fontWeight(.medium)
                                    if let contact = item.supplier.contactName, !contact.isEmpty {
                                        Text(contact)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isGenerating)
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #endif
                }

                if let error = generateError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .navigationTitle("Select Supplier")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Search suppliers...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isGenerating {
                    ProgressView("Generating PO...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .task { loadSuppliers() }
        }
    }

    private var filteredSuppliers: [PartsService.SupplierWithCount] {
        guard !searchText.isEmpty else { return suppliers }
        let query = searchText.lowercased()
        return suppliers.filter {
            $0.supplier.name.lowercased().contains(query)
        }
    }

    private func loadSuppliers() {
        guard let service = appCore.partsService else { return }
        do {
            suppliers = try service.listSuppliers()
        } catch {
            print("[SupplierPickerSheet] Load error: \(error)")
        }
    }

    private func generatePO(supplierId: Int64) {
        guard let service = appCore.ordersService else { return }
        isGenerating = true
        generateError = nil
        do {
            _ = try service.generatePOFromJPO(jpoId: jpoId, supplierId: supplierId)
            onGenerated()
            dismiss()
        } catch {
            generateError = error.localizedDescription
        }
        isGenerating = false
    }
}
