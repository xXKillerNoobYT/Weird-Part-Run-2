# 32A — Navigation Restructure: Sidebar Order + Tab Naming + Missing Pages

> **Chain position:** **32A** (standalone, no dependencies)
> **Prerequisite:** None
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Read ALL files mentioned below first. Understand the current state, then implement ALL changes in one pass. When done, wait for user confirmation.

## Context

The sidebar navigation order doesn't match how people actually use the app. Dashboards and daily-use pages should be at the top. Administrative/management pages at the bottom. Tab names within modules need to be clearer. Some designed pages are missing from navigation.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` — module + tab definitions

## Task

### Step 1: Reorder the `appModules` array

Change the order of modules in the `appModules` array to this EXACT order:

```swift
let appModules: [AppModule] = [
    // ── DAILY USE (everyone) ──
    // 1. Dashboard — first thing every morning
    AppModule(id: "dashboard", ...),
    // 2. Jobs — what you work on all day
    AppModule(id: "jobs", ...),
    // 3. Chat — constant communication
    AppModule(id: "chat", ...),
    // 4. Scheduling — check schedule, dispatch, time off
    AppModule(id: "scheduling", ...),

    // ── WORK TOOLS (role-based) ──
    // 5. Warehouse — movements, receiving, staging
    AppModule(id: "warehouse", ...),
    // 6. Orders — JPOs, POs, procurement
    AppModule(id: "orders", ...),
    // 7. Fleet — trucks, trailers, my truck
    AppModule(id: "fleet", ...),
    // 8. Tools — registry, checkouts, kits
    AppModule(id: "tools", ...),
    // 9. Notebooks — job notes, templates
    AppModule(id: "notebooks", ...),

    // ── MANAGEMENT (office/admin) ──
    // 10. Parts — catalog, pricing, forecasting
    AppModule(id: "parts", ...),
    // 11. People — customers, employees, contacts
    AppModule(id: "people", ...),
    // 12. Office — spending, reports, HR
    AppModule(id: "office", ...),
    // 13. Settings — app config, security
    AppModule(id: "settings", ...),
]
```

### Step 2: Fix tab order WITHIN modules

**Orders module** — reorder tabs to follow the workflow (create JPO → becomes PO → procurement → manage):

```swift
AppModule(id: "orders", label: "Orders", icon: "cart.fill", tabs: [
    AppTab(id: "orders-jpos", label: "Job Orders", icon: "doc.badge.plus", path: "/orders/jpos"),
    AppTab(id: "orders-pos", label: "Purchase Orders", icon: "doc.text.fill", path: "/orders/purchase-orders"),
    AppTab(id: "orders-procurement", label: "Procurement", icon: "cart.badge.plus", path: "/orders/procurement"),
    AppTab(id: "orders-parts", label: "Parts Mgmt", icon: "list.bullet.rectangle.portrait", path: "/orders/parts"),
    AppTab(id: "orders-staging", label: "Stage Planner", icon: "list.clipboard.fill", path: "/orders/staging"),
    AppTab(id: "orders-approvals", label: "Approvals", icon: "checkmark.circle.fill", path: "/orders/approvals"),
    AppTab(id: "orders-returns", label: "Returns", icon: "arrow.uturn.left", path: "/orders/returns"),
    AppTab(id: "orders-wishlist", label: "Wishlist", icon: "heart.text.clipboard", path: "/orders/wishlist"),
], permission: "view_orders"),
```

**Tools module** — dashboard first, admin last:

```swift
AppModule(id: "tools", label: "Tools", icon: "wrench.adjustable.fill", tabs: [
    AppTab(id: "tools-dashboard", label: "Dashboard", icon: "chart.bar.fill", path: "/tools/dashboard"),
    AppTab(id: "tools-registry", label: "All Tools", icon: "list.bullet", path: "/tools/registry"),
    AppTab(id: "tools-checkouts", label: "Checkouts", icon: "arrow.right.circle.fill", path: "/tools/checkouts"),
    AppTab(id: "tools-kits", label: "Kits", icon: "suitcase.fill", path: "/tools/kits"),
    AppTab(id: "tools-maintenance", label: "Maintenance", icon: "wrench.adjustable.fill", path: "/tools/maintenance"),
    AppTab(id: "tools-admin", label: "Admin", icon: "person.badge.key.fill", path: "/tools/admin", permission: "manage_tools"),
], permission: "view_tools"),
```

