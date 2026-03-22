# 31G — Inventory Grid: Location Picker + Group by Type + Actions

> **Plan:** `docs/plans/ios-warehouse-pages.md`

## Instructions

Read the file first, then fix all issues. When done, wait for user confirmation.

## Context

The inventory grid page is hardcoded to warehouse location ID 1. It needs a location picker (default = last visited), parts grouped by type for easy browsing, low-stock styling, and action buttons.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSInventoryGridPage.swift` (93 lines)

## Task

1. **Remove hardcoded location** — replace `getStockAtLocation(locationType: "warehouse", locationId: 1)` with a location picker:
   ```swift
   @State private var selectedLocationType = "warehouse"
   @State private var selectedLocationId: Int64 = 1
   @AppStorage("lastWarehouseLocationId") private var lastLocationId: Int64 = 1

   // On appear, use last visited location
   .onAppear { selectedLocationId = lastLocationId }
   // On change, save as last visited
   .onChange(of: selectedLocationId) { lastLocationId = selectedLocationId }
   ```

2. **Add location picker** at the top — dropdown or picker showing available locations

3. **Group parts by type** — instead of a flat list, group by part type (category/type hierarchy):
   ```swift
   // Group stockItems by type name
   let grouped = Dictionary(grouping: stockItems) { $0.typeName ?? "Uncategorized" }
   let sortedTypes = grouped.keys.sorted()

   ForEach(sortedTypes, id: \.self) { typeName in
       Section(typeName) {
           ForEach(grouped[typeName]!, id: \.partId) { item in
               inventoryRow(item)
           }
       }
   }
   ```
   **Note:** The stock query may need to JOIN parts → types to get type names. Add this to the service method if needed.

4. **Add low-stock styling** — color-code quantities:
   ```swift
   .foregroundStyle(
       item.qty <= 0 ? .red :
       item.qty <= item.minStock ? .orange :
       .primary
   )
   ```

5. **Add action buttons per row** — swipe or tap actions:
   - [Transfer] — open movement wizard with this part pre-selected
   - [View Detail] — open part detail sheet
   - [Audit] — add to audit queue

6. **Remove `#if os(iOS)` platform guard**

7. **Add smart card filters** — filter by stock status: All | Low Stock | Out of Stock | Healthy

## Success Criteria

- [ ] Location picker replaces hardcoded ID 1
- [ ] Default = last visited location (persisted)
- [ ] Parts grouped by type in sections
- [ ] Low-stock color styling (red/orange/normal)
- [ ] Action buttons: Transfer, View Detail, Audit
- [ ] Platform guard removed
- [ ] Smart card filters for stock status
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 31H.**
