# 31H — Warehouse Returns + Tools + Network + Settings Fixes

> **Plan:** `docs/plans/ios-warehouse-pages.md`

## Instructions

Read all 4 files first, then fix all issues. When done, wait for user confirmation.

## Context

Four smaller pages need fixes: Returns (display-only → actionable), Tools (display-only → actionable), Network (remove dummy data), Settings (fix error handling). All need platform guard removal.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSWarehouseReturnsPage.swift` (186 lines)
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSWarehouseToolsPage.swift` (184 lines)
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSWarehouseNetworkPage.swift` (125 lines)
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSWarehouseSettingsPage.swift` (169 lines)

## Task

### IOSWarehouseReturnsPage — Add Actions

1. **Make rows tappable** — tap to view return detail
2. **Add action buttons per row** (for appropriate statuses):
   - Pending: [Approve] [Reject (reason required)]
   - Approved: [Mark Shipped]
   - Shipped: [Mark Completed]
3. **Add [Create Return] toolbar button** with ActiveSheet pattern
4. **Replace capsule chips with smart card filters**
5. **Remove platform guard**
6. **Fix: status filter doesn't trigger loadData()** — add `.onChange(of: statusFilter) { loadData() }`

### IOSWarehouseToolsPage — Add Actions

1. **Make rows tappable** — tap to navigate to tool detail (IOSToolRegistryPage or similar)
2. **Add swipe actions:**
   - Available: [Check Out]
   - Checked Out: [Return]
   - Any: [Maintenance]
3. **Replace capsule chips with smart card filters**
4. **Remove platform guard**
5. **Add [+ Register Tool] toolbar button** if it doesn't exist

### IOSWarehouseNetworkPage — Remove Dummy Data

1. **Remove fake device list** and hardcoded "Pending Phase 16" text
2. **Keep the page structure** but show honest placeholder:
   ```swift
   EmptyStateView(
       icon: "network",
       title: "Network Discovery",
       message: "Device network discovery will be available in a future update. This page will show connected shop computers, tablets, and phones on your local network."
   )
   ```
3. **Remove the fake scan delay** (`scanForDevices()` that just waits 2 sec)
4. **Keep the page in the router** — don't remove it
5. **Remove platform guard**

### IOSWarehouseSettingsPage — Fix Error Handling

1. **Replace `print()` errors with `.alert()`** — errors should show to the user
2. **Change `onAppear` to `.task`** for initial settings load:
   ```swift
   // Replace:
   .onAppear { loadSettings() }
   // With:
   .task { loadSettings() }
   ```
3. **Add loading state** while settings load
4. **No platform guard to remove** (this file doesn't have one)

## Success Criteria

- [ ] Returns: rows tappable, Approve/Reject/Ship/Complete actions, smart cards
- [ ] Tools: rows tappable, Check Out/Return/Maintenance swipe actions, smart cards
- [ ] Network: dummy data removed, honest placeholder, fake scan removed
- [ ] Settings: print→alert, onAppear→.task, loading state
- [ ] Platform guards removed from Returns, Tools, Network
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 31I.**
