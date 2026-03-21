# Fix Prompt 11C: Supplier Checkbox Picker for Brands

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.
>
> **DEPENDS ON:** Prompts 11A and 11B must be completed first.
> - 11A added `linkBrandToSupplier`, `unlinkBrandFromSupplier`, and `setBrandSuppliers` to `core/Sources/WiredPartCore/Services/PartsService.swift`
> - 11B added `BrandDetailSheet` to `Weird Parts IOS/Features/Parts/PartsBrandsPage.swift` which references `BrandSupplierPickerSheet` — this prompt creates that view.

---

## What the User Wants

Inside the brand detail sheet, there's a "Manage" button in the Suppliers section header. Tapping it should open a full-screen checklist of ALL suppliers in the system. Suppliers already linked to this brand have their checkbox checked. The user checks/unchecks suppliers and taps "Save" — the links are updated in the database.

---

## File To Edit

**`Weird Parts IOS/Features/Parts/PartsBrandsPage.swift`**

Add this struct at the bottom of the file, after `BrandDetailSheet`:

```swift
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
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
            guard let db = appCore.db else {
                isLoading = false
                loadError = "Database not available"
                return
            }
            guard let service = appCore.partsService else {
                isLoading = false
                loadError = "Parts service not available"
                return
            }

            // Get all active suppliers
            let allRows = try db.writer.read { dbConn -> [(Int64, String, String?, String?)] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT id, name, phone, contact_name
                    FROM suppliers
                    WHERE deleted_at IS NULL AND is_active = 1
                    ORDER BY name ASC
                    """)
                return rows.map { ($0["id"] as Int64, $0["name"] as String, $0["phone"], $0["contact_name"]) }
            }

            // Get currently linked suppliers for this brand
            let linked = try service.getBrandSuppliers(brandId: brandId)
            let linkedIds = Set(linked.compactMap { $0.id })

            // Build check items
            allSuppliers = allRows.map { (id, name, phone, contact) in
                SupplierCheckItem(
                    id: id,
                    name: name,
                    phone: phone,
                    contactName: contact,
                    isLinked: linkedIds.contains(id)
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
```

---

## Success Criteria

1. **Build succeeds** — no compile errors
2. Brand detail sheet → tap "Manage" → supplier picker opens
3. Picker shows ALL active suppliers with checkboxes
4. Suppliers already linked to this brand are pre-checked
5. User can check/uncheck suppliers freely
6. Tap "Save" → links update in database → picker closes → detail sheet shows updated list
7. Tap "Cancel" → no changes saved
8. Search bar filters the supplier list by name, contact, or phone
9. Summary line shows "3 of 12 suppliers selected" (updates live as you check/uncheck)
10. If no suppliers exist in the system, shows "Add suppliers in Parts > Suppliers first"

---

## Full User Flow Test

1. Navigate to **Parts > Brands**
2. Tap **"Lutron"** → Brand Detail Sheet opens
3. See brand info (name, website, notes, part count)
4. See "Suppliers That Carry This Brand" section — empty or showing linked suppliers
5. Tap **"Manage"** button in section header
6. Supplier Picker opens showing all suppliers with checkboxes
7. Check **"Home Depot Supply"** and **"Graybar"** → summary shows "2 of X selected"
8. Tap **"Save"**
9. Back on detail sheet — now shows Home Depot Supply and Graybar with green checkmarks
10. Tap **"Done"** → back to brands list
11. Lutron row now shows "2 suppliers" under the part count

---

## All 11A-11B-11C Prompts Complete

The brand-supplier linking feature is fully implemented across three layers:
- **11A:** Service methods (link, unlink, set)
- **11B:** Brand detail sheet with supplier list display
- **11C:** Checkbox picker for managing links
