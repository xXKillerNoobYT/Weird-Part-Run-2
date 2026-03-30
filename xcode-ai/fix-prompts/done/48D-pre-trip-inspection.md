# 48D — Pre-Trip Inspection

> **Chain position:** 48A → 48B → 48C → **48D** → 48E
> **Prerequisite:** 48B (vehicle detail inspections tab)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read any existing inspection pages and `FleetService.swift`. Build pre-trip inspection with customizable checklist per vehicle type + trailer type, 4 sections, Pass/Fail/Conditional results, and clock-in integration.

## Context

Pre-trip inspections are required before driving. The checklist varies by vehicle type (van vs truck vs trailer). There are 4 sections: Exterior (tires, lights, body damage), Interior (mirrors, gauges, seatbelts), Equipment (fire extinguisher, first aid, safety cones), and Notes (free-text observations). The result is Pass, Fail, or Conditional (minor issues noted but safe to drive). Failed inspections should block clock-in until resolved. If a trailer is attached, both vehicle AND trailer checklists are combined.

## Task

### Step 1: Migration

```swift
// Migration: inspection templates + records
try db.create(table: "inspection_templates") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("vehicle_type", .text).notNull()  // "van", "truck", "trailer", etc.
    t.column("section", .text).notNull()        // "exterior", "interior", "equipment"
    t.column("item_name", .text).notNull()
    t.column("item_description", .text)
    t.column("is_critical", .boolean).notNull().defaults(to: false)  // critical = auto-fail if not OK
    t.column("sort_order", .integer).notNull().defaults(to: 0)
    t.column("is_active", .boolean).notNull().defaults(to: true)
}

try db.create(table: "inspection_records") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("vehicle_id", .integer).notNull().references("vehicles")
    t.column("trailer_id", .integer).references("trailers")
    t.column("inspector_id", .integer).notNull().references("users")
    t.column("result", .text).notNull()  // "pass", "fail", "conditional"
    t.column("notes", .text)
    t.column("performed_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    t.column("odometer_reading", .integer)
    t.column("fuel_level", .double)
}

try db.create(table: "inspection_results") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("inspection_id", .integer).notNull().references("inspection_records")
    t.column("template_item_id", .integer).notNull().references("inspection_templates")
    t.column("status", .text).notNull()  // "ok", "issue", "na"
    t.column("notes", .text)
    t.column("photo_path", .text)
}

// Seed default inspection items
let vehicleExterior = [
    ("Tires - Tread Depth", true), ("Tires - Pressure", true),
    ("Headlights", true), ("Taillights", true), ("Turn Signals", true),
    ("Brake Lights", true), ("Mirrors", false), ("Windshield", false),
    ("Body Damage", false), ("Fluid Leaks", true)
]
let vehicleInterior = [
    ("Seatbelt", true), ("Horn", true), ("Gauges Working", false),
    ("Wipers", false), ("Heater/AC", false), ("Dashboard Lights", false)
]
let vehicleEquipment = [
    ("Fire Extinguisher", true), ("First Aid Kit", false),
    ("Safety Cones/Triangles", false), ("Spare Tire", false)
]
// Insert seed data for "van" and "truck" vehicle types...
```

### Step 2: Inspection Flow UI

