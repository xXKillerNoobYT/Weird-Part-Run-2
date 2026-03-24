# 28A — Procurement Planner: Demand Consolidation + Stock Logic + Smart Cards

> **Chain position:** **28A** → 28B → 28C → 28D
> **Prerequisite:** 27B complete (JPO per-part status model)
> **Plan:** `docs/plans/ios-procurement-page.md` — Section 1
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** This is a COMPLETE REDESIGN of `IOSProcurementPage.swift`. Read the plan document AND the current file first. The current page is wrong — it lists approved JPOs. The new page aggregates ALL demand by PART from 4 sources. When done, wait for user confirmation.

## Context

The Procurement Planner turns DEMAND into ORDERS. It aggregates demand from 4 sources (JPO parts, Wishlist, Forecast, Overstock), groups by part, shows stock levels vs TARGET, and provides pull-from-shelf vs order options. The goal is to maintain TARGET value for all parts.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSProcurementPage.swift` — current (will be replaced)
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — existing JPO/PO methods
- `core/Sources/WiredPartCore/Services/PartsService.swift` — stock queries, forecast data
- `docs/plans/ios-procurement-page.md` — full design spec

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSProcurementPage.swift` — complete rewrite
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — add procurement aggregation methods

## Task

### Step 1: Add procurement aggregation service methods

In `OrdersService.swift`, add a method that consolidates all demand:

```swift
/// A single part's consolidated demand across all sources.
public struct ProcurementItem: Sendable, Identifiable {
    public let id: Int64          // part_id
    public let partName: String
    public let partCode: String?
    public let brandName: String?
    public let isGeneric: Bool     // brand is "General" or nil
    public let totalDemand: Int    // sum of all sources
    public let shopStock: Int
    public let minStock: Int
    public let targetStock: Int
    public let maxStock: Int
    public let deltaToTarget: Int  // positive = need more, negative = over target
    public let sources: [DemandSource]
    public let urgency: String     // "overstock", "understock", "below_target", "good"
}

public struct DemandSource: Sendable, Identifiable {
    public let id = UUID()
    public let sourceType: String  // "jpo", "wishlist", "forecast", "overstock"
    public let sourceId: Int64?    // JPO ID, wishlist item ID, etc.
    public let sourceName: String  // "JPO #127 (Smith Res.)", "Forecast restock", etc.
    public let quantity: Int
}

/// Get all consolidated procurement demand, grouped by part.
public func getProcurementDemand() throws -> [ProcurementItem] {
    try db.writer.read { dbConn in
        // 1. Get approved JPO lines not yet in procurement
        // 2. Get approved wishlist items not yet ordered
        // 3. Get forecast items (auto-approved, below MIN)
        // 4. Get overstock items (above MAX)
        // 5. Group by part_id, aggregate quantities
        // 6. For each part: query shop stock, min/target/max
        // 7. Calculate deltaToTarget and urgency

        // Start with JPO lines that are approved but not yet in_procurement/ordered
        let jpoLines = try Row.fetchAll(dbConn, sql: """
            SELECT jl.part_id, p.name AS part_name, p.code AS part_code,
                   b.name AS brand_name,
                   CASE WHEN b.name IS NULL OR b.name = 'General' THEN 1 ELSE 0 END AS is_generic,
                   jl.quantity, jl.id AS line_id,
                   jpo.id AS jpo_id, j.job_name
            FROM jpo_lines jl
            JOIN job_purchase_orders jpo ON jpo.id = jl.jpo_id
            JOIN jobs j ON j.id = jpo.job_id
            LEFT JOIN parts p ON p.id = jl.part_id
            LEFT JOIN brands b ON b.id = p.brand_id
            WHERE jl.line_status = 'approved'
              AND jl.deleted_at IS NULL
              AND jpo.deleted_at IS NULL
            """)

        // Group by part_id
        var partDemand: [Int64: (part: Row, sources: [DemandSource], totalQty: Int)] = [:]

        for row in jpoLines {
            guard let partId: Int64 = row["part_id"] else { continue }
            let jpoId: Int64 = row["jpo_id"]
            let jobName: String = row["job_name"] ?? ""
            let qty: Int = row["quantity"]

            let source = DemandSource(
                sourceType: "jpo",
                sourceId: jpoId,
                sourceName: "JPO #\(jpoId) (\(jobName))",
                quantity: qty
            )

            if partDemand[partId] != nil {
                partDemand[partId]!.sources.append(source)
                partDemand[partId]!.totalQty += qty
            } else {
                partDemand[partId] = (part: row, sources: [source], totalQty: qty)
            }
        }

        // TODO: Also query wishlist_items (status = "approved") and forecast items
        // Group them into the same partDemand dictionary with sourceType "wishlist"/"forecast"

        // Build final items with stock info
        var items: [ProcurementItem] = []
        for (partId, data) in partDemand {
            let shopStock = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(SUM(qty), 0) FROM stock
                WHERE part_id = ? AND deleted_at IS NULL
                """, arguments: [partId]) ?? 0

            let stockInfo = try Row.fetchOne(dbConn, sql: """
                SELECT COALESCE(min_stock_level, 0) AS min_stock,
                       COALESCE(target_stock_level, 0) AS target_stock,
                       COALESCE(max_stock_level, 0) AS max_stock
                FROM parts WHERE id = ?
                """, arguments: [partId])

            let minStock = (stockInfo?["min_stock"] as Int?) ?? 0
            let targetStock = (stockInfo?["target_stock"] as Int?) ?? 0
            let maxStock = (stockInfo?["max_stock"] as Int?) ?? 0
            let delta = targetStock - shopStock

            let urgency: String
            if shopStock > maxStock { urgency = "overstock" }
            else if shopStock < minStock { urgency = "understock" }
            else if shopStock < targetStock { urgency = "below_target" }
            else { urgency = "good" }

            items.append(ProcurementItem(
                id: partId,
                partName: data.part["part_name"] ?? "Unknown",
                partCode: data.part["part_code"],
                brandName: data.part["brand_name"],
                isGeneric: (data.part["is_generic"] as Int?) == 1,
                totalDemand: data.totalQty,
                shopStock: shopStock,
                minStock: minStock,
                targetStock: targetStock,
                maxStock: maxStock,
                deltaToTarget: delta,
                sources: data.sources,
                urgency: urgency
            ))
        }

        // Check for overstock items (above MAX, no demand — still show them)
        let overstockParts = try Row.fetchAll(dbConn, sql: """
            SELECT p.id, p.name, p.code, COALESCE(SUM(s.qty), 0) AS stock,
                   p.max_stock_level
            FROM parts p
            LEFT JOIN stock s ON s.part_id = p.id AND s.deleted_at IS NULL
            WHERE p.deleted_at IS NULL AND p.max_stock_level > 0
            GROUP BY p.id
            HAVING stock > p.max_stock_level
            """)
        for row in overstockParts {
            let partId: Int64 = row["id"]
            if partDemand[partId] == nil {
                // Overstock part with no demand — add as overstock-only item
                let stock: Int = row["stock"]
                let maxS: Int = row["max_stock_level"]
                items.append(ProcurementItem(
                    id: partId,
                    partName: row["name"] ?? "Unknown",
                    partCode: row["code"],
                    brandName: nil,
                    isGeneric: false,
                    totalDemand: 0,
                    shopStock: stock,
                    minStock: 0, targetStock: 0, maxStock: maxS,
                    deltaToTarget: 0 - (stock - maxS),
                    sources: [DemandSource(sourceType: "overstock", sourceId: nil,
                                          sourceName: "Overstock (above MAX)", quantity: stock - maxS)],
                    urgency: "overstock"
                ))
            }
        }

        // Sort: overstock first (mandatory), then understock, then below_target, then good
        let urgencyOrder = ["overstock": 0, "understock": 1, "below_target": 2, "good": 3]
        items.sort { (urgencyOrder[$0.urgency] ?? 99) < (urgencyOrder[$1.urgency] ?? 99) }
        return items
    }
}
```

