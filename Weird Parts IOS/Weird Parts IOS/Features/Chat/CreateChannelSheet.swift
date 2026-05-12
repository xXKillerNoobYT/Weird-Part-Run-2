import SwiftUI
import WiredPartCore

/// Sheet for creating a new chat channel or DM.
struct CreateChannelSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let channelType: String
    var onSave: () -> Void

    @State private var channelName = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var saveError: String?

    // Supplier channel state
    @State private var selectedSupplierId: Int64 = 0
    @State private var suppliers: [PartsService.SupplierWithCount] = []
    @State private var isLoadingSuppliers = false
    @State private var supplierLoadError: String?

    private var isDM: Bool { channelType == "dm" }
    private var isSupplier: Bool { channelType == "supplier" }

    var body: some View {
        NavigationStack {
            Form {
                if isSupplier {
                    Section("Supplier") {
                        if isLoadingSuppliers && suppliers.isEmpty {
                            ProgressView("Loading suppliers...")
                        }

                        Picker("Select Supplier", selection: $selectedSupplierId) {
                            Text("Choose...").tag(Int64(0))
                            ForEach(suppliers, id: \.supplier.id) { item in
                                Text(item.supplier.name).tag(item.supplier.id ?? Int64(0))
                            }
                        }
                        .disabled(isLoadingSuppliers)

                        if let error = supplierLoadError {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                    Section("Channel Name (Optional)") {
                        TextField("Auto-generated if blank", text: $channelName)
                    }
                } else {
                    Section(isDM ? "Conversation Name" : "Channel Name") {
                        TextField(isDM ? "e.g. John & Jane" : "e.g. general-chat", text: $channelName)
                    }

                    if !isDM {
                        Section("Description (Optional)") {
                            TextEditor(text: $description)
                                .frame(minHeight: 60)
                        }
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
            .navigationTitle(isSupplier ? "Supplier Channel" : (isDM ? "New Message" : "New Channel"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                await loadSuppliers()
            }
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { saveChannel() }
                        .disabled(isCreateDisabled || isSaving)
                        .fontWeight(.semibold)
                }
            }
            .task {
                await loadSuppliers()
            }
        }
    }

    private var isCreateDisabled: Bool {
        if isSupplier { return selectedSupplierId == 0 }
        return channelName.isEmpty
    }

    @MainActor
    private func loadSuppliers() async {
        guard isSupplier, !isLoadingSuppliers, !isSaving else { return }

        isLoadingSuppliers = true
        supplierLoadError = nil
        defer { isLoadingSuppliers = false }

        guard let service = appCore.partsService else {
            supplierLoadError = "Parts service not available"
            return
        }

        do {
            suppliers = try service.listSuppliers()
            if selectedSupplierId != 0 && !suppliers.contains(where: { ($0.supplier.id ?? 0) == selectedSupplierId }) {
                selectedSupplierId = 0
            }
        } catch {
            supplierLoadError = userFriendlyError(error, context: "load suppliers")
        }
    }

    private func saveChannel() {
        guard let service = appCore.chatService,
              let userId = appCore.currentUser?.id else {
            saveError = "Chat service not available"
            return
        }
        isSaving = true
        saveError = nil
        do {
            if isSupplier {
                let supplier = suppliers.first(where: { ($0.supplier.id ?? 0) == selectedSupplierId })
                let displayName = supplier?.supplier.contactName ?? supplier?.supplier.name ?? "Supplier"
                let name = channelName.isEmpty ? "Channel: \(supplier?.supplier.name ?? "Supplier")" : channelName
                _ = try service.createSupplierChannel(
                    name: name,
                    supplierId: selectedSupplierId,
                    supplierDisplayName: displayName,
                    contactId: nil,
                    role: nil,
                    createdBy: userId
                )
            } else {
                _ = try service.createChannel(
                    name: channelName,
                    channelType: channelType,
                    createdBy: userId
                )
            }
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}
