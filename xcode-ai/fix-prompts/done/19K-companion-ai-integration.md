# 19K — Companion System AI Integration (Read-Only)

## Context
You are working on a SwiftUI iOS app with on-device AI via Apple Foundation Models. The Companions page needs AI assistant integration for reading companion data and explaining rules/polls. The AI panel is read-only — it cannot create or modify rules.

**Existing AI pattern:** `IOSAIAssistantPanel` is used across pages. It connects to `FoundationModelsService` which registers tool definitions. Each page provides context-specific tools.

**Available PartsService methods for AI context:**
- `listCompanionRulesHierarchy()` — all rules with sources/targets
- `getActivePolls(userId:, isAdmin:)` — current polls
- `getLastWeekResults(userId:)` — recent poll results
- `getUserVotingAccuracy(userId:)` — training metric
- `getQualifiedPairs(...)` — pairs meeting thresholds
- `getTrainingQuestion()` — training question data

**File:** `core/Sources/WiredPartCore/AI/FoundationModelsService.swift`

## Task

### 1. Add companion tool definitions in FoundationModelsService

Find the tool definitions section and add companion-related tools:

```swift
// MARK: - Companion Tools

/// Tool: list_companion_rules — returns all active companion rules with hierarchy
/// AI can explain what each rule does, which categories are linked, and the cascade structure
static let listCompanionRulesTool = ToolDefinition(
    name: "list_companion_rules",
    description: "List all companion rules showing which categories/styles/types are linked together. Use this to explain what companion rules exist and how they work.",
    parameters: []
)

/// Tool: get_active_polls — returns current polls and voting status
static let getActivePollsTool = ToolDefinition(
    name: "get_active_polls",
    description: "Get currently active companion polls that users are voting on. Shows what category pairings are being proposed.",
    parameters: []
)

/// Tool: explain_co_occurrence — shows why a pairing was suggested with points breakdown
static let explainCoOccurrenceTool = ToolDefinition(
    name: "explain_co_occurrence",
    description: "Explain why a specific category pairing was suggested by showing the co-occurrence data: how many jobs had both categories, total points, and confidence score.",
    parameters: [
        ToolParameter(name: "category_a", type: "string", description: "First category name"),
        ToolParameter(name: "category_b", type: "string", description: "Second category name")
    ]
)

/// Tool: get_voting_summary — summarizes recent voting patterns
static let getVotingSummaryTool = ToolDefinition(
    name: "get_voting_summary",
    description: "Get a summary of recent poll results and voting patterns. Shows which pairings passed or failed and general team alignment.",
    parameters: []
)
```

### 2. Implement tool handlers

In the tool handling section, add handlers for the companion tools:

