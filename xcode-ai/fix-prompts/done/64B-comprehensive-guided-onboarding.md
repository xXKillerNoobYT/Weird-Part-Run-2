# 64B — Comprehensive Per-Page Guided Onboarding

> **Chain position:** After 64A
> **Priority:** HIGH — the user wants every page covered with guided tasks
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

Build a comprehensive guided onboarding system that covers EVERY page in the app. The user must do at least ONE key action on each page before moving on, but can do as much as they want. The system remembers what they've already completed. Tasks are hat-aware — users only see tasks they have permission to do.

**Read these files first:**
- `Shared/PageHelpSheet.swift` — help content per page
- `Shared/HelpContentRegistry.swift` — registry of all help content
- `App/AppCore.swift` — for permissions and services
- `Navigation/NavigationConfig.swift` — all modules and tabs

## Architecture

### OnboardingProgressManager

Create `Shared/OnboardingProgressManager.swift`:

```swift
import SwiftUI
import WiredPartCore

/// Tracks guided onboarding progress per-page, per-user.
/// Stores completion state in UserDefaults keyed by userId.
@MainActor
class OnboardingProgressManager: ObservableObject {
    @Published var completedTasks: Set<String> = []
    @Published var currentModule: String?
    @Published var isOnboardingActive = false

    private let userId: Int64
    private let storageKey: String

    init(userId: Int64) {
        self.userId = userId
        self.storageKey = "onboarding_progress_\(userId)"
        loadProgress()
    }

    func markCompleted(_ taskId: String) {
        completedTasks.insert(taskId)
        saveProgress()
    }

    func isCompleted(_ taskId: String) -> Bool {
        completedTasks.contains(taskId)
    }

    func resetProgress() {
        completedTasks.removeAll()
        saveProgress()
    }

    /// Returns tasks for a page filtered by user's hat permissions.
    func tasksForPage(_ pageId: String, permissions: [String]) -> [OnboardingTask] {
        allTasks[pageId]?.filter { task in
            task.requiredPermission == nil || permissions.contains(task.requiredPermission!)
        } ?? []
    }

    /// Returns the count of completed vs total for a module.
    func moduleProgress(_ moduleId: String, permissions: [String]) -> (completed: Int, total: Int) {
        let moduleTasks = allTasks.filter { $0.key.hasPrefix(moduleId) }
        let available = moduleTasks.values.flatMap { $0 }.filter { task in
            task.requiredPermission == nil || permissions.contains(task.requiredPermission!)
        }
        let done = available.filter { completedTasks.contains($0.id) }
        return (done.count, available.count)
    }

    private func loadProgress() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            completedTasks = saved
        }
    }

    private func saveProgress() {
        if let data = try? JSONEncoder().encode(completedTasks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

struct OnboardingTask: Identifiable {
    let id: String           // "dashboard-clock-in"
    let title: String        // "Clock In to a Job"
    let description: String  // "Try clocking in to any active job..."
    let requiredPermission: String?  // nil = everyone, "manage_jobs" = hat-gated
    let isRequired: Bool     // true = must do this, false = optional bonus
}
```

### Per-Page Task Definitions

Create `Shared/OnboardingTasks.swift` with ALL tasks organized by page:

