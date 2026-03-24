# 23B — Forecasting Page: AI Integration (Read-Only)

> **Chain position:** 23A → **23B**
> **Prerequisite:** 23A complete (service layer, no raw SQL)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The AI assistant panel already exists (`IOSAIAssistantPanel.swift`) and uses Foundation Models with tool calling. The catalog page has a page-context notification pattern where it posts `.catalogPageActive` when visible and `.catalogPageInactive` when the user leaves. The AI panel picks this up and adds page-specific context.

The forecasting page needs the same pattern — when the user is on the forecasting page, the AI should be able to answer questions like:
- "Which parts are running low?"
- "What's trending up in usage?"
- "How much should I order for the critical items?"
- "When was the forecast last updated?"

This is **read-only** — the AI can query forecast data but cannot modify it.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift` — see the `.catalogPageActive` notification pattern (~line 180)
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift` — see how it posts context (~line 140)
- `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` — see notification name definitions (~line 182)
- `core/Sources/WiredPartCore/AI/AITools.swift` — existing AI tools
- `core/Sources/WiredPartCore/AI/FoundationModelsService.swift` — chatWithTools() method (~line 282)

**Files to modify:**
- `core/Sources/WiredPartCore/AI/AITools.swift` — add forecast tool
- `core/Sources/WiredPartCore/AI/FoundationModelsService.swift` — register new tool
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift` — post context notification
- `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` — add notification names
- `Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift` — handle forecast context

## Task

### Step 1: Add notification names

In `NavigationConfig.swift`, add alongside the existing catalog notifications:

```swift
static let forecastingPageActive = Notification.Name("WiredPart.forecastingPageActive")
static let forecastingPageInactive = Notification.Name("WiredPart.forecastingPageInactive")
```

### Step 2: Post context from forecasting page

In `PartsForecastingPage.swift`, add `.onAppear` / `.onDisappear` to post forecast context to the AI panel:

```swift
.onAppear {
    postForecastContext()
}
.onDisappear {
    NotificationCenter.default.post(name: .forecastingPageInactive, object: nil)
}
```

Add the context builder:

```swift
private func postForecastContext() {
    let critical = forecastRows.filter { ($0.part.forecastDaysUntilLow ?? 999) <= 7 }
    let warning = forecastRows.filter {
        let d = $0.part.forecastDaysUntilLow ?? 999
        return d > 7 && d <= 30
    }

    var context = "User is on the Forecasting page. "
    context += "Total parts: \(forecastRows.count). "
    context += "Critical (≤7 days): \(critical.count). "
    context += "Warning (7-30 days): \(warning.count). "
    context += "Current filter: \(filterUrgency.label). "

    if !critical.isEmpty {
        let topCritical = critical.prefix(5).map { "\($0.part.name) (\($0.part.forecastDaysUntilLow ?? 0)d, order \($0.part.forecastSuggestedOrder ?? 0))" }
        context += "Top critical: \(topCritical.joined(separator: "; ")). "
    }

    if let lastRun = forecastRows.first(where: { $0.part.forecastLastRun != nil })?.part.forecastLastRun {
        context += "Last recalculated: \(lastRun). "
    }

    NotificationCenter.default.post(
        name: .forecastingPageActive,
        object: nil,
        userInfo: ["context": context]
    )
}
```

Also re-post context after data loads (at the end of `loadData()`):

```swift
// At end of loadData(), after setting forecastRows:
if !forecastRows.isEmpty {
    postForecastContext()
}
```

### Step 3: Add GetForecastDataTool

In `AITools.swift`, add a new tool following the same pattern as `SearchPartsTool`:

```swift
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
public struct GetForecastDataTool: FoundationModels.Tool {
    let db: AppDatabase
    let permissions: [String]

    public let name = "get_forecast_data"
    public let description = """
        Get demand forecasting data for parts. Returns parts with their average daily usage (ADU), \
        reorder points, suggested order quantities, and days until low stock. \
        Can filter by urgency level (critical, warning, healthy) or search by part name.
        """

    public struct Input: Codable, Sendable {
        let urgency: String?   // "critical", "warning", "healthy", or nil for all
        let search: String?    // part name search
        let limit: Int?        // max results (default 10)
    }

