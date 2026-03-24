# 33A — Add Help/Info Button to ALL Pages (Program Standard)

> **Chain position:** **33A** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. EVERY page in the app must have a help/info button
2. The button goes in the toolbar (secondary action placement)
3. It presents a sheet explaining what the page does and how to use it
4. Content is static text — no AI, no database queries

## Instructions

### Step 1: Create HelpSheet Component

Create a reusable component at `Weird Parts IOS/Weird Parts IOS/Shared/PageHelpSheet.swift`:

```swift
import SwiftUI

/// Reusable help sheet for any page.
struct PageHelpSheet: View {
    let title: String
    let sections: [(heading: String, body: String)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections.indices, id: \.self) { i in
                    Section(sections[i].heading) {
                        Text(sections[i].body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

### Step 2: Add to Every Page

For EVERY page under `Features/`, add a help button in the toolbar:

```swift
.toolbar {
    ToolbarItem(placement: .secondaryAction) {
        Button { showHelp = true } label: {
            Image(systemName: "questionmark.circle")
        }
    }
}
.sheet(isPresented: $showHelp) {
    PageHelpSheet(title: "Page Name Help", sections: [
        ("What This Page Does", "Brief description of the page purpose."),
        ("How To Use It", "Step-by-step instructions."),
        ("Tips", "Pro tips for power users.")
    ])
}
```

**If the page already uses `ActiveSheet` enum**, add `.help` case instead:
```swift
case help
// In sheetContent:
case .help:
    PageHelpSheet(title: "...", sections: [...])
```

### Step 3: Write Help Content for Every Page

Each page needs 2-3 sections of help text. Use the page's actual functionality to write relevant content. Examples:

**Dashboard Overview:**
- What: "Your daily command center. See clock status, quick stats, and recent activity."
- How: "Tap cards to filter. Pull down to refresh. Use the QR scanner for quick lookups."

**Parts Catalog:**
- What: "Browse all parts in your inventory. Search, filter, and manage your parts catalog."
- How: "Use the search bar to find parts by name or code. Tap filter chips to narrow results. Tap a part to see details."

**Warehouse Audit:**
- What: "Verify inventory accuracy by counting parts on shelves. The system compares your counts to expected quantities."
- How: "Start an audit session, select a zone, and count each part. Discrepancies are flagged for review."

Write ACCURATE help text for every page — don't copy/paste generic text.

## Success Criteria

- [ ] `PageHelpSheet` component created
- [ ] EVERY page under Features/ has a help button
- [ ] Help content is specific and accurate for each page
- [ ] Help button uses `questionmark.circle` SF Symbol consistently
- [ ] Project builds with no errors