```swift
/// All onboarding tasks organized by page ID.
let allTasks: [String: [OnboardingTask]] = [

    // MARK: - Dashboard
    "dashboard-overview": [
        OnboardingTask(id: "dashboard-view-kpis", title: "View Your Dashboard", description: "Look at the KPI cards showing your business overview.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "dashboard-tap-kpi", title: "Tap a KPI Card", description: "Tap any KPI card to see detailed information.", requiredPermission: nil, isRequired: false),
    ],
    "dashboard-clock": [
        OnboardingTask(id: "clock-in", title: "Clock In", description: "Clock in to the Shop or any active job to start tracking your time.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "clock-out", title: "Clock Out", description: "Clock out when you're done. Answer the questionnaire.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "clock-break", title: "Take a Break", description: "Try the Break or Lunch button to see how break tracking works.", requiredPermission: nil, isRequired: false),
    ],
    "dashboard-daily-report": [
        OnboardingTask(id: "daily-report-view", title: "View a Daily Report", description: "See how the system auto-generates daily reports from clock and to-do data.", requiredPermission: nil, isRequired: true),
    ],
    "dashboard-scanner": [
        OnboardingTask(id: "scanner-open", title: "Open the QR Scanner", description: "Try scanning a QR code or typing a tool/part ID.", requiredPermission: nil, isRequired: false),
    ],

    // MARK: - Jobs
    "jobs-list": [
        OnboardingTask(id: "jobs-view-list", title: "Browse Jobs", description: "See all active and completed jobs. Tap the status cards to filter.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "jobs-create", title: "Create a Job", description: "Tap + to create a new job with name, customer, and priority.", requiredPermission: "manage_jobs", isRequired: true),
        OnboardingTask(id: "jobs-tap-detail", title: "View Job Detail", description: "Tap any job to see its full dashboard with hours, budget, and team.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Chat
    "chat-channels": [
        OnboardingTask(id: "chat-view-channels", title: "View Channels", description: "See all your message channels — job chats, DMs, Q&A, and supplier messages.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "chat-send-message", title: "Send a Message", description: "Open any channel and send a test message.", requiredPermission: nil, isRequired: false),
    ],

    // MARK: - Parts
    "parts-catalog": [
        OnboardingTask(id: "catalog-search", title: "Search for a Part", description: "Type a part name in the search bar. Try natural language like 'red copper fittings'.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "catalog-filter", title: "Use Filters", description: "Tap the filter chips to narrow by category, brand, or type.", requiredPermission: nil, isRequired: false),
        OnboardingTask(id: "catalog-detail", title: "View Part Detail", description: "Tap a part to see its full info — stock, pricing, history, location.", requiredPermission: nil, isRequired: true),
    ],
    "parts-categories": [
        OnboardingTask(id: "categories-browse", title: "Browse the Hierarchy", description: "Expand the tree to see Category → Style → Type → Brand → Color.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "categories-add", title: "Add a Category", description: "Tap + to add a new category to the hierarchy.", requiredPermission: "manage_parts", isRequired: false),
    ],
    "parts-brands": [
        OnboardingTask(id: "brands-view", title: "View Brands", description: "See all brands and their linked suppliers.", requiredPermission: nil, isRequired: true),
    ],
    "parts-suppliers": [
        OnboardingTask(id: "suppliers-view", title: "View Suppliers", description: "See supplier scores and contact info.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "suppliers-sort", title: "Sort Suppliers", description: "Try sorting by quality, on-time, or reliability score.", requiredPermission: nil, isRequired: false),
    ],
    "parts-pricing": [
        OnboardingTask(id: "pricing-view", title: "View Pricing Tiers", description: "See how pricing cascades from category to individual part.", requiredPermission: "view_pricing", isRequired: true),
    ],
    "parts-companions": [
        OnboardingTask(id: "companions-view", title: "View Companion Rules", description: "See which parts are commonly used together.", requiredPermission: nil, isRequired: true),
    ],
    "parts-forecasting": [
        OnboardingTask(id: "forecast-view", title: "Check Forecasts", description: "See which parts are running low and what the system recommends.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "forecast-recalculate", title: "Run a Recalculation", description: "Tap the recalculate button to update all forecasts.", requiredPermission: "manage_parts", isRequired: false),
    ],
    "parts-import": [
        OnboardingTask(id: "import-view", title: "View Import/Export", description: "See how to import parts from CSV or export your catalog.", requiredPermission: "manage_parts", isRequired: false),
    ],

    // MARK: - Warehouse
    "warehouse-dashboard": [
        OnboardingTask(id: "wh-dashboard-view", title: "View Warehouse Dashboard", description: "See today's movements, receiving activity, and audit status.", requiredPermission: nil, isRequired: true),
    ],
    "warehouse-movements": [
        OnboardingTask(id: "wh-movements-view", title: "View Movements", description: "See recent stock movements — transfers, receives, returns.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "wh-movement-start", title: "Start a Movement", description: "Tap + to start the Movement Wizard and move stock between locations.", requiredPermission: "manage_warehouse", isRequired: false),
    ],
    "warehouse-locations": [
        OnboardingTask(id: "wh-locations-view", title: "View Floor Plan", description: "See the warehouse layout with shelves, pipe racks, and storage units.", requiredPermission: nil, isRequired: true),
    ],
    "warehouse-staging": [
        OnboardingTask(id: "wh-staging-view", title: "View Staging Area", description: "See parts staged for jobs, organized into boxes.", requiredPermission: nil, isRequired: true),
    ],
    "warehouse-receiving": [
        OnboardingTask(id: "wh-receiving-view", title: "View Receiving", description: "See incoming shipments and start receiving sessions.", requiredPermission: nil, isRequired: true),
    ],
    "warehouse-audit": [
        OnboardingTask(id: "wh-audit-view", title: "View Audit Queue", description: "See which parts need counting based on confidence levels.", requiredPermission: nil, isRequired: true),
    ],
    "warehouse-inventory": [
        OnboardingTask(id: "wh-inventory-view", title: "Browse Inventory", description: "See all parts with stock levels at your location.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Orders
    "orders-pos": [
        OnboardingTask(id: "po-view-list", title: "View Purchase Orders", description: "See all POs — draft, ordered, partial, received.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "po-create", title: "Create a PO", description: "Tap + to start a new purchase order for a supplier.", requiredPermission: "manage_orders", isRequired: false),
    ],
    "orders-jpos": [
        OnboardingTask(id: "jpo-view-list", title: "View Job Orders", description: "See parts orders from job crews.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "jpo-create", title: "Create a JPO", description: "Use the cart builder to order parts for a job.", requiredPermission: nil, isRequired: true),
    ],
    "orders-procurement": [
        OnboardingTask(id: "procurement-view", title: "View Procurement", description: "See consolidated demand from JPOs, wishlist, and forecasts.", requiredPermission: "manage_orders", isRequired: true),
    ],

    // MARK: - Fleet
    "fleet-dashboard": [
        OnboardingTask(id: "fleet-dashboard-view", title: "View Fleet Dashboard", description: "See vehicle status, fuel costs, and maintenance due.", requiredPermission: nil, isRequired: true),
    ],
    "fleet-vehicles": [
        OnboardingTask(id: "fleet-vehicles-view", title: "View Vehicles", description: "See all company vehicles with status and assignments.", requiredPermission: nil, isRequired: true),
    ],
    "fleet-my-vehicle": [
        OnboardingTask(id: "fleet-my-truck", title: "View Your Vehicle", description: "See your assigned truck, parts, tools, and recent logs.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Scheduling
    "scheduling-calendar": [
        OnboardingTask(id: "schedule-view", title: "View Calendar", description: "See the week/month schedule with job assignments.", requiredPermission: nil, isRequired: true),
    ],
    "scheduling-dispatch": [
        OnboardingTask(id: "dispatch-view", title: "View Dispatch Board", description: "See who's assigned where today. Drag workers onto jobs.", requiredPermission: "manage_scheduling", isRequired: true),
    ],
    "scheduling-time-off": [
        OnboardingTask(id: "timeoff-view", title: "View Time Off", description: "See time-off requests and their approval status.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Tools
    "tools-dashboard": [
        OnboardingTask(id: "tools-dashboard-view", title: "View Tools Dashboard", description: "See checked-out tools, maintenance due, and quick actions.", requiredPermission: nil, isRequired: true),
    ],
    "tools-registry": [
        OnboardingTask(id: "tools-browse", title: "Browse Tools", description: "See all company tools with status and location.", requiredPermission: nil, isRequired: true),
    ],
    "tools-checkouts": [
        OnboardingTask(id: "tools-checkouts-view", title: "View Checkouts", description: "See who has what tools checked out.", requiredPermission: nil, isRequired: true),
    ],

    // MARK: - Notebooks
    "notebooks-list": [
        OnboardingTask(id: "notebooks-view", title: "View Notebooks", description: "See job notebooks, general notes, and daily reports.", requiredPermission: nil, isRequired: true),
        OnboardingTask(id: "notebooks-create", title: "Create a Notebook", description: "Tap + to create a new notebook for a job or general notes.", requiredPermission: nil, isRequired: false),
    ],

    // MARK: - People
    "people-employees": [
        OnboardingTask(id: "people-view", title: "View Employees", description: "See your team, their hats, and contact info.", requiredPermission: nil, isRequired: true),
    ],
    "people-customers": [
        OnboardingTask(id: "customers-view", title: "View Customers", description: "See customer list with job history.", requiredPermission: nil, isRequired: true),
    ],
    "people-hats": [
        OnboardingTask(id: "hats-view", title: "View Hats & Permissions", description: "See how permissions work — hats control who can do what.", requiredPermission: "manage_people", isRequired: false),
    ],

    // MARK: - Office
    "office-dashboard": [
        OnboardingTask(id: "office-view", title: "View Office Dashboard", description: "See the daily briefing, attention items, and financial snapshot.", requiredPermission: "manage_jobs", isRequired: true),
    ],
    "office-approvals": [
        OnboardingTask(id: "approvals-view", title: "View Approvals Queue", description: "See all pending approvals — JPOs, deletions, tool edits, time-off.", requiredPermission: "manage_jobs", isRequired: true),
    ],

    // MARK: - Settings
    "settings-themes": [
        OnboardingTask(id: "settings-theme", title: "Set Your Theme", description: "Choose light/dark mode and your preferred color.", requiredPermission: nil, isRequired: false),
    ],
    "settings-about": [
        OnboardingTask(id: "settings-about-view", title: "View App Info", description: "See version, database, and device info.", requiredPermission: nil, isRequired: false),
    ],
]
```

