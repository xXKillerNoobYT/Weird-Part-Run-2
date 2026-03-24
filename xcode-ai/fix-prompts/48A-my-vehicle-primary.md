# 48A — My Vehicle Primary View

> **Chain position:** **48A** → 48B → 48C → 48D → 48E
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read `IOSMyVehiclePage.swift` (or equivalent) and `FleetService.swift`. Redesign My Vehicle as the primary worker view with smart cards, two inventory types (Truck Stock vs Transfer Area), quick actions, and trailer section.

## Context

My Vehicle is the most-used fleet page for field workers. It shows their assigned vehicle's status at a glance: what tools are loaded, what parts are on the truck, fuel level, upcoming maintenance. The truck has two inventory types: Truck Stock (permanent parts with MIN/TARGET/MAX levels, like a mini warehouse) and Transfer Area (parts being moved between locations — picking up from warehouse to deliver to a job site, or returning unused parts). Quick actions let workers do common tasks fast. If a trailer is attached, it shows below.

## Task

### Step 1: Smart Cards

```swift
@State private var vehicleStats: MyVehicleStats?
@State private var loadError: String?
@State private var isLoading = true

struct MyVehicleStats: Sendable {
    let toolCount: Int
    let partCount: Int
    let fuelLevel: Double?     // 0.0-1.0, nil if not tracked
    let maintenanceDue: Int
    let transferItems: Int     // items in transfer area
    let hasTrailer: Bool
    let trailerName: String?
}

ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 12) {
        SmartCard(title: "Tools", count: vehicleStats?.toolCount ?? 0,
                  icon: "wrench.fill", color: .blue)
        SmartCard(title: "Parts", count: vehicleStats?.partCount ?? 0,
                  icon: "shippingbox.fill", color: .green)

        if let fuel = vehicleStats?.fuelLevel {
            SmartCard(title: "Tank", value: "\(Int(fuel * 100))%",
                      icon: "fuelpump.fill",
                      color: fuel < 0.25 ? .red : fuel < 0.5 ? .orange : .green)
        }

        SmartCard(title: "Maintenance", count: vehicleStats?.maintenanceDue ?? 0,
                  icon: "wrench.and.screwdriver.fill",
                  color: (vehicleStats?.maintenanceDue ?? 0) > 0 ? .red : .green)
    }
    .padding(.horizontal)
}
```

### Step 2: Service Methods

```swift
// MARK: - My Vehicle

func getMyVehicleStats(userId: Int64) async throws -> MyVehicleStats {
    try await db.read { db in
        // Find assigned vehicle
        guard let assignment = try Row.fetchOne(db, sql: """
            SELECT va.vehicle_id, v.name, v.fuel_level
            FROM vehicle_assignments va
            JOIN vehicles v ON va.vehicle_id = v.id
            WHERE va.employee_id = ? AND va.is_active = 1
            ORDER BY va.assigned_date DESC LIMIT 1
            """, arguments: [userId]) else {
            throw FleetServiceError.noVehicleAssigned
        }

        let vehicleId: Int64 = assignment["vehicle_id"]

        let toolCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM tool_checkouts tc
            JOIN tools t ON tc.tool_id = t.id
            WHERE tc.checked_out_by = ? AND tc.returned_at IS NULL
            AND t.location_type = 'vehicle'
            """, arguments: [userId]) ?? 0

        let partCount = try Int.fetchOne(db, sql: """
            SELECT COALESCE(SUM(quantity), 0) FROM vehicle_stock
            WHERE vehicle_id = ? AND stock_type = 'truck_stock'
            """, arguments: [vehicleId]) ?? 0

        let maintenanceDue = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM vehicles
            WHERE id = ? AND next_maintenance_date <= date('now', '+7 days')
            """, arguments: [vehicleId]) ?? 0

        let transferItems = try Int.fetchOne(db, sql: """
            SELECT COALESCE(SUM(quantity), 0) FROM vehicle_stock
            WHERE vehicle_id = ? AND stock_type = 'transfer'
            """, arguments: [vehicleId]) ?? 0

        let trailer = try Row.fetchOne(db, sql: """
            SELECT t.name FROM trailer_attachments ta
            JOIN trailers t ON ta.trailer_id = t.id
            WHERE ta.vehicle_id = ? AND ta.detached_at IS NULL
            """, arguments: [vehicleId])

        return MyVehicleStats(
            toolCount: toolCount,
            partCount: partCount,
            fuelLevel: assignment["fuel_level"],
            maintenanceDue: maintenanceDue,
            transferItems: transferItems,
            hasTrailer: trailer != nil,
            trailerName: trailer?["name"]
        )
    }
}
```

