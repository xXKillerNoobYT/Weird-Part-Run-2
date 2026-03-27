# 64A — Guided Onboarding Walkthrough + New User Welcome

> **Chain position:** Standalone
> **Priority:** HIGH — first impression for every user
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

Create a proper guided onboarding experience for two scenarios:
1. **New company setup** — admin creating the business from scratch
2. **New user joining** — employee logging in for the first time

Read these files first:
- `Auth/OnboardingWelcomeView.swift` — existing welcome screen
- `Auth/OnboardingCompleteView.swift` — existing completion screen
- `Auth/BusinessProfileSetupView.swift` — business profile form
- `Auth/AdminAccountSetupView.swift` — admin creation
- `Features/Dashboard/DashboardView.swift` — existing Getting Started checklist (~line 159)
- `Shared/PageHelpSheet.swift` — help content system

## Task

### Part 1: Make Getting Started Checklist Interactive

In `DashboardView.swift`, the checklist items are display-only. Make them tappable NavigationLinks:

```swift
checklistItem(
    step: 1,
    title: "Add Your Team",
    subtitle: "Add employees so they can clock in and get assigned to jobs.",
    icon: "person.badge.plus",
    color: .blue,
    isComplete: stats.employeeCount > 0,
    destination: { IOSEmployeesPage().environmentObject(appCore) }
)
```

Update the `checklistItem` function to accept an optional destination and wrap in a NavigationLink when provided:

```swift
private func checklistItem<Destination: View>(
    step: Int,
    title: String,
    subtitle: String,
    icon: String,
    color: Color,
    isComplete: Bool,
    @ViewBuilder destination: @escaping () -> Destination = { EmptyView() }
) -> some View {
    NavigationLink {
        destination()
    } label: {
        // existing HStack content
    }
    .buttonStyle(.plain)
    .disabled(isComplete)  // Don't navigate if already done
}
```

Wire destinations:
- Step 1 "Add Your Team" → `IOSEmployeesPage()`
- Step 2 "Set Up Parts Catalog" → `PartsRouter(tabId: "parts-import")` (import/export page)
- Step 3 "Create Your First Job" → `IOSCreateJobSheet()` presented as sheet
- Step 4 "Configure Warehouse" → `WarehouseOnboardingWizard()`

Fix Step 4 completion check — currently hardcoded `false`:
```swift
isComplete: warehouseHasFloorPlan  // Check if any floor plan exists
```

Add a state variable:
```swift
@State private var warehouseHasFloorPlan = false
```

Load it in `loadData()`:
```swift
warehouseHasFloorPlan = (try? appCore.warehouseService?.listFloorPlans().count ?? 0) > 0
```

### Part 2: New User Welcome (Non-Admin)

When a non-admin user logs in for the first time, they see a different welcome experience. Create `NewUserWelcomeView.swift` in `Auth/`:

```swift
struct NewUserWelcomeView: View {
    @EnvironmentObject private var appCore: AppCore
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some View {
        if !hasSeenWelcome {
            welcomeOverlay
        }
    }

    private var welcomeOverlay: some View {
        VStack(spacing: 24) {
            // Welcome header
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to WiredPart!")
                .font(.title)
                .fontWeight(.bold)

            if let user = appCore.currentUser {
                Text("Hi \(user.displayName), you're all set up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Role-based quick tips
            VStack(alignment: .leading, spacing: 16) {
                tipRow(icon: "clock.fill", color: .green,
                       title: "Clock In",
                       detail: "Start each day by clocking in from the Dashboard.")

                tipRow(icon: "doc.text.fill", color: .blue,
                       title: "Parts Orders",
                       detail: "Need parts on a job? Create a Job Parts Order (JPO).")

                tipRow(icon: "questionmark.circle.fill", color: .orange,
                       title: "Need Help?",
                       detail: "Tap the ? button on any page for guidance. Tap the AI button (bottom right) to ask questions.")

                tipRow(icon: "qrcode.viewfinder", color: .purple,
                       title: "QR Scanning",
                       detail: "Scan QR codes to quickly find parts, tools, and POs.")
            }
            .padding(.horizontal, 24)

            Button {
                withAnimation { hasSeenWelcome = true }
            } label: {
                Text("Got It — Let's Go!")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func tipRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

Wire it into `IOSMainView.swift` — show as an overlay on first login:
```swift
.overlay {
    NewUserWelcomeView()
        .environmentObject(appCore)
}
```

### Part 3: Module Tour (Optional, First Visit)

Add a `@AppStorage("hasSeenModuleTour")` flag. On first visit to the main app after the welcome, show a brief horizontal carousel explaining the key modules:

```swift
struct ModuleTourView: View {
    @AppStorage("hasSeenModuleTour") private var hasSeenTour = false
    @State private var currentPage = 0

