# 65A — Guided Onboarding Walkthrough (Every Page)

> **Chain position:** After 64C (Tier 8)
> **Priority:** HIGH — first impression for every new user
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

Create a comprehensive guided onboarding system that covers EVERY page in the app. When a new user logs in for the first time (or when `@AppStorage("hasCompletedOnboarding")` is false), walk them through the entire application module-by-module.

**Read these files first:**
- `Auth/OnboardingCompleteView.swift` — existing completion screen
- `Auth/OnboardingWelcomeView.swift` — existing welcome screen
- `Shared/OnboardingProgressManager.swift` — existing progress tracker (from 64B)
- `Shared/OnboardingTasks.swift` — existing task definitions (from 64B)
- `Shared/OnboardingBanner.swift` — existing per-page banner (from 64B)
- `Navigation/NavigationConfig.swift` — all modules and tabs
- `App/AppCore.swift` — permissions and user hat
- `Features/Dashboard/DashboardView.swift` — Getting Started checklist

## Architecture

### New Files

1. **`Auth/OnboardingWalkthroughView.swift`** — full-screen guided walkthrough (the main new view)
2. **`Shared/OnboardingProgress.swift`** — persistent state tracker for the walkthrough specifically (separate from the per-page OnboardingProgressManager)

### Walkthrough Flow

When `@AppStorage("hasCompletedOnboarding")` is false AND the user has logged in:

1. **Welcome Screen** — "Welcome to WiredPart" with app description, user's name, company name, "Let's Get Started" button
2. **Module Steps** — one step per module the user has permission to access (filtered by hat)
3. **Completion Screen** — summary of what they learned, links to skipped modules, "Go to Dashboard" button

### Step Structure

Each step in the walkthrough has:
- **Title** (e.g., "Step 3 of 12 — Parts Catalog")
- **Progress bar** at the top showing overall progress
- **Module icon** (large, colored)
- **Description** — 2-3 sentences explaining what this module does and when to use it
- **Key Buttons** — highlight 2-3 important buttons/actions with icon + label + explanation
- **Required Action** — ONE thing the user must do (or skip). Examples:
  - Dashboard: "Tap a KPI card to see details"
  - Clock: "View the job list to see available jobs"
  - Parts: "Search for any part using the search bar"
  - Warehouse: "View a warehouse location"
- **"I Did It" button** — marks the action as completed
- **"Skip" button** — moves to next step, marks this one as skipped
- **"Back" button** — go to previous step

### Module Order (filtered by hat permissions)

