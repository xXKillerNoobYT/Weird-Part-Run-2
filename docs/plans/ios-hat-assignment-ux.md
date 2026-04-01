# iOS Hat Assignment & Access Control UX

> **Status:** Q&A answered 2026-03-31 — ready to code. `getHatMembers()` added to PeopleService ✅. Xcode prompt PE-022 written ✅.
> **GitHub Issue:** [#17](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/17) — "User Aces controles"
> **Related PE:** PE-022
> **Priority:** High — owner cannot manage user access without this working intuitively

---

## What This Does (Plain English)

This fixes the user experience around managing **who gets what access** in the app.

Right now the app has all the parts — you can create hats, you can set which permissions each hat gives, and you can assign hats to employees — but these three things are scattered across pages and the connections between them aren't obvious. The result is that users report "there's no way to add a hat to a user" even though the feature exists, just hidden inside Employee Detail → Hats tab.

This plan makes the hat/permission system **discoverable and usable** by:
1. Making hats tappable (shows a detail sheet: member list + assign/remove UI)
2. Adding navigation tiles on the People Dashboard to Hats & Permissions
3. Ensuring the Employee Detail Hats tab is clearly labeled and easy to find

---

## Why We Need This

GitHub issue #17 filed 2026-03-31: "No way to add a Hat or hats to a user or verify? NO way to change what permissions a hat actily gives the user to add remove permissions."

The feature exists but isn't discoverable. Fixing this is critical for onboarding — the owner can't configure access control without understanding these flows.

---

## Current State

### What exists today

| File | What it does | Gap |
|------|-------------|-----|
| `IOSHatsPage.swift` | Lists hats with member count badge | Rows are NOT tappable — no detail view, no member list |
| `IOSPermissionsPage.swift` | Full hat × permission matrix (toggles) | Works, but navigation from dashboard unclear |
| `IOSEmployeeDetailPage.swift` | Profile + Hats tab + Teams tab | Hats tab has toggle list — functional but hard to find |
| `IOSPeopleDashboardPage.swift` | Dashboard tiles for Employees, Customers, Contractors, etc. | No tiles for Hats or Permissions |
| `PeopleRouter.swift` | Routes "people-hats" → IOSHatsPage, "people-permissions" → IOSPermissionsPage | Navigation exists |

### Recent security fix (2026-03-31, commit 4e0d5e0)
- AuthService: `getUserPermissions`, `hasPermission`, `getUserHats`, `getUserHatNames` were all missing `deleted_at IS NULL` on `user_hats` — soft-deleted hat assignments still granted permissions. **Fixed.**
- IOSPermissionsPage: 10 permission keys that existed in `defaultPermissionMap` were missing from the hardcoded `allPermissions` list in the UI — they appeared in the DB but couldn't be toggled. **Fixed.**
- PeopleService: 3 more `user_hats` queries missing `deleted_at` filter. **Fixed.**

### Data layer (fully working — no changes needed here)
- `PeopleService.listHats()` — returns all hats with `userCount`
- `PeopleService.createHat(name:description:)` — creates a hat
- `PeopleService.deleteHat(id:)` — soft deletes a hat
- `PeopleService.getEmployeeHats(userId:)` — returns hats assigned to an employee
- `AuthService.getHatPermissions(hatId:)` — returns permission keys for a hat
- `AuthService.addHatPermission(hatId:permissionKey:)` — grants a permission
- `AuthService.removeHatPermission(hatId:permissionKey:)` — revokes a permission
- Hat assignment to users: via `PeopleService` (need to verify exact method name — likely `assignHat` or `toggleHat`)

---

## Proposed Changes

### A. IOSHatsPage — Make rows tappable (hat detail sheet)

**File:** `Weird Parts IOS/Weird Parts IOS/Features/People/IOSHatsPage.swift`

Add a `HatDetailSheet` that opens when a hat row is tapped. The sheet shows:

```
┌─────────────────────────────────────┐
│  ← Electrician                      │
│  "Electricians working on field jobs"│
├─────────────────────────────────────┤
│  MEMBERS (3)                         │
│  • John Smith                        │  ← remove button (if manage_hats)
│  • Maria Torres                      │
│  • Dave Lee                          │
│  [+ Add Employee]                    │  ← picker if manage_hats permission
├─────────────────────────────────────┤
│  PERMISSIONS (7)                     │  ← navigate to Permissions page
│  View Jobs, Clock In/Out, ...        │
│  [Edit Permissions →]                │
└─────────────────────────────────────┘
```

**New component:** `HatDetailSheet(hat:onDismiss:)` with:
- `@State var members: [PeopleService.HatMember]` — loaded via `getHatMembers(hatId:)` on appear
- `@State var canManageHats: Bool` — from `hasPermission("manage_hats")`
- `@State var showAddEmployeePicker: Bool` — sheet to pick from non-assigned employees
- **Member rows are tappable → navigate to employee full profile** (Q&A Q2 decision)
- Remove button per member: calls `toggleHatAssignment(employeeId:hatId:assign:false)` (gated on `manage_hats`)
- Add employee picker: calls `toggleHatAssignment(employeeId:hatId:assign:true)` (gated on `manage_hats`)
- **Permission summary section:** shows first 5 permission keys for this hat + "Edit Permissions →" button (Q&A Q5 decision — owner wants to see what a hat grants)

**Methods to verify before implementation:**
- Check `PeopleService` for `assignHat`/`removeHat` methods (or equivalent) — if they don't exist, they need to be added to the core
- Check if `PeopleService.listHats()` has a way to get members per hat — may need `getHatMembers(hatId:)`

### B. IOSPeopleDashboardPage — Add Hats & Permissions tiles

**File:** `Weird Parts IOS/Weird Parts IOS/Features/People/IOSPeopleDashboardPage.swift`

Add two navigation tiles in a "Management" section (separate from Employees/Customers/Contractors):

| Tile | Icon | Route | Permission Required |
|------|------|-------|---------------------|
| Hats & Roles | `graduationcap.fill` | `people-hats` | `manage_people` |
| Permissions | `lock.shield.fill` | `people-permissions` | `manage_people` |

**Q&A Decision (Q1):** Both tiles are visible ONLY to users with `manage_people` permission. Regular employees do not see them on the dashboard.

### C. IOSEmployeeDetailPage — Label the Hats tab more clearly

**File:** `Weird Parts IOS/Weird Parts IOS/Features/People/IOSEmployeeDetailPage.swift`

Current tab label: `"hats"` (raw string). Update to show count badge:
```swift
// Before
"hats"

// After
"Hats (\(assignedHatCount))"
```

Add a callout banner in the Hats tab when `allHats.isEmpty || !canManageHats`:
```
"You need the 'manage_people' permission to assign hats."
```

---

## Data Flow

### Assigning a hat to an employee (proposed flow)
1. User taps People Dashboard → Hats & Roles
2. `IOSHatsPage` loads — shows all hats with member counts
3. User taps a hat row → `HatDetailSheet` opens
4. Sheet loads members via `PeopleService.getHatMembers(hatId:)`
5. User taps "+ Add Employee" → employee picker sheet
6. User selects employee → calls `PeopleService.assignHat(userId:hatId:)` (or equivalent)
7. Sheet refreshes — new employee appears in member list
8. Member count badge on IOSHatsPage updates on sheet dismiss

### Editing permissions for a hat (current flow — works, just not discoverable)
1. User taps People Dashboard → Permissions
2. `IOSPermissionsPage` loads — hat selector at top, toggles below
3. User taps a hat chip → toggles update
4. User flips toggle → `AuthService.addHatPermission()` / `removeHatPermission()`

---

## Files to Create
- None (modifications only)

## Files to Modify
- `IOSHatsPage.swift` — add `HatDetailSheet`, make rows tappable
- `IOSPeopleDashboardPage.swift` — add Hats & Permissions tiles
- `IOSEmployeeDetailPage.swift` — improve Hats tab label + hint text

## Core Changes (needed before Xcode prompt)

**Verified existing methods (no changes needed):**
- `toggleHatAssignment(employeeId:hatId:assign:)` — assigns or removes a hat from an employee ✅
- `getAllHatsWithAssignment(employeeId:)` — used in EmployeeDetailPage Hats tab ✅
- `listHats()` — used in IOSHatsPage ✅

**Missing method — must add to core before Xcode prompt:**
- `getHatMembers(hatId: Int64) throws -> [EmployeeListItem]`
  - Query: `SELECT u.id, u.display_name, u.phone FROM users u JOIN user_hats uh ON uh.user_id = u.id WHERE uh.hat_id = ? AND uh.deleted_at IS NULL AND u.deleted_at IS NULL`
  - This is the hat-centric inverse of `getAllHatsWithAssignment` (which is employee-centric)
  - **Action:** Direct Swift edit to PeopleService.swift — add this method near line 991

---

## Test Plan
- Test 1: Tap a hat row — `HatDetailSheet` opens, shows correct member count
- Test 2: Add employee to hat — member appears immediately, hat count badge updates
- Test 3: Remove employee from hat — member disappears, auth permissions revoked
- Test 4: People Dashboard shows Hats & Roles tile — tapping navigates to IOSHatsPage
- Test 5: People Dashboard shows Permissions tile — tapping navigates to IOSPermissionsPage
- Test 6: Employee without `manage_people` permission sees tiles but cannot modify (read-only)

---

## User Roles Affected
- **Owner/Admin:** Can now easily find and use hat assignment + permission configuration via People Dashboard
- **Manager (manage_hats):** Can assign/remove hats from employees via hat detail sheet; can navigate to employee profile from hat detail
- **Employee (Q&A Q3 decision):** Employees CAN see all hats + which permissions each hat grants — useful to know who to contact for specific tasks. This is read-only from their perspective.
- **Developer:** `getHatMembers()` added to PeopleService ✅; `toggleHatAssignment()` exists ✅

---

## Security Considerations
- Permission gate: `manage_hats` required to toggle assignments
- Permission gate: `manage_people` required to see Permissions tile on dashboard
- Assignment changes must be logged in audit trail (existing audit infrastructure)
- After hat assignment change, the auth cache must be invalidated so permissions take effect immediately

---

## Apple HIG Notes
- Sheet presentation: use `.sheet(item:)` pattern already established in this codebase
- Member list: use `List` with `.insetGrouped` style (consistent with rest of app)
- Add/Remove buttons: must be ≥44×44pt tap target (see PE-009b)
- Permission summary in sheet: truncate to 3-5 permissions with "and N more" pattern

---

## Implementation Order

1. **Check core** — verify `assignHat`/`removeHat`/`getHatMembers` exist in `PeopleService`
2. **If missing, add to core** — direct Swift edit (not Xcode prompt)
3. **Write Xcode prompt PE-022** — UI changes in IOSHatsPage + IOSPeopleDashboardPage + IOSEmployeeDetailPage
4. **User runs PE-022 in Xcode**
5. **hunt-fix-verify** catches any issues
