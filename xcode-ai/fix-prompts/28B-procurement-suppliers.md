# 28B — Procurement: Supplier Selection Per Part

> **Chain position:** 28A → **28B** → 28C → 28D
> **Prerequisite:** 28A complete (demand consolidation, pull options)
> **Plan:** `docs/plans/ios-procurement-page.md` — Supplier Selection section
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Read 28A results and the plan first. When done, wait for user confirmation.

## Context

After 28A, each part row shows demand sources and pull options. Now add per-part supplier selection: show ALL suppliers that carry each part, highlight cheapest/highest-rated/fastest. Support splitting an order by JPO when one JPO is more urgent. Generic parts (brand = "General") are supplier-locked per job.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSProcurementPage.swift` — after 28A
- `core/Sources/WiredPartCore/Services/PartsService.swift` — supplier-part links, supplier scores
- `docs/plans/ios-procurement-page.md` — Supplier Selection section

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSProcurementPage.swift`
- `core/Sources/WiredPartCore/Services/OrdersService.swift` (add supplier query for procurement)

## Task

### Step 1: Add supplier data to ProcurementItem

Add a `suppliers` array to each `ProcurementItem`:

```swift
public struct PartSupplierOption: Sendable, Identifiable {
    public let id: Int64           // supplier_id
    public let name: String
    public let unitPrice: Double?
    public let reliabilityScore: Double?
    public let processingDays: Int?
    public let deliveryDay: String?  // e.g., "Monday", "Wednesday"
    public let isToday2PM: Bool     // can make today's cutoff?
    public let tag: String?         // "cheapest", "rated", "fastest", or nil
}
```

Query supplier-part links for each part in procurement. Assign tags:
- `"cheapest"` → lowest `unitPrice`
- `"rated"` → highest `reliabilityScore`
- `"fastest"` → shortest delivery considering 2 PM cutoff:
  - If current time < 2 PM → supplier's next delivery day from today counts
  - If current time ≥ 2 PM → window closed, next available after processing time

### Step 2: Add supplier selection UI to each part row

After the pull options, show supplier radio buttons:

```swift
// Supplier selection — radio buttons with highlight tags
ForEach(item.suppliers) { supplier in
    HStack {
        // Radio button
        Image(systemName: selectedSupplier[item.id] == supplier.id
            ? "largecircle.fill.circle" : "circle")
            .foregroundStyle(.accentColor)

        Text(supplier.name)
            .font(.caption)

        if let price = supplier.unitPrice {
            Text(String(format: "$%.2f", price))
                .font(.caption)
                .monospaced()
        }

        // Tags
        if let tag = supplier.tag {
            Text(tag == "cheapest" ? "🟢cheapest" :
                 tag == "rated" ? "⭐rated" :
                 tag == "fastest" ? "⚡fastest" : "")
                .font(.caption2)
                .foregroundStyle(tag == "cheapest" ? .green : tag == "fastest" ? .orange : .purple)
        }

        if supplier.isToday2PM {
            Text("📦today")
                .font(.caption2)
                .foregroundStyle(.blue)
        }
    }
    .onTapGesture { selectedSupplier[item.id] = supplier.id }
}
```

### Step 3: Add state for supplier selection

```swift
@State private var selectedSupplier: [Int64: Int64] = [:]  // [partId: supplierId]
```

### Step 4: Generic parts — supplier lock per job

For generic parts (brand = "General"), check the JPO's job tags. If the job already has a supplier for this part type, pre-select that supplier and show a lock icon:

```swift
if item.isGeneric {
    // Check if any source JPO already has a supplier set for this part
    // If so, pre-select and show "🔒 Locked to [Supplier] for Job #412"
    Text("🔒 Generic — supplier locked per job")
        .font(.caption2)
        .foregroundStyle(.orange)
}
```

### Step 5: Split order by JPO

Add a [Split by JPO] button that expands the part row to show per-JPO supplier selection:

```swift
Button("Split by JPO") { expandedPartId = item.id }

// When expanded:
if expandedPartId == item.id {
    ForEach(item.sources.filter { $0.sourceType == "jpo" }) { source in
        HStack {
            Text(source.sourceName)
                .font(.caption)
            Spacer()
            Text("qty: \(source.quantity)")
                .font(.caption)
            // Per-JPO supplier picker
            Picker("", selection: /* per-source supplier binding */) {
                ForEach(item.suppliers) { s in
                    Text(s.name).tag(s.id)
                }
            }
            .pickerStyle(.menu)
        }
    }
}
```

### Step 6: 2 PM cutoff logic

In the supplier query, calculate whether each supplier can make today's delivery:

```swift
let now = Date()
let calendar = Calendar.current
let hour = calendar.component(.hour, from: now)
let isPre2PM = hour < 14

// For each supplier:
// If isPre2PM AND supplier.deliveryDay includes today's weekday
//   AND supplier.processingDays == 0 (same-day)
// Then isToday2PM = true
```

## Success Criteria

- [ ] Suppliers listed per part with unit price and scores
- [ ] Tags: 🟢cheapest, ⭐rated, ⚡fastest highlighted
- [ ] 2 PM cutoff: "📦today" badge when same-day delivery possible
- [ ] Radio button selection per part
- [ ] Generic parts show lock icon + pre-select job's supplier
- [ ] Split by JPO allows per-JPO supplier picking
- [ ] State tracks selected supplier per part
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 28B Results (YYYY-MM-DD)
- Per-part supplier selection with tags
- 2PM cutoff calculation
- Generic part supplier lock
- Split by JPO option
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 28C.**
