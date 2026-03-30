# 66A — Office Dashboard Dead Buttons & QR Scanner Details

> **Chain position:** **66A** (standalone)
> **Issue:** Dead navigation buttons + empty QR action
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. Use existing `NavigationLink` or `NotificationCenter.default.post(name: .navigateToModule)` patterns — do NOT invent a new navigation mechanism
2. Every button must do something when tapped — no empty closures, no TODO comments
3. Use `appCore.xxxService` for any service calls — never create services directly
4. Project must build with zero errors when done

## Context

The Office Dashboard page (`IOSOfficeDashboardPage.swift`) has Quick Action buttons and attention item taps that either have `// TODO: Navigate to...` comments or empty closures. The QR Scanner page has a "Details" button that does nothing. These are high-visibility buttons on primary pages — users see them every day.

### Navigation Pattern (already in codebase)

The app uses `NotificationCenter` to request cross-module navigation. IOSMainView listens for `.navigateToModule`:

```swift
// In NavigationConfig.swift:
static let navigateToModule = Notification.Name("WiredPart.navigateToModule")

// To navigate:
NotificationCenter.default.post(
    name: .navigateToModule,
    object: nil,
    userInfo: ["moduleId": "orders", "tabId": "orders-jpos"]
)

// IOSMainView handles it at line ~100
```

Alternatively, use `NavigationLink` to push a destination directly (works when already inside a NavigationStack).

## Files to Modify

### 1. IOSOfficeDashboardPage.swift — Quick Actions (5 buttons)

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSOfficeDashboardPage.swift`

Find the Quick Actions section. Fix any buttons that have `// TODO` comments or empty closures. The 4 quick action targets are:

| Button | Target Page | Preferred Approach |
|--------|------------|-------------------|
| Review JPOs | `OrdersRouter(tabId: "orders-jpos")` | `NavigationLink` |
| Manage Jobs | `IOSManageJobsPage()` | `NavigationLink` |
| View Reports | `IOSReportsRouter(tabId: "reports-hub")` | `NavigationLink` |
| Dispatch Board | `IOSDispatchPage()` | `NavigationLink` |

Each NavigationLink must pass `.environmentObject(appCore)` to its destination:

```swift
NavigationLink {
    OrdersRouter(tabId: "orders-jpos")
        .environmentObject(appCore)
} label: {
    quickActionLabel("Review JPOs", icon: "doc.text.magnifyingglass", color: .blue)
}
.buttonStyle(.plain)
```

### 2. IOSOfficeDashboardPage.swift — Attention Item Navigation (1 button)

Find where attention items are tapped (the `ForEach(attentionItems)` section). If tapping an attention item does nothing or has a TODO, fix it. The attention item tap should open a detail sheet showing:
- Item type, priority (color-coded), created date
- Description (the item's subtitle)
- Suggested action text

Use the `ActiveSheet` enum pattern:
```swift
case attentionDetail(AttentionItem)  // Add to existing ActiveSheet enum

// In the .sheet(item:) handler:
case .attentionDetail(let item):
    NavigationStack {
        List {
            Section("Details") {
                LabeledContent("Type", value: item.itemType.replacingOccurrences(of: "_", with: " ").capitalized)
                LabeledContent("Priority") {
                    Text(String(describing: item.priority).capitalized)
                        .foregroundStyle(colorForPriority(item.priority))
                        .fontWeight(.semibold)
                }
                LabeledContent("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section("Description") {
                Text(item.subtitle)
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { activeSheet = nil }
            }
        }
    }
```

### 3. IOSDashboardQRScannerPage.swift — "Details" Button

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/IOSDashboardQRScannerPage.swift`

Find the `DSQuickActionButton(title: "Details", ...)` around line 456. If its closure is empty `{ }`, wire it to show a detail sheet for the scanned item:

```swift
DSQuickActionButton(title: "Details", icon: "info.circle", color: .blue) {
    autoLockAction { activeSheet = .scannedDetail }
}
```

Make sure `.scannedDetail` exists in the page's `ActiveSheet` enum. The sheet should show the scan result's full metadata (type, name, location, any associated data).

If `.scannedDetail` is already handled in the `.sheet(item:)` modifier, just make sure it displays useful information (not an empty view).

## Success Criteria

- [ ] All 4 Quick Action buttons navigate to real pages (not TODO stubs)
- [ ] Attention item tap opens a detail sheet with type/priority/description
- [ ] QR Scanner "Details" button opens a detail view for the scanned item
- [ ] No `// TODO: Navigate` comments remain in either file
- [ ] No empty closures `{ }` on any user-facing button in these files
- [ ] All destinations receive `.environmentObject(appCore)`
- [ ] Project builds with zero errors
