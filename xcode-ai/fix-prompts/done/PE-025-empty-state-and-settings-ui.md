# Fix Prompt PE-025: Empty State UX — Teams, Settings Layout, Edit Tabs

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## What This Fixes

Three quick UI improvements identified in real user testing (GitHub #30, #31, #32):

1. **Teams page shows "No Teams" with no explanation** — users don't know they need employees first
2. **Edit Tabs page layout is confusing in sidebar mode** — the modal + sidebar overlap is disorienting
3. **Settings → Page Layout defaults to a mode that feels wrong** — no preview of what each mode does

---

## Fix 1: Teams Page Empty State (#30)

**File:** `Features/People/IOSTeamsPage.swift` (or wherever the Teams empty state is defined)

When there are no teams, the current empty state shows a generic "No Teams" message. Add context:

**Current behavior:** Generic empty state
**Target behavior:** Helpful empty state with next action

```swift
// Replace the empty ContentUnavailableView with:
ContentUnavailableView {
    Label("No Teams Yet", systemImage: "person.3.fill")
} description: {
    Text("Teams are built from employees. Create your employees first, then organize them into teams here.")
} actions: {
    NavigationLink(destination: IOSEmployeesPage()) {
        Label("Go to Employees", systemImage: "person.badge.plus")
    }
    .buttonStyle(.borderedProminent)
}
```

If you can't use a NavigationLink here (depends on navigation structure), use a Button that navigates programmatically. The key message is: "Teams require employees — create employees first."

---

## Fix 2: Edit Tabs Layout (#31)

**File:** `Features/Settings/TabBarEditorView.swift` or wherever the "Edit Tabs" page lives

The issue: in sidebar navigation mode, the Edit Tabs page shows both the sidebar nav and a modal-style tab editor, which is visually confusing.

Add a note at the top of the page explaining what the view controls, so users understand the relationship between the sidebar they see and the tab editor:

```swift
// Add an informational banner at the top:
if horizontalSizeClass == .regular {
    // iPad / larger layout — show explanatory note
    VStack(alignment: .leading, spacing: 4) {
        Text("Customizing Navigation Tabs")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
        Text("These tabs appear in the bottom tab bar when using compact layout. In sidebar mode (current), they also determine which sections appear in the sidebar.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal)
    .padding(.top, 8)
}
```

Also ensure the page has `.navigationTitle("Edit Tabs")` and `.navigationBarTitleDisplayMode(.inline)` so it has clear framing.

---

## Fix 3: Settings Page Layout Default (#32)

**File:** `Features/Settings/IOSNavigationSettingsPage.swift` (or wherever Page Layout selector lives)

The page layout selector shows options but no preview of what each looks like. Add a subtitle/description under each layout option so users know what they're picking before tapping it.

Find the layout picker (likely a `Picker` or list of radio-style buttons). For each layout option, add a brief description:

```swift
// Example — adapt to actual option names:
ForEach(layoutOptions) { option in
    VStack(alignment: .leading, spacing: 2) {
        Text(option.name)
            .font(.body)
        Text(option.description)  // e.g., "Tab bar at bottom, sidebar on iPad"
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .tag(option.id)
}
```

If the layout options are an enum, add a computed `description: String` property to each case explaining what that layout looks like in practice.

The goal: users should be able to pick the right layout without having to try each one.

---

## Success Criteria

1. Teams empty state clearly says "create employees first" and links to the Employees page
2. Edit Tabs page has enough context that users understand what they're editing
3. Settings Page Layout options each have a description so users can make an informed choice
4. All fixes compile with 0 errors

---

## After Completing

Log results in `xcode-ai/prompt-results-log.md` with the standard format. Mark PE-025 DONE in `xcode-ai/fix-prompts/00-fix-order.md`. Comment on GitHub issues #30, #31, #32 noting the fix.
