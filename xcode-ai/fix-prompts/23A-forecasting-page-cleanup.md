# 23A — Forecasting Page: Service Layer + Recalculate + Trend Indicators

> **Chain position:** **23A** → 23B
> **Prerequisite:** None (page already works, this is cleanup + enhancement)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The forecasting page works but has architectural violations: it imports GRDB directly and runs raw SQL instead of using the existing `PartsService` methods. It also has leftover `#if os()` platform guards from before the app went iOS-only. The service layer already has `listForecastData()` and `recalculateForecasts()` — they just aren't wired up.

Additionally, the page is missing a "Recalculate" button (the service method exists but there's no UI trigger), trend indicators (ADU-30 vs ADU-90 comparison), and a "last recalculated" timestamp.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift` — the page to fix
- `core/Sources/WiredPartCore/Services/PartsService.swift` — search for `MARK: - 7. Forecasting` section (~line 2402)
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift` — Part struct with forecast fields

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift`
- `core/Sources/WiredPartCore/Services/PartsService.swift` (minor addition)

## Task

### Step 1: Update PartsService — add forecast data method with stock

The existing `listForecastData()` returns `[Part]` but doesn't include current stock (which requires a JOIN on the `stock` table). Add a new method that returns forecast rows with stock included:

```swift
/// Forecast row with current stock included (requires stock table JOIN).
public struct ForecastDataRow: Sendable {
    public let part: Part
    public let currentStock: Int
}

/// List parts with forecast data and current stock for the forecasting dashboard.
public func listForecastDataWithStock(search: String? = nil) throws -> [ForecastDataRow] {
    do {
        return try db.writer.read { dbConn in
            var whereClauses = ["p.deleted_at IS NULL"]
            var args: [DatabaseValueConvertible?] = []

            if let search, !search.isEmpty {
                whereClauses.append("(p.name LIKE ? OR p.code LIKE ?)")
                let pattern = "%\(search)%"
                args.append(pattern)
                args.append(pattern)
            }

            let sql = """
                SELECT p.*, COALESCE(SUM(s.qty), 0) AS current_stock
                FROM parts p
                LEFT JOIN stock s ON s.part_id = p.id AND s.deleted_at IS NULL
                WHERE \(whereClauses.joined(separator: " AND "))
                GROUP BY p.id
                ORDER BY COALESCE(p.forecast_days_until_low, 9999) ASC
                """

            let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
            return rows.map { row in
                let part = try! Part(row: row)
                let stock: Int = row["current_stock"]
                return ForecastDataRow(part: part, currentStock: stock)
            }
        }
    } catch {
        if isTableNotFoundError(error) { return [] }
        throw error
    }
}
```

### Step 2: Replace raw SQL with service call

In `PartsForecastingPage.swift`:

**Remove** `import GRDB`.

**Replace** the `ForecastRow` struct and the `loadData()` method. Instead of the custom struct, use the service:

```swift
@State private var forecastRows: [PartsService.ForecastDataRow] = []
```

Replace `loadData()`:

```swift
@Sendable
private func loadData() async {
    isLoading = true
    loadError = nil
    do {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        let rows = try service.listForecastDataWithStock()
        await MainActor.run {
            forecastRows = rows
            isLoading = false
        }
    } catch {
        await MainActor.run {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}
```

Update all references from `row.name` to `row.part.name`, `row.code` to `row.part.code`, `row.adu30` to `row.part.forecastAdu30`, etc. The `ForecastRow` struct can be deleted entirely.

### Step 3: Remove platform guards

Delete all `#if os(iOS)` / `#elseif os(macOS)` / `#endif` blocks. Keep only the iOS code inside them:

```swift
// BEFORE:
#if os(iOS)
.background(Color(.secondarySystemGroupedBackground))
#elseif os(macOS)
.background(Color(.secondarySystemGroupedBackground))
#endif

// AFTER:
.background(Color(.secondarySystemGroupedBackground))
```

Do this for all 3 occurrences (lines ~50-54, ~72-76, ~149-151).

### Step 4: Add Recalculate button in toolbar

Add a toolbar button that triggers `PartsService.recalculateForecasts()`:

```swift
@State private var isRecalculating = false
@State private var lastRecalculated: String?

// In the body, add toolbar:
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button {
            Task { await recalculateForecasts() }
        } label: {
            if isRecalculating {
                ProgressView()
            } else {
                Label("Recalculate", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(isRecalculating)
    }
}
```

Add the recalculate method:

```swift
@Sendable
private func recalculateForecasts() async {
    isRecalculating = true
    do {
        guard let service = appCore.partsService else { return }
        try service.recalculateForecasts()
        await loadData()  // Reload after recalculation
    } catch {
        await MainActor.run {
            loadError = "Recalculation failed: \(error.localizedDescription)"
        }
    }
    await MainActor.run {
        isRecalculating = false
    }
}
```

### Step 5: Add trend indicator

Show whether usage is trending up, down, or stable by comparing ADU-30 to ADU-90:

```swift
@ViewBuilder
private func trendIndicator(adu30: Double?, adu90: Double?) -> some View {
    if let short = adu30, let long = adu90, long > 0 {
        let ratio = short / long
        if ratio > 1.15 {
            // Usage trending up (30-day > 90-day by 15%+)
            Image(systemName: "arrow.up.right")
                .font(.caption2)
                .foregroundStyle(.red)
        } else if ratio < 0.85 {
            // Usage trending down
            Image(systemName: "arrow.down.right")
                .font(.caption2)
                .foregroundStyle(.green)
        } else {
            // Stable
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
```

Add this indicator next to the ADU display in `forecastRowView`:

```swift
HStack(spacing: 4) {
    if let adu = row.part.forecastAdu30, adu > 0 {
        Text(String(format: "ADU: %.1f/day", adu))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
    trendIndicator(adu30: row.part.forecastAdu30, adu90: row.part.forecastAdu90)
}
```

### Step 6: Show "last recalculated" timestamp

Add a footer section in the list showing when forecasts were last calculated:

```swift
// In the list, after the parts section:
if let lastRun = forecastRows.first(where: { $0.part.forecastLastRun != nil })?.part.forecastLastRun {
    Section {
        HStack {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text("Last recalculated: \(formatTimestamp(lastRun))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

Add a simple timestamp formatter:

```swift
private func formatTimestamp(_ iso: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: iso) {
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
    // Try without fractional seconds
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: iso) {
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
    return iso
}
```

### Step 7: Update ForecastDetailSheet

Update the detail sheet to use `ForecastDataRow` instead of the old `ForecastRow`:

```swift
private struct ForecastDetailSheet: View {
    let row: PartsService.ForecastDataRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Part") {
                    LabeledContent("Name", value: row.part.name)
                    if let code = row.part.code {
                        LabeledContent("Code", value: code)
                    }
                    LabeledContent("Current Stock", value: "\(row.currentStock)")
                }

                Section("Forecast Metrics") {
                    if let adu30 = row.part.forecastAdu30 {
                        LabeledContent("Avg Daily Usage (30d)", value: String(format: "%.2f", adu30))
                    }
                    if let adu90 = row.part.forecastAdu90 {
                        LabeledContent("Avg Daily Usage (90d)", value: String(format: "%.2f", adu90))
                    }
                    // Trend row
                    if let adu30 = row.part.forecastAdu30, let adu90 = row.part.forecastAdu90, adu90 > 0 {
                        let ratio = adu30 / adu90
                        LabeledContent("Usage Trend") {
                            HStack(spacing: 4) {
                                if ratio > 1.15 {
                                    Image(systemName: "arrow.up.right")
                                        .foregroundStyle(.red)
                                    Text("Increasing")
                                        .foregroundStyle(.red)
                                } else if ratio < 0.85 {
                                    Image(systemName: "arrow.down.right")
                                        .foregroundStyle(.green)
                                    Text("Decreasing")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                    Text("Stable")
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                    if let rp = row.part.forecastReorderPoint {
                        LabeledContent("Reorder Point", value: "\(rp)")
                    }
                    if let target = row.part.forecastTargetQty {
                        LabeledContent("Target Qty", value: "\(target)")
                    }
                    if let suggested = row.part.forecastSuggestedOrder {
                        LabeledContent("Suggested Order") {
                            Text("\(suggested)")
                                .fontWeight(.bold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if let days = row.part.forecastDaysUntilLow {
                        LabeledContent("Days Until Low") {
                            Text("\(days)")
                                .fontWeight(.bold)
                                .foregroundStyle(days <= 7 ? .red : days <= 30 ? .orange : .green)
                        }
                    }
                }

                Section("Stock Levels") {
                    if let min = row.part.minStockLevel {
                        LabeledContent("Min Stock", value: "\(min)")
                    }
                    if let max = row.part.maxStockLevel {
                        LabeledContent("Max Stock", value: "\(max)")
                    }
                    if let target = row.part.targetStockLevel {
                        LabeledContent("Target Stock", value: "\(target)")
                    }
                    if let rp = row.part.reorderPoint {
                        LabeledContent("Manual Reorder Point", value: "\(rp)")
                    }
                }

                if let lastRun = row.part.forecastLastRun {
                    Section("Last Updated") {
                        Text(lastRun)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Forecast Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

**Note:** Check the actual `Part` model field names — they may be `minStockLevel`, `maxStockLevel`, `targetStockLevel`, `reorderPoint` or similar. Match the exact CodingKeys from `PartsModels.swift`.

## Important Notes

- The `listForecastDataWithStock()` method is needed because `listForecastData()` returns `[Part]` without the current stock (stock lives in a separate table). The JOIN is necessary.
- `recalculateForecasts()` iterates ALL parts — on a large catalog this could take a few seconds. The `isRecalculating` state with ProgressView handles this.
- Trend thresholds (15% up/down) are intentionally generous — small fluctuations don't trigger the indicator.
- The `ForecastRow` struct should be deleted entirely once replaced with `ForecastDataRow`. Delete the private `ForecastRow` struct at the bottom of the file.
- Make `ForecastDataRow` conform to `Identifiable` (using `part.id`) so `.sheet(item:)` works.
- Remove the `#if os(iOS)` / `#elseif os(macOS)` blocks on ALL 3 occurrences.
- Check if `Part` uses `minStockLevel` or `min_stock_level` as Swift property names — match accordingly.

## Success Criteria

- [ ] `import GRDB` removed from PartsForecastingPage
- [ ] Raw SQL replaced with `PartsService.listForecastDataWithStock()`
- [ ] All `#if os()` platform guards removed
- [ ] Recalculate button in toolbar triggers `recalculateForecasts()`
- [ ] Recalculate shows ProgressView while running
- [ ] Trend indicator (up/down/stable) shown on each row
- [ ] "Last recalculated" timestamp shown in list footer
- [ ] Detail sheet updated to use `ForecastDataRow`
- [ ] Old `ForecastRow` struct deleted
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 23A Results (YYYY-MM-DD)
- Removed import GRDB + raw SQL → PartsService.listForecastDataWithStock()
- Removed 3 #if os() platform guards
- Added Recalculate toolbar button with ProgressView
- Added trend indicators (ADU-30 vs ADU-90)
- Added "last recalculated" timestamp footer
- Updated ForecastDetailSheet to use ForecastDataRow
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 23B.**
