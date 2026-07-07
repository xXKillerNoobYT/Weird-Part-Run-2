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
    @State private var loadError: String?
    private enum POSheet: Identifiable {
        case supplierScanner
        var id: String { "supplierScanner" }
    }
    @State private var activePOSheet: POSheet?

    var body: some View {
        NavigationStack {
            Form {
                Section("PO Number") {
                    TextField("e.g. PO-00042", text: $poNumber)
                        .font(.system(.body, design: .monospaced))
                }

                Section("Supplier") {
                    HStack {
                        TextField("Search suppliers...", text: $supplierSearch)
                            .onChange(of: supplierSearch) { loadSuppliers() }
                        Button {
                            activePOSheet = .supplierScanner
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Scan supplier QR code")
                        .accessibilityHint("Opens the camera to scan a supplier code.")
                        .accessibilityIdentifier("orders-create-po-scan-supplier-qr")
                    }

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
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .accessibilityLabel("Supplier \(item.supplier.name)")
                            .accessibilityValue(selectedSupplierId == item.supplier.id ? "Selected" : "Not selected")
                            .accessibilityHint("Selects this supplier for the new purchase order.")
                            .accessibilityIdentifier("orders-create-po-supplier-row-\(item.supplier.id.map(String.init) ?? item.supplier.name.lowercased().replacingOccurrences(of: " ", with: "-"))")
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
            // Fix #149: dismiss keyboard when scrolling PO form
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Purchase Order")
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
                        Button("Create") { savePO() }
                            .disabled(poNumber.isEmpty || selectedSupplierId == nil)
                            .fontWeight(.semibold)
                    }
                }
            }
            .task {
                generatePONumber()
                loadSuppliers()
            }
            .sheet(item: $activePOSheet) { sheet in
                switch sheet {
                case .supplierScanner:
                    QRScanSheet(expectedType: .supplier) { result in
                        if let supplierId = result.entityId, result.isFound {
                            selectedSupplierId = supplierId
                            supplierSearch = result.fields["name"] ?? ""
                        }
                    }
                    .environmentObject(appCore)
                }
            }
            .alert("Error", isPresented: Binding<Bool>(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("OK") { loadError = nil }
            } message: {
                Text(loadError ?? "")
            }
        }
    }

    private func generatePONumber() {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            return
        }
        do {
            let existing = try service.listPurchaseOrders(status: nil)
            poNumber = String(format: "PO-%05d", existing.count + 1)
        } catch {
            poNumber = "PO-NEW"
        }
    }

    private func loadSuppliers() {
        guard let service = appCore.partsService else {
            loadError = "Service not available"
            return
        }
        do {
            suppliers = try service.listSuppliers(
                search: supplierSearch.isEmpty ? nil : supplierSearch
            )
        } catch {
            loadError = userFriendlyError(error, context: "load PO data")
        }
    }

    private func savePO() {
        guard let service = appCore.ordersService,
              let supplierId = selectedSupplierId else {
            saveError = "Orders service not available"
            return
        }
        isSaving = true
        saveError = nil
        do {
            _ = try service.createPurchaseOrder(
                poNumber: poNumber,
                supplierId: supplierId,
                notes: notes.isEmpty ? nil : notes
            )
            appCore.onboardingManager?.markCompleted("po-create")
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save order")
        }
        isSaving = false
    }
}
