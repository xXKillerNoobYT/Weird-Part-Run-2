# 58A — Help Buttons on ALL Pages (Integrated with ActiveSheet)

> **Chain position:** Standalone — run after 57A
> **Prerequisite:** 57A (multiple .sheet() fixes)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**Add a help button to EVERY feature page in the app.** The help button MUST be integrated into the existing `ActiveSheet` enum pattern — NOT as a separate `.sheet(isPresented:)`. Pages that already have `showHelp` Bool + separate `.sheet()` need to be MIGRATED to the ActiveSheet pattern.

**Read first:** `Weird Parts IOS/Weird Parts IOS/Shared/PageHelpSheet.swift` — this is the reusable component.

## The Pattern

For every page that has an `ActiveSheet` enum, add a `.help` case:

```swift
private enum ActiveSheet: Identifiable {
    case help  // ADD THIS
    case createItem
    case editItem(Item)
    // ... existing cases

    var id: String {
        switch self {
        case .help: "help"
        case .createItem: "createItem"
        case .editItem(let item): "editItem-\(item.id)"
        }
    }
}
```

Add the help toolbar button:

```swift
.toolbar {
    ToolbarItem(placement: .secondaryAction) {
        Button { activeSheet = .help } label: {
            Image(systemName: "questionmark.circle")
        }
    }
}
```

Add the help case to the sheet content:

```swift
.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .help:
        PageHelpSheet(
            title: "Page Name Help",
            sections: [
                ("What This Page Does", "Description of the page purpose."),
                ("How to Use It", "Step by step instructions."),
                ("Tips", "Helpful tips for using this page effectively.")
            ]
        )
    // ... existing cases
    }
}
```

For pages that DON'T have an ActiveSheet yet (read-only pages, settings pages), create one:

```swift
@State private var activeSheet: ActiveSheet?

private enum ActiveSheet: Identifiable {
    case help
    var id: String { "help" }
}
```

## Pages That Need MIGRATION (have showHelp Bool — REMOVE IT)

These pages already have help buttons but use the wrong pattern. Convert them:

1. Remove `@State private var showHelp = false`
2. Remove `.sheet(isPresented: $showHelp) { PageHelpSheet(...) }`
3. Add `.help` case to existing `ActiveSheet` enum
4. Move the `PageHelpSheet(...)` content into the `sheetContent(for:)` switch

Search for `showHelp` to find all of these files (~43 files).

## Pages That Need ADDITION (no help button at all)

Every Swift file under `Features/` that is a full page (has `NavigationStack` or is a router destination) and does NOT have a help button needs one added.

**Entire sections missing help buttons:**
- `Features/Chat/` — ALL 9 files
- `Features/Tools/` — ALL 7 files
- `Features/Fleet/` — ALL 17 files
- `Features/Reports/` — ALL 9 files
- `Features/Scheduling/` — ALL 12 files
- `Features/Notebooks/` — ALL 7 files
- `Features/People/` — 10 of 11 files
- `Features/Orders/` — ALL 16 files

## Help Content Guidelines

For each page, write 2-3 sections of help content that explain:
1. **What This Page Does** — one paragraph explaining the purpose
2. **How to Use It** — practical instructions
3. **Tips** — optional, helpful tips

The help content should be written for a field worker who has never used the app before. Keep it simple, practical, and jargon-free.

Examples:

```swift
// For IOSPurchaseOrdersPage:
PageHelpSheet(
    title: "Purchase Orders",
    sections: [
        ("What This Page Does",
         "View and manage all purchase orders sent to suppliers. Track order status from draft through delivery."),
        ("How to Use It",
         "Tap a PO to see details. Use the status cards at the top to filter by status. Swipe left on a PO to cancel it. Use the + button to create a new PO or the QR button to scan one."),
        ("Tips",
         "The 'awaiting delivery' count shows how many POs are ordered but haven't arrived yet. Check this daily to follow up on late deliveries.")
    ]
)

// For IOSMyTruckPage:
PageHelpSheet(
    title: "My Vehicle",
    sections: [
        ("What This Page Does",
         "Your personal vehicle dashboard. See your truck's parts, tools, fuel logs, and daily status at a glance."),
        ("How to Use It",
         "Quick actions let you log fuel, mileage, or report issues. The parts section shows what's on your truck — both spare parts and items being hauled for jobs."),
        ("Tips",
         "Complete your pre-trip inspection each morning before clocking in. Keep your spare parts stocked — the system will remind you when items are running low.")
    ]
)
```

## Skip These (no help button needed)

- Router files (just routing logic)
- Sheet/form files that are presented FROM other pages (they're not standalone)
- The `PageHelpSheet` itself

## Success Criteria

- [ ] EVERY feature page has a help button in the toolbar
- [ ] ZERO separate `.sheet(isPresented: $showHelp)` — all integrated into ActiveSheet
- [ ] Help content is written for each page (practical, field-worker-friendly)
- [ ] ZERO multiple `.sheet()` modifiers caused by help button addition
- [ ] Project builds with zero errors

## Log Entry

```
## Prompt 58A Results (YYYY-MM-DD)
- Help buttons migrated (showHelp → ActiveSheet): X files
- Help buttons added (new): X files
- Total pages with help: X
- Build: [PASS/FAIL]
```