    let pages: [(icon: String, title: String, description: String)] = [
        ("house.fill", "Dashboard", "Your daily command center. Clock in, see KPIs, scan QR codes."),
        ("briefcase.fill", "Jobs", "Track every job from start to finish. Clock hours, manage to-dos, track warranty."),
        ("cart.fill", "Orders", "Create parts orders for jobs. Track POs from draft to delivery."),
        ("building.2.fill", "Warehouse", "Know where every part is. Audit stock, manage locations, prep job boxes."),
        ("person.3.fill", "People", "Your team, customers, and contractors. Hats control who can do what."),
        ("wrench.fill", "Tools", "Track every tool and kit. Checkout, return, trade, maintain."),
    ]
    // ... TabView with page indicator
}
```

Show this AFTER the `NewUserWelcomeView` is dismissed, only once. Users can skip it.

### Part 4: First-Visit Page Hints

For the first time a user visits certain complex pages, show a brief inline hint banner at the top that auto-dismisses after 10 seconds or on tap:

```swift
struct FirstVisitHint: View {
    let pageId: String
    let message: String
    @AppStorage private var hasSeen: Bool

    init(pageId: String, message: String) {
        self.pageId = pageId
        self.message = message
        self._hasSeen = AppStorage(wrappedValue: false, "firstVisit_\(pageId)")
    }

    var body: some View {
        if !hasSeen {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.caption)
                Spacer()
                Button { withAnimation { hasSeen = true } } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
            }
            .padding(10)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    withAnimation { hasSeen = true }
                }
            }
        }
    }
}
```

Add to key pages:
- Clock Page: "Tap a job to clock in. Use the GPS-sorted list to find nearby jobs quickly."
- JPO Creation: "Search for parts on the left, add them to your cart. The AI suggests related parts on the right."
- Movement Wizard: "Follow the 5 steps to move parts. The system guides you through each one."
- Audit Page: "Tap 'Audit This Shelf' to count parts. The system hides expected counts so you count fresh."

## Important Notes

- `@AppStorage` keys persist per-device. Different devices will show the welcome again (intentional — each device should introduce itself).
- The admin user who created the business will see the Getting Started checklist but NOT the NewUserWelcomeView (they've already been through onboarding).
- The module tour is skippable — don't force it. Some users learn by doing.
- First-visit hints auto-dismiss after 10 seconds — they're nudges, not blockers.
- All hint text should be practical and specific to the page, not generic.

## Success Criteria

- [ ] Getting Started checklist items are tappable NavigationLinks
- [ ] Step 4 (Warehouse) correctly checks for floor plan existence
- [ ] NewUserWelcomeView shows on first login (non-admin)
- [ ] NewUserWelcomeView has role-appropriate tips
- [ ] Module tour shows after welcome (optional, skippable)
- [ ] First-visit hints appear on complex pages (auto-dismiss 10s)
- [ ] `@AppStorage` flags prevent re-showing after dismissal
- [ ] Admin user sees checklist, not the new user welcome
- [ ] Project builds with zero errors

## Log Entry

```
## Prompt 64A Results (YYYY-MM-DD)
- Getting Started checklist: navigable (4 items wired)
- NewUserWelcomeView: created with 4 tip rows
- Module tour: X pages
- First-visit hints: added to X pages
- Build: PASS/FAIL
```
