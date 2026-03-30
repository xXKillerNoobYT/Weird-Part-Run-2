# 47F — Tool Management Page

> **Chain position:** 47A → 47B → 47C → 47D → 47E → **47F**
> **Prerequisite:** 47E (maintenance types)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read the existing Tools Admin page (likely IOSToolsAdminPage.swift) and `ToolsService.swift`. Rename Admin to Management. Add bulk operations, categories/types config, company policies, location assignment, and full audit trail.

## Context

The "Admin" tab in Tools is being renamed to "Management" for consistency with other modules. This page is for managers to configure tool categories and types, set company-wide policies (checkout limits, auto-return rules), assign home locations to tools/kits, run bulk operations (retire multiple tools, reassign), and view the full audit trail with filters and export.

## Task

### Step 1: Rename Admin to Management

```swift
// In IOSToolsRouter.swift, rename the tab:
// Old: case admin = "Admin"
// New: case management = "Management"

// Update the router case and tab label
case management = "Management"

// Update icon
Label("Management", systemImage: "gearshape.2.fill")
```

### Step 2: Management Page Structure

```swift
struct IOSToolManagementPage: View {
    @EnvironmentObject var appCore: AppCore
    @State private var selectedSection: ManagementSection = .categories
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    enum ManagementSection: String, CaseIterable {
        case categories = "Categories"
        case policies = "Policies"
        case locations = "Locations"
        case bulk = "Bulk Actions"
        case history = "History"
    }

    enum ActiveSheet: Identifiable {
        case addCategory
        case editCategory(id: Int64)
        case addType
        case editPolicy
        case assignLocation(toolId: Int64)
        case bulkAction
        case exportHistory

        var id: String { String(describing: self) }
    }

    var body: some View {
        List {
            // Section picker
            Picker("Section", selection: $selectedSection) {
                ForEach(ManagementSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            switch selectedSection {
            case .categories: categoriesSection
            case .policies: policiesSection
            case .locations: locationsSection
            case .bulk: bulkActionsSection
            case .history: historySection
            }
        }
        .navigationTitle("Tool Management")
        .sheet(item: $activeSheet) { sheet in
            // sheet routing
        }
    }
}
```

### Step 3: Categories & Types Config

```swift
@State private var categories: [ToolCategory] = []
@State private var types: [ToolType] = []

var categoriesSection: some View {
    Group {
        Section {
            ForEach(categories) { category in
                HStack {
                    VStack(alignment: .leading) {
                        Text(category.name).font(.subheadline)
                        Text("\(category.toolCount) tools")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        activeSheet = .editCategory(id: category.id)
                    } label: {
                        Image(systemName: "pencil.circle")
                    }
                }
            }

            Button {
                activeSheet = .addCategory
            } label: {
                Label("Add Category", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Tool Categories")
        }

        Section {
            ForEach(types) { type in
                HStack {
                    Text(type.name).font(.subheadline)
                    Spacer()
                    Text(type.categoryName)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Button {
                activeSheet = .addType
            } label: {
                Label("Add Type", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Tool Types")
        }
    }
}
```

### Step 4: Company Policies

```swift
@State private var maxCheckoutDays: Int = 30
@State private var autoReturnEnabled: Bool = false
@State private var autoReturnDays: Int = 14
@State private var requireConditionCheck: Bool = true
@State private var tradeTimeout: Int = 7
@State private var policySaveError: String?

var policiesSection: some View {
    Group {
        Section("Checkout Rules") {
            Stepper("Max checkout: \(maxCheckoutDays) days",
                    value: $maxCheckoutDays, in: 1...365)

            Toggle("Auto-return reminders", isOn: $autoReturnEnabled)
            if autoReturnEnabled {
                Stepper("Remind after \(autoReturnDays) days",
                        value: $autoReturnDays, in: 1...maxCheckoutDays)
            }

            Toggle("Require condition check", isOn: $requireConditionCheck)
                .disabled(true)  // Always required per design
            Text("Condition checks are always required on checkout and return.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section("Trade Rules") {
            Stepper("Trade timeout: \(tradeTimeout) days",
                    value: $tradeTimeout, in: 1...30)
        }

        Section {
            Button("Save Policies") {
                Task { await savePolicies() }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)

            if let error = policySaveError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        }
    }
}

func savePolicies() async {
    guard let service = appCore.toolsService else {
        policySaveError = "Tools service not available"
        return
    }
    do {
        try await service.updateToolPolicies(
            maxCheckoutDays: maxCheckoutDays,
            autoReturnEnabled: autoReturnEnabled,
            autoReturnDays: autoReturnDays,
            tradeTimeoutDays: tradeTimeout
        )
        policySaveError = nil
    } catch {
        policySaveError = error.localizedDescription
    }
}
```

