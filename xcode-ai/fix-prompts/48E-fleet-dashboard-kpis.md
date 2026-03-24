# 48E — Fleet Dashboard KPIs

> **Chain position:** 48A → 48B → 48C → 48D → **48E**
> **Prerequisite:** 48D (inspection records for KPIs)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read `IOSFleetDashboardPage.swift` and `FleetService.swift`. Redesign the fleet dashboard with smart cards, vehicle status list, cost summary (hat-gated), upcoming maintenance, and fleet report references.

## Context

The fleet dashboard is the landing page for the Fleet module. Managers need a bird's-eye view: how many vehicles, how many active, maintenance due, overdue inspections, trailer count, plus cost summaries for fuel/miles/maintenance. The cost summary section is hat-gated (only visible with view_fleet_financials permission). The vehicle status list shows all vehicles with their current assignment and status. A link to fleet reports (in the Reports section) provides deeper analytics.

## Task

### Step 1: Smart Cards (Two Rows)

```swift
@State private var fleetStats: FleetDashboardStats?
@State private var loadError: String?
@State private var isLoading = true

struct FleetDashboardStats: Sendable {
    let totalVehicles: Int
    let activeVehicles: Int
    let maintenanceDue: Int
    let overdueInspections: Int
    let totalTrailers: Int
    // Cost stats (hat-gated)
    let fuelCostMTD: Double?
    let milesMTD: Int?
    let maintenanceCostMTD: Double?
}

// Row 1: Fleet status
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 12) {
        SmartCard(title: "Vehicles", count: fleetStats?.totalVehicles ?? 0,
                  icon: "car.fill", color: .blue)
        SmartCard(title: "Active", count: fleetStats?.activeVehicles ?? 0,
                  icon: "checkmark.circle.fill", color: .green)
        SmartCard(title: "Maint. Due", count: fleetStats?.maintenanceDue ?? 0,
                  icon: "wrench.fill",
                  color: (fleetStats?.maintenanceDue ?? 0) > 0 ? .orange : .green)
        SmartCard(title: "Overdue Inspect", count: fleetStats?.overdueInspections ?? 0,
                  icon: "exclamationmark.triangle.fill",
                  color: (fleetStats?.overdueInspections ?? 0) > 0 ? .red : .green)
        SmartCard(title: "Trailers", count: fleetStats?.totalTrailers ?? 0,
                  icon: "truck.box.fill", color: .purple)
    }
    .padding(.horizontal)
}

// Row 2: Costs (hat-gated)
if appCore.hasPermission("view_fleet_financials"), let stats = fleetStats {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
            if let fuelCost = stats.fuelCostMTD {
                SmartCard(title: "Fuel MTD", value: "$\(Int(fuelCost))",
                          icon: "fuelpump.fill", color: .orange)
            }
            if let miles = stats.milesMTD {
                SmartCard(title: "Miles MTD", value: "\(miles)",
                          icon: "speedometer", color: .blue)
            }
            if let maintCost = stats.maintenanceCostMTD {
                SmartCard(title: "Maint. MTD", value: "$\(Int(maintCost))",
                          icon: "wrench.and.screwdriver.fill", color: .red)
            }
        }
        .padding(.horizontal)
    }
}
```

### Step 2: Service Methods

```swift
// MARK: - Fleet Dashboard

func getFleetDashboardStats() async throws -> FleetDashboardStats {
    try await db.read { db in
        let totalVehicles = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM vehicles WHERE status != 'retired'
            """) ?? 0

        let activeVehicles = try Int.fetchOne(db, sql: """
            SELECT COUNT(DISTINCT va.vehicle_id) FROM vehicle_assignments va
            WHERE va.is_active = 1
            """) ?? 0

        let maintenanceDue = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM vehicles
            WHERE next_maintenance_date <= date('now', '+7 days')
            AND status != 'retired'
            """) ?? 0

        let overdueInspections = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM vehicles v
            WHERE v.status != 'retired'
            AND (v.last_inspection_date IS NULL
                 OR v.last_inspection_date < date('now'))
            AND v.id IN (SELECT vehicle_id FROM vehicle_assignments WHERE is_active = 1)
            """) ?? 0

        let totalTrailers = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM trailers WHERE status != 'retired'
            """) ?? 0

        // Cost stats (month-to-date)
        let startOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!

        let fuelCostMTD = try Double.fetchOne(db, sql: """
            SELECT COALESCE(SUM(cost), 0) FROM fuel_logs
            WHERE logged_at >= ?
            """, arguments: [startOfMonth])

        let milesMTD = try Int.fetchOne(db, sql: """
            SELECT COALESCE(SUM(miles), 0) FROM mileage_logs
            WHERE logged_at >= ?
            """, arguments: [startOfMonth])

        let maintenanceCostMTD = try Double.fetchOne(db, sql: """
            SELECT COALESCE(SUM(cost), 0) FROM vehicle_maintenance_records
            WHERE performed_at >= ?
            """, arguments: [startOfMonth])

        return FleetDashboardStats(
            totalVehicles: totalVehicles,
            activeVehicles: activeVehicles,
            maintenanceDue: maintenanceDue,
            overdueInspections: overdueInspections,
            totalTrailers: totalTrailers,
            fuelCostMTD: fuelCostMTD,
            milesMTD: milesMTD,
            maintenanceCostMTD: maintenanceCostMTD
        )
    }
}

func getVehicleStatusList() async throws -> [VehicleStatusItem] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT v.id, v.name, v.vehicle_type, v.status, v.license_plate,
                   v.last_inspection_date, v.next_maintenance_date,
                   u.first_name || ' ' || u.last_name as driver_name
            FROM vehicles v
            LEFT JOIN vehicle_assignments va ON v.id = va.vehicle_id AND va.is_active = 1
            LEFT JOIN users u ON va.employee_id = u.id
            WHERE v.status != 'retired'
            ORDER BY v.name
            """)
        .map { VehicleStatusItem(row: $0) }
    }
}

func getUpcomingFleetMaintenance(limit: Int = 10) async throws -> [FleetMaintenanceItem] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT v.id as vehicle_id, v.name as vehicle_name,
                   v.next_maintenance_date,
                   julianday(v.next_maintenance_date) - julianday('now') as days_until
            FROM vehicles v
            WHERE v.next_maintenance_date IS NOT NULL
            AND v.status != 'retired'
            ORDER BY v.next_maintenance_date ASC
            LIMIT ?
            """, arguments: [limit])
        .map { FleetMaintenanceItem(row: $0) }
    }
}
```

