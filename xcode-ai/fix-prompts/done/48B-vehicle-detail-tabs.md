# 48B — Vehicle Detail Tabs

> **Chain position:** 48A → **48B** → 48C
> **Prerequisite:** 48A (vehicle inventory types)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read the existing vehicle detail page and `FleetService.swift`. Rebuild with 7 tabs: Overview, Parts, Tools, Assignments, Maintenance, Usage, Inspections.

## Context

The vehicle detail page needs a tabbed layout so managers and drivers can see everything about a specific vehicle. Overview shows the vehicle summary. Parts tab shows spare parts with health bars plus the transfer area. Tools tab lists checked-out tools with status. Assignments shows driver history. Maintenance tracks scheduled and completed maintenance. Usage combines fuel and mileage tracking. Inspections shows pre-trip inspection history.

## Task

### Step 1: Tab Structure

```swift
struct IOSVehicleDetailPage: View {
    let vehicleId: Int64
    @EnvironmentObject var appCore: AppCore
    @State private var selectedTab: VehicleTab = .overview
    @State private var vehicle: VehicleDetail?
    @State private var loadError: String?
    @State private var isLoading = true

    enum VehicleTab: String, CaseIterable {
        case overview = "Overview"
        case parts = "Parts"
        case tools = "Tools"
        case assignments = "Assignments"
        case maintenance = "Maintenance"
        case usage = "Usage"
        case inspections = "Inspections"
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let vehicle = vehicle {
                vehicleContent(vehicle)
            }
        }
        .navigationTitle(vehicle?.name ?? "Vehicle")
        .task { await loadData() }
        .refreshable { await loadData() }
    }

    func vehicleContent(_ vehicle: VehicleDetail) -> some View {
        VStack(spacing: 0) {
            // Tab picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(VehicleTab.allCases, id: \.self) { tab in
                        Button(tab.rawValue) {
                            selectedTab = tab
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedTab == tab ? .blue : .gray)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            // Tab content
            List {
                switch selectedTab {
                case .overview: overviewTab(vehicle)
                case .parts: partsTab(vehicle)
                case .tools: toolsTab(vehicle)
                case .assignments: assignmentsTab(vehicle)
                case .maintenance: maintenanceTab(vehicle)
                case .usage: usageTab(vehicle)
                case .inspections: inspectionsTab(vehicle)
                }
            }
        }
    }
}
```

### Step 2: Overview Tab

```swift
func overviewTab(_ vehicle: VehicleDetail) -> some View {
    Group {
        Section("Vehicle Info") {
            LabeledContent("Name", value: vehicle.name)
            LabeledContent("Type", value: vehicle.vehicleType.capitalized)
            if let vin = vehicle.vin {
                LabeledContent("VIN", value: vin)
            }
            LabeledContent("Year", value: "\(vehicle.year ?? 0)")
            LabeledContent("Make/Model", value: "\(vehicle.make ?? "") \(vehicle.model ?? "")")
            LabeledContent("License Plate", value: vehicle.licensePlate ?? "—")
            LabeledContent("Status", value: vehicle.status.capitalized)
        }

        Section("Current Assignment") {
            if let driver = vehicle.currentDriver {
                HStack {
                    Image(systemName: "person.fill")
                    Text(driver)
                }
            } else {
                Text("Unassigned").foregroundStyle(.secondary)
            }
        }

        Section("Quick Stats") {
            LabeledContent("Odometer", value: "\(vehicle.odometer ?? 0) mi")
            if let fuel = vehicle.fuelLevel {
                LabeledContent("Fuel Level", value: "\(Int(fuel * 100))%")
            }
            LabeledContent("Last Inspection", value: vehicle.lastInspectionDate?.formatted(.dateTime.month().day()) ?? "Never")
        }
    }
}
```

### Step 3: Parts Tab

```swift
@State private var vehicleParts: [VehiclePartItem] = []
@State private var transferParts: [VehiclePartItem] = []

func partsTab(_ vehicle: VehicleDetail) -> some View {
    Group {
        // Spare parts (permanent stock)
        Section("Spare Parts") {
            if vehicleParts.isEmpty {
                Text("No spare parts loaded").foregroundStyle(.secondary)
            } else {
                ForEach(vehicleParts) { part in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.partName).font(.subheadline)
                            Text("Qty: \(part.quantity) / Target: \(part.targetQty ?? 0)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Health bar
                        if let target = part.targetQty, target > 0 {
                            ProgressView(value: Double(part.quantity), total: Double(target))
                                .tint(healthColor(current: part.quantity, min: part.minQty, target: target))
                                .frame(width: 60)
                        }
                    }
                }
            }
        }

        // Transfer area
        Section("Transfer Area") {
            if transferParts.isEmpty {
                Text("No items in transit").foregroundStyle(.secondary)
            } else {
                ForEach(transferParts) { part in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.partName).font(.subheadline)
                            HStack(spacing: 4) {
                                Text(part.sourceLocation ?? "?")
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                Text(part.destinationLocation ?? "?")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("x\(part.quantity)")
                            .font(.subheadline).monospacedDigit()
                    }
                }
            }
        }
    }
}

func healthColor(current: Int, min: Int?, target: Int) -> Color {
    if current < (min ?? 0) { return .red }
    if current >= target { return .green }
    return .orange
}
```

