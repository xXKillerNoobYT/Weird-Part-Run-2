# 30C — JPO Creation: Companion Rules + AI Suggestions Panel

> **Chain position:** 30A → 30B → **30C** → 30D → 30E
> **Prerequisite:** 30B complete (smart search)
> **Plan:** `docs/plans/ios-jpo-creation-page.md` — Suggestions Panel section

## Instructions

Read 30B results and the plan. When done, wait for user confirmation.

## Context

The suggestions panel shows related parts based on what's in the cart. Top 5 are from Companion Rules (data-backed), bottom 3 are AI picks (experimental). Suggestions update when a cart item is selected/highlighted or when the last item is added. Parts already in the cart show "✅ Already in cart" instead of [+ Add].

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOCreationPage.swift` — fill in suggestions panel
- `core/Sources/WiredPartCore/Services/PartsService.swift` — query companion rules for a part

## Task

### Step 1: Track which cart item drives suggestions

```swift
@State private var highlightedCartPartId: Int64?  // tapped cart item
@State private var lastAddedPartId: Int64?         // most recently added

private var suggestionContextPartId: Int64? {
    highlightedCartPartId ?? lastAddedPartId ?? cartItems.first?.partId
}
```

When a cart item is tapped, set `highlightedCartPartId`. When a part is added to cart, set `lastAddedPartId`.

### Step 2: Load companion suggestions

```swift
@State private var companionSuggestions: [(partId: Int64, partName: String, suggestedQty: Int, points: Int, confidence: Double, pattern: String)] = []
@State private var aiSuggestions: [(partName: String, reason: String, suggestedQty: Int, partId: Int64?)] = []

