# 26A — PO List Page: Cleanup + Count Badges

> **Chain position:** **26A** → 26B → 26C → 26D → 26E → 26F
> **Prerequisite:** None
> **Plan:** `docs/plans/ios-purchase-orders-page.md` — Issues + Section 1
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement. When done, wait for user confirmation before proceeding to the next prompt.

## Context

The PO list page is clean but has minor issues: a leftover `#if os(iOS)` platform guard, no count badges on status filter chips, the `guard let service` doesn't set `loadError`, and dates are displayed as raw strings.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPurchaseOrdersPage.swift` — the page to fix
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — listPurchaseOrders method

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPurchaseOrdersPage.swift`

## Task

### Step 1: Remove `#if os(iOS)` platform guard

Find and remove the `#if os(iOS)` / `#endif` block around `.listStyle(.insetGrouped)`. Keep the iOS code, remove the guard.

### Step 2: Add count badges to status filter chips

The status chips currently show just the name. Add a count showing how many POs are in each status:

```swift
// Load all POs once (unfiltered) to get counts
@State private var allPurchaseOrders: [OrdersService.POListItem] = []

// Compute counts per status
private func countForStatus(_ status: String) -> Int {
    if status == "all" { return allPurchaseOrders.count }
    return allPurchaseOrders.filter { $0.status == status }.count
}
```

Update the chip label:

```swift
Text("\(status == "all" ? "All" : status.capitalized) (\(countForStatus(status)))")
```

Update `loadData()` to load all POs for counts, then filter for display:

```swift
private func loadData() {
    guard let service = appCore.ordersService else {
        loadError = "Orders service not available"
        isLoading = false
        return
    }
    isLoading = purchaseOrders.isEmpty
    loadError = nil
    do {
        // Load all for counts
        allPurchaseOrders = try service.listPurchaseOrders(status: nil)
        // Load filtered for display
        purchaseOrders = statusFilter == "all"
            ? allPurchaseOrders
            : allPurchaseOrders.filter { $0.status == statusFilter }
    } catch {
        loadError = error.localizedDescription
    }
    isLoading = false
}
```

### Step 3: Fix guard on ordersService

The current `guard let service = appCore.ordersService else { return }` silently fails. Fix it to set loadError:

```swift
guard let service = appCore.ordersService else {
    loadError = "Orders service not available"
    isLoading = false
    return
}
```

### Step 4: Format date strings

The `orderDate` is displayed as a raw ISO string. Format it:

```swift
private func formatDate(_ isoString: String?) -> String? {
    guard let str = isoString else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withFullDate]
    guard let date = iso.date(from: String(str.prefix(10))) else { return str }
    let display = DateFormatter()
    display.dateStyle = .medium
    return display.string(from: date)
}
```

Use in the row:

```swift
if let date = formatDate(po.orderDate) {
    Text(date)
        .font(.caption)
        .foregroundStyle(.tertiary)
}
```

## Success Criteria

- [ ] `#if os(iOS)` platform guard removed
- [ ] Status chips show count badges: "Draft (3)", "Ordered (5)", etc.
- [ ] `guard` on ordersService sets loadError instead of silent return
- [ ] Dates formatted as "Mar 20, 2026" instead of ISO strings
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 26A Results (YYYY-MM-DD)
- Removed platform guard
- Count badges on all 7 status chips
- Fixed silent guard failure → loadError
- Date formatting: ISO → medium style
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 26B.**
