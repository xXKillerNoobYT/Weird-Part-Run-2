# 47E — Tool Maintenance Types

> **Chain position:** 47A → 47B → 47C → 47D → **47E** → 47F
> **Prerequisite:** 47A (dashboard maintenance due section)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read `ToolsService.swift` and any existing maintenance pages. Add 5 maintenance types with scheduling and tracking: time-based, usage-based, schedule-based, decreasing-based (confidence decay), and condition-triggered.

## Context

Different tools need different maintenance strategies. A drill might need maintenance every 500 hours of use (usage-based). A fire extinguisher needs annual inspection (time-based). A saw blade needs replacement on a fixed schedule (schedule-based). Some tools lose reliability over time at a predictable decay rate (decreasing-based — confidence math). Others only need maintenance when a condition check flags damage (condition-triggered). Each type has its own tracking and scheduling logic.

## Task

### Step 1: Migration

```swift
// Migration: tool_maintenance table
try db.create(table: "tool_maintenance_configs") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("tool_id", .integer).notNull().references("tools")
    t.column("maintenance_type", .text).notNull()
        // "time_based", "usage_based", "schedule_based", "decreasing_based", "condition_triggered"
    t.column("interval_days", .integer)         // time_based: days between maintenance
    t.column("usage_threshold", .double)        // usage_based: hours/cycles before maintenance
    t.column("schedule_cron", .text)            // schedule_based: e.g., "0 0 1 */6 *" (every 6 months)
    t.column("decay_rate", .double)             // decreasing_based: confidence decay per day (0.0-1.0)
    t.column("decay_floor", .double)            // decreasing_based: minimum confidence before mandatory
    t.column("condition_triggers", .text)       // condition_triggered: JSON array ["poor", "damaged"]
    t.column("description", .text)
    t.column("is_active", .boolean).notNull().defaults(to: true)
    t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
}

try db.create(table: "tool_maintenance_records") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("tool_id", .integer).notNull().references("tools")
    t.column("config_id", .integer).references("tool_maintenance_configs")
    t.column("maintenance_type", .text).notNull()
    t.column("performed_by", .integer).notNull().references("users")
    t.column("performed_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    t.column("condition_before", .text)
    t.column("condition_after", .text)
    t.column("notes", .text)
    t.column("cost", .double)
    t.column("next_due_date", .date)       // calculated next maintenance date
    t.column("usage_at_maintenance", .double)  // usage counter reading at time of maintenance
}

// Add usage tracking to tools
try db.alter(table: "tools") { t in
    t.add(column: "total_usage_hours", .double).defaults(to: 0)
    t.add(column: "confidence_score", .double).defaults(to: 1.0)  // 1.0 = full confidence
    t.add(column: "last_maintenance_date", .date)
}
```

### Step 2: Maintenance Type Service Methods

