# 60H — First Launch Getting Started Checklist
> Chain position: Standalone
> Log file: xcode-ai/prompt-results-log.md

## Instructions

When a user opens the app for the first time, the Dashboard shows empty KPI cards (0 active jobs, 0 clocked in, $0 spent, etc.) with no guidance on what to do next. New users are completely lost. Fix: detect empty state and show a "Getting Started" checklist card that guides users through initial setup steps.

## Task

### Step 1: Add empty-state detection to DashboardView

In `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardView.swift`, add a computed property to detect whether this is a fresh install with no data:

```swift
/// True if the app has no meaningful data — indicates first-launch or empty state.
private var isFirstLaunchState: Bool {
    stats.activeJobs == 0 &&
    stats.totalEmployees == 0 &&
    stats.totalParts == 0
}
```

Note: Check what properties `DashboardStats` actually has. The property names might be different (e.g., `jobCount`, `employeeCount`, `partCount`). Adapt the property names to match the actual struct. If the struct doesn't have these fields, use the existing fields that indicate zero data.

### Step 2: Add checklist state tracking

Add state properties to track checklist completion. Use `@AppStorage` so the checklist state persists across app launches:

```swift
@AppStorage("onboarding_checklist_dismissed") private var checklistDismissed = false
```

### Step 3: Create the Getting Started checklist card

Add a new computed property for the checklist view:

```swift
// MARK: - Getting Started Checklist

@ViewBuilder
private var gettingStartedChecklist: some View {
    if isFirstLaunchState && !checklistDismissed {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .font(.title2)
                Text("Getting Started")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    withAnimation { checklistDismissed = true }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Welcome to WiredPart! Complete these steps to set up your business.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                checklistItem(
                    step: 1,
                    title: "Add Your Team",
                    subtitle: "Add employees so they can clock in and get assigned to jobs.",
                    icon: "person.badge.plus",
                    color: .blue,
                    isComplete: stats.totalEmployees > 0,
                    destination: "people"
                )

                checklistItem(
                    step: 2,
                    title: "Set Up Parts Catalog",
                    subtitle: "Import or create your parts inventory so you can track stock and order materials.",
                    icon: "wrench.and.screwdriver.fill",
                    color: .green,
                    isComplete: stats.totalParts > 0,
                    destination: "parts"
                )

                checklistItem(
                    step: 3,
                    title: "Create Your First Job",
                    subtitle: "Jobs are the core of WiredPart — create one to start tracking work.",
                    icon: "briefcase.fill",
                    color: .orange,
                    isComplete: stats.activeJobs > 0,
                    destination: "jobs"
                )

                checklistItem(
                    step: 4,
                    title: "Configure Your Warehouse",
                    subtitle: "Set up warehouse locations and bins so parts can be tracked on shelves.",
                    icon: "building.2.fill",
                    color: .purple,
                    isComplete: false, // No easy way to check — leave unchecked
                    destination: "warehouse"
                )
            }

            // Progress indicator
            let completed = [
                stats.totalEmployees > 0,
                stats.totalParts > 0,
                stats.activeJobs > 0
            ].filter { $0 }.count

            HStack {
                Text("\(completed) of 4 complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView(value: Double(completed), total: 4.0)
                    .frame(width: 100)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        )
        .padding(.horizontal, DS.Space.lg)
    }
}
```

### Step 4: Add the checklist item helper

```swift
private func checklistItem(
    step: Int,
    title: String,
    subtitle: String,
    icon: String,
    color: Color,
    isComplete: Bool,
    destination: String
) -> some View {
    HStack(spacing: 12) {
        // Step indicator
        ZStack {
            Circle()
                .fill(isComplete ? Color.green : color.opacity(0.15))
                .frame(width: 36, height: 36)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            } else {
                Text("\(step)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }
        }

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .strikethrough(isComplete)
                .foregroundStyle(isComplete ? .secondary : .primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        Spacer()

        if !isComplete {
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .contentShape(Rectangle())
    .onTapGesture {
        if !isComplete {
            // TODO: Navigate to the relevant section
            // This requires integration with the app's navigation system.
            // For now, the checklist serves as a visual guide.
        }
    }
}
```

### Step 5: Wire the checklist into the Dashboard body

In the `body` property, add `gettingStartedChecklist` ABOVE the KPI section but below the clock status banner:

Find this section in the body:

```swift
clockStatusBanner
    .padding(.horizontal, DS.Space.lg)

if isLoading {
    DSLoadingState()
```

Change it to:

```swift
clockStatusBanner
    .padding(.horizontal, DS.Space.lg)

gettingStartedChecklist

if isLoading {
    DSLoadingState()
```

The checklist will only render when `isFirstLaunchState && !checklistDismissed`, so it has zero impact on existing users with data.

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardView.swift` — add getting started checklist, empty state detection

## Success Criteria

- [ ] Fresh install with no data shows the "Getting Started" checklist card on the Dashboard
- [ ] Checklist has 4 steps: Add Team, Set Up Parts, Create First Job, Configure Warehouse
- [ ] Completed steps show a green checkmark and strikethrough text
- [ ] Progress indicator shows "X of 4 complete" with a progress bar
- [ ] Dismiss button (X) hides the checklist permanently via `@AppStorage`
- [ ] Users with existing data (jobs > 0, employees > 0) never see the checklist
- [ ] The checklist card has proper spacing and shadow, matching the app's design system
- [ ] No compilation errors