**Warehouse module** — follow receiving workflow, rename Receiving to Sorting:

```swift
AppModule(id: "warehouse", label: "Warehouse", icon: "building.fill", tabs: [
    AppTab(id: "warehouse-dashboard", label: "Dashboard", icon: "chart.bar.fill", path: "/warehouse/dashboard"),
    AppTab(id: "warehouse-receiving", label: "Sorting", icon: "shippingbox.fill", path: "/warehouse/receiving"),
    AppTab(id: "warehouse-staging", label: "Staging", icon: "tray.2.fill", path: "/warehouse/staging"),
    AppTab(id: "warehouse-movements", label: "Movements", icon: "arrow.left.arrow.right", path: "/warehouse/movements"),
    AppTab(id: "warehouse-inventory", label: "Inventory", icon: "square.grid.3x3.fill", path: "/warehouse/inventory"),
    AppTab(id: "warehouse-locations", label: "Locations", icon: "map.fill", path: "/warehouse/locations"),
    AppTab(id: "warehouse-audit", label: "Audit", icon: "checkmark.shield.fill", path: "/warehouse/audit", permission: "perform_audit"),
    AppTab(id: "warehouse-returns", label: "Returns", icon: "arrow.uturn.left", path: "/warehouse/returns"),
    AppTab(id: "warehouse-tools", label: "Tools", icon: "wrench.and.screwdriver.fill", path: "/warehouse/tools"),
    AppTab(id: "warehouse-network", label: "Network", icon: "antenna.radiowaves.left.and.right", path: "/warehouse/network", permission: "manage_devices"),
    AppTab(id: "warehouse-settings", label: "Settings", icon: "gearshape.fill", path: "/warehouse/settings", permission: "manage_warehouse"),
], permission: "view_warehouse"),
```

**People module** — consolidate HR tabs from Office into People:

```swift
AppModule(id: "people", label: "People", icon: "person.2.fill", tabs: [
    AppTab(id: "people-employees", label: "Employees", icon: "person.fill", path: "/people/employees", permission: "view_people"),
    AppTab(id: "people-customers", label: "Customers", icon: "person.crop.circle", path: "/people/customers", permission: "view_customers"),
    AppTab(id: "people-contacts", label: "Contacts", icon: "person.crop.rectangle.fill", path: "/people/contacts"),
    AppTab(id: "people-contractors", label: "Contractors", icon: "person.badge.shield.checkmark.fill", path: "/people/contractors", permission: "view_contractors"),
    AppTab(id: "people-teams", label: "Teams", icon: "person.3.fill", path: "/people/teams"),
    AppTab(id: "people-hats", label: "Hats & Roles", icon: "graduationcap.fill", path: "/people/hats", permission: "manage_people"),
    AppTab(id: "people-permissions", label: "Permissions", icon: "lock.shield.fill", path: "/people/permissions", permission: "manage_people"),
], permission: "view_people"),
```

**Office module** — remove HR tabs (moved to People), keep operations + finance:

```swift
AppModule(id: "office", label: "Office", icon: "briefcase.fill", tabs: [
    AppTab(id: "office-manage-jobs", label: "Manage Jobs", icon: "hammer.fill", path: "/office/manage-jobs", permission: "manage_jobs"),
    AppTab(id: "office-warehouse-exec", label: "Warehouse", icon: "building.fill", path: "/office/warehouse-exec", permission: "manage_warehouse"),
    AppTab(id: "office-deletion-approvals", label: "Deletions", icon: "trash.circle", path: "/office/deletion-approvals", permission: "manage_jobs"),
    AppTab(id: "office-spending", label: "Spending", icon: "dollarsign.circle.fill", path: "/office/spending", permission: "show_dollar_values"),
    AppTab(id: "office-timesheets", label: "Timesheets", icon: "clock.badge.checkmark", path: "/office/timesheets", permission: "view_reports"),
    AppTab(id: "office-pre-billing", label: "Pre-Billing", icon: "doc.text.fill", path: "/office/pre-billing", permission: "export_reports"),
    AppTab(id: "office-bookkeeper", label: "Bookkeeper", icon: "books.vertical.fill", path: "/office/bookkeeper", permission: "export_reports"),
    AppTab(id: "office-profitability", label: "Profitability", icon: "chart.pie.fill", path: "/office/profitability", permission: "show_dollar_values"),
    AppTab(id: "office-labor-overview", label: "Labor Overview", icon: "person.3.fill", path: "/office/labor-overview", permission: "view_labor"),
    AppTab(id: "office-daily-summary", label: "Daily Summary", icon: "chart.bar.fill", path: "/office/daily-summary", permission: "view_reports"),
], permission: "manage_jobs"),
```

### Step 3: Rename tabs for clarity

| Current Name | New Name | Reason |
|-------------|----------|--------|
| "Requests" (Orders) | "Job Orders" | "Requests" is vague — these are Job Purchase Orders |
| "Registry" (Tools) | "All Tools" | Consistent with "All Notebooks", "All Jobs" pattern |
| "Receiving" (Warehouse) | "Sorting" | Page actually does sorting/routing, not just receiving |
| "Deletion Approvals" (Office) | "Deletions" | Shorter, fits sidebar better |

### Step 4: Verify router handles new paths

Check that `IOSContentRouter.swift` and all module routers handle:
- `/orders/wishlist` → placeholder or stub page for now
- `/people/employees` → `IOSEmployeesPage` (was under Office)
- `/people/hats` → `IOSHatsPage` (was under Office)
- `/people/permissions` → `IOSPermissionsPage` (was under Office)

If any route is missing, add it to the appropriate router. If a page doesn't exist yet (Wishlist), create a placeholder:

```swift
struct IOSWishlistPage: View {
    var body: some View {
        ContentUnavailableView("Coming Soon", systemImage: "heart.text.clipboard", description: Text("Wishlist will be available in a future update."))
            .navigationTitle("Wishlist")
    }
}
```

## Important Notes

- Do NOT change module IDs — other code references them (e.g., `"dashboard"`, `"parts"`)
- Do NOT change tab IDs — TabBarPreferences stores user preferences using these
- Only change: order in the array, label text, tab membership between modules
- The People router (`PeopleRouter.swift`) needs to handle the new paths for employees/hats/permissions
- The Office router (`OfficeRouter.swift`) needs to REMOVE employees/hats/permissions paths
- Keep ALL existing permissions on tabs — don't change permission strings

## Success Criteria

- [ ] Modules in correct order: Dashboard, Jobs, Chat, Scheduling, Warehouse, Orders, Fleet, Tools, Notebooks, Parts, People, Office, Settings
- [ ] Orders tabs reordered: Job Orders first, Wishlist last
- [ ] Tools tabs reordered: Dashboard first, Admin last
- [ ] Warehouse tabs reordered + Receiving renamed to Sorting
- [ ] People module has Employees, Hats, Permissions (moved from Office)
- [ ] Office module no longer has Employees, Hats, Permissions
- [ ] "Requests" → "Job Orders", "Registry" → "All Tools", "Deletion Approvals" → "Deletions"
- [ ] All routes work — no broken navigation
- [ ] Wishlist placeholder page created
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 32A Results (YYYY-MM-DD)
- Reordered 13 modules in sidebar (daily use → work tools → management)
- Reordered tabs in Orders, Tools, Warehouse
- Moved Employees/Hats/Permissions from Office → People
- Renamed 4 tabs for clarity
- Created Wishlist placeholder page
- Updated People + Office routers
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding.**