private func loadSuggestions() {
    guard let contextPartId = suggestionContextPartId,
          let service = appCore.partsService else { return }

    // Top 5: Companion Rules
    do {
        // Query companion_rules where source includes contextPartId
        // Get the target parts with points and confidence
        // companionSuggestions = try service.getCompanionSuggestionsForPart(partId: contextPartId, limit: 5)
        // NOTE: Check what companion methods exist — may need to add a query method
    } catch { }

    // Bottom 3: AI Picks
    Task {
        let aiService = FoundationModelsService()
        guard aiService.checkAvailability() == .available else { return }

        let cartNames = cartItems.map(\.partName).joined(separator: ", ")
        let contextPart = cartItems.first(where: { $0.partId == contextPartId })?.partName ?? ""

        let prompt = """
            For a construction/electrical job, the worker has these parts in their order:
            Cart: \(cartNames)
            Currently looking at: \(contextPart)

            Suggest 3 additional parts they likely need that are NOT in the cart.
            For each, give: part name, brief reason, suggested quantity.
            Format: partName|reason|qty (one per line)
            """

        let result = await aiService.generate(
            instructions: "You suggest construction parts. Return exactly 3 suggestions in partName|reason|qty format.",
            prompt: prompt
        )

        if let text = result.text {
            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            await MainActor.run {
                aiSuggestions = lines.prefix(3).compactMap { line in
                    let parts = line.components(separatedBy: "|")
                    guard parts.count >= 3 else { return nil }
                    let name = parts[0].trimmingCharacters(in: .whitespaces)
                    let reason = parts[1].trimmingCharacters(in: .whitespaces)
                    let qty = Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 1
                    // Try to match to a real part in catalog
                    let matchedPart = try? service.searchParts(query: name, limit: 1).first
                    return (partName: matchedPart?.name ?? name, reason: reason,
                            suggestedQty: qty, partId: matchedPart?.id)
                }
            }
        }
    }
}
```

### Step 3: Build suggestions panel UI

```swift
private var suggestionsPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("Suggestions")
                .font(.headline)
            Spacer()
            if let name = cartItems.first(where: { $0.partId == suggestionContextPartId })?.partName {
                Text("for: \(name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

        // Top 5: Companion Rules
        if !companionSuggestions.isEmpty {
            Text("Companion Rules")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(companionSuggestions, id: \.partId) { suggestion in
                suggestionRow(
                    icon: "🔗",
                    partName: suggestion.partName,
                    detail: suggestion.pattern, // "Usually 1 per 20 fittings"
                    subDetail: "\(suggestion.points) pts · \(Int(suggestion.confidence))% conf",
                    suggestedQty: suggestion.suggestedQty,
                    partId: suggestion.partId
                )
            }
        }

        // Bottom 3: AI Picks
        if !aiSuggestions.isEmpty {
            Text("AI Picks")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(aiSuggestions.indices, id: \.self) { idx in
                let suggestion = aiSuggestions[idx]
                suggestionRow(
                    icon: "🤖",
                    partName: suggestion.partName,
                    detail: suggestion.reason,
                    subDetail: nil,
                    suggestedQty: suggestion.suggestedQty,
                    partId: suggestion.partId
                )
            }
        }

        if companionSuggestions.isEmpty && aiSuggestions.isEmpty {
            Text("Add parts to see suggestions")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

@ViewBuilder
private func suggestionRow(icon: String, partName: String, detail: String,
                           subDetail: String?, suggestedQty: Int, partId: Int64?) -> some View {
    let isInCart = cartItems.contains(where: { $0.partId == partId })

    HStack(spacing: 8) {
        Text(icon)
        VStack(alignment: .leading, spacing: 1) {
            Text(partName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let sub = subDetail {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        Spacer()
        if isInCart {
            Text("✅ In cart")
                .font(.caption2)
                .foregroundStyle(.green)
        } else {
            Button {
                // 30D handles the confirm dialog + feedback
                if let pid = partId,
                   let part = try? appCore.partsService?.getPart(id: pid) {
                    addToCart(part: part, quantity: suggestedQty)
                }
            } label: {
                Text("+ Add \(suggestedQty)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }
    .padding(.vertical, 2)
}
```

### Step 4: Trigger suggestion reload

Load suggestions when:
- Cart item added: `.onChange(of: cartItems.count) { loadSuggestions() }`
- Cart item tapped: set `highlightedCartPartId`, call `loadSuggestions()`
- On initial load if cart has items

### Step 5: Add companion query method if missing

In `PartsService`, check if there's a method to get companion suggestions for a specific part. If not, add:

```swift
/// Get companion suggestions for a part (for JPO creation suggestions panel).
public func getCompanionSuggestionsForPart(partId: Int64, limit: Int = 5) throws -> [(partId: Int64, partName: String, suggestedQty: Int, points: Int, confidence: Double, pattern: String)] {
    // Query companion_rule_sources for rules containing partId
    // Get the corresponding targets from companion_rule_targets
    // Join with parts for names
    // Calculate suggested qty from the rule's ratio
    // Return sorted by points DESC
    return try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT DISTINCT rt.part_id AS target_part_id, p.name AS part_name,
                   cr.name AS rule_name, cop.points, cop.confidence
            FROM companion_rule_sources rs
            JOIN companion_rules cr ON cr.id = rs.rule_id
            JOIN companion_rule_targets rt ON rt.rule_id = cr.id
            JOIN parts p ON p.id = rt.part_id
            LEFT JOIN co_occurrence_pairs cop ON
                (cop.part_a_id = ? AND cop.part_b_id = rt.part_id)
                OR (cop.part_b_id = ? AND cop.part_a_id = rt.part_id)
            WHERE rs.part_id = ?
              AND cr.deleted_at IS NULL
              AND p.deleted_at IS NULL
              AND rt.part_id != ?
            ORDER BY COALESCE(cop.points, 0) DESC
            LIMIT ?
            """, arguments: [partId, partId, partId, partId, limit])

        return rows.map { row in
            (partId: row["target_part_id"] as Int64,
             partName: row["part_name"] as String? ?? "Unknown",
             suggestedQty: 1, // TODO: calculate from rule ratio
             points: row["points"] as Int? ?? 0,
             confidence: row["confidence"] as Double? ?? 0,
             pattern: "Companion of \(row["rule_name"] as String? ?? "rule")")
        }
    }
}
```

**Note:** Check actual table names — they may be `companion_rule_sources`, `companion_rule_targets`, or similar. Adapt the query to match.

## Success Criteria

- [ ] Top 5 companion suggestions shown with points/confidence
- [ ] Bottom 3 AI picks with reasons
- [ ] Context switches when cart item tapped
- [ ] "✅ In cart" indicator for already-added parts
- [ ] [+ Add X] button adds with suggested quantity
- [ ] Suggestions reload on cart change and item selection
- [ ] AI gracefully degrades when unavailable
- [ ] Companion query method exists in PartsService
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 30D.**