```swift
struct OnboardingModule: Identifiable {
    let id: String
    let title: String
    let icon: String
    let iconColor: Color
    let description: String
    let keyFeatures: [(icon: String, label: String, detail: String)]
    let requiredAction: String
    let actionHint: String   // What to do to complete
    let requiredPermission: String?  // nil = everyone sees this
}

let onboardingModules: [OnboardingModule] = [
    OnboardingModule(
        id: "dashboard",
        title: "Dashboard",
        icon: "house.fill",
        iconColor: .blue,
        description: "Your daily command center. See business KPIs, clock in/out, scan QR codes, and review your Getting Started checklist.",
        keyFeatures: [
            ("chart.bar.fill", "KPI Cards", "Tap any card to drill into detailed metrics"),
            ("qrcode.viewfinder", "QR Scanner", "Scan parts, tools, or PO barcodes instantly"),
            ("checklist", "Getting Started", "Track your company setup progress"),
        ],
        requiredAction: "Tap any KPI card to see the detail sheet",
        actionHint: "Find a card like 'Active Jobs' or 'Open POs' and tap it",
        requiredPermission: nil
    ),
    OnboardingModule(
        id: "clock",
        title: "Clock In/Out",
        icon: "clock.fill",
        iconColor: .green,
        description: "Track your work hours. Clock in to the shop or a specific job. The system tracks GPS location and supports breaks and lunches.",
        keyFeatures: [
            ("play.circle.fill", "Clock In", "Start tracking time on a job or at the shop"),
            ("pause.circle.fill", "Break/Lunch", "Tracks break compliance with state rules"),
            ("doc.text.fill", "Daily Summary", "Auto-generated report of your day"),
        ],
        requiredAction: "View the job list to see available clock-in targets",
        actionHint: "Scroll through the list of active jobs",
        requiredPermission: nil
    ),
    OnboardingModule(
        id: "jobs",
        title: "Jobs",
        icon: "briefcase.fill",
        iconColor: .orange,
        description: "Every project your company works on. Browse active jobs, see details like budget, hours, team, and to-dos. Managers can create and manage jobs.",
        keyFeatures: [
            ("list.bullet", "Job List", "Filter by status — active, scheduled, completed"),
            ("doc.text.magnifyingglass", "Job Detail", "Full dashboard with hours, budget, team, and daily reports"),
            ("checklist.checked", "Questionnaire", "End-of-day questions track job progress"),
        ],
        requiredAction: "Tap any job to view its detail page",
        actionHint: "Pick any job from the list and tap it",
        requiredPermission: nil
    ),
    OnboardingModule(
        id: "chat",
        title: "Chat & Messages",
        icon: "bubble.left.and.bubble.right.fill",
        iconColor: .purple,
        description: "Per-job group chat, direct messages, Q&A escalation, and RFI threads. Stay in sync with your team without leaving the app.",
        keyFeatures: [
            ("bubble.left.fill", "Channels", "Job chats, DMs, Q&A, supplier messages"),
            ("exclamationmark.bubble.fill", "Escalation", "Questions auto-escalate if unanswered"),
            ("paperclip", "Attachments", "Share photos, PDFs, and files in any channel"),
        ],
        requiredAction: "View the channels list to see message types",
        actionHint: "Open the Chat tab and browse the channel list",
        requiredPermission: nil
    ),
    OnboardingModule(
        id: "parts",
        title: "Parts Catalog",
        icon: "shippingbox.fill",
        iconColor: .teal,
        description: "Your complete parts inventory. Search by name, category, or brand. View stock levels, pricing, and history. The hierarchy is Category → Style → Type → Brand → Color.",
        keyFeatures: [
            ("magnifyingglass", "Smart Search", "Natural language — try 'red copper fittings'"),
            ("tag.fill", "Categories", "5-level hierarchy organizes everything"),
            ("chart.line.uptrend.xyaxis", "Forecasting", "AI predicts when to reorder"),
        ],
        requiredAction: "Search for any part in the catalog",
        actionHint: "Type a part name or category in the search bar",
        requiredPermission: nil
    ),
    OnboardingModule(
        id: "warehouse",
        title: "Warehouse",
        icon: "building.2.fill",
        iconColor: .indigo,
        description: "Know where every part is physically located. View the floor plan, track movements, run audits, and manage receiving.",
        keyFeatures: [
            ("map.fill", "Floor Plan", "Visual layout of shelves, racks, and storage"),
            ("arrow.left.arrow.right", "Movements", "Track every part transfer"),
            ("checkmark.shield.fill", "Audits", "Count verification with hidden system counts"),
        ],
        requiredAction: "View the warehouse dashboard or a location",
        actionHint: "Open any tab in the Warehouse section",
        requiredPermission: nil
    ),
    OnboardingModule(
        id: "orders",
        title: "Orders & Procurement",
        icon: "cart.fill",
        iconColor: .pink,
        description: "Two-stage ordering: crews create Job Parts Orders (JPOs), office converts them to Purchase Orders (POs) for suppliers. Track from request to delivery.",
        keyFeatures: [
            ("doc.badge.plus", "JPOs", "Field crews request parts for their jobs"),
            ("doc.text.fill", "POs", "Office sends orders to suppliers"),
            ("tray.full.fill", "Procurement", "Consolidated demand planner"),
        ],
        requiredAction: "View the orders list to understand the JPO → PO flow",
        actionHint: "Browse the Job Orders or Purchase Orders tab",
        requiredPermission: nil
    ),
    OnboardingModule(
        id: "fleet",
        title: "Fleet & Vehicles",
        icon: "truck.box.fill",
        iconColor: .red,
        description: "Track company vehicles, fuel, mileage, maintenance, and inspections. Each driver has a 'My Truck' view with their assigned vehicle.",
        keyFeatures: [
            ("truck.box.fill", "My Truck", "Your assigned vehicle, parts, and tools"),
            ("fuelpump.fill", "Fuel Logs", "Track fuel purchases and costs"),
            ("wrench.fill", "Maintenance", "Scheduled and unscheduled maintenance tracking"),
        ],
        requiredAction: "View the vehicles list",
        actionHint: "Open the Fleet tab and browse vehicles",
        requiredPermission: nil
    ),
    OnboardingModule(
        id: "tools",
        title: "Tools & Equipment",
        icon: "wrench.and.screwdriver.fill",
        iconColor: .yellow,
        description: "Track every tool and kit. Checkout, return, and trade tools between workers. Maintenance schedules keep tools in working order.",
        keyFeatures: [
            ("qrcode.viewfinder", "QR Lookup", "Scan any tool's QR code for instant info"),
            ("arrow.triangle.swap", "Checkout/Return", "Know who has what"),
            ("bag.fill", "Kits", "Group tools into kits with checklists"),
        ],
        requiredAction: "Browse the tool registry",
        actionHint: "Open the Tools tab and scroll through available tools",
        requiredPermission: nil
    ),
    OnboardingModule(
        id: "notebooks",
        title: "Notebooks",
        icon: "book.fill",
        iconColor: .brown,
        description: "Job notebooks for field notes, general notebooks for anything else. To-do stages track work items through completion. Templates standardize common entries.",
        keyFeatures: [
            ("doc.text.fill", "Job Notebooks", "Attached to specific jobs"),
            ("checklist", "To-Do Stages", "Track items from new → in-progress → done"),
            ("doc.on.clipboard", "Templates", "Standardize daily reports and field notes"),
        ],
        requiredAction: "View the notebooks list to understand the structure",
        actionHint: "Open the Notebooks tab and browse existing notebooks",
        requiredPermission: nil
    ),
    OnboardingModule(
        id: "scheduling",
        title: "Scheduling & Dispatch",
        icon: "calendar",
        iconColor: .cyan,
        description: "Schedule crews to jobs. The dispatch board shows who's working where. The pipeline tracks upcoming work. AI suggests optimal assignments.",
        keyFeatures: [
            ("calendar.badge.clock", "Calendar", "Month view with day details"),
            ("person.3.sequence.fill", "Dispatch", "Assign workers to jobs"),
            ("chart.bar.doc.horizontal", "Pipeline", "Short and long-term work queue"),
        ],
        requiredAction: "View the schedule calendar",
        actionHint: "Open the Scheduling tab and look at the calendar view",
        requiredPermission: nil
    ),
    OnboardingModule(
        id: "people",
        title: "People & Teams",
        icon: "person.3.fill",
        iconColor: .mint,
        description: "Manage employees, customers, contractors, and contacts. Hats control permissions — what each person can see and do in the app.",
        keyFeatures: [
            ("person.crop.circle.badge.checkmark", "Employees", "Your team with hats and skills"),
            ("building.2.crop.circle.fill", "Customers", "Job history and billing info"),
            ("person.text.rectangle", "Hats", "Permission groups control access"),
        ],
        requiredAction: "View the employees list",
        actionHint: "Open the People tab and browse employees",
        requiredPermission: "manage_people"
    ),
    OnboardingModule(
        id: "office",
        title: "Office & Approvals",
        icon: "building.columns.fill",
        iconColor: .gray,
        description: "The manager's hub. Daily AI briefing, approval queue for JPOs and requests, financial overview, and manage jobs settings.",
        keyFeatures: [
            ("checkmark.seal.fill", "Approvals", "JPO, deletion, tool edit, time-off approvals"),
            ("chart.pie.fill", "Financials", "Spending dashboard and budget tracking"),
            ("doc.richtext", "Reports", "Pre-billing, timesheets, profitability"),
        ],
        requiredAction: "View the approvals queue",
        actionHint: "Open the Office tab and check the Approvals page",
        requiredPermission: "manage_jobs"
    ),
    OnboardingModule(
        id: "reports",
        title: "Reports & Analytics",
        icon: "chart.bar.xaxis",
        iconColor: .orange,
        description: "Labor reports, financial summaries, fleet analytics, warehouse metrics, and scheduling efficiency. Export to PDF or CSV.",
        keyFeatures: [
            ("doc.text.fill", "Timesheets", "Employee hours by job and period"),
            ("dollarsign.circle.fill", "Pre-Billing", "Job cost summaries for invoicing"),
            ("square.and.arrow.up", "Export", "PDF and CSV export on every report"),
        ],
        requiredAction: "Browse the report categories",
        actionHint: "Open the Reports tab and see the available report types",
        requiredPermission: "manage_jobs"
    ),
    OnboardingModule(
        id: "settings",
        title: "Settings",
        icon: "gearshape.fill",
        iconColor: .gray,
        description: "Customize your experience. Theme, notifications, data storage, break/lunch policies, and company configuration.",
        keyFeatures: [
            ("paintbrush.fill", "Theme", "Light/dark mode and accent color"),
            ("bell.fill", "Notifications", "Control what alerts you receive"),
            ("externaldrive.fill", "Data Storage", "Database location and backups"),
        ],
        requiredAction: "View the theme settings",
        actionHint: "Open Settings and check the Appearance section",
        requiredPermission: nil
    ),
]
```

