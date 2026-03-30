# 61H — Add People Dashboard Tab to NavigationConfig

> **Chain position:** **61H** (standalone)
> **Issue:** T2-10
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT remove any existing tabs from the People module
2. The dashboard tab should be the FIRST tab in the People module
3. Use the same tab pattern as other modules (icon + label)
4. Project must build with zero errors when done

## Context

`IOSPeopleDashboardPage` exists and is fully built, but there's no way to reach it. The People module's NavigationConfig doesn't include a "dashboard" tab, and the PeopleRouter has no case for it. This means users can't see the people overview/dashboard.

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` (or wherever module tabs are defined)
2. The People router file (likely `PeopleRouter.swift` or similar in Features/People/)
3. `Weird Parts IOS/Weird Parts IOS/Features/People/IOSPeopleDashboardPage.swift` (verify it compiles)

## Task

### 1. Find NavigationConfig

Search for `NavigationConfig` or the file that defines module tabs. Look for where other modules define their tabs (e.g., Warehouse has "dashboard", "inventory", "movements", etc.).

### 2. Add "dashboard" Tab to People Module

Find the People module's tab list and add "dashboard" as the FIRST tab:

```swift
// Example pattern (actual code may differ):
case .people:
    return [
        TabItem(id: "dashboard", label: "Dashboard", icon: "person.3.fill"),  // ADD THIS
        TabItem(id: "employees", label: "Employees", icon: "person.fill"),
        TabItem(id: "teams", label: "Teams", icon: "person.3"),
        // ... existing tabs
    ]
```

### 3. Add Route Case to People Router

Find the People router and add the dashboard case:

```swift
enum PeopleRoute: String, CaseIterable {
    case dashboard  // ADD THIS
    case employees
    case teams
    // ... existing cases
}
```

In the router's body/switch:
```swift
case .dashboard:
    IOSPeopleDashboardPage()
```

### 4. Wire Tab to Route

In whatever view handles tab selection for the People module, add the mapping:

```swift
case "dashboard":
    IOSPeopleDashboardPage()
```

### 5. Verify IOSPeopleDashboardPage

Open `IOSPeopleDashboardPage.swift` and verify:
- It accepts `@EnvironmentObject var appCore: AppCore` (or however the app provides dependencies)
- It has a proper `NavigationStack` or works within one
- It displays actual content (not just a placeholder)

If it has compilation issues, fix them.

## Success Criteria

- [ ] "Dashboard" tab added as first tab in People module
- [ ] PeopleRouter has a `dashboard` case pointing to IOSPeopleDashboardPage
- [ ] Tab icon is appropriate (e.g., "person.3.fill" or "chart.bar.fill")
- [ ] IOSPeopleDashboardPage is reachable by tapping the Dashboard tab in People
- [ ] Existing People tabs remain unchanged and functional
- [ ] Project builds with zero errors
