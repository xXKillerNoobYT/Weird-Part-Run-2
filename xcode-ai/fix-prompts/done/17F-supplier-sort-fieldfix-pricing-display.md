# 17F — Supplier Sort Options, Field Fix, and Supplier Pricing on Pricing/Categories Pages

> **Chain position:** 17A → 17B → 17C → 17D → 17E → **17F** → 17G–17H
> **Prerequisite:** 17E complete (contacts integration)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Three issues to fix:

1. **Sort options missing** — The suppliers list has no way to sort (by name, quality score, on-time rate, etc.)
2. **Field mapping bug** — Line 291 in `PartsSuppliersPage.swift` maps `partCount: item.brandCount` — wrong field being used for the part count
3. **Supplier pricing display** — Per-supplier part costs (from `part_suppliers.supplier_cost_price`) need to be shown on the **Pricing page** and **Categories page** — NOT on the supplier detail page

**Key files:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift` — sort + field fix
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsPricingPage.swift` — add supplier cost column
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesEditorPanel.swift` — add supplier cost info
- `core/Sources/WiredPartCore/Services/PartsService.swift` — helper for supplier costs per part

## Task

### Step 1: Fix the field mapping bug

In `PartsSuppliersPage.swift`, find the line where `SupplierListRow` is constructed in `loadData()`. Look for `partCount: item.brandCount` or similar wrong mapping. The part count should come from a count of `part_suppliers` rows for this supplier:

```swift
// Fix: use actual part count, not brand count
partCount: item.partCount,  // Make sure this maps to the correct column
```

If `partCount` isn't being queried from the database, add it to the SELECT in `loadData()`:

```swift
// Add to the supplier query:
(SELECT COUNT(*) FROM part_suppliers WHERE supplier_id = suppliers.id AND deleted_at IS NULL) AS part_count
```

And map it:
```swift
partCount: row["part_count"] ?? 0
```

### Step 2: Add sort options to the suppliers page

Add a sort enum and picker to `PartsSuppliersPage`:

```swift
enum SupplierSortOption: String, CaseIterable {
    case nameAsc = "Name A→Z"
    case nameDesc = "Name Z→A"
    case qualityDesc = "Quality ↓"
    case onTimeDesc = "On-Time ↓"
    case reliabilityDesc = "Reliability ↓"
    case partCountDesc = "Most Parts"
    case recentlyAdded = "Recently Added"
}

@State private var sortOption: SupplierSortOption = .nameAsc
```

Add a sort picker in the toolbar or below the Active/All picker:

```swift
HStack {
    Picker("Filter", selection: /* existing binding */) {
        Text("Active").tag(0)
        Text("All").tag(1)
    }
    .pickerStyle(.segmented)

    Menu {
        ForEach(SupplierSortOption.allCases, id: \.self) { option in
            Button(option.rawValue) { sortOption = option }
        }
    } label: {
        Image(systemName: "arrow.up.arrow.down")
            .frame(width: 44, height: 44)
    }
}
.padding(.horizontal)
.padding(.vertical, 8)
```

Apply sorting in `filteredSuppliers`:

```swift
var filteredSuppliers: [SupplierListRow] {
    var result = suppliers
    if let active = filterActive {
        result = result.filter { ($0.isActive == 1) == active }
    }
    if !searchText.isEmpty {
        let q = searchText.lowercased()
        result = result.filter {
            $0.name.lowercased().contains(q)
            || ($0.contactName?.lowercased().contains(q) ?? false)
            || ($0.accountNumber?.lowercased().contains(q) ?? false)
        }
    }
    switch sortOption {
    case .nameAsc: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    case .nameDesc: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
    case .qualityDesc: result.sort { ($0.qualityScore ?? 0) > ($1.qualityScore ?? 0) }
    case .onTimeDesc: result.sort { ($0.onTimeRate ?? 0) > ($1.onTimeRate ?? 0) }
    case .reliabilityDesc: result.sort { ($0.reliabilityScore ?? 0) > ($1.reliabilityScore ?? 0) }
    case .partCountDesc: result.sort { $0.partCount > $1.partCount }
    case .recentlyAdded: break // already sorted by id desc from query
    }
    return result
}
```

### Step 3: Add supplier cost service helper

In `PartsService.swift`, add a method to get supplier costs for a part (used by Pricing page and Categories page):

```swift
// =========================================================================
// MARK: - 14. Supplier Costs per Part
// =========================================================================

/// Supplier cost data for a single part.
public struct PartSupplierCost: Sendable {
    public let supplierId: Int64
    public let supplierName: String
    public let supplierCostPrice: Double?
    public let supplierPartNumber: String?
    public let isPreferred: Bool
}