```swift
struct PreTripInspectionView: View {
    let vehicleId: Int64
    let trailerId: Int64?
    @EnvironmentObject var appCore: AppCore
    @State private var checklistItems: [InspectionCheckItem] = []
    @State private var generalNotes: String = ""
    @State private var odometerReading: String = ""
    @State private var fuelLevel: Double = 1.0
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isLoading = true
    @State private var loadError: String?
    let onComplete: (String) -> Void  // passes result: "pass"/"fail"/"conditional"

    struct InspectionCheckItem: Identifiable {
        let id: Int64
        let templateItemId: Int64
        let section: String
        let itemName: String
        let itemDescription: String?
        let isCritical: Bool
        var status: String  // "ok", "issue", "na"
        var notes: String
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading checklist...")
                } else if let error = loadError {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle",
                                          description: Text(error))
                } else {
                    inspectionForm
                }
            }
            .navigationTitle("Pre-Trip Inspection")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submitInspection() }
                    }
                    .disabled(!allItemsChecked || isSaving)
                }
            }
            .task { await loadChecklist() }
        }
    }

    var inspectionForm: some View {
        List {
            // Progress
            Section {
                let checked = checklistItems.filter { $0.status != "" }.count
                ProgressView(value: Double(checked), total: Double(checklistItems.count))
                    .tint(.blue)
                Text("\(checked)/\(checklistItems.count) items checked")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Exterior section
            let exterior = checklistItems.filter { $0.section == "exterior" }
            if !exterior.isEmpty {
                Section("Exterior") {
                    ForEach($checklistItems) { $item in
                        if item.section == "exterior" {
                            InspectionItemRow(item: $item)
                        }
                    }
                }
            }

            // Interior section
            let interior = checklistItems.filter { $0.section == "interior" }
            if !interior.isEmpty {
                Section("Interior") {
                    ForEach($checklistItems) { $item in
                        if item.section == "interior" {
                            InspectionItemRow(item: $item)
                        }
                    }
                }
            }

            // Equipment section
            let equipment = checklistItems.filter { $0.section == "equipment" }
            if !equipment.isEmpty {
                Section("Equipment") {
                    ForEach($checklistItems) { $item in
                        if item.section == "equipment" {
                            InspectionItemRow(item: $item)
                        }
                    }
                }
            }

            // Vehicle readings
            Section("Readings") {
                TextField("Odometer", text: $odometerReading)
                    .keyboardType(.numberPad)
                HStack {
                    Text("Fuel Level")
                    Slider(value: $fuelLevel, in: 0...1, step: 0.05)
                    Text("\(Int(fuelLevel * 100))%")
                        .font(.caption).monospacedDigit()
                }
            }

            // Notes
            Section("Notes") {
                TextField("General observations...", text: $generalNotes, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let error = saveError {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
    }

    var allItemsChecked: Bool {
        checklistItems.allSatisfy { $0.status != "" }
    }
}
```

### Step 3: Inspection Item Row

```swift
struct InspectionItemRow: View {
    @Binding var item: PreTripInspectionView.InspectionCheckItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.itemName)
                    .font(.subheadline)
                if item.isCritical {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                Spacer()
            }

            // Status picker
            HStack(spacing: 8) {
                StatusButton(label: "OK", systemImage: "checkmark.circle.fill",
                            color: .green, isSelected: item.status == "ok") {
                    item.status = "ok"
                }
                StatusButton(label: "Issue", systemImage: "xmark.circle.fill",
                            color: .red, isSelected: item.status == "issue") {
                    item.status = "issue"
                }
                StatusButton(label: "N/A", systemImage: "minus.circle.fill",
                            color: .gray, isSelected: item.status == "na") {
                    item.status = "na"
                }
            }

            // Notes field when issue
            if item.status == "issue" {
                TextField("Describe the issue...", text: $item.notes)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusButton: View {
    let label: String
    let systemImage: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(label)
            }
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(isSelected ? color.opacity(0.2) : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? color : .secondary.opacity(0.3)))
        }
        .buttonStyle(.plain)
    }
}
```

### Step 4: Result Calculation + Submit

```swift
func submitInspection() async {
    isSaving = true
    saveError = nil
    guard let service = appCore.fleetService else {
        saveError = "Fleet service not available"
        isSaving = false
        return
    }

    // Calculate result
    let hasCriticalIssue = checklistItems.contains { $0.isCritical && $0.status == "issue" }
    let hasAnyIssue = checklistItems.contains { $0.status == "issue" }

    let result: String
    if hasCriticalIssue {
        result = "fail"       // Critical item failed = FAIL
    } else if hasAnyIssue {
        result = "conditional" // Non-critical issues = CONDITIONAL
    } else {
        result = "pass"       // All OK = PASS
    }

    do {
        try await service.saveInspection(
            vehicleId: vehicleId,
            trailerId: trailerId,
            inspectorId: appCore.currentUserId,
            result: result,
            items: checklistItems.map { item in
                InspectionItemResult(
                    templateItemId: item.templateItemId,
                    status: item.status,
                    notes: item.notes.isEmpty ? nil : item.notes
                )
            },
            notes: generalNotes.isEmpty ? nil : generalNotes,
            odometerReading: Int(odometerReading),
            fuelLevel: fuelLevel
        )
        onComplete(result)
    } catch {
        saveError = error.localizedDescription
    }
    isSaving = false
}
```