### Step 2: Rewrite IOSProcurementPage

Complete rewrite with smart card filters and the demand consolidation view:

```swift
struct IOSProcurementPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var items: [OrdersService.ProcurementItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var sourceFilter: String? = nil // nil = all

    var body: some View {
        VStack(spacing: 0) {
            smartCardFilters
            if isLoading {
                ProgressView("Loading procurement data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
            } else if filteredItems.isEmpty {
                EmptyStateView(icon: "cart", title: "No Procurement Needs",
                    message: "All demand has been fulfilled.")
            } else {
                procurementList
            }
        }
        .navigationTitle("Procurement")
        .refreshable { await loadData() }
        .task { await loadData() }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        // 4 source cards + All card
        // JPO Parts | Wishlist | Forecast | Overstock | All
        // Tap to filter, tap again to deselect (show all)
        // Cards always show global counts
        let jpoCount = items.filter { $0.sources.contains { $0.sourceType == "jpo" } }.count
        let wishlistCount = items.filter { $0.sources.contains { $0.sourceType == "wishlist" } }.count
        let forecastCount = items.filter { $0.sources.contains { $0.sourceType == "forecast" } }.count
        let overstockCount = items.filter { $0.urgency == "overstock" }.count

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                smartCard("JPO Parts", count: jpoCount, icon: "📋", filter: "jpo")
                smartCard("Wishlist", count: wishlistCount, icon: "🛒", filter: "wishlist")
                smartCard("Forecast", count: forecastCount, icon: "📊", filter: "forecast")
                smartCard("Overstock", count: overstockCount, icon: "⚠️", filter: "overstock")
                smartCard("All", count: items.count, icon: "", filter: nil)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func smartCard(_ label: String, count: Int, icon: String, filter: String?) -> some View {
        Button {
            withAnimation { sourceFilter = sourceFilter == filter ? nil : filter }
        } label: {
            VStack(spacing: 4) {
                Text("\(icon) \(count)")
                    .font(.title3)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption2)
            }
            .frame(minWidth: 70)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(sourceFilter == filter ? Color.accentColor : Color.secondary.opacity(0.12))
            )
            .foregroundStyle(sourceFilter == filter ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtered Items

    private var filteredItems: [OrdersService.ProcurementItem] {
        guard let filter = sourceFilter else { return items }
        if filter == "overstock" {
            return items.filter { $0.urgency == "overstock" }
        }
        return items.filter { $0.sources.contains { $0.sourceType == filter } }
    }

    // MARK: - Procurement List

    private var procurementList: some View {
        List {
            // KPI summary
            Section {
                HStack {
                    Label("\(filteredItems.count) parts need attention", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            ForEach(filteredItems) { item in
                procurementRow(item)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func procurementRow(_ item: OrdersService.ProcurementItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Part header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.partName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let code = item.partCode {
                        Text(code)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("Total: \(item.totalDemand)")
                    .font(.subheadline)
                    .fontWeight(.bold)
            }

            // Stock level + delta to target
            HStack(spacing: 8) {
                Text("Shop: \(item.shopStock)")
                    .font(.caption)
                Text("(Target: \(item.targetStock))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Delta badge
                let delta = item.deltaToTarget
                if delta > 0 {
                    Text("(+\(delta) to target)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                } else if delta < 0 {
                    Text("(\(delta) over target)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                } else {
                    Text("At target ✓")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // Overstock warning
            if item.urgency == "overstock" {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("OVER MAX — mandatory pull of at least \(item.shopStock - item.maxStock)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Sources
            ForEach(item.sources) { source in
                HStack(spacing: 4) {
                    sourceIcon(source.sourceType)
                    Text(source.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("qty: \(source.quantity)")
                        .font(.caption)
                        .monospaced()
                }
            }

            // Pull options (next prompt 28B handles supplier selection)
            // For now, show the stock-aware options:
            pullOptionsView(item)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func pullOptionsView(_ item: OrdersService.ProcurementItem) -> some View {
        if item.shopStock > 0 && item.totalDemand > 0 {
            VStack(spacing: 4) {
                // Option 1: Pull to Target + order remaining (RECOMMENDED)
                let pullToTarget = max(0, item.shopStock - item.targetStock)
                let orderAfterPull = max(0, item.totalDemand - pullToTarget)
                if pullToTarget > 0 {
                    pullButton(
                        label: "Pull \(pullToTarget) to target" + (orderAfterPull > 0 ? " + order \(orderAfterPull)" : ""),
                        isRecommended: true
                    )
                }

                // Option 2: Pull all + order remaining
                let orderAfterAll = max(0, item.totalDemand - item.shopStock)
                if item.shopStock >= item.totalDemand {
                    pullButton(label: "Pull \(item.totalDemand) from shelf (no order needed)", isRecommended: pullToTarget == 0)
                } else {
                    pullButton(label: "Pull all \(item.shopStock) + order \(orderAfterAll)", isRecommended: false)
                }

                // Option 3: Order all
                pullButton(label: "Order all \(item.totalDemand)", isRecommended: false)
            }
        }
    }

    private func pullButton(label: String, isRecommended: Bool) -> some View {
        Button { /* TODO: execute pull/order action */ } label: {
            Text(label)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(isRecommended ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                .foregroundStyle(isRecommended ? .accentColor : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func sourceIcon(_ type: String) -> some View {
        switch type {
        case "jpo": Image(systemName: "doc.text").foregroundStyle(.blue).font(.caption2)
        case "wishlist": Image(systemName: "heart").foregroundStyle(.pink).font(.caption2)
        case "forecast": Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.green).font(.caption2)
        case "overstock": Image(systemName: "exclamationmark.triangle").foregroundStyle(.red).font(.caption2)
        default: Image(systemName: "circle").foregroundStyle(.secondary).font(.caption2)
        }
    }

    // MARK: - Data

    @Sendable
    private func loadData() async {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
        isLoading = items.isEmpty
        loadError = nil
        do {
            items = try service.getProcurementDemand()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
```