```swift
case "list_companion_rules":
    guard let service = partsService else { return "Parts service not available" }
    let rules = try service.listCompanionRulesHierarchy()
    if rules.isEmpty { return "No companion rules exist yet." }
    var result = "Active Companion Rules (\(rules.count)):\n\n"
    for rule in rules {
        let srcNames = rule.sources.map { src in
            // Build hierarchy name from category/style/type
            "Category \(src.categoryId)" + (src.styleId != nil ? " > Style \(src.styleId!)" : "")
        }.joined(separator: ", ")
        let tgtNames = rule.targets.map { tgt in
            "Category \(tgt.categoryId)" + (tgt.styleId != nil ? " > Style \(tgt.styleId!)" : "")
        }.joined(separator: ", ")

        result += "• \(rule.name) [\(rule.matchLevel)] — \(srcNames) → \(tgtNames)"
        if rule.tryMatchBrand == 1 { result += " [Brand Match]" }
        if rule.autoColorMatch == 1 { result += " [Color Match]" }
        if rule.isOrphaned { result += " ⚠️ ORPHANED (parent deleted)" }
        if rule.childCount > 0 { result += " (\(rule.childCount) sub-rules)" }
        result += "\n"
    }
    return result

case "get_active_polls":
    guard let service = partsService else { return "Parts service not available" }
    let userId = currentUserId ?? 0
    let polls = try service.getActivePolls(userId: userId, isAdmin: false)
    if polls.isEmpty { return "No active polls right now. The system needs at least 3 months of ordering data to start suggesting companion rules." }
    var result = "Active Polls (\(polls.count)):\n\n"
    for poll in polls {
        result += "• \(poll.proposedRuleName) [\(poll.matchLevel)]\n"
        result += "  \(poll.sourceName) → \(poll.targetName)\n"
        result += "  Status: \(poll.status), \(poll.daysRemaining) days remaining\n"
        if let myVote = poll.myVote {
            result += "  Your vote: \(myVote)\n"
        } else {
            result += "  You haven't voted yet\n"
        }
        result += "\n"
    }
    return result

case "explain_co_occurrence":
    guard let service = partsService, let db = database else { return "Service not available" }
    let catA = parameters["category_a"] ?? ""
    let catB = parameters["category_b"] ?? ""
    // Look up the co_occurrence_pair for these categories
    let row = try db.writer.read { dbConn in
        try Row.fetchOne(dbConn, sql: """
            SELECT cop.points, cop.co_occurrence_count, cop.confidence,
                   cop.rejection_count, cop.is_blocked, cop.match_level,
                   ca.name AS cat_a_name, cb.name AS cat_b_name
            FROM co_occurrence_pairs cop
            JOIN part_categories ca ON ca.id = cop.category_a_id
            JOIN part_categories cb ON cb.id = cop.category_b_id
            WHERE LOWER(ca.name) LIKE ? AND LOWER(cb.name) LIKE ?
               OR LOWER(ca.name) LIKE ? AND LOWER(cb.name) LIKE ?
            LIMIT 1
            """, arguments: ["%\(catA.lowercased())%", "%\(catB.lowercased())%",
                             "%\(catB.lowercased())%", "%\(catA.lowercased())%"])
    }
    guard let row = row else { return "No co-occurrence data found for '\(catA)' and '\(catB)'. These categories may not appear together on jobs." }
    return """
    Co-occurrence: \(row["cat_a_name"] as String) + \(row["cat_b_name"] as String)
    Points: \(row["points"] as Int)
    Co-occurred on \(row["co_occurrence_count"] as Int) jobs
    Confidence: \(Int((row["confidence"] as Double) * 100))%
    Level: \(row["match_level"] as String)
    Rejections: \(row["rejection_count"] as Int)\(row["is_blocked"] as Int == 1 ? " (BLOCKED)" : "")
    """

case "get_voting_summary":
    guard let service = partsService else { return "Service not available" }
    let userId = currentUserId ?? 0
    let results = try service.getLastWeekResults(userId: userId)
    if results.isEmpty { return "No poll results from the past week." }
    var result = "Recent Poll Results:\n\n"
    for r in results {
        result += "• \(r.pollName): \(r.passed ? "✅ Passed" : "❌ Didn't Pass")"
        if let vote = r.myVote {
            result += " (You voted: \(vote == "accept" ? "Yes" : "No") — \(r.matchedWinner ? "matched winner" : "different from winner"))"
        }
        result += "\n"
    }
    return result
```

### 3. Register companion tools

In the tool registration section, add the 4 companion tools to the tools array:
```swift
listCompanionRulesTool,
getActivePollsTool,
explainCoOccurrenceTool,
getVotingSummaryTool,
```

### 4. Add AI panel to PartsCompanionsPage

In `PartsCompanionsPage.swift`, add the AI assistant panel. Follow the same pattern used on other pages (e.g., `PartsCatalogPage`):

```swift
// Add to ActiveSheet enum:
case aiAssistant

// Add toolbar button:
Button { activeSheet = .aiAssistant } label: {
    Image(systemName: "sparkles")
}

// Add to sheet handler:
case .aiAssistant:
    IOSAIAssistantPanel(context: "companion_rules")
```

## Success Criteria
- [ ] 4 AI tools registered: list_companion_rules, get_active_polls, explain_co_occurrence, get_voting_summary
- [ ] AI can list all companion rules with hierarchy details
- [ ] AI can show active polls and user's vote status
- [ ] AI can explain why a pairing was suggested (points, jobs, confidence)
- [ ] AI can summarize recent voting results
- [ ] AI is strictly read-only — cannot create/modify rules or cast votes
- [ ] AI panel accessible via sparkles toolbar button on Companions page
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 19K Results (YYYY-MM-DD)
- Added 4 AI tools: list_companion_rules, get_active_polls, explain_co_occurrence, get_voting_summary
- All read-only — AI cannot modify companion data
- AI panel added to PartsCompanionsPage via sparkles button
- Build: [PASS/FAIL]
```

When done, the companion rules system is complete. Continue with the next prompt chain.
