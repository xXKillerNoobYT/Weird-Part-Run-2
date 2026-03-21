# Fix Prompt 11B: Brand Detail Sheet With Supplier List

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.
>
> **DEPENDS ON:** Prompt 11A must be completed first. It adds `getBrandSuppliers(brandId:)`, `linkBrandToSupplier(brandId:supplierId:)`, `unlinkBrandFromSupplier(brandId:supplierId:)`, and `setBrandSuppliers(brandId:supplierIds:)` to `PartsService.swift`.

---

## What the User Wants

Right now, tapping a brand on the Brands page opens a simple edit form (name, website, notes). The user wants to see which suppliers carry that brand — and manage those links — without leaving the brand view. The flow should be:

1. Tap "Lutron" → opens **Brand Detail Sheet** showing brand info + list of linked suppliers
2. Tap "Manage Suppliers" → opens **Supplier Picker** (prompt 11C) with checkboxes
3. Check/uncheck suppliers → save → back to detail → supplier list is updated

---

## File To Edit

**`Weird Parts IOS/Features/Parts/PartsBrandsPage.swift`**

### Step 1: Change What Happens When You Tap a Brand Row

Currently (line 74-75), tapping a brand opens `BrandFormSheet` for editing:

```swift
Button {
    editingBrand = brand
} label: {
```

Change this so tapping opens a **new `BrandDetailSheet`** instead. Keep the edit form as a sub-action inside the detail sheet.

Replace the `editingBrand` state and sheet (lines 15, 40-42):

```swift
// REMOVE this:
@State private var editingBrand: BrandListRow?

// REPLACE with:
@State private var selectedBrand: BrandListRow?
```

Replace the `.sheet(item: $editingBrand)` (line 40) with:

```swift
.sheet(item: $selectedBrand) { brandRow in
    BrandDetailSheet(brand: brandRow) { await loadData() }
}
```

Update the row tap action (line 74-75):

```swift
Button {
    selectedBrand = brand
} label: {
```

Update the swipe edit action (line 128-130):

```swift
Button {
    selectedBrand = brand
} label: {
    Label("Edit", systemImage: "pencil")
}
.tint(.orange)
```

### Step 2: Also Show Supplier Count on the Brand Row

In `brandsList`, update the right side of each row to show supplier count alongside part count. This requires loading supplier counts in `loadData()`.

Update `BrandListRow` to include supplier count:

```swift
struct BrandListRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let website: String?
    let notes: String?
    let partCount: Int
    let supplierCount: Int   // ADD THIS
}
```

Update the SQL in `loadData()` to join supplier count:

```swift
let results = try Row.fetchAll(dbConnection, sql: """
    SELECT b.*,
           COUNT(DISTINCT p.id) AS part_count,
           COALESCE((SELECT COUNT(*) FROM brand_supplier_links bsl
                     WHERE bsl.brand_id = b.id AND bsl.deleted_at IS NULL), 0) AS supplier_count
    FROM brands b
    LEFT JOIN parts p ON p.brand_id = b.id AND p.deleted_at IS NULL
    WHERE b.deleted_at IS NULL
    GROUP BY b.id
    ORDER BY b.name ASC
    """)
```

Update the row mapping to include it:

```swift
BrandListRow(
    id: row["id"],
    name: row["name"],
    website: row["website"],
    notes: row["notes"],
    partCount: row["part_count"],
    supplierCount: row["supplier_count"]
)
```

Show it on the row:

```swift
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
```

### Step 3: Create `BrandDetailSheet`

Add this **new struct** at the bottom of `PartsBrandsPage.swift`, AFTER the existing `BrandFormSheet`:

```swift
// MARK: - Brand Detail Sheet

private struct BrandDetailSheet: View {
    let brand: BrandListRow
    let onUpdate: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var linkedSuppliers: [WiredPartCore.Supplier] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showEditForm = false
    @State private var showSupplierPicker = false

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
                            showSupplierPicker = true
                        } label: {
                            Label("Manage", systemImage: "checklist")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle(brand.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showEditForm = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            .sheet(isPresented: $showEditForm) {
                BrandFormSheet(brand: brand) {
                    await onUpdate()
                }
            }
            .sheet(isPresented: $showSupplierPicker) {
                BrandSupplierPickerSheet(brandId: brand.id) {
                    loadSuppliers()
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
```

**Note:** `BrandSupplierPickerSheet` is created in the next prompt (11C). For now this file references it — if you build before completing 11C, you'll get a compile error on that name. That's expected.

---

## Success Criteria

1. Tapping a brand row opens the **Brand Detail Sheet** (not the edit form directly)
2. The detail sheet shows brand name, website, notes, part count
3. Below that, a "Suppliers That Carry This Brand" section lists linked suppliers
4. Each supplier shows name, phone, and a green checkmark
5. If no suppliers are linked, it says "No suppliers linked to this brand yet."
6. A "Manage" button in the section header exists (it will open the picker from 11C)
7. A pencil icon in the toolbar opens the existing `BrandFormSheet` for editing
8. The brand row in the list now shows a supplier count under the parts count

---

## When Done

**Read and implement prompt `11C-brand-supplier-picker.md` next.** It creates the `BrandSupplierPickerSheet` that the "Manage" button opens.