### Per-Page Onboarding Banner

Create `Shared/OnboardingBanner.swift`:

```swift
struct OnboardingBanner: View {
    let pageId: String
    @EnvironmentObject private var appCore: AppCore
    @EnvironmentObject private var onboardingManager: OnboardingProgressManager

    var body: some View {
        let permissions = appCore.permissions
        let tasks = onboardingManager.tasksForPage(pageId, permissions: permissions)
        let incomplete = tasks.filter { !onboardingManager.isCompleted($0.id) }

        if onboardingManager.isOnboardingActive && !incomplete.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "graduationcap.fill")
                        .foregroundStyle(.blue)
                    Text("Try This")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(tasks.count - incomplete.count)/\(tasks.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(incomplete) { task in
                    HStack(spacing: 8) {
                        Image(systemName: task.isRequired ? "circle" : "circle.dashed")
                            .font(.caption)
                            .foregroundStyle(task.isRequired ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.title)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(task.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Show completed tasks with checkmarks
                let completed = tasks.filter { onboardingManager.isCompleted($0.id) }
                if !completed.isEmpty {
                    ForEach(completed) { task in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(task.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .strikethrough()
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
        }
    }
}
```

### Wiring Into Pages

Every feature page adds the banner at the top of its content and calls `markCompleted` when the user performs the action:

