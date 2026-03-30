# 47C — Kit Management

> **Chain position:** 47A → 47B → **47C** → 47D
> **Prerequisite:** 47B (tool detail + condition check)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read the existing kit pages and `ToolsService.swift`. Add 4 kit types, missing tools status, full inspection checklist, consumable restocking, and kit version history.

## Context

Kits are collections of tools and/or consumables. There are 4 types: consumable-only (e.g., PPE kit), tool+consumable (e.g., termination kit with wire nuts + strippers), mixed (anything goes), and tools-only (e.g., hand tool set). Each kit type has different inspection rules. Inspections check every item — tools for presence/condition, consumables for quantity. Restocking consumables pulls from warehouse stock.

## Task

### Step 1: Kit Type Model

```swift
enum KitType: String, CaseIterable, Sendable {
    case consumableOnly = "consumable_only"
    case toolAndConsumable = "tool_and_consumable"
    case mixed = "mixed"
    case toolsOnly = "tools_only"

    var displayName: String {
        switch self {
        case .consumableOnly: return "Consumable Only"
        case .toolAndConsumable: return "Tool + Consumable"
        case .mixed: return "Mixed"
        case .toolsOnly: return "Tools Only"
        }
    }

    var icon: String {
        switch self {
        case .consumableOnly: return "shippingbox.fill"
        case .toolAndConsumable: return "wrench.and.screwdriver.fill"
        case .mixed: return "square.grid.2x2.fill"
        case .toolsOnly: return "wrench.fill"
        }
    }
}

// Migration: add kit_type to tool_kits
try db.alter(table: "tool_kits") { t in
    t.add(column: "kit_type", .text).defaults(to: "mixed")
}
```

### Step 2: Missing Tools Status

```swift
struct KitStatus: Sendable {
    let kitId: Int64
    let kitName: String
    let kitType: KitType
    let totalItems: Int
    let presentItems: Int
    let missingItems: Int
    let damagedItems: Int
    let lowConsumables: Int  // below MIN qty
    let lastInspection: Date?

    var healthPercent: Double {
        guard totalItems > 0 else { return 1.0 }
        return Double(presentItems) / Double(totalItems)
    }

    var statusLabel: String {
        if missingItems > 0 { return "Incomplete" }
        if damagedItems > 0 { return "Needs Repair" }
        if lowConsumables > 0 { return "Restock Needed" }
        return "Complete"
    }

    var statusColor: Color {
        if missingItems > 0 { return .red }
        if damagedItems > 0 { return .orange }
        if lowConsumables > 0 { return .yellow }
        return .green
    }
}

// Service method
func getKitStatus(kitId: Int64) async throws -> KitStatus
```

### Step 3: Full Inspection Checklist

```swift
struct KitInspectionView: View {
    let kit: KitDetail
    @EnvironmentObject var appCore: AppCore
    @State private var checklistItems: [InspectionItem] = []
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var inspectionComplete = false

    struct InspectionItem: Identifiable {
        let id: Int64
        let name: String
        let itemType: String  // "tool" or "consumable"
        let requiredQty: Int
        var currentQty: Int
        var condition: String  // "good", "fair", "poor", "damaged", "missing"
        var isChecked: Bool
        var notes: String
    }

    var body: some View {
        NavigationStack {
            List {
                // Progress header
                Section {
                    let checked = checklistItems.filter(\.isChecked).count
                    VStack(spacing: 4) {
                        ProgressView(value: Double(checked), total: Double(checklistItems.count))
                            .tint(.blue)
                        Text("\(checked)/\(checklistItems.count) items inspected")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Tools section
                let tools = checklistItems.filter { $0.itemType == "tool" }
                if !tools.isEmpty {
                    Section("Tools") {
                        ForEach($checklistItems) { $item in
                            if item.itemType == "tool" {
                                ToolInspectionRow(item: $item)
                            }
                        }
                    }
                }

                // Consumables section
                let consumables = checklistItems.filter { $0.itemType == "consumable" }
                if !consumables.isEmpty {
                    Section("Consumables") {
                        ForEach($checklistItems) { $item in
                            if item.itemType == "consumable" {
                                ConsumableInspectionRow(item: $item)
                            }
                        }
                    }
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Kit Inspection")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete") {
                        Task { await completeInspection() }
                    }
                    .disabled(!allItemsChecked || isSaving)
                }
            }
        }
    }

    var allItemsChecked: Bool {
        checklistItems.allSatisfy(\.isChecked)
    }

    func completeInspection() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        do {
            try await service.saveKitInspection(
                kitId: kit.id,
                inspectorId: appCore.currentUserId,
                items: checklistItems.map { item in
                    KitInspectionResult(
                        itemId: item.id,
                        condition: item.condition,
                        currentQty: item.currentQty,
                        notes: item.notes
                    )
                }
            )
            inspectionComplete = true
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

struct ToolInspectionRow: View {
    @Binding var item: KitInspectionView.InspectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .green : .secondary)
                Text(item.name).font(.subheadline)
                Spacer()
            }
            if item.isChecked {
                Picker("Condition", selection: $item.condition) {
                    Text("Good").tag("good")
                    Text("Fair").tag("fair")
                    Text("Poor").tag("poor")
                    Text("Damaged").tag("damaged")
                    Text("Missing").tag("missing")
                }
                .pickerStyle(.segmented)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { item.isChecked.toggle() }
    }
}

struct ConsumableInspectionRow: View {
    @Binding var item: KitInspectionView.InspectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .green : .secondary)
                Text(item.name).font(.subheadline)
                Spacer()
                Text("\(item.currentQty)/\(item.requiredQty)")
                    .font(.caption).monospacedDigit()
            }
            if item.isChecked {
                Stepper("Qty: \(item.currentQty)", value: $item.currentQty, in: 0...item.requiredQty * 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { item.isChecked.toggle() }
    }
}
```

