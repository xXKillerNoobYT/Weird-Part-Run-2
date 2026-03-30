# 61D — Enforce 44px Minimum Touch Targets on 6 Pages

> **Chain position:** **61D** (standalone)
> **Issue:** T2-06
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT change visual appearance of elements — only add minimum height constraints
2. DO NOT add touch target modifiers to elements that ALREADY have `.frame(minHeight: 44)` or are naturally 44px+
3. Use `.frame(minHeight: 44)` — NOT `.frame(height: 44)` (minHeight allows growth)
4. Apply to EVERY tappable element: buttons, list rows, navigation links, toggles, pickers
5. Project must build with zero errors when done

## Context

Apple's Human Interface Guidelines require all tappable elements to be at least 44x44 points. Several pages have small touch targets — thin list rows, tiny buttons, cramped toggle rows. This makes the app difficult to use on iPhone, especially for users with larger fingers.

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSTimeOffPage.swift`
2. `Weird Parts IOS/Weird Parts IOS/Features/People/IOSHatsPage.swift`
3. `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/IOSNotebooksListPage.swift`
4. `Weird Parts IOS/Weird Parts IOS/Features/Fleet/IOSVehiclesPage.swift`
5. `Weird Parts IOS/Weird Parts IOS/Features/Jobs/JobsListPage.swift`
6. `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSManageJobsPage.swift`

## Task

### 1. Audit Each File for Small Touch Targets

In each file, find EVERY element that responds to taps:

- `Button { ... } label: { ... }` — check the label view's height
- `NavigationLink { ... }` — check the label/content height
- List rows that have `.onTapGesture` — check row height
- `Toggle` rows — check container height
- `Picker` rows — check container height
- Toolbar buttons — these are usually fine (system-managed)
- `.swipeActions` — these are system-managed, skip them

### 2. Add `.frame(minHeight: 44)` to Small Elements

For each element that could be shorter than 44px, add the constraint:

**Buttons:**
```swift
// BEFORE:
Button("Edit") { ... }

// AFTER:
Button("Edit") { ... }
    .frame(minHeight: 44)
```

**List rows with custom content:**
```swift
// BEFORE:
HStack {
    Text(item.name)
    Spacer()
    Text(item.status)
}

// AFTER:
HStack {
    Text(item.name)
    Spacer()
    Text(item.status)
}
.frame(minHeight: 44)
```

**NavigationLinks:**
```swift
// BEFORE:
NavigationLink(destination: DetailPage()) {
    Text(item.name)
}

// AFTER:
NavigationLink(destination: DetailPage()) {
    Text(item.name)
        .frame(minHeight: 44)
}
```

### 3. Elements That Do NOT Need Changes

Skip these — they are already 44px+ naturally:
- List rows that contain images + multi-line text (VStack with title + subtitle)
- System `Form` rows with `TextField` (system handles sizing)
- Large buttons with significant padding
- `.navigationBarItems` and `.toolbar` items (system-managed)
- Elements already using `.frame(minHeight: 44)` or `dsMinTapTarget()`

### 4. Check for `dsMinTapTarget()` Modifier

Search for `dsMinTapTarget` in the project. If this custom modifier exists, use it instead of `.frame(minHeight: 44)` for consistency. If it doesn't exist, use `.frame(minHeight: 44)`.

### 5. Also Fix Horizontal Touch Targets

For icon-only buttons (trash, edit, share icons), ensure minimum WIDTH too:
```swift
Button(action: { ... }) {
    Image(systemName: "trash")
}
.frame(minWidth: 44, minHeight: 44)
```

### 6. Page-Specific Guidance

**IOSTimeOffPage:** Time-off request rows are likely compact. Each row needs `minHeight: 44`.

**IOSHatsPage:** Hat assignment rows may be small text-only. Each row needs `minHeight: 44`.

**IOSNotebooksListPage:** Notebook list rows may be compact. Each row needs `minHeight: 44`.

**IOSVehiclesPage:** Vehicle list rows likely have icons+text and may already be fine. Check action buttons.

**JobsListPage:** Job list cards are probably already large. Check filter buttons and toolbar actions.

**IOSManageJobsPage:** Check all action buttons in the management interface — approve, reject, archive buttons.

## Success Criteria

- [ ] All 6 pages audited for touch targets
- [ ] Every tappable element has at least 44px height
- [ ] Icon-only buttons have at least 44x44px frame
- [ ] No visual layout changes (elements may have more breathing room, but no style changes)
- [ ] Project builds with zero errors
