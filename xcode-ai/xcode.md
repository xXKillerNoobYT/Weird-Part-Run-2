# WiredPart iOS — Xcode AI Instructions

> **READ THIS FILE** at the start of every conversation. It tells you what the project is, what patterns to follow, and what mistakes to avoid. This is your memory.

---

## What This App Is

**WiredPart** is a construction/trade business management app. It manages jobs, employees, parts inventory, warehouse operations, fleet, tools, orders, scheduling, reports, chat, and notebooks. It runs on iOS (iPhone + iPad) with a shared `core/` Swift package (`WiredPartCore`).

**Architecture:** SwiftUI views → `AppCore` (ObservableObject) → `WiredPartCore` services → GRDB/SQLite.

**Key files:**
- `App/AppCore.swift` — The central state holder. All services live here. Passed as `@EnvironmentObject`.
- `core/Sources/WiredPartCore/Services/` — 15 service files (AuthService, JobsService, PartsService, etc.)
- `core/Sources/WiredPartCore/Database/AppDatabase.swift` — GRDB database setup + migrations
- `Navigation/IOSMainView.swift` — Tab bar + sidebar navigation root

---

## Coding Standards

### 1. Error Handling — NEVER Swallow Errors

```swift
// BAD — user sees empty screen, no idea why
catch { print("[Page] Error: \(error)") }

// BAD — infinite spinner
guard let service = appCore.someService else { return }

// GOOD — show the error
catch {
    loadError = error.localizedDescription
    isLoading = false
}

// GOOD — clear loading if service missing
guard let service = appCore.someService else {
    isLoading = false
    loadError = "Service unavailable"
    return
}
```

### 2. Sheet/Popup Dismissal — THE #1 BUG SOURCE

SwiftUI rule: **Only ONE `.sheet` modifier per view hierarchy level.** Multiple `.sheet` on the same view = broken behavior.

```swift
// BAD — only the last .sheet works, others may not dismiss
SomeView()
    .sheet(isPresented: $showA) { ViewA() }
    .sheet(isPresented: $showB) { ViewB() }
    .sheet(isPresented: $showC) { ViewC() }

// GOOD — use a single .sheet with an enum
enum ActiveSheet: Identifiable {
    case addItem, editItem, settings
    var id: Self { self }
}
@State private var activeSheet: ActiveSheet?

SomeView()
    .sheet(item: $activeSheet) { sheet in
        switch sheet {
        case .addItem: AddItemView()
        case .editItem: EditItemView()
        case .settings: SettingsView()
        }
    }
```

**Always reload data when a sheet closes:**
```swift
.sheet(isPresented: $showForm) {
    FormView(onSave: { loadData() })
}
// OR
.onChange(of: showForm) { _, isShowing in
    if !isShowing { loadData() }
}
```

### 3. UI States — Every Page Needs Three States

Every data-loading view MUST handle: loading, error, AND empty.

```swift
if isLoading {
    ProgressView()
} else if let error = loadError {
    ErrorStateView(message: error) { loadData() }
} else if items.isEmpty {
    EmptyStateView(title: "No Items", message: "Tap + to add one", icon: "plus.circle")
} else {
    // actual content
}
```

### 4. No Placeholder / Stub Text

Never leave user-visible text like:
- "Will be implemented in Phase X"
- "Content will be loaded from..."
- "TODO" / "Coming Soon" (unless gated behind a feature flag)

If a feature isn't built yet, show `EmptyStateView` with a clear message like "This feature requires sync to be configured."

### 5. Concurrency

- Use `Task { @MainActor in }` — never `DispatchQueue.main.asyncAfter` for async work
- Mark view models and ObservableObjects with `@MainActor`
- Never use `fatalError()` in production paths — throw errors instead
- Guard against concurrent continuation use in delegate callbacks

### 6. CRUD — Every List Needs Actions

If a user can see a list of things, they need to be able to:
- **Add** new items (toolbar + button)
- **Edit** existing items (tap row → detail → edit button)
- **Delete** items (swipe-to-delete with confirmation dialog)

### 7. Data Reload Pattern

```swift
.onAppear { loadData() }
.refreshable { await loadDataAsync() }
```

### 8. Service Access Pattern

```swift
// All services accessed through AppCore environment object
@EnvironmentObject private var appCore: AppCore

// Safe access:
guard let service = appCore.jobsService else {
    isLoading = false
    loadError = "Jobs service unavailable"
    return
}
let jobs = try service.listJobs()
```

---

## Known Issues (From Audit)

1. **IOSSyncManager** — completely stubbed. `syncNow()` and `startPeerDiscovery()` are fake sleeps.
2. **SyncWaitingView** — shows fake progress animation. No real sync occurs.
3. **AppCore** — `db!`, `authService!`, `settingsService!` are IUOs. Should be safe optionals.
4. **Multiple pages** suppress "no such table" errors silently.
5. **~30 pages** are read-only where users expect CRUD actions.
6. **CategoriesEditorPanel** has 7 `.sheet` modifiers on one view — popup conflicts.
7. **IOSMainView** has multiple `.sheet` modifiers — potential dismiss conflicts.
8. **~15 pages** have `guard let service else { return }` without clearing `isLoading`.

---

## Skill Files

- When working on **data model or service code**, read `xcode-ai/skills/data-layer.md`
- When working on **UI views**, read `xcode-ai/skills/ui-patterns.md`
- When working on **sheets/popups**, pay extra attention to the sheet dismissal rules above

---

## File Structure

```
Weird Parts IOS/
├── App/              ← AppCore, entry point, location manager
├── Auth/             ← Login, onboarding, device pairing, sync waiting
├── Navigation/       ← Tab bar, routing, content router, user menu
├── Features/
│   ├── Dashboard/    ← Main dashboard, KPIs, QR scanner
│   ├── Jobs/         ← Job list, detail, clock, labor, reports
│   ├── Parts/        ← Catalog, categories, brands, suppliers, pricing
│   ├── Warehouse/    ← Inventory, movements, receiving, audit, staging
│   ├── Orders/       ← JPOs, POs, procurement, returns, unified order form
│   ├── Fleet/        ← Vehicles, trailers, fuel, mileage, maintenance
│   ├── People/       ← Employees, customers, contractors, contacts, teams
│   ├── Scheduling/   ← Dispatch, calendar, time off, templates
│   ├── Notebooks/    ← Job notebooks, templates, general notebooks
│   ├── Chat/         ← Channels, messages, Q&A, RFI
│   ├── Tools/        ← Registry, kits, checkouts, maintenance
│   ├── Reports/      ← Timesheets, labor, spending, pre-billing, exports
│   ├── Office/       ← Manage jobs, warehouse exec, spending dashboard
│   └── Settings/     ← 25+ settings pages
├── DesignSystem/     ← Tokens, styles, reusable components
├── Shared/           ← EmptyState, ErrorState, FormSheet, SearchableList
├── Scanning/         ← QR, OCR, document scan, camera match
├── Sync/             ← SyncManager, peer browser, status view
├── AI/               ← AI assistant panel, text editor, availability
└── WebFallback/      ← Fallback web view
```