### Step 5: Location Assignment

```swift
@State private var unassignedTools: [ToolBasic] = []

var locationsSection: some View {
    Group {
        Section("Unassigned Tools") {
            if unassignedTools.isEmpty {
                Text("All tools have home locations").foregroundStyle(.secondary)
            } else {
                ForEach(unassignedTools) { tool in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tool.name).font(.subheadline)
                            if let serial = tool.serialNumber {
                                Text("S/N: \(serial)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Assign") {
                            activeSheet = .assignLocation(toolId: tool.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }

        Section {
            Text("Home location determines where a tool should be stored when not checked out. Used for returns and inventory counts.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

### Step 6: Bulk Operations

```swift
@State private var selectedToolIds: Set<Int64> = []
@State private var allTools: [ToolBasic] = []
@State private var bulkAction: BulkToolAction?
@State private var bulkError: String?

enum BulkToolAction: String, CaseIterable {
    case retire = "Retire Selected"
    case reassign = "Reassign Selected"
    case setCategory = "Set Category"
    case scheduleMaintenance = "Schedule Maintenance"
}

var bulkActionsSection: some View {
    Group {
        Section {
            Text("Selected: \(selectedToolIds.count) tools")
                .font(.subheadline).fontWeight(.medium)

            ForEach(BulkToolAction.allCases, id: \.self) { action in
                Button(action.rawValue) {
                    bulkAction = action
                    activeSheet = .bulkAction
                }
                .disabled(selectedToolIds.isEmpty)
            }

            if let error = bulkError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        } header: {
            Text("Bulk Actions")
        }

        Section("Select Tools") {
            ForEach(allTools) { tool in
                HStack {
                    Image(systemName: selectedToolIds.contains(tool.id)
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedToolIds.contains(tool.id) ? .blue : .secondary)

                    Text(tool.name).font(.subheadline)
                    Spacer()
                    Text(tool.status.capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedToolIds.contains(tool.id) {
                        selectedToolIds.remove(tool.id)
                    } else {
                        selectedToolIds.insert(tool.id)
                    }
                }
            }
        }
    }
}
```

### Step 7: Records & History (Full Audit Trail)

```swift
@State private var historyRecords: [ToolChangeRecord] = []
@State private var historyFilter: HistoryFilter = .all
@State private var historySearch: String = ""

enum HistoryFilter: String, CaseIterable {
    case all = "All"
    case checkouts = "Checkouts"
    case returns = "Returns"
    case trades = "Trades"
    case maintenance = "Maintenance"
    case edits = "Edits"
    case lostStolen = "Lost/Stolen"
}

var historySection: some View {
    Group {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HistoryFilter.allCases, id: \.self) { filter in
                        Button(filter.rawValue) {
                            historyFilter = filter
                            Task { await loadHistory() }
                        }
                        .buttonStyle(.bordered)
                        .tint(historyFilter == filter ? .blue : .gray)
                        .controlSize(.small)
                    }
                }
            }
        }
        .listRowSeparator(.hidden)

        Section {
            ForEach(historyRecords) { record in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: historyIcon(record.changeType))
                            .foregroundStyle(historyColor(record.changeType))
                        Text(record.changedByName ?? "System")
                            .font(.subheadline).fontWeight(.medium)
                        Spacer()
                        Text(record.changedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(record.description)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if historyRecords.isEmpty {
                Text("No records found").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Activity Log")
                Spacer()
                Button {
                    activeSheet = .exportHistory
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
            }
        }
    }
}

