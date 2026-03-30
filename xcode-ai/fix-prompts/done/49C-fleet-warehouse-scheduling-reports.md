# 49C — Fleet, Warehouse & Scheduling Reports

> **Chain position:** 49A → 49B → **49C** → 49D
> **Prerequisite:** 49A (report categories), 49B (export toolbar)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read `FleetService.swift`, `WarehouseService.swift`, and `SchedulingService.swift`. Create new report pages for Fleet (fuel costs, maintenance trends, mileage, utilization), Warehouse (inventory value, backorders, turnover), and Scheduling (crew utilization, dispatch efficiency, pipeline).

## Context

These three report categories were placeholders in 49A. Now we build real report pages with data from existing services. Each report page gets the export toolbar from 49B. All financial data is hat-gated.

## Task

### Step 1: Fleet Reports

```swift
struct FleetReportsView: View {
    var body: some View {
        List {
            NavigationLink("Fuel Cost Report") {
                FleetFuelCostReport()
            }
            NavigationLink("Maintenance Trends") {
                FleetMaintenanceTrendsReport()
            }
            NavigationLink("Mileage Summary") {
                FleetMileageSummaryReport()
            }
            NavigationLink("Vehicle Utilization") {
                FleetUtilizationReport()
            }
        }
    }
}

struct FleetFuelCostReport: View {
    @EnvironmentObject var appCore: AppCore
    @State private var fuelData: [FuelReportRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var dateRange: DateRange = .thisMonth

    var body: some View {
        List {
            // Date range picker
            Section {
                Picker("Period", selection: $dateRange) {
                    ForEach(DateRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .onChange(of: dateRange) { _, _ in Task { await loadData() } }
            }

            // Summary
            Section("Summary") {
                LabeledContent("Total Fuel Cost", value: "$\(totalFuelCost, specifier: "%.2f")")
                LabeledContent("Total Gallons", value: "\(totalGallons, specifier: "%.1f")")
                LabeledContent("Avg Cost/Gallon", value: "$\(avgCostPerGallon, specifier: "%.2f")")
            }

            // Per-vehicle breakdown
            Section("By Vehicle") {
                ForEach(fuelData) { row in
                    HStack {
                        Text(row.vehicleName).font(.subheadline)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("$\(row.totalCost, specifier: "%.2f")")
                                .font(.subheadline)
                            Text("\(row.gallons, specifier: "%.1f") gal")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Fuel Costs")
        .reportExportToolbar(
            title: "Fuel Cost Report",
            columns: ["Vehicle", "Gallons", "Cost", "Cost/Gallon"],
            rows: fuelData.map { [$0.vehicleName, String(format: "%.1f", $0.gallons),
                                  String(format: "%.2f", $0.totalCost),
                                  String(format: "%.2f", $0.costPerGallon)] }
        )
        .task { await loadData() }
    }

    var totalFuelCost: Double { fuelData.reduce(0) { $0 + $1.totalCost } }
    var totalGallons: Double { fuelData.reduce(0) { $0 + $1.gallons } }
    var avgCostPerGallon: Double { totalGallons > 0 ? totalFuelCost / totalGallons : 0 }

    func loadData() async {
        isLoading = true
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }
        do {
            fuelData = try await service.getFuelCostReport(
                startDate: dateRange.startDate, endDate: dateRange.endDate
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// Similar pattern for MaintenanceTrends, MileageSummary, Utilization reports
// Each with:
// - Date range picker
// - Summary section
// - Detailed breakdown
// - .reportExportToolbar()
```

### Step 2: Warehouse Reports

```swift
struct WarehouseReportsView: View {
    var body: some View {
        List {
            NavigationLink("Inventory Value") {
                WarehouseInventoryValueReport()
            }
            NavigationLink("Backorder Status") {
                WarehouseBackorderReport()
            }
            NavigationLink("Inventory Turnover") {
                WarehouseTurnoverReport()
            }
        }
    }
}

struct WarehouseInventoryValueReport: View {
    @EnvironmentObject var appCore: AppCore
    @State private var valueData: [InventoryValueRow] = []
    @State private var loadError: String?

    var body: some View {
        List {
            Section("Total Value") {
                LabeledContent("On Hand", value: "$\(totalOnHand, specifier: "%.2f")")
                LabeledContent("On Order", value: "$\(totalOnOrder, specifier: "%.2f")")
                LabeledContent("Combined", value: "$\(totalOnHand + totalOnOrder, specifier: "%.2f")")
            }

            Section("By Category") {
                ForEach(valueData) { row in
                    HStack {
                        Text(row.categoryName).font(.subheadline)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("$\(row.onHandValue, specifier: "%.2f")")
                                .font(.subheadline)
                            Text("\(row.itemCount) items")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Inventory Value")
        .reportExportToolbar(
            title: "Inventory Value Report",
            columns: ["Category", "Items", "On Hand Value", "On Order Value"],
            rows: valueData.map { [$0.categoryName, "\($0.itemCount)",
                                   String(format: "%.2f", $0.onHandValue),
                                   String(format: "%.2f", $0.onOrderValue)] }
        )
        .task { await loadData() }
    }

    var totalOnHand: Double { valueData.reduce(0) { $0 + $1.onHandValue } }
    var totalOnOrder: Double { valueData.reduce(0) { $0 + $1.onOrderValue } }

    func loadData() async {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            return
        }
        do {
            valueData = try await service.getInventoryValueReport()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// Similar for Backorder and Turnover reports
```

### Step 3: Scheduling Reports

