# 39A — Hats & Permission Audit (Cross-Cutting)

> **Chain position:** **39A** (standalone, prerequisite for 44C, 45A, 45B)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. All permission checks go through `appCore.hasPermission("key")`

## Instructions

**IMPORTANT:** Before implementing, read ALL files in `Features/` that gate content by role. Search for hardcoded role checks like `if role == "manager"`, `role == "admin"`, `role == "office"`, `.contains("manager")`, etc. Replace every one with hat permission checks using `appCore.hasPermission("key")`. Also add new permission keys that don't exist yet and seed them into the correct default hats.

## Context

The app currently has a hat/permission system (IOSHatsPage, IOSPermissionsPage), but many pages bypass it with hardcoded role string checks. This creates maintenance problems and makes it impossible for admins to customize access. Every content gate must go through the centralized permission system.

New permission keys are needed for job financials, job management, and self-assignment features that were designed but never added to the permission seed data.

## Task

### Step 1: Add New Permission Keys to Migration

In `AppDatabase+Migrations.swift`, add a new migration that seeds these permission keys:

```swift
// Migration: seed_new_permission_keys
// Add to the appropriate migration block

// New permission keys to insert into permissions table
let newPermissions: [(key: String, label: String, category: String)] = [
    ("view_job_financials", "View Job Financials", "jobs"),
    ("manage_jobs", "Manage Jobs", "jobs"),
    ("create_jobs", "Create Jobs", "jobs"),
    ("self_assign_ready_jobs", "Self-Assign Ready Jobs", "jobs"),
    ("self_assign_contact_jobs", "Self-Assign Contact Jobs", "jobs"),
    ("view_all_jobs", "View All Jobs", "jobs"),
    ("view_job_reports", "View Job Reports", "reports"),
    ("manage_scheduling", "Manage Scheduling", "scheduling"),
    ("approve_time_off", "Approve Time Off", "scheduling"),
    ("manage_fleet", "Manage Fleet", "fleet"),
    ("manage_warehouse", "Manage Warehouse", "warehouse"),
    ("manage_orders", "Manage Orders", "orders"),
    ("approve_orders", "Approve Orders", "orders"),
    ("manage_people", "Manage People", "people"),
    ("view_spending", "View Spending", "reports"),
    ("manage_tools", "Manage Tools", "tools"),
    ("manage_settings", "Manage Settings", "settings"),
    ("view_audit_log", "View Audit Log", "settings"),
]
```

### Step 2: Seed Default Hat Assignments

Assign permissions to default hats:

- **Owner/Admin hat:** ALL permissions
- **Manager hat:** All except `manage_settings`, `view_audit_log`
- **Lead/Foreman hat:** `manage_jobs`, `create_jobs`, `self_assign_ready_jobs`, `view_all_jobs`, `view_job_reports`, `manage_scheduling`, `manage_warehouse`
- **Worker hat:** `self_assign_ready_jobs`, `self_assign_contact_jobs`
- **Office hat:** `view_job_financials`, `manage_jobs`, `create_jobs`, `view_all_jobs`, `view_job_reports`, `manage_orders`, `approve_orders`, `manage_people`, `view_spending`, `manage_scheduling`, `approve_time_off`

### Step 3: Audit Every Page for Hardcoded Role Checks

Search the ENTIRE `Features/` directory for patterns like:
- `role == "manager"` or `role == "admin"` or `role == "office"`
- `role.contains("manager")` or `role.contains("admin")`
- `isManager` or `isAdmin` computed properties based on role strings
- Any `if/guard` that checks a user's role string directly

Replace each with the appropriate `appCore.hasPermission("key")` call.

**Example transformation:**

```swift
// BEFORE:
if currentUser.role == "manager" || currentUser.role == "admin" {
    // show financial section
}

// AFTER:
if appCore.hasPermission("view_job_financials") {
    // show financial section
}
```

### Step 4: Add Permission Helper if Missing

If `AppCore` doesn't already have a `hasPermission` method, add:

```swift
func hasPermission(_ key: String) -> Bool {
    guard let userId = currentUser?.id else { return false }
    // Check user's hats → hat_permissions → match key
    // This should already exist from the Hats/Permissions pages
    return userPermissions.contains(key)
}
```

### Step 5: Files to Audit (non-exhaustive — search for ALL)

- `JobsListPage.swift` — job visibility, financial data
- `IOSJobDetailTabView.swift` — financial tab, edit actions
- `IOSCreateJobSheet.swift` — create permission
- `IOSEditJobSheet.swift` — edit permission
- `DashboardView.swift` — admin widgets
- `IOSDispatchPage.swift` — scheduling permissions
- `IOSTimeOffPage.swift` — approval permissions
- `IOSFleetDashboardPage.swift` — fleet management
- `IOSPODetailPage.swift` — approve/reject actions
- `IOSSpendingDashboardPage.swift` — financial visibility
- `IOSEmployeesPage.swift` — manage people
- `IOSPermissionsPage.swift` — settings access
- `AuditLogPage.swift` — audit log access
- `OfficeRouter.swift` — office section visibility
- `UserMenuSheet.swift` — menu item visibility

### Step 6: Update ConflictResolver

Add any new tables to the whitelist in `ConflictResolver.swift`.

## Important Notes
- Do NOT remove the hat/permission system — enhance it
- Some pages may legitimately need no permission gate (e.g., the user's own profile)
- The `appCore.hasPermission()` call should be fast (cached in memory, not a DB query per check)
- Permission keys are lowercase_snake_case by convention
- If a page has BOTH role checks and permission checks, consolidate to permission-only

## Success Criteria
- [ ] New migration seeds 15+ permission keys
- [ ] Default hats get appropriate permission assignments
- [ ] Zero hardcoded role string checks remain in Features/
- [ ] All gated content uses `appCore.hasPermission("key")`
- [ ] ConflictResolver whitelist updated
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 39A Results (YYYY-MM-DD)
- X files audited for hardcoded role checks
- X permission keys added
- X files converted to hasPermission()
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