### Step 5: Clock-In Integration

```swift
// In clock-in flow, check latest inspection
func checkInspectionRequired(vehicleId: Int64) async throws -> InspectionRequirement {
    try await db.read { db in
        let latestInspection = try Row.fetchOne(db, sql: """
            SELECT result, performed_at FROM inspection_records
            WHERE vehicle_id = ?
            ORDER BY performed_at DESC LIMIT 1
            """, arguments: [vehicleId])

        guard let inspection = latestInspection else {
            return .required(reason: "No inspection on record")
        }

        let result: String = inspection["result"]
        let performedAt: Date = inspection["performed_at"]
        let isToday = Calendar.current.isDateInToday(performedAt)

        if result == "fail" {
            return .blocked(reason: "Vehicle failed last inspection")
        }
        if !isToday {
            return .required(reason: "No inspection today")
        }
        return .cleared
    }
}

enum InspectionRequirement: Sendable {
    case cleared
    case required(reason: String)
    case blocked(reason: String)
}
```

### Step 6: Service Methods

```swift
// MARK: - Inspections

func getInspectionChecklist(vehicleType: String, trailerType: String?) async throws -> [InspectionTemplate]

func saveInspection(
    vehicleId: Int64, trailerId: Int64?, inspectorId: Int64,
    result: String, items: [InspectionItemResult],
    notes: String?, odometerReading: Int?, fuelLevel: Double?
) async throws {
    try await db.write { db in
        try db.execute(sql: """
            INSERT INTO inspection_records
            (vehicle_id, trailer_id, inspector_id, result, notes, odometer_reading, fuel_level)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [vehicleId, trailerId, inspectorId, result, notes,
                            odometerReading, fuelLevel])

        let inspectionId = db.lastInsertedRowID

        for item in items {
            try db.execute(sql: """
                INSERT INTO inspection_results
                (inspection_id, template_item_id, status, notes)
                VALUES (?, ?, ?, ?)
                """, arguments: [inspectionId, item.templateItemId, item.status, item.notes])
        }

        // Update vehicle readings
        if let odometer = odometerReading {
            try db.execute(sql: """
                UPDATE vehicles SET odometer = ?, fuel_level = ?,
                last_inspection_date = date('now'), updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [odometer, fuelLevel, vehicleId])
        }
    }
}

func getInspectionHistory(vehicleId: Int64, limit: Int = 20) async throws -> [InspectionRecord]
```

## Important Notes
- Checklist items come from inspection_templates, filtered by vehicle type
- If a trailer is attached, BOTH vehicle AND trailer checklists are combined
- Critical items (is_critical=true) cause auto-FAIL if marked "issue"
- Non-critical issues result in "conditional" (safe to drive with noted issues)
- Clock-in checks latest inspection: FAIL blocks clock-in, no inspection today requires one
- Each item has 3 states: OK (green), Issue (red + notes required), N/A (gray)
- Seed default inspection items for common vehicle types

## Success Criteria
- [ ] Migration: inspection_templates, inspection_records, inspection_results + seed data
- [ ] Customizable checklist per vehicle type + trailer type
- [ ] 4 sections: Exterior, Interior, Equipment, Notes
- [ ] 3 states per item: OK, Issue, N/A with visual buttons
- [ ] Critical items auto-fail on "issue"
- [ ] Result: Pass/Fail/Conditional
- [ ] Clock-in integration: block on fail, require if no inspection today
- [ ] Odometer + fuel level readings
- [ ] Progress bar for completion tracking
- [ ] Service: getInspectionChecklist, saveInspection, checkInspectionRequired
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 48D Results (YYYY-MM-DD)
- Pre-trip inspection checklist with 4 sections
- Critical item auto-fail logic
- Clock-in integration
- Migration: 3 tables + seed data
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 48E.**
