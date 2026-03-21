# Prompt 15A — Brands & Suppliers: Use Service Layer Instead of Raw SQL

> Read `xcode-ai/xcode.md` first for project conventions.

## Goal

Both `PartsBrandsPage.swift` and `PartsSuppliersPage.swift` bypass the service layer entirely, writing raw SQL directly in SwiftUI views. `PartsService` already has methods for all of these operations. Replace all raw SQL with service calls.

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsBrandsPage.swift`
2. `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift`

## Step 1: Fix PartsBrandsPage — loadData()

**File:** `PartsBrandsPage.swift`

Find the `loadData()` method (around line 188). It currently does:
```swift
guard let db = appCore.db else { ... }
let rows = try await db.writer.read { dbConnection -> [BrandListRow] in
    let results = try Row.fetchAll(dbConnection, sql: "SELECT b.*, COUNT(DISTINCT p.id) AS part_count ...")
```

Replace the entire `loadData()` body with a service call:

```swift
@Sendable
private func loadData() async {
    guard let service = appCore.partsService else {
        isLoading = false
        loadError = "Parts service not available."
        return
    }
    do {
        let result = try service.listBrands(search: searchText.isEmpty ? nil : searchText)
        await MainActor.run {
            brands = result.map { bwc in
                BrandListRow(
                    id: bwc.brand.id ?? 0,
                    name: bwc.brand.name,
                    website: bwc.brand.website,
                    notes: bwc.brand.notes,
                    partCount: bwc.partCount
                )
            }
            isLoading = false
            loadError = nil
        }
    } catch {
        await MainActor.run {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}
```

## Step 2: Fix PartsBrandsPage — deleteBrand()

Find `deleteBrand()` (around line 226). Replace the raw SQL with:

```swift
private func deleteBrand(_ brand: BrandListRow) async {
    guard let service = appCore.partsService else { return }
    do {
        try service.deleteBrand(id: brand.id)
        await loadData()
    } catch {
        // Will be properly handled in prompt 15B
        print("[PartsBrandsPage] Delete brand error: \(error)")
    }
}
```

## Step 3: Fix PartsBrandsPage — BrandFormSheet.save()

Find `BrandFormSheet.save()` (around line 311). Replace raw SQL with service calls:

```swift
private func save() async throws {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    guard !trimmedName.isEmpty else { return }
    guard let service = appCore.partsService else {
        throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
    }
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
```

Remove `import GRDB` from the file since it's no longer needed.

## Step 4: Fix PartsSuppliersPage — loadData()

**File:** `PartsSuppliersPage.swift`

Find `loadData()` (around line 233). Replace with:

```swift
@Sendable
private func loadData() async {
    guard let service = appCore.partsService else {
        isLoading = false
        loadError = "Parts service not available."
        return
    }
    do {
        let result = try service.listSuppliers(search: searchText.isEmpty ? nil : searchText)
        await MainActor.run {
            suppliers = result.map { swc in
                SupplierListRow(
                    id: swc.supplier.id ?? 0,
                    name: swc.supplier.name,
                    contactName: swc.supplier.contactName,
                    email: swc.supplier.email,
                    phone: swc.supplier.phone,
                    address: swc.supplier.address,
                    website: swc.supplier.website,
                    repName: nil, repEmail: nil, repPhone: nil,
                    notes: swc.supplier.notes,
                    deliveryMethod: nil, deliveryDays: nil,
                    onTimeRate: nil, qualityScore: nil, reliabilityScore: nil,
                    isActive: 1,
                    partCount: swc.brandCount
                )
            }
            isLoading = false
            loadError = nil
        }
    } catch {
        await MainActor.run {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}
```

**Note:** The `PartsService.listSuppliers()` returns `SupplierWithCount` which has `brandCount` not all the extra supplier fields (repName, scores, etc.). If the `Supplier` model in WiredPartCore has these fields, use them. If not, set them to nil — the detail view will still work since it handles nil gracefully.

**Important:** Check the `Supplier` model in `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift` for available fields and map accordingly.

## Step 5: Fix PartsSuppliersPage — deleteSupplier()

Replace raw SQL with service call:

```swift
private func deleteSupplier(_ supplier: SupplierListRow) async {
    guard let service = appCore.partsService else { return }
    do {
        try service.deleteSupplier(id: supplier.id)
        await loadData()
    } catch {
        print("[PartsSuppliersPage] Delete supplier error: \(error)")
    }
}
```

## Step 6: Fix PartsSuppliersPage — SupplierFormSheet.save()

Replace raw SQL INSERT/UPDATE with service calls:

```swift
private func save() async throws {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    guard !trimmedName.isEmpty else { return }
    guard let service = appCore.partsService else {
        throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
    }
    if let s = supplier {
        try service.updateSupplier(
            id: s.id, name: trimmedName,
            contactName: contactName.isEmpty ? nil : contactName,
            email: email.isEmpty ? nil : email,
            phone: phone.isEmpty ? nil : phone,
            address: address.isEmpty ? nil : address,
            website: website.isEmpty ? nil : website,
            notes: notes.isEmpty ? nil : notes
        )
    } else {
        _ = try service.createSupplier(
            name: trimmedName,
            contactName: contactName.isEmpty ? nil : contactName,
            email: email.isEmpty ? nil : email,
            phone: phone.isEmpty ? nil : phone,
            address: address.isEmpty ? nil : address,
            website: website.isEmpty ? nil : website,
            notes: notes.isEmpty ? nil : notes
        )
    }
}
```

Remove `import GRDB` from the file.

## Logging

After completing this prompt, append results to `xcode-ai/prompt-results-log.md`.

## Success Criteria

- [ ] Build succeeds with no errors
- [ ] No raw SQL remains in either `PartsBrandsPage.swift` or `PartsSuppliersPage.swift`
- [ ] No `import GRDB` in either file
- [ ] All data operations go through `PartsService` methods
- [ ] Guard-let-else for service sets `isLoading = false` and `loadError`
- [ ] Brands list still loads, creates, edits, and deletes correctly
- [ ] Suppliers list still loads, creates, edits, and deletes correctly

## Next

When all criteria are met, read and implement `xcode-ai/fix-prompts/15B-brands-suppliers-delete-errors.md`.