### Step 3: Two Inventory Types

```swift
// Migration: add stock_type to vehicle_stock
try db.alter(table: "vehicle_stock") { t in
    t.add(column: "stock_type", .text).defaults(to: "truck_stock")
        // "truck_stock" = permanent (MIN/TARGET/MAX)
        // "transfer" = in-transit (source/destination)
    t.add(column: "min_qty", .integer)
    t.add(column: "target_qty", .integer)
    t.add(column: "max_qty", .integer)
    t.add(column: "source_location", .text)       // transfer: where it came from
    t.add(column: "destination_location", .text)   // transfer: where it's going
    t.add(column: "transfer_reason", .text)        // "job_delivery", "return", "restock"
}

// UI: Tabs for Truck Stock vs Transfer Area
@State private var inventoryTab: InventoryTab = .truckStock

enum InventoryTab: String, CaseIterable {
    case truckStock = "Truck Stock"
    case transfer = "Transfer"
}

Section {
    Picker("Inventory", selection: $inventoryTab) {
        ForEach(InventoryTab.allCases, id: \.self) { tab in
            Text(tab.rawValue).tag(tab)
        }
    }
    .pickerStyle(.segmented)

    switch inventoryTab {
    case .truckStock:
        // Permanent stock with MIN/TARGET/MAX bars
        ForEach(truckStock) { item in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.partName).font(.subheadline)
                    Text("Qty: \(item.quantity)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                // Health bar: red below MIN, green at TARGET, yellow between
                if let target = item.targetQty {
                    ProgressView(value: Double(item.quantity), total: Double(target))
                        .tint(item.quantity < (item.minQty ?? 0) ? .red :
                              item.quantity >= target ? .green : .orange)
                        .frame(width: 60)
                }
            }
        }

    case .transfer:
        // In-transit items with source → destination
        ForEach(transferItems) { item in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.partName).font(.subheadline)
                    Text("\(item.sourceLocation ?? "?") → \(item.destinationLocation ?? "?")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("×\(item.quantity)")
                    .font(.subheadline).monospacedDigit()
            }
        }
        if transferItems.isEmpty {
            Text("No items in transit").foregroundStyle(.secondary)
        }
    }
} header: {
    Text("Inventory")
}
```

### Step 4: Quick Actions

```swift
Section("Quick Actions") {
    HStack(spacing: 12) {
        QuickActionButton(title: "Log Fuel", icon: "fuelpump.fill", color: .blue) {
            activeSheet = .logFuel
        }
        QuickActionButton(title: "Report Issue", icon: "exclamationmark.triangle.fill", color: .red) {
            activeSheet = .reportIssue
        }
        QuickActionButton(title: "Add Part", icon: "plus.circle.fill", color: .green) {
            activeSheet = .addTransferItem
        }
    }
}
```

### Step 5: Trailer Section

```swift
if let stats = vehicleStats, stats.hasTrailer {
    Section {
        HStack {
            Image(systemName: "truck.box.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text(stats.trailerName ?? "Trailer")
                    .font(.subheadline).fontWeight(.medium)
                Text("Attached")
                    .font(.caption).foregroundStyle(.green)
            }
            Spacer()
            NavigationLink("Details") {
                // Navigate to trailer detail (48C)
            }
        }
    } header: {
        Text("Trailer")
    }
}
```

## Important Notes
- Truck Stock = permanent inventory with MIN/TARGET/MAX levels (like a mini warehouse on wheels)
- Transfer Area = items being moved between locations (temporary, has source and destination)
- Fuel level shows as percentage in smart card — red below 25%, orange below 50%
- If no vehicle is assigned to the current user, show a clear "No vehicle assigned" message
- Quick actions are the most common things a driver does: log fuel, report an issue, add a part to transfer
- Trailer section only appears when a trailer is attached

## Success Criteria
- [ ] Smart cards: Tools, Parts, Tank (%), Maintenance Due
- [ ] Two inventory types: Truck Stock (MIN/TARGET/MAX bars) vs Transfer Area (source→destination)
- [ ] Migration: stock_type + MIN/TARGET/MAX + source/destination columns
- [ ] Quick actions: Log Fuel, Report Issue, Add Part
- [ ] Trailer attached section with navigation to detail
- [ ] Service: getMyVehicleStats
- [ ] "No vehicle assigned" fallback state
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 48A Results (YYYY-MM-DD)
- My Vehicle smart cards: 4 KPIs
- Truck Stock vs Transfer Area inventory
- Quick actions + trailer section
- Service: getMyVehicleStats
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 48B.**
