# 49D — Report Builder

> **Chain position:** 49A → 49B → 49C → **49D**
> **Prerequisite:** 49B (export), 49C (report data methods)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read the Custom/Shared reports placeholder views from 49A. Build a simple report builder: pick type, pick fields, pick filters, generate. Save custom report configurations. Run saved reports with updated date ranges.

## Context

The report builder lets managers create custom reports without developer help. The flow is: (1) Pick a report type (Labor Hours, Parts Usage, Costs, etc.), (2) Pick which fields/columns to include, (3) Set filters (date range, specific job, employee, etc.), (4) Generate the report. Saved configurations can be re-run with new date ranges. Shared reports are visible to all users with the right permissions.

## Task

### Step 1: Migration

```swift
try db.create(table: "saved_reports") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("name", .text).notNull()
    t.column("report_type", .text).notNull()
    t.column("columns_json", .text).notNull()    // JSON array of selected column keys
    t.column("filters_json", .text).notNull()    // JSON object of filter settings
    t.column("created_by", .integer).notNull().references("users")
    t.column("is_shared", .boolean).notNull().defaults(to: false)
    t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    t.column("last_run_at", .datetime)
}
```

### Step 2: Report Type Definitions

```swift
enum CustomReportType: String, CaseIterable, Sendable {
    case laborHours = "labor_hours"
    case partsUsage = "parts_usage"
    case jobCosts = "job_costs"
    case toolCheckouts = "tool_checkouts"
    case vehicleFuel = "vehicle_fuel"
    case orderHistory = "order_history"

    var displayName: String {
        switch self {
        case .laborHours: return "Labor Hours"
        case .partsUsage: return "Parts Usage"
        case .jobCosts: return "Job Costs"
        case .toolCheckouts: return "Tool Checkouts"
        case .vehicleFuel: return "Vehicle Fuel"
        case .orderHistory: return "Order History"
        }
    }

    var availableColumns: [ReportColumn] {
        switch self {
        case .laborHours:
            return [
                .init(key: "employee_name", label: "Employee"),
                .init(key: "date", label: "Date"),
                .init(key: "hours", label: "Hours"),
                .init(key: "job_name", label: "Job"),
                .init(key: "activity_type", label: "Activity"),
                .init(key: "clock_in", label: "Clock In"),
                .init(key: "clock_out", label: "Clock Out"),
                .init(key: "notes", label: "Notes"),
            ]
        case .partsUsage:
            return [
                .init(key: "part_name", label: "Part"),
                .init(key: "category", label: "Category"),
                .init(key: "quantity_used", label: "Qty Used"),
                .init(key: "job_name", label: "Job"),
                .init(key: "date", label: "Date"),
                .init(key: "cost", label: "Unit Cost"),
                .init(key: "total_cost", label: "Total Cost"),
            ]
        case .jobCosts:
            return [
                .init(key: "job_name", label: "Job"),
                .init(key: "labor_cost", label: "Labor Cost"),
                .init(key: "material_cost", label: "Material Cost"),
                .init(key: "total_cost", label: "Total Cost"),
                .init(key: "budget", label: "Budget"),
                .init(key: "variance", label: "Variance"),
            ]
        case .toolCheckouts:
            return [
                .init(key: "tool_name", label: "Tool"),
                .init(key: "employee_name", label: "Employee"),
                .init(key: "checkout_date", label: "Checkout Date"),
                .init(key: "return_date", label: "Return Date"),
                .init(key: "condition_out", label: "Condition Out"),
                .init(key: "condition_in", label: "Condition In"),
            ]
        case .vehicleFuel:
            return [
                .init(key: "vehicle_name", label: "Vehicle"),
                .init(key: "date", label: "Date"),
                .init(key: "gallons", label: "Gallons"),
                .init(key: "cost", label: "Cost"),
                .init(key: "odometer", label: "Odometer"),
            ]
        case .orderHistory:
            return [
                .init(key: "po_number", label: "PO #"),
                .init(key: "supplier_name", label: "Supplier"),
                .init(key: "order_date", label: "Order Date"),
                .init(key: "total", label: "Total"),
                .init(key: "status", label: "Status"),
                .init(key: "items_count", label: "Items"),
            ]
        }
    }

    var availableFilters: [ReportFilter] {
        switch self {
        case .laborHours:
            return [.dateRange, .employee, .job]
        case .partsUsage:
            return [.dateRange, .job, .category]
        case .jobCosts:
            return [.dateRange, .job, .status]
        case .toolCheckouts:
            return [.dateRange, .employee]
        case .vehicleFuel:
            return [.dateRange, .vehicle]
        case .orderHistory:
            return [.dateRange, .supplier, .status]
        }
    }
}

struct ReportColumn: Identifiable, Sendable {
    let key: String
    let label: String
    var id: String { key }
}

enum ReportFilter: String, Sendable {
    case dateRange, employee, job, category, vehicle, supplier, status
}
```