```swift
struct SchedulingReportsView: View {
    var body: some View {
        List {
            NavigationLink("Crew Utilization") {
                SchedulingCrewUtilizationReport()
            }
            NavigationLink("Dispatch Efficiency") {
                SchedulingDispatchEfficiencyReport()
            }
            NavigationLink("Pipeline Summary") {
                SchedulingPipelineReport()
            }
        }
    }
}

struct SchedulingCrewUtilizationReport: View {
    @EnvironmentObject var appCore: AppCore
    @State private var utilizationData: [CrewUtilizationRow] = []
    @State private var loadError: String?
    @State private var dateRange: DateRange = .thisWeek

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $dateRange) {
                    ForEach(DateRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .onChange(of: dateRange) { _, _ in Task { await loadData() } }
            }

            Section("Summary") {
                LabeledContent("Avg Utilization", value: "\(Int(avgUtilization * 100))%")
                LabeledContent("Total Scheduled Hours", value: "\(totalHours, specifier: "%.1f")")
            }

            Section("By Employee") {
                ForEach(utilizationData) { row in
                    HStack {
                        Text(row.employeeName).font(.subheadline)
                        Spacer()
                        VStack(alignment: .trailing) {
                            ProgressView(value: row.utilization)
                                .tint(row.utilization > 0.8 ? .green :
                                      row.utilization > 0.5 ? .orange : .red)
                                .frame(width: 60)
                            Text("\(Int(row.utilization * 100))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Crew Utilization")
        .reportExportToolbar(
            title: "Crew Utilization Report",
            columns: ["Employee", "Scheduled Hours", "Available Hours", "Utilization %"],
            rows: utilizationData.map { [$0.employeeName,
                                         String(format: "%.1f", $0.scheduledHours),
                                         String(format: "%.1f", $0.availableHours),
                                         "\(Int($0.utilization * 100))%"] }
        )
        .task { await loadData() }
    }

    var avgUtilization: Double {
        guard !utilizationData.isEmpty else { return 0 }
        return utilizationData.reduce(0) { $0 + $1.utilization } / Double(utilizationData.count)
    }
    var totalHours: Double { utilizationData.reduce(0) { $0 + $1.scheduledHours } }

    func loadData() async {
        guard let service = appCore.schedulingService else {
            loadError = "Scheduling service not available"
            return
        }
        do {
            utilizationData = try await service.getCrewUtilizationReport(
                startDate: dateRange.startDate, endDate: dateRange.endDate
            )
        } catch {
            loadError = error.localizedDescription
        }
    }
}
```

### Step 4: Shared DateRange Enum

```swift
enum DateRange: String, CaseIterable {
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisQuarter = "This Quarter"
    case thisYear = "This Year"

    var startDate: Date {
        let cal = Calendar.current
        switch self {
        case .thisWeek:
            return cal.dateInterval(of: .weekOfYear, for: Date())!.start
        case .lastWeek:
            let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: Date())!
            return cal.dateInterval(of: .weekOfYear, for: lastWeek)!.start
        case .thisMonth:
            return cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        case .lastMonth:
            let lastMonth = cal.date(byAdding: .month, value: -1, to: Date())!
            return cal.date(from: cal.dateComponents([.year, .month], from: lastMonth))!
        case .thisQuarter:
            let month = cal.component(.month, from: Date())
            let quarterStart = ((month - 1) / 3) * 3 + 1
            return cal.date(from: DateComponents(year: cal.component(.year, from: Date()), month: quarterStart))!
        case .thisYear:
            return cal.date(from: DateComponents(year: cal.component(.year, from: Date())))!
        }
    }

    var endDate: Date { Date() }
}
```

### Step 5: Service Methods (add to respective services)

```swift
// FleetService
func getFuelCostReport(startDate: Date, endDate: Date) async throws -> [FuelReportRow]
func getMaintenanceTrendsReport(startDate: Date, endDate: Date) async throws -> [MaintenanceTrendRow]
func getMileageSummaryReport(startDate: Date, endDate: Date) async throws -> [MileageSummaryRow]
func getVehicleUtilizationReport(startDate: Date, endDate: Date) async throws -> [VehicleUtilizationRow]

// WarehouseService
func getInventoryValueReport() async throws -> [InventoryValueRow]
func getBackorderReport() async throws -> [BackorderRow]
func getTurnoverReport(startDate: Date, endDate: Date) async throws -> [TurnoverRow]

// SchedulingService
func getCrewUtilizationReport(startDate: Date, endDate: Date) async throws -> [CrewUtilizationRow]
func getDispatchEfficiencyReport(startDate: Date, endDate: Date) async throws -> [DispatchEfficiencyRow]
func getPipelineSummaryReport() async throws -> [PipelineSummaryRow]
```

## Important Notes
- All report pages use the .reportExportToolbar() modifier from 49B
- Date range picker is shared across all time-based reports
- Financial report pages are hat-gated (already enforced by category visibility in 49A)
- Service methods return report-specific row types for clean data flow
- Each report has a summary section at top and detailed breakdown below
- Utilization reports show progress bars per employee/vehicle

## Success Criteria
- [ ] Fleet: 4 report pages (Fuel Cost, Maintenance Trends, Mileage, Utilization)
- [ ] Warehouse: 3 report pages (Inventory Value, Backorders, Turnover)
- [ ] Scheduling: 3 report pages (Crew Utilization, Dispatch Efficiency, Pipeline)
- [ ] All pages have .reportExportToolbar()
- [ ] Shared DateRange enum
- [ ] Service methods for all 10 report types
- [ ] Summary + detail sections on each report
- [ ] Replace placeholder views from 49A
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 49C Results (YYYY-MM-DD)
- 10 new report pages across Fleet/Warehouse/Scheduling
- All with export toolbar
- DateRange enum shared across reports
- Service: 10 report query methods
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 49D.**