    public func call(_ input: Input) async throws -> String {
        guard permissions.contains("view_parts_catalog") || permissions.contains("admin") else {
            return "You don't have permission to view forecast data."
        }

        return try db.writer.read { dbConn in
            var whereClauses = ["p.deleted_at IS NULL"]
            var args: [DatabaseValueConvertible?] = []

            // Urgency filter
            if let urgency = input.urgency?.lowercased() {
                switch urgency {
                case "critical":
                    whereClauses.append("COALESCE(p.forecast_days_until_low, 999) <= 7")
                case "warning":
                    whereClauses.append("COALESCE(p.forecast_days_until_low, 999) > 7")
                    whereClauses.append("COALESCE(p.forecast_days_until_low, 999) <= 30")
                case "healthy":
                    whereClauses.append("COALESCE(p.forecast_days_until_low, 999) > 30")
                default:
                    break
                }
            }

            // Search filter
            if let search = input.search, !search.isEmpty {
                whereClauses.append("(p.name LIKE ? OR p.code LIKE ?)")
                let pattern = "%\(search)%"
                args.append(pattern)
                args.append(pattern)
            }

            let limit = min(input.limit ?? 10, 25)
            args.append(limit)

            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT p.name, p.code,
                       p.forecast_adu_30, p.forecast_adu_90,
                       p.forecast_reorder_point, p.forecast_suggested_order,
                       p.forecast_days_until_low, p.forecast_last_run,
                       COALESCE(SUM(s.qty), 0) AS current_stock
                FROM parts p
                LEFT JOIN stock s ON s.part_id = p.id AND s.deleted_at IS NULL
                WHERE \(whereClauses.joined(separator: " AND "))
                GROUP BY p.id
                ORDER BY COALESCE(p.forecast_days_until_low, 9999) ASC
                LIMIT ?
                """, arguments: StatementArguments(args))

            if rows.isEmpty {
                return "No parts found matching that criteria."
            }

            var result = "Found \(rows.count) parts:\n"
            for row in rows {
                let name: String = row["name"] ?? "?"
                let code: String? = row["code"]
                let adu30: Double? = row["forecast_adu_30"]
                let days: Int? = row["forecast_days_until_low"]
                let suggested: Int? = row["forecast_suggested_order"]
                let stock: Int = row["current_stock"] ?? 0

                var line = "• \(name)"
                if let c = code { line += " (\(c))" }
                line += " — Stock: \(stock)"
                if let d = days { line += ", \(d) days until low" }
                if let a = adu30 { line += ", ADU: \(String(format: "%.1f", a))/day" }
                if let s = suggested, s > 0 { line += ", suggest ordering \(s)" }
                result += line + "\n"
            }
            return result
        }
    }
}
#endif
```

### Step 4: Register the tool

In `FoundationModelsService.swift`, in the `chatWithTools()` method, add the new tool to the tools array:

```swift
let tools: [any FoundationModels.Tool] = [
    SearchPartsTool(db: db, permissions: permissions),
    SearchContactsTool(db: db, permissions: permissions),
    SearchJobsTool(db: db, permissions: permissions),
    GetSupplierInfoTool(db: db, permissions: permissions),
    GetForecastDataTool(db: db, permissions: permissions),  // NEW
]
```

### Step 5: Handle forecast context in AI panel

In `IOSAIAssistantPanel.swift`, add forecast context handling alongside the catalog context:

```swift
@State private var forecastContext: String?
```

Add notification receivers (near the existing `.onReceive` for catalog):

```swift
.onReceive(NotificationCenter.default.publisher(for: .forecastingPageActive)) { notification in
    if let context = notification.userInfo?["context"] as? String {
        forecastContext = context
    }
}
.onReceive(NotificationCenter.default.publisher(for: .forecastingPageInactive)) { _ in
    forecastContext = nil
}
```

In the `generateResponse()` method, add forecast context to the navigation context (alongside the existing catalog context block):

```swift
if let ctx = forecastContext {
    navContext += "\n\nForecasting Page Context: \(ctx)"
    navContext += " You can help the user understand their forecast data, identify parts that need reordering, and explain usage trends."
}
```

## Important Notes

- The AI is **read-only** for forecasting — it can query and explain data but cannot trigger recalculations or create POs.
- The `GetForecastDataTool` respects the same permission check pattern as other tools.
- The tool returns at most 25 results to keep responses concise.
- Page context is posted both `onAppear` and after `loadData()` completes, so the AI always has current data.
- The `forecastContext` and `catalogContext` are independent — both can be active if the user navigates between them quickly, but `.onDisappear` clears the stale one.
- Follow the exact same `#if canImport(FoundationModels)` / `@available` guard pattern used by the existing tools.

## Success Criteria

- [ ] `.forecastingPageActive` / `.forecastingPageInactive` notifications defined
- [ ] Forecasting page posts context on appear and after data load
- [ ] `GetForecastDataTool` queries forecast data with urgency/search filters
- [ ] Tool registered in `chatWithTools()` tools array
- [ ] AI panel receives and uses forecast context
- [ ] AI can answer "which parts are running low?" with real data
- [ ] Read-only — no data modification through AI
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 23B Results (YYYY-MM-DD)
- GetForecastDataTool: urgency filter, search, stock + ADU + days display
- Forecasting page context: critical count, top items, last run timestamp
- AI panel: forecast context handling alongside catalog context
- Build: [PASS/FAIL]
```

**Forecasting page review complete. Continue with the next page review.**