```swift
// MARK: - Maintenance Types

enum MaintenanceType: String, CaseIterable, Sendable {
    case timeBased = "time_based"
    case usageBased = "usage_based"
    case scheduleBased = "schedule_based"
    case decreasingBased = "decreasing_based"
    case conditionTriggered = "condition_triggered"

    var displayName: String {
        switch self {
        case .timeBased: return "Time-Based"
        case .usageBased: return "Usage-Based"
        case .scheduleBased: return "Schedule-Based"
        case .decreasingBased: return "Confidence Decay"
        case .conditionTriggered: return "Condition-Triggered"
        }
    }

    var icon: String {
        switch self {
        case .timeBased: return "clock.fill"
        case .usageBased: return "gauge.with.dots.needle.50percent"
        case .scheduleBased: return "calendar"
        case .decreasingBased: return "chart.line.downtrend.xyaxis"
        case .conditionTriggered: return "exclamationmark.triangle.fill"
        }
    }
}

/// Calculate next maintenance due date for a tool
func calculateNextMaintenanceDate(toolId: Int64) async throws -> Date? {
    try await db.read { db in
        let configs = try Row.fetchAll(db, sql: """
            SELECT * FROM tool_maintenance_configs
            WHERE tool_id = ? AND is_active = 1
            """, arguments: [toolId])

        let tool = try Row.fetchOne(db, sql: """
            SELECT total_usage_hours, confidence_score, last_maintenance_date
            FROM tools WHERE id = ?
            """, arguments: [toolId])

        guard let tool = tool else { return nil }

        var earliestDue: Date?

        for config in configs {
            let type: String = config["maintenance_type"]
            var dueDate: Date?

            switch type {
            case "time_based":
                if let intervalDays: Int = config["interval_days"],
                   let lastMaint: Date = tool["last_maintenance_date"] {
                    dueDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: lastMaint)
                }

            case "usage_based":
                if let threshold: Double = config["usage_threshold"],
                   let currentUsage: Double = tool["total_usage_hours"] {
                    let lastRecord = try Row.fetchOne(db, sql: """
                        SELECT usage_at_maintenance FROM tool_maintenance_records
                        WHERE tool_id = ? AND maintenance_type = 'usage_based'
                        ORDER BY performed_at DESC LIMIT 1
                        """, arguments: [toolId])
                    let lastUsage = lastRecord?["usage_at_maintenance"] as? Double ?? 0
                    let remaining = threshold - (currentUsage - lastUsage)
                    if remaining <= 0 {
                        dueDate = Date()  // overdue
                    }
                    // Can't predict exact date for usage-based
                }

            case "schedule_based":
                // Parse schedule_cron for next occurrence
                // Simplified: use interval_days as fallback
                if let intervalDays: Int = config["interval_days"],
                   let lastMaint: Date = tool["last_maintenance_date"] {
                    dueDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: lastMaint)
                }

            case "decreasing_based":
                if let decayRate: Double = config["decay_rate"],
                   let floor: Double = config["decay_floor"],
                   let currentConfidence: Double = tool["confidence_score"] {
                    // Days until confidence drops below floor
                    // confidence(t) = confidence_0 * (1 - decay_rate)^t
                    // Solve for t: floor = current * (1 - decay_rate)^t
                    // t = log(floor/current) / log(1 - decay_rate)
                    if currentConfidence > floor && decayRate > 0 && decayRate < 1 {
                        let daysUntilFloor = log(floor / currentConfidence) / log(1.0 - decayRate)
                        dueDate = Calendar.current.date(byAdding: .day, value: Int(ceil(daysUntilFloor)), to: Date())
                    } else if currentConfidence <= floor {
                        dueDate = Date()  // already below floor
                    }
                }

            case "condition_triggered":
                // No scheduled date — triggered by condition checks
                break

            default:
                break
            }

            if let due = dueDate {
                if earliestDue == nil || due < earliestDue! {
                    earliestDue = due
                }
            }
        }

        return earliestDue
    }
}

/// Record maintenance performed
func recordMaintenance(
    toolId: Int64, configId: Int64?, maintenanceType: String,
    performedBy: Int64, conditionBefore: String?, conditionAfter: String?,
    notes: String?, cost: Double?
) async throws {
    try await db.write { db in
        let currentUsage = try Double.fetchOne(db, sql: """
            SELECT total_usage_hours FROM tools WHERE id = ?
            """, arguments: [toolId]) ?? 0

        // Calculate next due date
        var nextDue: Date?
        if let configId = configId {
            let config = try Row.fetchOne(db, sql: """
                SELECT * FROM tool_maintenance_configs WHERE id = ?
                """, arguments: [configId])
            if let intervalDays: Int = config?["interval_days"] {
                nextDue = Calendar.current.date(byAdding: .day, value: intervalDays, to: Date())
            }
        }

        try db.execute(sql: """
            INSERT INTO tool_maintenance_records
            (tool_id, config_id, maintenance_type, performed_by,
             condition_before, condition_after, notes, cost,
             next_due_date, usage_at_maintenance)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [toolId, configId, maintenanceType, performedBy,
                            conditionBefore, conditionAfter, notes, cost,
                            nextDue, currentUsage])

        // Reset confidence score for decreasing-based
        if maintenanceType == "decreasing_based" {
            try db.execute(sql: """
                UPDATE tools SET confidence_score = 1.0,
                last_maintenance_date = date('now'),
                updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [toolId])
        } else {
            try db.execute(sql: """
                UPDATE tools SET last_maintenance_date = date('now'),
                next_maintenance_date = ?,
                updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [nextDue, toolId])
        }
    }
}

/// Update confidence scores daily (call on app launch)
func updateConfidenceScores() async throws {
    try await db.write { db in
        let configs = try Row.fetchAll(db, sql: """
            SELECT tmc.tool_id, tmc.decay_rate, t.confidence_score, t.last_maintenance_date
            FROM tool_maintenance_configs tmc
            JOIN tools t ON tmc.tool_id = t.id
            WHERE tmc.maintenance_type = 'decreasing_based' AND tmc.is_active = 1
            """)

        for config in configs {
            let toolId: Int64 = config["tool_id"]
            let decayRate: Double = config["decay_rate"] ?? 0.01
            let currentScore: Double = config["confidence_score"] ?? 1.0

            let newScore = max(0, currentScore * (1.0 - decayRate))

            try db.execute(sql: """
                UPDATE tools SET confidence_score = ?,
                updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [newScore, toolId])
        }
    }
}
```

### Step 3: Maintenance Configuration UI

