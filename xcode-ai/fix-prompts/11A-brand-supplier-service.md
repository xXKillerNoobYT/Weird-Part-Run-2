# Fix Prompt 11A: Add Brand-Supplier Link/Unlink Methods

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## What the User Wants

When you tap a brand (like "Lutron") on the Brands page, you should be able to see which suppliers carry that brand and manage those links. The database table `brand_supplier_links` already exists. The read methods `getBrandSuppliers(brandId:)` and `getSupplierBrands(supplierId:)` already exist in `PartsService.swift`. But there are **no methods to create or remove links**. This prompt adds them.

---

## File To Edit

**`core/Sources/WiredPartCore/Services/PartsService.swift`**

Find this section (around line 1337):

```swift
/// Get all suppliers for a brand (via brand_supplier_links).
public func getBrandSuppliers(brandId: Int64) throws -> [Supplier] {
```

**Add these three new methods DIRECTLY AFTER `getSupplierBrands(supplierId:)` (which ends around line 1377):**

```swift
    // MARK: - Brand-Supplier Linking

    /// Link a supplier to a brand. If a soft-deleted link exists, reactivate it.
    /// Returns the link row ID.
    @discardableResult
    public func linkBrandToSupplier(brandId: Int64, supplierId: Int64) throws -> Int64 {
        try db.writer.write { dbConn in
            // Check if a soft-deleted link exists — reactivate it
            if let existing = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT id FROM brand_supplier_links
                    WHERE brand_id = ? AND supplier_id = ?
                    """,
                arguments: [brandId, supplierId]
            ) {
                let linkId: Int64 = existing["id"]
                try dbConn.execute(
                    sql: """
                        UPDATE brand_supplier_links
                        SET deleted_at = NULL, is_active = 1
                        WHERE id = ?
                        """,
                    arguments: [linkId]
                )
                return linkId
            }

            // Create new link
            try dbConn.execute(
                sql: """
                    INSERT INTO brand_supplier_links (brand_id, supplier_id, is_active, created_at)
                    VALUES (?, ?, 1, datetime('now'))
                    """,
                arguments: [brandId, supplierId]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Remove a brand-supplier link (soft delete).
    public func unlinkBrandFromSupplier(brandId: Int64, supplierId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE brand_supplier_links
                    SET deleted_at = datetime('now')
                    WHERE brand_id = ? AND supplier_id = ? AND deleted_at IS NULL
                    """,
                arguments: [brandId, supplierId]
            )
        }
    }

    /// Set the complete list of suppliers for a brand.
    /// Links suppliers in `supplierIds`, unlinks any not in the list.
    public func setBrandSuppliers(brandId: Int64, supplierIds: Set<Int64>) throws {
        // Get currently linked supplier IDs
        let currentSuppliers = try getBrandSuppliers(brandId: brandId)
        let currentIds = Set(currentSuppliers.map { $0.id! })

        // Add new links
        let toAdd = supplierIds.subtracting(currentIds)
        for supplierId in toAdd {
            try linkBrandToSupplier(brandId: brandId, supplierId: supplierId)
        }

        // Remove old links
        let toRemove = currentIds.subtracting(supplierIds)
        for supplierId in toRemove {
            try unlinkBrandFromSupplier(brandId: brandId, supplierId: supplierId)
        }
    }
```

---

## Success Criteria

1. The project compiles with no errors after adding these methods
2. `linkBrandToSupplier` creates a row in `brand_supplier_links`
3. `unlinkBrandFromSupplier` soft-deletes the row (sets `deleted_at`)
4. `setBrandSuppliers` syncs the full list — adds missing links, removes extras
5. Re-linking a previously unlinked supplier reactivates the existing row instead of creating a duplicate

---

## When Done

**Read and implement prompt `11B-brand-detail-sheet.md` next.** It uses these methods to show the supplier list inside the brand detail view.
