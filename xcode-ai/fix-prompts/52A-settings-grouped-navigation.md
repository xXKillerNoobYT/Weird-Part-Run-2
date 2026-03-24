# Prompt 52A — Settings Grouped Navigation

> **Area:** Settings
> **Dependencies:** None
> **What the user sees:** Settings is a flat list of 23+ pages. Hard to find anything.
> **What this fixes:** Reorganize into 10 grouped sections with search.

---

## Task

Reorganize `SettingsRouter` into 10 grouped sections with iOS Settings-style navigation and a search bar at the top.

## Groups (in order)

1. **General** (icon: gear) — About, Themes, Notifications, App Config
2. **Company** (icon: building.2) — Company Profiles, Billing/Pay, PDF Settings, Payment Tracking
3. **Operations** (icon: wrench.and.screwdriver) — Break/Lunch Policy, Tool Policies, Pre-Trip Checklists, Dispatch Preferences
4. **Warehouse** (icon: shippingbox) — Forecast Config, Organization Thresholds, Audit Settings
5. **Sync & Devices** (icon: arrow.triangle.2.circlepath) — Sync, Bluetooth, Device Management, Bootstrap
6. **Security** (icon: lock.shield) — Security Admin, Key Management, Audit Log
7. **Data** (icon: externaldrive) — Backups, Export, Database Reset
8. **AI & Integrations** (icon: cpu) — AI Config, Integrations, Supplier Bridge
9. **Templates** (icon: doc.text) — Daily Reports, Job Estimation Questions, Report Templates, Clock-Out Questions
10. **Advanced** (icon: gearshape.2) — Update Protocol, Remote Sync, Shared Channels

## Search

- Add `@State private var searchText = ""` and `.searchable(text: $searchText, prompt: "Search Settings")`
- Each `NavigationLink` has searchable keywords: page name + key setting labels
- Example: Bluetooth page keywords: "bluetooth", "pairing", "devices", "wireless"
- Example: Backups page keywords: "backup", "restore", "database", "export"
- When `searchText` is not empty, show flat filtered list (ignore groups)
- When `searchText` is empty, show grouped sections

## Group Headers

Each section uses `Section { } header: { Label("Group Name", systemImage: "icon.name") }` with the SF Symbol icons listed above.

## Existing Pages

All existing pages stay exactly where they are — just reorganized into groups. No page content changes in this prompt.

## New Routes

Add route cases for new pages that don't exist yet (they'll be stubs for now, created in later prompts):
- `.breakLunchPolicy`
- `.toolPolicies`
- `.preTripChecklists`
- `.dispatchPreferences`
- `.forecastConfig`
- `.organizationThresholds`
- `.auditSettings`
- `.dailyReportTemplates`
- `.jobEstimationQuestions`
- `.reportTemplates`
- `.paymentTracking`

Each stub page: `ContentUnavailableView("Coming Soon", systemImage: "wrench", description: Text("This page is being built."))`

## Build target

iOS only. Must compile. Start prompt 52B next.