### Step 3: Report Builder UI

```swift
struct ReportBuilderView: View {
    @EnvironmentObject var appCore: AppCore
    @State private var selectedType: CustomReportType = .laborHours
    @State private var selectedColumns: Set<String> = []
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var endDate: Date = Date()
    @State private var filterJobId: Int64?
    @State private var filterEmployeeId: Int64?
    @State private var filterVehicleId: Int64?
    @State private var step: BuilderStep = .type
    @State private var reportName: String = ""
    @State private var generatedRows: [[String]] = []
    @State private var isGenerating = false
    @State private var generateError: String?

    enum BuilderStep: Int, CaseIterable {
        case type = 0
        case fields = 1
        case filters = 2
        case results = 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack {
                ForEach(BuilderStep.allCases, id: \.rawValue) { s in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(s.rawValue <= step.rawValue ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .overlay(Text("\(s.rawValue + 1)").font(.caption2).foregroundStyle(.white))
                        Text(stepLabel(s)).font(.caption2)
                    }
                    if s != .results {
                        Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 2).frame(maxWidth: 30)
                    }
                }
            }
            .padding()

            // Step content
            List {
                switch step {
                case .type: typeStep
                case .fields: fieldsStep
                case .filters: filtersStep
                case .results: resultsStep
                }
            }
        }
        .navigationTitle("Report Builder")
    }

    func stepLabel(_ step: BuilderStep) -> String {
        switch step {
        case .type: return "Type"
        case .fields: return "Fields"
        case .filters: return "Filters"
        case .results: return "Results"
        }
    }

    var typeStep: some View {
        Group {
            Section("Select Report Type") {
                ForEach(CustomReportType.allCases, id: \.self) { type in
                    HStack {
                        Text(type.displayName)
                        Spacer()
                        if selectedType == type {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedType = type }
                }
            }

            Section {
                Button("Next: Select Fields") {
                    selectedColumns = Set(selectedType.availableColumns.map(\.key))
                    step = .fields
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
    }

    var fieldsStep: some View {
        Group {
            Section("Select Columns") {
                ForEach(selectedType.availableColumns) { col in
                    Toggle(col.label, isOn: Binding(
                        get: { selectedColumns.contains(col.key) },
                        set: { isOn in
                            if isOn { selectedColumns.insert(col.key) }
                            else { selectedColumns.remove(col.key) }
                        }
                    ))
                }
            }

            Section {
                HStack {
                    Button("Back") { step = .type }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Next: Filters") { step = .filters }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedColumns.isEmpty)
                }
            }
        }
    }

    var filtersStep: some View {
        Group {
            Section("Date Range") {
                DatePicker("Start", selection: $startDate, displayedComponents: .date)
                DatePicker("End", selection: $endDate, displayedComponents: .date)
            }

            // Additional filters based on type
            // (job picker, employee picker, etc.)

            Section {
                HStack {
                    Button("Back") { step = .fields }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Generate Report") {
                        Task { await generateReport() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
                }
            }
        }
    }

    var resultsStep: some View {
        Group {
            if isGenerating {
                Section { ProgressView("Generating...") }
            } else if let error = generateError {
                Section { Text(error).foregroundStyle(.red) }
            } else {
                Section {
                    Text("\(generatedRows.count) rows generated")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                // Results table
                Section {
                    ForEach(0..<min(generatedRows.count, 50), id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(0..<selectedColumnLabels.count, id: \.self) { j in
                                HStack {
                                    Text(selectedColumnLabels[j])
                                        .font(.caption).foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)
                                    Text(j < generatedRows[i].count ? generatedRows[i][j] : "")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Save + Export
                Section {
                    TextField("Report Name", text: $reportName)

                    HStack {
                        Button("Save Configuration") {
                            Task { await saveReport() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(reportName.isEmpty)

                        Spacer()

                        Button("New Report") {
                            step = .type
                            generatedRows = []
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    var selectedColumnLabels: [String] {
        selectedType.availableColumns
            .filter { selectedColumns.contains($0.key) }
            .map(\.label)
    }

    func generateReport() async {
        isGenerating = true
        generateError = nil
        step = .results
        // Call service to generate report based on type, columns, filters
        do {
            generatedRows = try await appCore.reportsService?.generateCustomReport(
                type: selectedType.rawValue,
                columns: Array(selectedColumns),
                startDate: startDate,
                endDate: endDate,
                filters: [:]
            ) ?? []
        } catch {
            generateError = error.localizedDescription
        }
        isGenerating = false
    }

    func saveReport() async {
        // Save to saved_reports table
    }
}
```