### Step 4: Restock Consumables

```swift
// Service method
func restockKitConsumables(
    kitId: Int64, items: [(partId: Int64, qty: Int)], userId: Int64
) async throws {
    try await db.write { db in
        for item in items {
            // Check warehouse stock
            let available = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(quantity), 0) FROM stock_levels
                WHERE part_id = ? AND location_type = 'shelf'
                """, arguments: [item.partId]) ?? 0

            guard available >= item.qty else {
                throw ToolsServiceError.insufficientStock(
                    partName: "Part \(item.partId)",
                    available: available, requested: item.qty
                )
            }

            // Deduct from warehouse
            try db.execute(sql: """
                UPDATE stock_levels SET quantity = quantity - ?
                WHERE part_id = ? AND location_type = 'shelf'
                """, arguments: [item.qty, item.partId])

            // Add to kit
            try db.execute(sql: """
                UPDATE kit_items SET current_qty = current_qty + ?
                WHERE kit_id = ? AND part_id = ?
                """, arguments: [item.qty, kitId, item.partId])

            // Log movement
            try db.execute(sql: """
                INSERT INTO stock_movements
                (part_id, from_location, to_location, quantity, moved_by, moved_at, reason)
                VALUES (?, 'warehouse_shelf', 'kit_\(kitId)', ?, ?, datetime('now'), 'kit_restock')
                """, arguments: [item.partId, item.qty, userId])
        }
    }
}

// UI: Restock button on kit detail
Button {
    activeSheet = .restockConsumables
} label: {
    Label("Restock Consumables", systemImage: "arrow.down.to.line.compact")
}
.disabled(lowConsumables.isEmpty)
```

### Step 5: Kit Version History

```swift
func getKitVersionHistory(kitId: Int64) async throws -> [KitChangeRecord] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT pcl.id, pcl.field_name, pcl.old_value, pcl.new_value,
                   pcl.changed_at, pcl.change_type,
                   u.first_name || ' ' || u.last_name as changed_by_name
            FROM part_change_log pcl
            LEFT JOIN users u ON pcl.changed_by = u.id
            WHERE pcl.entity_type = 'kit' AND pcl.entity_id = ?
            ORDER BY pcl.changed_at DESC
            LIMIT 100
            """, arguments: [kitId])
        .map { row in
            KitChangeRecord(
                id: row["id"],
                fieldName: row["field_name"],
                oldValue: row["old_value"],
                newValue: row["new_value"],
                changedAt: row["changed_at"],
                changeType: row["change_type"],
                changedByName: row["changed_by_name"]
            )
        }
    }
}
```

## Important Notes
- 4 kit types determine what items are allowed: consumable_only (parts only), tools_only (tools only), tool_and_consumable and mixed (both)
- Inspection must check EVERY item — no partial inspections allowed
- Tools get condition assessment, consumables get quantity count
- Restocking pulls from warehouse shelf stock and creates a movement record
- Kit version history tracks additions, removals, restocks, and inspections
- Missing status turns the kit card red on the dashboard

## Success Criteria
- [ ] 4 kit types with distinct icons and rules
- [ ] Missing tools status with health percentage
- [ ] Full inspection checklist (tools AND consumables)
- [ ] Inspection progress bar (X/Y items checked)
- [ ] Restock consumables from warehouse stock
- [ ] Kit version history
- [ ] Migration for kit_type column
- [ ] Service methods: getKitStatus, saveKitInspection, restockKitConsumables, getKitVersionHistory
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 47C Results (YYYY-MM-DD)
- 4 kit types: consumable-only, tool+consumable, mixed, tools-only
- Full inspection checklist with progress
- Restock consumables from warehouse
- Kit version history
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 47D.**
