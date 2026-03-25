# 62N — Group PO Line Items by Job on IOSPODetailPage
> Chain position: Standalone

## Task

On `IOSPODetailPage`, PO line items are displayed as a flat list. Group them by job so users can see which parts are for which job. Items not linked to a job (forecast/restock orders) get their own "General Stock" section.

### Step 1: Update the PO detail data to include job info per line

In `core/Sources/WiredPartCore/Services/OrdersService.swift`, find the method that fetches PO line items (likely `getPODetail` or `getPOLineItems`). The SQL query that fetches line items needs to JOIN through `jpo_lines` → `job_parts_orders` → `jobs` to get the job name:

If the line items query doesn't already include job info, update it:

```sql
SELECT li.*,
       COALESCE(p.name, 'Unknown Part') AS part_name,
       p.code AS part_code,
       j.job_name,
       j.id AS job_id
FROM po_line_items li
LEFT JOIN parts p ON p.id = li.part_id
LEFT JOIN jpo_lines jl ON jl.po_line_id = li.id
LEFT JOIN job_parts_orders jpo ON jpo.id = jl.jpo_id
LEFT JOIN jobs j ON j.id = jpo.job_id
WHERE li.po_id = ? AND li.deleted_at IS NULL
ORDER BY j.job_name NULLS LAST, li.id
```

Add `jobId` and `jobName` to the line item detail struct (if not already present):

```swift
public var jobId: Int64?
public var jobName: String?
```

### Step 2: Group line items in the view

In `IOSPODetailPage.swift`, add a computed property that groups line items by job:

```swift
private var groupedLineItems: [(jobName: String, items: [POLineDetail])] {
    let dict = Dictionary(grouping: poDetail?.lineItems ?? []) { item in
        item.jobName ?? "General Stock"
    }
    // Sort: named jobs first alphabetically, "General Stock" last
    return dict.sorted { lhs, rhs in
        if lhs.key == "General Stock" { return false }
        if rhs.key == "General Stock" { return true }
        return lhs.key < rhs.key
    }.map { (jobName: $0.key, items: $0.value) }
}
```

### Step 3: Update the List to use sections

Replace the flat `ForEach(lineItems)` with grouped sections:

```swift
List {
    // ... PO header section (status, supplier, dates) ...

    ForEach(groupedLineItems, id: \.jobName) { group in
        Section {
            ForEach(group.items) { item in
                // ... existing line item row ...
            }
        } header: {
            HStack {
                Image(systemName: group.jobName == "General Stock"
                      ? "shippingbox" : "hammer")
                Text(group.jobName)
                    .font(.headline)
                Spacer()
                Text("\(group.items.count) item\(group.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

### Step 4: Handle edge cases

- If ALL items have no job (pure stock reorder PO), don't show the "General Stock" header — just show items flat.
- If there's only one job, still show the section header (it's useful context).
- Make sure the job name resolution handles deleted jobs gracefully (use COALESCE in SQL).

```swift
// Skip section headers if there's only one group AND it's "General Stock"
if groupedLineItems.count == 1 && groupedLineItems[0].jobName == "General Stock" {
    // Render flat (no section header)
    ForEach(groupedLineItems[0].items) { item in
        lineItemRow(item)
    }
} else {
    // Render with sections
    ForEach(groupedLineItems, id: \.jobName) { group in
        Section(group.jobName) {
            ForEach(group.items) { item in
                lineItemRow(item)
            }
        }
    }
}
```

## Files to Modify

- `core/Sources/WiredPartCore/Services/OrdersService.swift` — add job_id/job_name to PO line item query
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift` — group line items by job with section headers

## Success Criteria
- [ ] PO line items are grouped by job name with section headers
- [ ] Each section shows job name, icon, and item count
- [ ] Items not linked to a job appear under "General Stock"
- [ ] Single-group "General Stock" renders without a section header
- [ ] Job names sort alphabetically, "General Stock" always last
- [ ] No compile errors