### Step 4: Tools Tab

```swift
@State private var vehicleTools: [VehicleToolItem] = []

func toolsTab(_ vehicle: VehicleDetail) -> some View {
    Section("Checked-Out Tools") {
        if vehicleTools.isEmpty {
            Text("No tools on this vehicle").foregroundStyle(.secondary)
        } else {
            ForEach(vehicleTools) { tool in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.toolName).font(.subheadline)
                        Text("Checked out by \(tool.checkedOutBy)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(tool.condition.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(conditionColor(tool.condition).opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }
}
```

### Step 5: Assignments Tab

```swift
@State private var assignments: [VehicleAssignment] = []

func assignmentsTab(_ vehicle: VehicleDetail) -> some View {
    Section("Driver History") {
        ForEach(assignments) { assignment in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(assignment.driverName).font(.subheadline)
                    Text("\(assignment.startDate.formatted(.dateTime.month().day().year())) — \(assignment.endDate?.formatted(.dateTime.month().day().year()) ?? "Present")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if assignment.endDate == nil {
                    Text("Active")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
    }
}
```

### Step 6: Maintenance Tab

```swift
@State private var maintenanceRecords: [VehicleMaintenanceRecord] = []
@State private var upcomingMaintenance: [VehicleMaintenanceSchedule] = []

func maintenanceTab(_ vehicle: VehicleDetail) -> some View {
    Group {
        Section("Upcoming") {
            if upcomingMaintenance.isEmpty {
                Text("No upcoming maintenance").foregroundStyle(.secondary)
            } else {
                ForEach(upcomingMaintenance) { item in
                    HStack {
                        Text(item.description).font(.subheadline)
                        Spacer()
                        let overdue = item.dueDate < Date()
                        Text(item.dueDate, format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundStyle(overdue ? .red : .secondary)
                    }
                }
            }
        }

        Section("History") {
            ForEach(maintenanceRecords) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.description).font(.subheadline)
                    HStack {
                        Text(record.performedAt, format: .dateTime.month().day().year())
                        if let cost = record.cost {
                            Text("$\(cost, specifier: "%.2f")")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

### Step 7: Usage Tab (Combined Fuel + Mileage)

```swift
@State private var fuelLogs: [FuelLog] = []
@State private var mileageLogs: [MileageLog] = []

func usageTab(_ vehicle: VehicleDetail) -> some View {
    Group {
        Section("Fuel History") {
            ForEach(fuelLogs.prefix(10)) { log in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(log.gallons, specifier: "%.1f") gal")
                            .font(.subheadline)
                        Text(log.loggedAt, format: .dateTime.month().day())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let cost = log.cost {
                        Text("$\(cost, specifier: "%.2f")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }

        Section("Mileage") {
            ForEach(mileageLogs.prefix(10)) { log in
                HStack {
                    Text("\(log.miles) mi")
                        .font(.subheadline)
                    Spacer()
                    Text(log.loggedAt, format: .dateTime.month().day())
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

### Step 8: Inspections Tab

```swift
@State private var inspections: [InspectionRecord] = []

func inspectionsTab(_ vehicle: VehicleDetail) -> some View {
    Section("Pre-Trip Inspections") {
        if inspections.isEmpty {
            Text("No inspections recorded").foregroundStyle(.secondary)
        } else {
            ForEach(inspections) { inspection in
                HStack {
                    Image(systemName: inspectionIcon(inspection.result))
                        .foregroundStyle(inspectionColor(inspection.result))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(inspection.inspectorName).font(.subheadline)
                        Text(inspection.performedAt, format: .dateTime.month().day().year().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(inspection.result.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(inspectionColor(inspection.result).opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

func inspectionIcon(_ result: String) -> String {
    switch result {
    case "pass": return "checkmark.circle.fill"
    case "fail": return "xmark.circle.fill"
    case "conditional": return "exclamationmark.circle.fill"
    default: return "questionmark.circle"
    }
}

func inspectionColor(_ result: String) -> Color {
    switch result {
    case "pass": return .green
    case "fail": return .red
    case "conditional": return .orange
    default: return .secondary
    }
}
```

## Important Notes
- 7 tabs in a horizontal scrollable picker (not system TabView — too many tabs)
- Parts tab separates Spare Parts (permanent stock with health bars) from Transfer Area (in-transit with source/dest)
- Usage tab combines fuel logs and mileage in one view
- Inspections show Pass/Fail/Conditional with color coding
- All tabs load data lazily (only when selected)
- Each tab has its own loading state — don't reload everything on tab switch

## Success Criteria
- [ ] 7-tab horizontal picker layout
- [ ] Overview: vehicle info, current assignment, quick stats
- [ ] Parts: spare parts with health bars + transfer area with source/dest
- [ ] Tools: checked-out tools with condition badges
- [ ] Assignments: driver history with active indicator
- [ ] Maintenance: upcoming + history with costs
- [ ] Usage: combined fuel + mileage logs
- [ ] Inspections: Pass/Fail/Conditional with color coding
- [ ] Lazy tab loading
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 48B Results (YYYY-MM-DD)
- 7-tab vehicle detail layout
- Parts: spare parts health bars + transfer area
- Tools, Assignments, Maintenance, Usage, Inspections tabs
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 48C.**