func loadHistory() async {
    guard let service = appCore.toolsService else {
        loadError = "Tools service not available"
        return
    }
    do {
        historyRecords = try await service.getToolAuditHistory(
            filter: historyFilter == .all ? nil : historyFilter.rawValue,
            search: historySearch.isEmpty ? nil : historySearch,
            limit: 100
        )
    } catch {
        loadError = error.localizedDescription
    }
}
```

### Step 8: Service Methods

```swift
// MARK: - Tool Management

func updateToolPolicies(
    maxCheckoutDays: Int, autoReturnEnabled: Bool,
    autoReturnDays: Int, tradeTimeoutDays: Int
) async throws {
    try await db.write { db in
        for (key, value) in [
            ("tool_max_checkout_days", String(maxCheckoutDays)),
            ("tool_auto_return_enabled", String(autoReturnEnabled)),
            ("tool_auto_return_days", String(autoReturnDays)),
            ("tool_trade_timeout_days", String(tradeTimeoutDays))
        ] {
            try db.execute(sql: """
                INSERT INTO settings (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """, arguments: [key, value])
        }
    }
}

func getToolAuditHistory(
    filter: String?, search: String?, limit: Int
) async throws -> [ToolChangeRecord] {
    try await db.read { db in
        var sql = """
            SELECT pcl.*, u.first_name || ' ' || u.last_name as changed_by_name
            FROM part_change_log pcl
            LEFT JOIN users u ON pcl.changed_by = u.id
            WHERE pcl.entity_type IN ('tool', 'kit')
            """
        var args: [DatabaseValueConvertible] = []

        if let filter = filter {
            sql += " AND pcl.change_type = ?"
            args.append(filter)
        }
        if let search = search, !search.isEmpty {
            sql += " AND (pcl.field_name LIKE ? OR pcl.new_value LIKE ?)"
            args.append("%\(search)%")
            args.append("%\(search)%")
        }

        sql += " ORDER BY pcl.changed_at DESC LIMIT ?"
        args.append(limit)

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            .map { row in ToolChangeRecord(row: row) }
    }
}

func getUnassignedTools() async throws -> [ToolBasic] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT id, name, serial_number, status
            FROM tools WHERE home_location IS NULL AND status != 'retired'
            ORDER BY name
            """)
        .map { row in
            ToolBasic(id: row["id"], name: row["name"],
                     serialNumber: row["serial_number"], status: row["status"])
        }
    }
}

func bulkRetireTools(toolIds: [Int64], retiredBy: Int64) async throws {
    try await db.write { db in
        for toolId in toolIds {
            try db.execute(sql: """
                UPDATE tools SET status = 'retired', updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [toolId])

            try db.execute(sql: """
                INSERT INTO part_change_log
                (entity_type, entity_id, field_name, old_value, new_value,
                 changed_by, changed_at, change_type)
                VALUES ('tool', ?, 'status', 'active', 'retired', ?, datetime('now'), 'bulk_retire')
                """, arguments: [toolId, retiredBy])
        }
    }
}
```

## Important Notes
- Rename "Admin" → "Management" in the router tab and all references
- 5 management sections: Categories, Policies, Locations, Bulk Actions, History
- Company policies are stored in settings table as key-value pairs
- Condition check is ALWAYS required — the toggle is disabled/informational only
- Bulk actions require tool selection first (checkmark list)
- History has 7 filter types + free-text search + export button
- Location assignment shows only tools without a home_location
- All operations are hat-gated (manage_tools permission)

## Success Criteria
- [ ] Renamed Admin → Management in router
- [ ] 5-section segmented picker layout
- [ ] Categories & types CRUD
- [ ] Company policies (checkout limits, auto-return, trade timeout)
- [ ] Location assignment for unassigned tools
- [ ] Bulk operations (retire, reassign, set category, schedule maintenance)
- [ ] Full audit trail with 7 filters + search + export
- [ ] Service: updateToolPolicies, getToolAuditHistory, getUnassignedTools, bulkRetireTools
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 47F Results (YYYY-MM-DD)
- Renamed Admin → Management
- 5 management sections
- Bulk operations, policies, location assignment
- Full audit trail with filters + export
- Build: PASS/FAIL
```

**Tools module complete. Proceed to Fleet prompts (48A).**
