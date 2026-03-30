# 48C — Trailer as Mini Warehouse

> **Chain position:** 48A → 48B → **48C** → 48D
> **Prerequisite:** 48A (vehicle inventory types)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read any existing trailer pages and `FleetService.swift`. Build the trailer as a mini warehouse with shelves/drawers/storage units, its own MIN/TARGET/MAX per part, linked to the primary warehouse. At the shop: ignore MIN/MAX (tight restocking). Away from shop: use full MIN/MAX rules.

## Context

Trailers are mobile storage units. They have physical storage organization (shelves, drawers, compartments) and carry their own parts inventory with MIN/TARGET/MAX levels. When the trailer is at the shop, restocking is easy so the MIN/MAX rules are relaxed (just restock as needed). When away from the shop, the MIN/MAX rules are enforced because the trailer is self-sufficient. Each trailer tracks its tools, inventory levels, and location history.

## Task

### Step 1: Migration

```swift
// Migration: trailer storage + inventory
try db.create(table: "trailer_storage_units") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("trailer_id", .integer).notNull().references("trailers")
    t.column("name", .text).notNull()         // "Shelf A", "Drawer 1", "Bin 3"
    t.column("unit_type", .text).notNull()     // "shelf", "drawer", "compartment", "bin"
    t.column("capacity_slots", .integer)
    t.column("sort_order", .integer).notNull().defaults(to: 0)
    t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
}

try db.create(table: "trailer_stock") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("trailer_id", .integer).notNull().references("trailers")
    t.column("storage_unit_id", .integer).references("trailer_storage_units")
    t.column("part_id", .integer).notNull().references("parts")
    t.column("quantity", .integer).notNull().defaults(to: 0)
    t.column("min_qty", .integer)
    t.column("target_qty", .integer)
    t.column("max_qty", .integer)
    t.column("updated_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
}

// Add location tracking to trailers
try db.alter(table: "trailers") { t in
    t.add(column: "is_at_shop", .boolean).defaults(to: true)
    t.add(column: "linked_warehouse_id", .integer)
}

try db.create(table: "trailer_location_history") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("trailer_id", .integer).notNull().references("trailers")
    t.column("location_type", .text).notNull()  // "shop", "job_site", "in_transit"
    t.column("job_id", .integer).references("jobs")
    t.column("latitude", .double)
    t.column("longitude", .double)
    t.column("arrived_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    t.column("departed_at", .datetime)
    t.column("recorded_by", .integer).references("users")
}
```

### Step 2: Trailer Detail Page

```swift
struct IOSTrailerDetailPage: View {
    let trailerId: Int64
    @EnvironmentObject var appCore: AppCore
    @State private var trailer: TrailerDetail?
    @State private var storageUnits: [TrailerStorageUnit] = []
    @State private var stock: [TrailerStockItem] = []
    @State private var tools: [TrailerToolItem] = []
    @State private var locationHistory: [TrailerLocationRecord] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var selectedTab: TrailerTab = .inventory

    enum TrailerTab: String, CaseIterable {
        case inventory = "Inventory"
        case tools = "Tools"
        case storage = "Storage"
        case history = "Location History"
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle",
                                      description: Text(error))
            } else if let trailer = trailer {
                trailerContent(trailer)
            }
        }
        .navigationTitle(trailer?.name ?? "Trailer")
        .task { await loadData() }
        .refreshable { await loadData() }
    }

    func trailerContent(_ trailer: TrailerDetail) -> some View {
        VStack(spacing: 0) {
            // Location badge
            HStack {
                Image(systemName: trailer.isAtShop ? "building.2.fill" : "map.fill")
                    .foregroundStyle(trailer.isAtShop ? .green : .blue)
                Text(trailer.isAtShop ? "At Shop" : "In Field")
                    .font(.caption).fontWeight(.medium)
                Spacer()
                if !trailer.isAtShop {
                    Text("MIN/MAX enforced")
                        .font(.caption2).foregroundStyle(.orange)
                } else {
                    Text("MIN/MAX relaxed")
                        .font(.caption2).foregroundStyle(.green)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            // Tab picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(TrailerTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            List {
                switch selectedTab {
                case .inventory: inventorySection(trailer)
                case .tools: toolsSection
                case .storage: storageSection
                case .history: locationHistorySection
                }
            }
        }
    }
}
```

### Step 3: Inventory with Location-Aware MIN/MAX

```swift
func inventorySection(_ trailer: TrailerDetail) -> some View {
    Group {
        // Summary
        Section {
            let belowMin = stock.filter { item in
                guard !trailer.isAtShop, let min = item.minQty else { return false }
                return item.quantity < min
            }
            if !belowMin.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(belowMin.count) items below MIN")
                        .font(.subheadline)
                }
            } else {
                Text("All stock levels OK").foregroundStyle(.green)
            }
        }

        // Stock list
        Section("Parts") {
            ForEach(stock) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.partName).font(.subheadline)
                        if let unitName = item.storageUnitName {
                            Text(unitName).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(item.quantity)")
                            .font(.subheadline).monospacedDigit()

                        // Show MIN/TARGET/MAX only when away from shop
                        if !trailer.isAtShop {
                            if let min = item.minQty, let target = item.targetQty {
                                ProgressView(value: Double(item.quantity),
                                             total: Double(target))
                                    .tint(item.quantity < min ? .red :
                                          item.quantity >= target ? .green : .orange)
                                    .frame(width: 50)
                            }
                        }
                    }
                }
            }
        }
    }
}
```