```swift
// Example: IOSEmployeesPage
var body: some View {
    VStack(spacing: 0) {
        OnboardingBanner(pageId: "people-employees")
        // ... existing page content
    }
    .task {
        // Auto-complete "view" tasks when the page loads
        onboardingManager.markCompleted("people-view")
    }
}
```

For action tasks (create, edit, etc.), mark completed after the action succeeds:

```swift
// In createJob completion handler:
onboardingManager.markCompleted("jobs-create")
```

### Onboarding Progress Dashboard

Add an "Onboarding Progress" section to the Dashboard that shows module-by-module completion:

```swift
// In DashboardView, after the Getting Started checklist:
if onboardingManager.isOnboardingActive {
    Section("App Tour Progress") {
        ForEach(NavigationConfig.modules) { module in
            let progress = onboardingManager.moduleProgress(module.id, permissions: appCore.permissions)
            if progress.total > 0 {
                HStack {
                    Image(systemName: module.icon)
                        .frame(width: 24)
                    Text(module.label)
                        .font(.subheadline)
                    Spacer()
                    Text("\(progress.completed)/\(progress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                        .frame(width: 60)
                }
            }
        }
    }
}
```

### Start/Stop Onboarding

The onboarding tour can be started from:
1. The Getting Started checklist (new "Take the Full Tour" button)
2. Settings → About → "Restart App Tour"
3. Auto-starts for new non-admin users

```swift
// In Getting Started checklist:
Button {
    withAnimation { onboardingManager.isOnboardingActive = true }
} label: {
    Label("Take the Full App Tour", systemImage: "graduationcap.fill")
}
.buttonStyle(.borderedProminent)
```

## Important Notes

- Tasks are filtered by hat permissions — a worker won't see "Create a Job" if they don't have `manage_jobs`
- "View" tasks auto-complete when the page loads — the user just has to visit
- "Action" tasks require the user to actually do something (create, edit, search)
- Progress persists per-user via UserDefaults keyed by userId
- The tour is optional — can be started/stopped anytime
- Required tasks (isRequired: true) must be completed for the module to show as "done"
- Optional tasks (isRequired: false) are bonus — doing them is encouraged but not required
- The OnboardingBanner is small and non-intrusive — it sits at the top of the page content
- Completed tasks show with strikethrough + green checkmark (satisfying visual feedback)

## Success Criteria

- [ ] OnboardingProgressManager tracks per-user, per-task completion
- [ ] 40+ tasks defined across all major pages
- [ ] Tasks filtered by hat permissions
- [ ] OnboardingBanner shows on every page when tour is active
- [ ] "View" tasks auto-complete on page visit
- [ ] "Action" tasks complete when user performs the action
- [ ] Progress dashboard shows on Dashboard with per-module bars
- [ ] Tour can be started from Getting Started checklist
- [ ] Tour can be restarted from Settings → About
- [ ] Auto-starts for new non-admin users
- [ ] Project builds with zero errors

## Log Entry

```
## Prompt 64B Results (YYYY-MM-DD)
- OnboardingProgressManager: created
- Tasks defined: X across Y pages
- OnboardingBanner: added to X pages
- Progress dashboard: on Dashboard
- Build: PASS/FAIL
```