### Step 3: Vehicle Status List

```swift
@State private var vehicles: [VehicleStatusItem] = []

Section {
    ForEach(vehicles) { vehicle in
        NavigationLink(value: vehicle.id) {
            HStack {
                Image(systemName: vehicleIcon(vehicle.vehicleType))
                    .foregroundStyle(statusColor(vehicle.status))
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicle.name).font(.subheadline)
                    if let driver = vehicle.driverName {
                        Text(driver).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Unassigned").font(.caption).foregroundStyle(.orange)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(vehicle.status.capitalized)
                        .font(.caption)
                        .foregroundStyle(statusColor(vehicle.status))

                    if let inspDate = vehicle.lastInspectionDate {
                        let isToday = Calendar.current.isDateInToday(inspDate)
                        Text(isToday ? "Inspected" : "No inspection")
                            .font(.caption2)
                            .foregroundStyle(isToday ? .green : .red)
                    }
                }
            }
        }
    }
} header: {
    HStack {
        Text("Vehicles")
        Spacer()
        Text("\(vehicles.count)").foregroundStyle(.secondary)
    }
}

func vehicleIcon(_ type: String) -> String {
    switch type {
    case "van": return "car.fill"
    case "truck": return "truck.box.fill"
    case "pickup": return "suv.side.fill"
    default: return "car.fill"
    }
}
```

### Step 4: Cost Summary (Hat-Gated)

```swift
if appCore.hasPermission("view_fleet_financials") {
    Section("Cost Summary — This Month") {
        if let stats = fleetStats {
            HStack {
                CostSummaryCard(title: "Fuel",
                               value: stats.fuelCostMTD ?? 0,
                               icon: "fuelpump.fill", color: .orange)
                CostSummaryCard(title: "Maintenance",
                               value: stats.maintenanceCostMTD ?? 0,
                               icon: "wrench.fill", color: .red)
            }

            // Week-over-week comparison placeholder
            Text("Detailed cost analysis available in Fleet Reports")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CostSummaryCard: View {
    let title: String
    let value: Double
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text("$\(Int(value))").font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

### Step 5: Upcoming Maintenance

```swift
@State private var upcomingMaintenance: [FleetMaintenanceItem] = []

Section {
    if upcomingMaintenance.isEmpty {
        Text("No upcoming maintenance").foregroundStyle(.secondary)
    } else {
        ForEach(upcomingMaintenance) { item in
            HStack {
                Text(item.vehicleName).font(.subheadline)
                Spacer()
                let days = Int(item.daysUntil)
                if days < 0 {
                    Text("Overdue \(abs(days))d")
                        .font(.caption).foregroundStyle(.red)
                } else if days == 0 {
                    Text("Due Today")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("In \(days)d")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
} header: {
    Text("Upcoming Maintenance")
}
```

### Step 6: Fleet Reports Reference

```swift
Section {
    NavigationLink {
        // Navigate to Reports > Fleet
        Text("Fleet Reports")  // placeholder — reports module handles this
    } label: {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.blue)
            Text("Fleet Reports")
            Spacer()
            Text("Fuel, Mileage, Maintenance trends")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
} header: {
    Text("Analytics")
}
```

## Important Notes
- Two smart card rows: fleet status (always visible) and costs (hat-gated)
- Cost stats are month-to-date (MTD)
- Vehicle status list shows current driver, inspection status, and vehicle type icon
- Overdue inspections = active vehicles with no inspection today
- Cost summary section only visible with view_fleet_financials permission
- Fleet Reports link goes to the Reports module (49C)
- Upcoming maintenance sorted by earliest due date

## Success Criteria
- [ ] Smart cards row 1: Vehicles, Active, Maint. Due, Overdue Inspect, Trailers
- [ ] Smart cards row 2 (hat-gated): Fuel MTD, Miles MTD, Maint. MTD
- [ ] Vehicle status list with driver, type icon, inspection status
- [ ] Cost summary section (hat-gated with view_fleet_financials)
- [ ] Upcoming maintenance with days-until countdown
- [ ] Fleet Reports navigation link
- [ ] Service: getFleetDashboardStats, getVehicleStatusList, getUpcomingFleetMaintenance
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 48E Results (YYYY-MM-DD)
- Fleet dashboard: 5+3 smart cards
- Vehicle status list with drivers
- Cost summary (hat-gated)
- Upcoming maintenance
- Service: 3 dashboard methods
- Build: PASS/FAIL
```

**Fleet module complete. Proceed to Reports prompts (49A).**