### Step 4: Storage Organization

```swift
var storageSection: some View {
    Group {
        ForEach(storageUnits) { unit in
            Section(unit.name) {
                let unitStock = stock.filter { $0.storageUnitId == unit.id }
                if unitStock.isEmpty {
                    Text("Empty").foregroundStyle(.secondary)
                } else {
                    ForEach(unitStock) { item in
                        HStack {
                            Text(item.partName).font(.subheadline)
                            Spacer()
                            Text("x\(item.quantity)")
                                .font(.caption).monospacedDigit()
                        }
                    }
                }
                Text("\(unitStock.count)/\(unit.capacitySlots ?? 0) slots used")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }

        if storageUnits.isEmpty {
            Section {
                Text("No storage units configured")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

### Step 5: Location History

```swift
var locationHistorySection: some View {
    Section("Location History") {
        ForEach(locationHistory) { record in
            HStack {
                Image(systemName: locationIcon(record.locationType))
                    .foregroundStyle(locationColor(record.locationType))
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.locationLabel).font(.subheadline)
                    HStack {
                        Text(record.arrivedAt, format: .dateTime.month().day().hour().minute())
                        if let departed = record.departedAt {
                            Text("→")
                            Text(departed, format: .dateTime.month().day().hour().minute())
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

func locationIcon(_ type: String) -> String {
    switch type {
    case "shop": return "building.2.fill"
    case "job_site": return "mappin.circle.fill"
    case "in_transit": return "truck.box.fill"
    default: return "location.fill"
    }
}
```

### Step 6: Service Methods

```swift
// MARK: - Trailer

func getTrailerDetail(trailerId: Int64) async throws -> TrailerDetail

func getTrailerStock(trailerId: Int64) async throws -> [TrailerStockItem] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT ts.*, p.name as part_name, tsu.name as storage_unit_name
            FROM trailer_stock ts
            JOIN parts p ON ts.part_id = p.id
            LEFT JOIN trailer_storage_units tsu ON ts.storage_unit_id = tsu.id
            WHERE ts.trailer_id = ?
            ORDER BY tsu.sort_order, p.name
            """, arguments: [trailerId])
        .map { TrailerStockItem(row: $0) }
    }
}

func getTrailerStorageUnits(trailerId: Int64) async throws -> [TrailerStorageUnit] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT * FROM trailer_storage_units
            WHERE trailer_id = ? ORDER BY sort_order
            """, arguments: [trailerId])
        .map { TrailerStorageUnit(row: $0) }
    }
}

func getTrailerLocationHistory(trailerId: Int64, limit: Int = 20) async throws -> [TrailerLocationRecord]

func updateTrailerLocation(
    trailerId: Int64, locationType: String, jobId: Int64?, recordedBy: Int64
) async throws {
    try await db.write { db in
        // Close previous location
        try db.execute(sql: """
            UPDATE trailer_location_history SET departed_at = datetime('now')
            WHERE trailer_id = ? AND departed_at IS NULL
            """, arguments: [trailerId])

        // Insert new location
        try db.execute(sql: """
            INSERT INTO trailer_location_history
            (trailer_id, location_type, job_id, recorded_by)
            VALUES (?, ?, ?, ?)
            """, arguments: [trailerId, locationType, jobId, recordedBy])

        // Update is_at_shop flag
        try db.execute(sql: """
            UPDATE trailers SET is_at_shop = ?, updated_at = datetime('now')
            WHERE id = ?
            """, arguments: [locationType == "shop", trailerId])
    }
}
```

## Important Notes
- At shop: ignore MIN/MAX (restocking is easy, just grab what you need)
- Away from shop: enforce MIN/MAX (trailer is self-sufficient, must have enough stock)
- Location badge at top clearly shows "At Shop" (green) vs "In Field" (blue)
- Storage units are physical containers: shelves, drawers, bins, compartments
- Each part in trailer_stock can optionally be assigned to a storage unit
- Location history tracks shop → job_site → in_transit transitions
- Linked warehouse determines where restock orders pull from

## Success Criteria
- [ ] Migration: trailer_storage_units, trailer_stock, trailer_location_history + trailer columns
- [ ] Trailer detail with 4 tabs (Inventory, Tools, Storage, History)
- [ ] At shop: MIN/MAX hidden/relaxed, green badge
- [ ] Away: MIN/MAX enforced with health bars, blue badge
- [ ] Storage organization with units and slot counts
- [ ] Location history with type icons
- [ ] Service: getTrailerDetail, getTrailerStock, getTrailerStorageUnits, updateTrailerLocation
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 48C Results (YYYY-MM-DD)
- Trailer as mini warehouse with storage units
- Location-aware MIN/MAX (shop vs field)
- Location history tracking
- Migration: 3 new tables + trailer columns
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 48D.**