/// Get all supplier costs for a specific part.
public func getPartSupplierCosts(partId: Int64) throws -> [PartSupplierCost] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT ps.supplier_id, s.name AS supplier_name,
                   ps.supplier_cost_price, ps.supplier_part_number, ps.is_preferred
            FROM part_suppliers ps
            JOIN suppliers s ON s.id = ps.supplier_id AND s.deleted_at IS NULL
            WHERE ps.part_id = ? AND ps.deleted_at IS NULL
            ORDER BY ps.is_preferred DESC, s.name ASC
            """, arguments: [partId])

        return rows.map { row in
            PartSupplierCost(
                supplierId: row["supplier_id"],
                supplierName: row["supplier_name"] ?? "",
                supplierCostPrice: row["supplier_cost_price"],
                supplierPartNumber: row["supplier_part_number"],
                isPreferred: (row["is_preferred"] as Int?) == 1
            )
        }
    }
}
```

### Step 4: Show supplier costs on the Pricing page

In `PartsPricingPage.swift`, when a user taps a part to edit pricing, the edit sheet should show supplier costs for context. In the pricing edit sheet (whichever sheet opens when editing a part's price), add a section:

```swift
// Inside the pricing edit sheet, after the cost/markup fields:
Section("Supplier Costs") {
    if supplierCosts.isEmpty {
        Text("No supplier pricing data.")
            .font(.caption)
            .foregroundStyle(.secondary)
    } else {
        ForEach(supplierCosts, id: \.supplierId) { sc in
            HStack {
                Text(sc.supplierName)
                    .font(.subheadline)
                if sc.isPreferred {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Spacer()
                if let cost = sc.supplierCostPrice {
                    Text(String(format: "$%.5f", cost))
                        .font(.subheadline)
                        .monospaced()
                } else {
                    Text("No price")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 36)
        }
    }
}
```

Add state and load:
```swift
@State private var supplierCosts: [PartsService.PartSupplierCost] = []

// In .task or .onAppear:
if let service = appCore.partsService {
    supplierCosts = (try? service.getPartSupplierCosts(partId: partId)) ?? []
}
```

### Step 5: Show supplier cost on the Categories page

In `CategoriesEditorPanel.swift` or whichever view shows part details within the categories tree, when a part is selected, show a brief supplier cost summary. This can be a small subtitle or expandable section.

If there's a part detail area in the categories editor, add:

```swift
// Below the part info in categories
if !supplierCosts.isEmpty {
    VStack(alignment: .leading, spacing: 4) {
        Text("Supplier Costs")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
        ForEach(supplierCosts.prefix(3), id: \.supplierId) { sc in
            HStack {
                Text(sc.supplierName)
                    .font(.caption)
                if sc.isPreferred {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Spacer()
                if let cost = sc.supplierCostPrice {
                    Text(String(format: "$%.2f", cost))
                        .font(.caption)
                        .monospaced()
                }
            }
        }
        if supplierCosts.count > 3 {
            Text("+\(supplierCosts.count - 3) more suppliers")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    .padding(.top, 4)
}
```

If the categories page doesn't have a part detail area yet, add the supplier cost info to wherever parts are listed/expanded in the tree.

## Important Notes

- Supplier costs display up to $0.00001 precision on the Pricing page (uses `$%.5f` format) but round to `$%.2f` on the Categories page for readability.
- Preferred supplier indicated by star icon (from `part_suppliers.is_preferred`).
- The field mapping bug (partCount using brandCount) may manifest as all suppliers showing "0 parts" or wrong numbers — check the actual column name in the query.
- Sort by quality/on-time/reliability uses the scores stored on the supplier record. If scores haven't been calculated yet (pre-17C), they'll be nil/0.
- The account number is now searchable (added to search filter).

## Success Criteria

- [ ] Field mapping bug fixed — part count shows correct number
- [ ] Sort menu with 7 options (name asc/desc, quality, on-time, reliability, part count, recent)
- [ ] Sorting works correctly for all options
- [ ] Account number searchable
- [ ] `getPartSupplierCosts` returns supplier costs for a part
- [ ] Pricing page edit sheet shows supplier costs section
- [ ] Categories page shows supplier cost summary for parts
- [ ] Preferred supplier marked with star
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 17F Results (YYYY-MM-DD)
- Field mapping bug fixed (partCount)
- Sort options: 7 choices with Menu picker
- Supplier costs displayed on Pricing page and Categories page
- getPartSupplierCosts service method
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 17G.**