### Step 4: Saved Reports

```swift
struct CustomReportsView: View {
    @EnvironmentObject var appCore: AppCore
    @State private var savedReports: [SavedReport] = []
    @State private var loadError: String?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ReportBuilderView()
                } label: {
                    Label("Create New Report", systemImage: "plus.circle.fill")
                }
            }

            Section("Saved Reports") {
                if savedReports.isEmpty {
                    Text("No saved reports").foregroundStyle(.secondary)
                } else {
                    ForEach(savedReports) { report in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.name).font(.subheadline)
                                Text(report.reportType.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let lastRun = report.lastRunAt {
                                Text(lastRun, format: .dateTime.month().day())
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        Task { await deleteReports(at: indexSet) }
                    }
                }
            }
        }
        .task { await loadSavedReports() }
    }

    func loadSavedReports() async {
        guard let service = appCore.reportsService else {
            loadError = "Reports service not available"
            return
        }
        do {
            savedReports = try await service.getSavedReports(userId: appCore.currentUserId)
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteReports(at indexSet: IndexSet) async {
        // Delete saved reports
    }
}
```

### Step 5: Service Methods

```swift
// MARK: - Custom Reports

func generateCustomReport(
    type: String, columns: [String],
    startDate: Date, endDate: Date,
    filters: [String: String]
) async throws -> [[String]] {
    // Build SQL query based on type and columns
    // Execute and return results as string arrays
}

func saveReportConfig(
    name: String, type: String, columns: [String],
    filters: [String: String], userId: Int64, isShared: Bool
) async throws -> Int64

func getSavedReports(userId: Int64) async throws -> [SavedReport]

func getSharedReports() async throws -> [SavedReport]

func deleteSavedReport(reportId: Int64) async throws
```

## Important Notes
- 4-step wizard: Type → Fields → Filters → Results
- Step indicator shows progress (numbered circles with connecting lines)
- Column selection defaults to all columns, user can deselect
- Results show first 50 rows in list format (not a table — mobile-friendly)
- Saved configurations store columns + filters as JSON
- Re-running a saved report lets user update the date range
- Shared reports are visible to all users with report access

## Success Criteria
- [ ] Migration: saved_reports table
- [ ] 6 report types with field + filter definitions
- [ ] 4-step builder wizard with step indicator
- [ ] Column selection with toggles
- [ ] Date range + type-specific filters
- [ ] Report generation and display
- [ ] Save configuration with name
- [ ] Saved reports list with re-run + delete
- [ ] Export toolbar on results
- [ ] Service: generateCustomReport, saveReportConfig, getSavedReports
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 49D Results (YYYY-MM-DD)
- Report builder: 4-step wizard
- 6 report types with configurable columns/filters
- Save/load report configurations
- Migration: saved_reports
- Build: PASS/FAIL
```

**Reports module complete. Proceed to Office prompts (50A).**