### OnboardingWalkthroughView.swift

Create `Auth/OnboardingWalkthroughView.swift`:

```swift
import SwiftUI
import WiredPartCore

struct OnboardingWalkthroughView: View {
    @EnvironmentObject private var appCore: AppCore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0
    @State private var showWelcome = true
    @State private var showCompletion = false
    @State private var completedModules: Set<String> = []
    @State private var skippedModules: Set<String> = []

    /// Modules filtered by user's hat permissions
    private var availableModules: [OnboardingModule] {
        let permissions = appCore.permissions
        return onboardingModules.filter { module in
            module.requiredPermission == nil ||
            permissions.contains(module.requiredPermission!)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if showWelcome {
                    welcomeScreen
                        .transition(.opacity)
                } else if showCompletion {
                    completionScreen
                        .transition(.move(edge: .trailing))
                } else {
                    stepView
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            .animation(.easeInOut(duration: 0.3), value: showWelcome)
            .animation(.easeInOut(duration: 0.3), value: showCompletion)
        }
        .onAppear { loadProgress() }
    }

    // MARK: - Welcome Screen

    private var welcomeScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Welcome to WiredPart")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if let user = appCore.currentUser {
                    Text("Hi \(user.displayName)!")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text("Let's walk through the app together so you know where everything is. This takes about 5 minutes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            VStack(spacing: 4) {
                Text("\(availableModules.count) modules")
                    .font(.headline)
                Text("based on your permissions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()

            Button {
                withAnimation { showWelcome = false }
            } label: {
                Text("Let's Get Started")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Skip Onboarding") {
                hasCompletedOnboarding = true
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer().frame(height: 40)
        }
    }

    // MARK: - Step View

    private var stepView: some View {
        let module = availableModules[safe: currentStep]

        return VStack(spacing: 0) {
            // Progress bar
            VStack(spacing: 4) {
                ProgressView(value: Double(currentStep + 1), total: Double(availableModules.count))
                    .tint(.blue)
                Text("Step \(currentStep + 1) of \(availableModules.count) — \(module?.title ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            if let module = module {
                ScrollView {
                    VStack(spacing: 24) {
                        // Module icon + title
                        VStack(spacing: 12) {
                            Image(systemName: module.icon)
                                .font(.system(size: 56))
                                .foregroundStyle(module.iconColor)

                            Text(module.title)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(module.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        // Key features
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Key Features")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(module.keyFeatures, id: \.label) { feature in
                                HStack(spacing: 12) {
                                    Image(systemName: feature.icon)
                                        .font(.title3)
                                        .foregroundStyle(module.iconColor)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(feature.label)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text(feature.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }

                        // Required action
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: completedModules.contains(module.id)
                                      ? "checkmark.circle.fill" : "target")
                                    .foregroundStyle(completedModules.contains(module.id) ? .green : .orange)
                                Text("Try This:")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }

                            Text(module.requiredAction)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)

                            Text(module.actionHint)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .italic()
                        }
                        .padding()
                        .background(
                            completedModules.contains(module.id)
                            ? Color.green.opacity(0.1)
                            : Color.orange.opacity(0.1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 24)
                }

                // Action buttons
                VStack(spacing: 12) {
                    if !completedModules.contains(module.id) {
                        Button {
                            completedModules.insert(module.id)
                            saveProgress()
                        } label: {
                            Label("I Did It!", systemImage: "checkmark.circle.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    HStack(spacing: 16) {
                        if currentStep > 0 {
                            Button {
                                withAnimation { currentStep -= 1 }
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()

                        if !completedModules.contains(module.id) {
                            Button("Skip") {
                                skippedModules.insert(module.id)
                                saveProgress()
                                advanceStep()
                            }
                            .foregroundStyle(.secondary)
                        }

                        Button {
                            advanceStep()
                        } label: {
                            Label("Next", systemImage: "chevron.right")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!completedModules.contains(module.id) && !skippedModules.contains(module.id))
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Completion Screen

    private var completionScreen: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 40)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)

                Text("You're All Set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("You've completed the WiredPart walkthrough.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Summary
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(completedModules.count) modules completed")
                            .font(.subheadline)
                    }
                    if !skippedModules.isEmpty {
                        HStack {
                            Image(systemName: "forward.fill")
                                .foregroundStyle(.orange)
                            Text("\(skippedModules.count) modules skipped")
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Skipped modules reminder
                if !skippedModules.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Skipped Modules")
                            .font(.headline)
                        Text("Tap the ? button on any page for help when you visit these later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(availableModules.filter { skippedModules.contains($0.id) }) { module in
                            HStack(spacing: 8) {
                                Image(systemName: module.icon)
                                    .foregroundStyle(module.iconColor)
                                    .frame(width: 24)
                                Text(module.title)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer().frame(height: 20)

                Button {
                    hasCompletedOnboarding = true
                } label: {
                    Text("Go to Dashboard")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Navigation

    private func advanceStep() {
        if currentStep < availableModules.count - 1 {
            withAnimation { currentStep += 1 }
        } else {
            withAnimation { showCompletion = true }
        }
    }

    // MARK: - Persistence

    private func loadProgress() {
        if let data = UserDefaults.standard.data(forKey: "onboarding_completed_modules"),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            completedModules = saved
        }
        if let data = UserDefaults.standard.data(forKey: "onboarding_skipped_modules"),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            skippedModules = saved
        }
        // Resume where left off
        let step = UserDefaults.standard.integer(forKey: "onboarding_current_step")
        if step > 0 && step < availableModules.count {
            currentStep = step
            showWelcome = false
        }
    }

    private func saveProgress() {
        if let data = try? JSONEncoder().encode(completedModules) {
            UserDefaults.standard.set(data, forKey: "onboarding_completed_modules")
        }
        if let data = try? JSONEncoder().encode(skippedModules) {
            UserDefaults.standard.set(data, forKey: "onboarding_skipped_modules")
        }
        UserDefaults.standard.set(currentStep, forKey: "onboarding_current_step")
    }
}

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

### OnboardingProgress.swift

Create `Shared/OnboardingProgress.swift`:

```swift
import SwiftUI