```swift
struct MaintenanceConfigSheet: View {
    let tool: ToolDetail
    @EnvironmentObject var appCore: AppCore
    @State private var selectedType: MaintenanceType = .timeBased
    @State private var intervalDays: Int = 90
    @State private var usageThreshold: Double = 500
    @State private var decayRate: Double = 0.02
    @State private var decayFloor: Double = 0.3
    @State private var conditionTriggers: Set<String> = ["poor", "damaged"]
    @State private var description: String = ""
    @State private var isSaving = false
    @State private var saveError: String?
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Maintenance Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(MaintenanceType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }
                }

                // Type-specific configuration
                switch selectedType {
                case .timeBased:
                    Section("Interval") {
                        Stepper("Every \(intervalDays) days", value: $intervalDays, in: 1...365)
                    }
                case .usageBased:
                    Section("Usage Threshold") {
                        HStack {
                            Text("After")
                            TextField("Hours", value: $usageThreshold, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("hours of use")
                        }
                    }
                case .scheduleBased:
                    Section("Schedule") {
                        Stepper("Every \(intervalDays) days", value: $intervalDays, in: 1...730)
                        Text("Maintenance on a fixed calendar schedule")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .decreasingBased:
                    Section("Confidence Decay") {
                        HStack {
                            Text("Decay rate:")
                            Slider(value: $decayRate, in: 0.001...0.1, step: 0.001)
                            Text("\(decayRate, specifier: "%.1f")%/day")
                                .font(.caption).monospacedDigit()
                        }
                        HStack {
                            Text("Maintenance floor:")
                            Slider(value: $decayFloor, in: 0.1...0.9, step: 0.05)
                            Text("\(Int(decayFloor * 100))%")
                                .font(.caption).monospacedDigit()
                        }
                        // Preview
                        let daysUntil = decayRate > 0
                            ? Int(ceil(log(decayFloor) / log(1.0 - decayRate)))
                            : 999
                        Text("At current rate, maintenance due in ~\(daysUntil) days")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .conditionTriggered:
                    Section("Trigger Conditions") {
                        ForEach(["fair", "poor", "damaged"], id: \.self) { condition in
                            Toggle(condition.capitalized, isOn: Binding(
                                get: { conditionTriggers.contains(condition) },
                                set: { isOn in
                                    if isOn { conditionTriggers.insert(condition) }
                                    else { conditionTriggers.remove(condition) }
                                }
                            ))
                        }
                        Text("Maintenance flagged when condition check returns any selected level")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Description") {
                    TextField("What maintenance is needed?", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let error = saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add Maintenance Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveConfig() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    func saveConfig() async {
        isSaving = true
        saveError = nil
        guard let service = appCore.toolsService else {
            saveError = "Tools service not available"
            isSaving = false
            return
        }
        do {
            try await service.createMaintenanceConfig(
                toolId: tool.id,
                type: selectedType.rawValue,
                intervalDays: [.timeBased, .scheduleBased].contains(selectedType) ? intervalDays : nil,
                usageThreshold: selectedType == .usageBased ? usageThreshold : nil,
                decayRate: selectedType == .decreasingBased ? decayRate : nil,
                decayFloor: selectedType == .decreasingBased ? decayFloor : nil,
                conditionTriggers: selectedType == .conditionTriggered ? Array(conditionTriggers) : nil,
                description: description.isEmpty ? nil : description
            )
            onComplete()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
```

### Step 4: Confidence Score Display

```swift
// On tool detail page, show confidence gauge for decreasing-based tools
if let confidence = tool.confidenceScore, tool.hasDecreasingMaintenance {
    Section("Reliability") {
        VStack(spacing: 8) {
            Gauge(value: confidence, in: 0...1) {
                Text("Confidence")
            } currentValueLabel: {
                Text("\(Int(confidence * 100))%")
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(confidenceColor(confidence))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(confidenceGradient)

            if let daysUntilMaintenance = tool.daysUntilMaintenance {
                Text("Maintenance due in \(daysUntilMaintenance) days")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

func confidenceColor(_ score: Double) -> Color {
    if score > 0.7 { return .green }
    if score > 0.4 { return .orange }
    return .red
}

var confidenceGradient: Gradient {
    Gradient(colors: [.red, .orange, .green])
}
```

## Important Notes
- 5 maintenance types each have different tracking logic
- Time-based: simple interval in days from last maintenance
- Usage-based: cumulative hours/cycles tracked on the tool
- Schedule-based: fixed calendar dates (uses interval_days as simplified form)
- Decreasing-based: confidence = current * (1 - decay_rate)^days; maintenance when < floor
- Condition-triggered: no schedule, triggered by condition check results
- updateConfidenceScores() should run on app launch to keep decay current
- A tool can have multiple maintenance configs (e.g., time-based oil change + usage-based blade replacement)

## Success Criteria
- [ ] Migration: tool_maintenance_configs + tool_maintenance_records + tools columns
- [ ] 5 maintenance types with type-specific configuration
- [ ] Confidence decay math: exponential decay with floor threshold
- [ ] Confidence gauge display on tool detail
- [ ] calculateNextMaintenanceDate considers all active configs
- [ ] recordMaintenance resets confidence and updates next_due_date
- [ ] updateConfidenceScores daily decay function
- [ ] MaintenanceConfigSheet with type-specific fields
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 47E Results (YYYY-MM-DD)
- 5 maintenance types: time, usage, schedule, decay, condition
- Confidence decay math with gauge display
- Maintenance config + records tables
- Service: calculateNextDue, recordMaintenance, updateConfidence
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 47F.**
