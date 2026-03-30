# 60N — AI Help Content Integration via HelpContentRegistry

> **Chain position:** Standalone (best after 58A which adds help to all pages)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

The AI assistant and the help system are completely disconnected. When a user asks the AI "how do I use this page?", the AI gives a worse answer than the help button would. Fix this by creating a `HelpContentRegistry` that stores all `PageHelpSheet` content in a queryable dictionary, so the AI can read from it.

**Read first:**
- `Weird Parts IOS/Weird Parts IOS/Shared/PageHelpSheet.swift` — see the component structure and the `sections: [(String, String)]` format
- `Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift` — see where the AI system prompt is constructed
- Any page that uses `PageHelpSheet` — see what content is passed in

## Task

### Step 1: Create HelpContentRegistry.swift

Create a new file at `Weird Parts IOS/Weird Parts IOS/Shared/HelpContentRegistry.swift`:

```swift
import Foundation

/// Central registry of all page help content. The AI assistant reads from this
/// to answer "how do I use this page?" questions with the same quality as the help button.
struct HelpContentRegistry {
    /// A single help entry for a page.
    struct HelpEntry {
        let pageTitle: String
        let sections: [(title: String, body: String)]
    }

    /// All help content keyed by page identifier (e.g., "parts-catalog", "jobs-list").
    /// Page identifiers match the tab IDs in NavigationConfig where possible.
    static let entries: [String: HelpEntry] = buildRegistry()

    /// Look up help content for a page. Returns nil if no help exists.
    static func helpFor(pageId: String) -> HelpEntry? {
        entries[pageId]
    }

    /// Format help content as a string the AI can include in its context.
    static func formattedHelp(for pageId: String) -> String? {
        guard let entry = entries[pageId] else { return nil }
        var result = "Help for \(entry.pageTitle):\n"
        for section in entry.sections {
            result += "\n## \(section.title)\n\(section.body)\n"
        }
        return result
    }

    /// Get a summary of all available help topics for the AI system prompt.
    static var availableTopics: String {
        entries.map { "\($0.key): \($0.value.pageTitle)" }
            .sorted()
            .joined(separator: "\n")
    }
}
```

### Step 2: Populate the registry from all existing PageHelpSheet content

In the same file, add the `buildRegistry()` function. Go through EVERY file in the codebase that creates a `PageHelpSheet` and extract its content into this registry. The sections array must contain the EXACT same text as the PageHelpSheet.

```swift
private extension HelpContentRegistry {
    static func buildRegistry() -> [String: HelpEntry] {
        var registry: [String: HelpEntry] = [:]

        // Parts Catalog
        registry["parts-catalog"] = HelpEntry(
            pageTitle: "Parts Catalog",
            sections: [
                // COPY the exact sections from PartsCatalogPage.swift's PageHelpSheet
                ("What This Page Does", "Browse and manage your complete parts inventory..."),
                ("How to Use It", "Use the search bar to find parts by name..."),
                ("Tips", "Use the AI assistant to filter by natural language...")
            ]
        )

        // Jobs List
        registry["jobs-list"] = HelpEntry(
            pageTitle: "Jobs",
            sections: [
                // COPY from JobsListPage.swift's PageHelpSheet
                ("What This Page Does", "..."),
                ("How to Use It", "..."),
                ("Tips", "...")
            ]
        )

        // Continue for EVERY page that has a PageHelpSheet...
        // Search the codebase for all PageHelpSheet usages and extract their content.
        // Use the file's corresponding NavigationConfig tab ID as the key.

        return registry
    }
}
```

**IMPORTANT:** Do NOT make up help content. Read each file that uses `PageHelpSheet`, copy the exact section titles and body text, and put them in the registry. If a page has no PageHelpSheet yet, skip it.

### Step 3: Wire into IOSAIAssistantPanel

In `IOSAIAssistantPanel.swift`, import the registry and include relevant help content in the AI system prompt:

1. Find where the system prompt is built (look for `systemPrompt` or similar).
2. When the AI knows which page the user is on (from the page context notifications — see 60M), look up that page's help content:

```swift
// In the system prompt construction:
var pageHelp = ""
if let pageId = currentPageId,
   let help = HelpContentRegistry.formattedHelp(for: pageId) {
    pageHelp = "\n\nPage Help Content (use this to answer questions about the current page):\n\(help)"
}
```

3. Append `pageHelp` to the system prompt.

4. Also add a general instruction to the AI system prompt:

```swift
let helpInstruction = """
When the user asks "how do I use this page?", "what does this page do?", or similar questions,
use the Page Help Content provided below to give an accurate, detailed answer.
"""
```

### Step 4: Map notification names to page IDs

Create a mapping so when a page context notification fires, you know which help entry to look up:

```swift
private let notificationToPageId: [Notification.Name: String] = [
    .catalogPageActive: "parts-catalog",
    .pricingPageActive: "parts-pricing",
    .suppliersPageActive: "parts-suppliers",
    .companionsPageActive: "parts-companions",
    .forecastingPageActive: "parts-forecasting",
    .jobsListPageActive: "jobs-list",
    .jobDetailPageActive: "job-detail",
    .clockPageActive: "clock",
    // ... add all notification → pageId mappings
]
```

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Shared/HelpContentRegistry.swift` — CREATE this new file
- `Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift` — wire registry into AI system prompt

## Success Criteria

- [ ] `HelpContentRegistry.swift` exists with `entries` dictionary and `formattedHelp(for:)` method
- [ ] Registry is populated with content from ALL existing PageHelpSheet usages (search codebase, do not guess)
- [ ] `helpFor(pageId:)` returns the correct help entry for any page that has help content
- [ ] IOSAIAssistantPanel includes page help content in the AI system prompt
- [ ] When user asks "how do I use this page?", AI can reference the same content as the help button
- [ ] No duplicate help content — registry is the single source of truth referenced by both help button and AI
- [ ] Builds without errors
