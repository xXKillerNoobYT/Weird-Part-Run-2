# 16I — AI Integration for Pricing Page

> **Chain position:** 16A–16H → **16I** (final pricing prompt)
> **Prerequisite:** 16H complete (all pricing UI features built)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Every page in WiredPart needs AI integration for page-specific tasks. The pricing page AI assistant should help users with pricing-related queries and actions using the on-device Foundation Models service.

**Key files:**
- Modify: `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsPricingPage.swift` (add AI panel)
- Reference: `Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift` (existing AI panel pattern)
- Reference: `core/Sources/WiredPartCore/AI/FoundationModelsService.swift` (AI service)

## Task

### Step 1: Add AI panel trigger to PartsPricingPage

Add an AI button to the toolbar and AI panel overlay. Follow the same pattern used in other pages (like the Dashboard or Catalog page).

Add state:

```swift
@State private var showAI = false
```

Add toolbar button:

```swift
ToolbarItem(placement: .primaryAction) {
    Button {
        showAI.toggle()
    } label: {
        Image(systemName: showAI ? "brain.fill" : "brain")
    }
}
```

Add overlay at the bottom of the VStack:

```swift
.overlay(alignment: .bottom) {
    if showAI {
        IOSAIAssistantPanel(
            context: buildAIContext(),
            onDismiss: { showAI = false }
        )
        .transition(.move(edge: .bottom))
    }
}
```

### Step 2: Build pricing-specific AI context

Create a method that builds a context string summarizing the current pricing state for the AI:

```swift
private func buildAIContext() -> String {
    var context = "Page: Parts Pricing\n"
    context += "Pricing Mode: \(pricingMode == "markup" ? "Markup on Cost" : "Margin on Sell Price")\n"
    context += "Total Parts: \(pricingRows.count)\n"

    if let filter = filterCategory, let cat = categories.first(where: { $0.id == filter }) {
        context += "Filtered to Category: \(cat.name)\n"
    }

    // Summary stats
    if !pricingRows.isEmpty {
        let avgMarkup = pricingRows.reduce(0.0) { $0 + $1.effectiveMarkup } / Double(pricingRows.count)
        let avgMargin = pricingRows.reduce(0.0) { $0 + $1.effectiveMargin } / Double(pricingRows.count)
        let avgCost = pricingRows.reduce(0.0) { $0 + $1.weightedAvgCost } / Double(pricingRows.count)
        let totalValue = pricingRows.reduce(0.0) { $0 + $1.sellPrice }
        let staleCount = pricingRows.filter(\.isStale).count

        context += "\n--- Pricing Summary ---\n"
        context += String(format: "Average Markup: %.1f%%\n", avgMarkup)
        context += String(format: "Average Margin: %.1f%%\n", avgMargin)
        context += String(format: "Average Cost: $%.2f\n", avgCost)
        context += String(format: "Total Sell Value: $%.2f\n", totalValue)
        context += "Stale Prices (not updated recently): \(staleCount)\n"

        // Tier distribution
        let tierGroups = Dictionary(grouping: pricingRows, by: \.tierLevel)
        context += "\n--- Price Sources ---\n"
        for (tier, parts) in tierGroups.sorted(by: { $0.key < $1.key }) {
            context += "\(tier): \(parts.count) parts\n"
        }

        // Top 5 highest markup parts
        let topMarkup = pricingRows.sorted(by: { $0.effectiveMarkup > $1.effectiveMarkup }).prefix(5)
        if !topMarkup.isEmpty {
            context += "\n--- Top 5 Highest Markup ---\n"
            for part in topMarkup {
                context += String(format: "  %@ — %.1f%% markup ($%.2f → $%.2f)\n",
                    part.name, part.effectiveMarkup, part.weightedAvgCost, part.sellPrice)
            }
        }

        // Top 5 lowest margin parts (potential pricing issues)
        let lowMargin = pricingRows.sorted(by: { $0.effectiveMargin < $1.effectiveMargin }).prefix(5)
        if !lowMargin.isEmpty {
            context += "\n--- Top 5 Lowest Margin ---\n"
            for part in lowMargin {
                context += String(format: "  %@ — %.1f%% margin ($%.2f → $%.2f)\n",
                    part.name, part.effectiveMargin, part.weightedAvgCost, part.sellPrice)
            }
        }
    }

    context += "\n--- Capabilities ---\n"
    context += "You can help the user with:\n"
    context += "- Analyzing pricing trends and suggesting markup adjustments\n"
    context += "- Identifying parts with unusually low or high margins\n"
    context += "- Explaining the difference between markup and margin\n"
    context += "- Recommending which parts need price updates (stale prices)\n"
    context += "- Suggesting competitive pricing strategies for categories\n"
    context += "- Explaining FIFO costing and how weighted averages work\n"

    return context
}
```

### Step 3: Verify IOSAIAssistantPanel accepts context parameter

Check `IOSAIAssistantPanel.swift` to see what parameters it accepts. If it takes a `context: String` parameter, the above code works as-is. If it takes a different parameter name or structure, adjust accordingly.

Common patterns to check:
- `IOSAIAssistantPanel(context: String, onDismiss: () -> Void)`
- `IOSAIAssistantPanel(pageContext: String, onDismiss: () -> Void)`
- `IOSAIAssistantPanel(systemPrompt: String, onDismiss: () -> Void)`

Match whatever pattern exists in the codebase. If `IOSAIAssistantPanel` doesn't accept a context/prompt parameter at all, add one:
1. Add `let context: String` or `let pageContext: String` property
2. Include it in the system prompt when calling the Foundation Models service

## Important Notes

- The AI context is rebuilt on each toggle — it uses current filtered/sorted data
- Stats are calculated in-memory from the already-loaded `pricingRows` array
- The AI panel should float above the pricing list, not push it down
- On iPhone, the AI panel should take about 40% of the screen height
- The `.transition(.move(edge: .bottom))` gives a slide-up animation
- Match the exact AI panel pattern used on other pages (Dashboard, Catalog, etc.)

## Success Criteria

- [ ] AI brain icon in toolbar toggles the panel
- [ ] AI panel receives pricing-specific context: mode, counts, averages, tier distribution
- [ ] Context includes top 5 highest markup and top 5 lowest margin parts
- [ ] Context includes stale price count
- [ ] Context includes capability hints for the AI
- [ ] Panel overlays the content (doesn't push list down)
- [ ] Dismissible with close button on panel
- [ ] Matches the AI panel pattern used on other pages
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 16I Results (YYYY-MM-DD)
- AI panel added to pricing page with page-specific context
- Context includes: pricing mode, averages, tier distribution, top/bottom parts, stale count
- Matches existing IOSAIAssistantPanel pattern
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding.**