/// Tracks which onboarding walkthrough pages have been visited and actions completed.
/// Uses @AppStorage keys so progress persists per-device.
class OnboardingProgress: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("onboarding_current_step") var currentStep = 0

    /// Pages visited during onboarding (stored as JSON Set<String>)
    @Published var visitedPages: Set<String> = []
    @Published var completedActions: Set<String> = []

    init() {
        loadState()
    }

    func markPageVisited(_ pageId: String) {
        visitedPages.insert(pageId)
        save()
    }

    func markActionCompleted(_ actionId: String) {
        completedActions.insert(actionId)
        save()
    }

    func isPageVisited(_ pageId: String) -> Bool {
        visitedPages.contains(pageId)
    }

    func isActionCompleted(_ actionId: String) -> Bool {
        completedActions.contains(actionId)
    }

    private func loadState() {
        if let data = UserDefaults.standard.data(forKey: "onboarding_visited_pages"),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            visitedPages = saved
        }
        if let data = UserDefaults.standard.data(forKey: "onboarding_completed_actions"),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            completedActions = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(visitedPages) {
            UserDefaults.standard.set(data, forKey: "onboarding_visited_pages")
        }
        if let data = try? JSONEncoder().encode(completedActions) {
            UserDefaults.standard.set(data, forKey: "onboarding_completed_actions")
        }
    }
}
```

### Wiring Into the App

In `WiredPartIOSApp.swift` (or wherever the root view is), show the walkthrough after login when onboarding is not complete:

```swift
// After login, check onboarding
if appCore.isAuthenticated {
    if !hasCompletedOnboarding {
        OnboardingWalkthroughView()
            .environmentObject(appCore)
    } else {
        IOSMainView()
            .environmentObject(appCore)
    }
}
```

### Post-Onboarding: Tooltip Hints for Skipped Pages

After onboarding completes, for each SKIPPED module, show a subtle tooltip the first time the user visits that page. Reuse the existing `FirstVisitHint` component (from 64A) — check `onboarding_skipped_modules` and show hints like:

```swift
// In IOSEmployeesPage (if "people" was skipped during onboarding):
if skippedModules.contains("people") {
    FirstVisitHint(
        pageId: "people-post-onboarding",
        message: "You skipped this during onboarding. Tap ? for a full guide to People management."
    )
}
```

Add these hint checks to the top-level page of each module (Dashboard, Clock, Jobs, etc.).

## Important Notes

- `@AppStorage("hasCompletedOnboarding")` persists per-device. New devices show onboarding again (intentional).
- The walkthrough is hat-aware — a Grunt won't see Office, Reports, or People steps.
- Progress is saved on every step change — the user can quit and resume.
- The "I Did It" button is trust-based — we don't verify the action was actually performed. The point is engagement, not enforcement.
- The completion screen shows skipped modules so the user knows what they missed.
- After onboarding, the Getting Started checklist on Dashboard continues to guide admin users through company setup (that's a separate flow — see 65B).
- If `OnboardingProgressManager` (from 64B) already exists, coordinate with it — the walkthrough should mark "view" tasks as completed in the progress manager too.

## Success Criteria

- [ ] `OnboardingWalkthroughView.swift` created in `Auth/`
- [ ] `OnboardingProgress.swift` created in `Shared/`
- [ ] Welcome screen shows with user name and module count
- [ ] Steps filtered by hat permissions (grunt vs manager)
- [ ] Progress bar shows "Step X of Y — Module Name"
- [ ] Each step has: icon, description, key features, required action
- [ ] "I Did It" and "Skip" buttons work correctly
- [ ] "Back" button navigates to previous step
- [ ] Progress persists across app restarts (can resume)
- [ ] Completion screen shows summary with completed/skipped counts
- [ ] Skipped modules listed with reminder to use ? button
- [ ] Wired into app root — shows after login when `hasCompletedOnboarding == false`
- [ ] Post-onboarding tooltip hints on skipped module pages
- [ ] Coordinates with existing OnboardingProgressManager (marks "view" tasks)
- [ ] Project builds with zero errors

## Log Entry

```
## Prompt 65A Results (YYYY-MM-DD)
- OnboardingWalkthroughView: created with X module steps
- OnboardingProgress: state tracking created
- Welcome screen: shows with user name + module count
- Hat filtering: X modules for grunt, Y for manager
- Persistence: resume works
- Completion screen: summary + skipped list
- Post-onboarding hints: added to X pages
- Build: PASS/FAIL
```
