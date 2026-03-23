import SwiftUI
import WiredPartCore

/// Brands management page showing all part brands with their linked suppliers.
///
/// Uses a searchable list with swipe actions for edit/delete.
/// Tap a brand to view/edit details. Create new brands via the + button.
struct PartsBrandsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var brands: [BrandListRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    // Single active-sheet enum to avoid multiple .sheet conflicts
    enum ActiveSheet: Identifiable {
        case addBrand
        case detailBrand(BrandListRow)

        var id: String {
            switch self {
            case .addBrand: return "addBrand"
            case .detailBrand(let b): return "detail-\(b.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var brandToDelete: BrandListRow?
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading brands...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
            } else if filteredBrands.isEmpty {
                emptyState
            } else {
                brandsList
            }
        }
        .searchable(text: $searchText, prompt: "Search brands...")
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { activeSheet = .addBrand } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addBrand:
                BrandFormSheet(brand: nil) { await loadData() }
                    .environmentObject(appCore)
            case .detailBrand(let brandRow):
                BrandDetailSheet(brand: brandRow) { await loadData() }
                    .environmentObject(appCore)
            }
        }
        .background(DS.Background.page)
        .task { await loadData() }
        .alert("Delete Brand?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { brandToDelete = nil }
            Button("Delete", role: .destructive) {
                if let brand = brandToDelete {
                    Task { await deleteBrand(brand) }
                }
            }
        } message: {
            if let brand = brandToDelete {
                Text("Delete \"\(brand.name)\"? This cannot be undone. \(brand.partCount) part(s) use this brand.")
            }
        }
    }

    // MARK: - Filtered

    private var filteredBrands: [BrandListRow] {
        if searchText.isEmpty { return brands }
        let query = searchText.lowercased()
        return brands.filter {
            $0.name.lowercased().contains(query) ||
            ($0.website?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Brands List

    @ViewBuilder
    private var brandsList: some View {
        List {
            if let error = deleteError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section {
                Text("\(filteredBrands.count) brand\(filteredBrands.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(filteredBrands) { brand in
                Button {
                    activeSheet = .detailBrand(brand)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(brand.name)
                                .font(.body)
                                .fontWeight(.medium)

                            HStack(spacing: 8) {
                                if let website = brand.website, !website.isEmpty {
                                    Text(website)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(brand.partCount)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("parts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if brand.supplierCount > 0 {
                                Text("\(brand.supplierCount) supplier\(brand.supplierCount == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 56)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        brandToDelete = brand
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        activeSheet = .detailBrand(brand)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tag")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Brands Yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Add brands to organize your parts by manufacturer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                activeSheet = .addBrand
            } label: {
                Label("Add Brand", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        guard let service = appCore.partsService else {
            isLoading = false
            loadError = "Parts service not available."
            return
        }
        do {
            let result = try service.listBrands(search: searchText.isEmpty ? nil : searchText)
            brands = result.map { bwc in
                BrandListRow(
                    id: bwc.brand.id ?? 0,
                    name: bwc.brand.name,
                    website: bwc.brand.website,
                    notes: bwc.brand.notes,
                    partCount: bwc.partCount,
                    supplierCount: bwc.supplierCount
                )
            }
            isLoading = false
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Delete

    private func deleteBrand(_ brand: BrandListRow) async {
        guard let service = appCore.partsService else { return }
        do {
            try service.deleteBrand(id: brand.id)
            brandToDelete = nil
            deleteError = nil
            await loadData()
        } catch {
            deleteError = "Failed to delete \(brand.name): \(error.localizedDescription)"
        }
    }
}

// MARK: - Brand List Row

struct BrandListRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let website: String?
    let notes: String?
    let partCount: Int
    let supplierCount: Int
}

// MARK: - Brand Form Sheet

private struct BrandFormSheet: View {
    let brand: BrandListRow?
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var website = ""
    @State private var notes = ""
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section("Brand Details") {
                    TextField("Brand Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Website (optional)", text: $website)
                        .frame(minHeight: 44)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(brand == nil ? "New Brand" : "Edit Brand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveAndDismiss() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let b = brand {
                    name = b.name
                    website = b.website ?? ""
                    notes = b.notes ?? ""
                }
            }
        }
    }

    private func saveAndDismiss() async {
        isSaving = true
        saveError = nil
        do {
            try await save()
            await onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    private func save() async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        guard let service = appCore.partsService else { return }
        if let b = brand {
            try service.updateBrand(
                id: b.id,
                name: trimmedName,
                website: website.isEmpty ? nil : website,
                notes: notes.isEmpty ? nil : notes
            )
        } else {
            _ = try service.createBrand(
                name: trimmedName,
                website: website.isEmpty ? nil : website,
                notes: notes.isEmpty ? nil : notes
            )
        }
    }
}

// MARK: - Brand Detail Sheet

private struct BrandDetailSheet: View {
    let brand: BrandListRow
    let onUpdate: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var linkedSuppliers: [Supplier] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private enum DetailActiveSheet: Identifiable {
        case editBrand
        case supplierPicker

        var id: String {
            switch self {
            case .editBrand: return "editBrand"
            case .supplierPicker: return "supplierPicker"
            }
        }
    }

    @State private var activeDetailSheet: DetailActiveSheet?

    var body: some View {
        NavigationStack {
            List {
                // Brand Info
                Section("Brand Details") {
                    LabeledContent("Name", value: brand.name)
                    if let website = brand.website, !website.isEmpty {
                        LabeledContent("Website", value: website)
                    }
                    if let notes = brand.notes, !notes.isEmpty {
                        LabeledContent("Notes", value: notes)
                    }
                    LabeledContent("Parts Using This Brand", value: "\(brand.partCount)")
                }

                // Linked Suppliers
                Section {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    } else if let error = loadError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if linkedSuppliers.isEmpty {
                        Text("No suppliers linked to this brand yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(linkedSuppliers, id: \.id) { supplier in
                            HStack(spacing: 12) {
                                Image(systemName: "building.2.fill")
                                    .foregroundStyle(.blue)
                                    .frame(width: 32, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(supplier.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    if let phone = supplier.phone, !phone.isEmpty {
                                        Text(phone)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                } header: {
                    HStack {
                        Text("Suppliers That Carry This Brand")
                        Spacer()
                        Button {
                            activeDetailSheet = .supplierPicker
                        } label: {
                            Label("Manage", systemImage: "checklist")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle(brand.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeDetailSheet = .editBrand
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            .sheet(item: $activeDetailSheet) { sheet in
                switch sheet {
                case .editBrand:
                    BrandFormSheet(brand: brand) {
                        await onUpdate()
                    }
                    .environmentObject(appCore)
                case .supplierPicker:
                    BrandSupplierPickerSheet(brandId: brand.id) {
                        loadSuppliers()
                    }
                    .environmentObject(appCore)
                }
            }
            .task { loadSuppliers() }
        }
    }

    private func loadSuppliers() {
        isLoading = true
        loadError = nil
        do {
            guard let service = appCore.partsService else {
                isLoading = false
                loadError = "Parts service unavailable"
                return
            }
            linkedSuppliers = try service.getBrandSuppliers(brandId: brand.id)
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Brand Supplier Picker Sheet

struct BrandSupplierPickerSheet: View {
    let brandId: Int64
    let onSave: () -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var allSuppliers: [SupplierCheckItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isSaving = false
    @State private var searchText = ""

    struct SupplierCheckItem: Identifiable {
        let id: Int64
        let name: String
        let phone: String?
        let contactName: String?
        var isLinked: Bool
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading suppliers...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    VStack(spacing: 12) {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                        Button("Retry") { loadSuppliers() }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if allSuppliers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "building.2")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Suppliers")
                            .font(.headline)
                        Text("Add suppliers in Parts > Suppliers first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    supplierList
                }
            }
            .navigationTitle("Manage Suppliers")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search suppliers...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveLinks() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task { loadSuppliers() }
        }
    }

    // MARK: - Filtered List

    private var filteredSuppliers: [SupplierCheckItem] {
        if searchText.isEmpty { return allSuppliers }
        let query = searchText.lowercased()
        return allSuppliers.filter {
            $0.name.lowercased().contains(query) ||
            ($0.contactName?.lowercased().contains(query) ?? false) ||
            ($0.phone?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Supplier List

    @ViewBuilder
    private var supplierList: some View {
        List {
            // Summary
            let linkedCount = allSuppliers.filter(\.isLinked).count
            Section {
                Text("\(linkedCount) of \(allSuppliers.count) suppliers selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Checkbox rows
            ForEach(filteredSuppliers) { supplier in
                Button {
                    toggleSupplier(supplier.id)
                } label: {
                    HStack(spacing: 14) {
                        // Checkbox
                        Image(systemName: supplier.isLinked ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(supplier.isLinked ? Color.accentColor : .secondary)
                            .frame(width: 28)

                        // Supplier info
                        VStack(alignment: .leading, spacing: 3) {
                            Text(supplier.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            if let contact = supplier.contactName, !contact.isEmpty {
                                Text(contact)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let phone = supplier.phone, !phone.isEmpty {
                            Text(phone)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Toggle

    private func toggleSupplier(_ supplierId: Int64) {
        if let index = allSuppliers.firstIndex(where: { $0.id == supplierId }) {
            allSuppliers[index].isLinked.toggle()
        }
    }

    // MARK: - Load

    private func loadSuppliers() {
        isLoading = true
        loadError = nil
        do {
            guard let service = appCore.partsService else {
                isLoading = false
                loadError = "Parts service not available"
                return
            }

            // Get all active suppliers via service
            let allItems = try service.listSuppliers()

            // Get currently linked suppliers for this brand
            let linked = try service.getBrandSuppliers(brandId: brandId)
            let linkedIds = Set(linked.compactMap { $0.id })

            // Build check items
            allSuppliers = allItems.map { item in
                let s = item.supplier
                return SupplierCheckItem(
                    id: s.id ?? 0,
                    name: s.name,
                    phone: s.phone,
                    contactName: s.contactName,
                    isLinked: linkedIds.contains(s.id ?? 0)
                )
            }
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Save

    private func saveLinks() async {
        isSaving = true
        do {
            guard let service = appCore.partsService else {
                isSaving = false
                return
            }
            let selectedIds = Set(allSuppliers.filter(\.isLinked).map(\.id))
            try service.setBrandSuppliers(brandId: brandId, supplierIds: selectedIds)
            await MainActor.run {
                isSaving = false
                onSave()
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSaving = false
                loadError = error.localizedDescription
            }
        }
    }
}