## Important Notes

- This is a COMPLETE REWRITE — the old page logic is wrong
- The `getProcurementDemand()` method is a starting point — it queries JPO lines but has TODOs for wishlist and forecast sources. Those will work once the wishlist table exists.
- Pull options use TARGET as the reference (confirmed by user)
- Over MAX items are sorted to the top with mandatory pull warning
- Smart card filters use the program standard pattern
- The pull option buttons are placeholders — 28B adds supplier selection, 28C adds PO generation
- Check actual table/column names: `jpo_lines` vs `jpo_line_items`, `job_purchase_orders`, etc.

## Success Criteria

- [ ] `getProcurementDemand()` method aggregates demand from approved JPO lines
- [ ] Overstock detection (above MAX) included
- [ ] Page completely rewritten with smart card filters
- [ ] 4 source cards: JPO Parts, Wishlist, Forecast, Overstock
- [ ] Each part shows: name, code, stock, target, delta (+X/-X)
- [ ] Pull options shown with recommended option highlighted
- [ ] Over MAX items show mandatory pull warning
- [ ] ErrorStateView + loadError guard
- [ ] No platform guards
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 28A Results (YYYY-MM-DD)
- Procurement page rewritten with demand consolidation
- getProcurementDemand service method
- Smart card filters, pull options, overstock warnings
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 28B.**
