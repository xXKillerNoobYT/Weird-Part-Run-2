# 31A — Warehouse Dashboard: Service Layer + Smart Cards + Quick Actions

> **Chain position:** **31A** → 31B-31I
> **Plan:** `docs/plans/ios-warehouse-pages.md`
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Read the file first, then fix all issues. When done, wait for user confirmation.

## Context

The warehouse dashboard imports GRDB and uses raw SQL. It needs to use service layer methods only. The quick action buttons both navigate to the same place. It needs smart card filters (program standard) and platform guard removal.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/WarehouseDashboardPage.swift` (357 lines)
- `core/Sources/WiredPartCore/Services/WarehouseService.swift` — getWarehouseKPIs, listMovements

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/WarehouseDashboardPage.swift`

## Task

### Step 1: Remove `import GRDB`

Remove the GRDB import. Replace any raw SQL queries with WarehouseService method calls. If a needed service method doesn't exist, add it to WarehouseService.

### Step 2: Replace filter chips with smart card filters

Replace any horizontal capsule chip filters with smart card filters (program standard — tap to filter, tap again for All, always show counts):

```swift
// Smart cards: Movements Today | Receiving Active | Audit Due | Staging Ready | All
// Each card shows a count and acts as a toggle filter
// When tapped, filters the activity feed to that category
// Tap again to deselect (show all)
```

Use the same smart card pattern from the forecasting page (23C) and PO list page (26A). Cards should be:
- **Movements Today** — count of movements created today
- **Receiving Active** — count of active receiving sessions
- **Audit Due** — count of parts needing audit (certainty < 80%)
- **Staging Ready** — count of items in staging area

### Step 3: Fix quick action buttons

Currently both "New Movement" and "Scan QR" dispatch the same notification. Fix:
- **New Movement** → open IOSMovementWizard as a sheet/fullScreenCover
- **Scan QR** → open QRScanSheet with appropriate type filter

```swift
@State private var activeSheet: ActiveSheet?

private enum ActiveSheet: Identifiable {
    case newMovement
    case qrScanner
    var id: String { String(describing: self) }
}
```

### Step 4: Remove `#if os(iOS)` / `#elseif os(macOS)` platform guards

Remove all platform guard blocks. Keep the iOS code. Check for both `#if os(iOS)` and the duplicated `#elseif os(macOS)` pattern.

### Step 5: Add direct navigation to sub-pages

Add quick-access buttons or links to: Audit, Staging, Receiving, Inventory Grid from the dashboard.

## Success Criteria

- [ ] `import GRDB` removed — all data via service layer
- [ ] Smart card filters: Movements Today, Receiving Active, Audit Due, Staging Ready
- [ ] Quick actions correctly open Movement Wizard and QR Scanner
- [ ] Platform guards removed
- [ ] ActiveSheet pattern for sheets
- [ ] Direct nav links to sub-pages
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 31A Results (YYYY-MM-DD)
- Removed GRDB, smart cards, fixed quick actions
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 31B.**
