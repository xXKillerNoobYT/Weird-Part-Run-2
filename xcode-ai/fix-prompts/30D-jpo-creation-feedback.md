# 30D — JPO Creation: Quantity Confirm + Companion Feedback Loop

> **Chain position:** 30A → 30B → 30C → **30D** → 30E
> **Prerequisite:** 30C complete (suggestions panel)
> **Plan:** `docs/plans/ios-jpo-creation-page.md` — Feedback Loop section

## Instructions

Read 30C results and the plan. When done, wait for user confirmation.

## Context

When a user accepts a suggestion, the system needs to: (1) show a quantity confirmation dialog so the user can adjust, and (2) feed the acceptance/adjustment back into the companion rules system to make it smarter over time.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOCreationPage.swift` — add confirm dialog + feedback
- `core/Sources/WiredPartCore/Services/PartsService.swift` — add companion feedback methods

## Task

### Step 1: Quantity confirmation dialog

When user taps [+ Add X] on a suggestion:

```swift
@State private var confirmingPart: Part?
@State private var confirmQty: Int = 1
@State private var confirmSource: String = ""  // "companion" or "ai"
@State private var confirmSuggestionPartId: Int64?
@State private var showConfirmDialog = false

// Trigger:
Button { prepareSuggestionConfirm(partId: pid, suggestedQty: qty, source: "companion") }

private func prepareSuggestionConfirm(partId: Int64, suggestedQty: Int, source: String) {
    guard let part = try? appCore.partsService?.getPart(id: partId) else { return }
    confirmingPart = part
    confirmQty = suggestedQty
    confirmSource = source
    confirmSuggestionPartId = partId
    showConfirmDialog = true
}

// Dialog:
.alert("Add \(confirmingPart?.name ?? "Part")?", isPresented: $showConfirmDialog) {
    TextField("Quantity", value: $confirmQty, format: .number)
        .keyboardType(.numberPad)
    Button("Cancel", role: .cancel) { }
    Button("Add to Cart") {
        if let part = confirmingPart {
            addToCart(part: part, quantity: confirmQty)
            recordSuggestionFeedback(
                partId: part.id!,
                suggestedQty: /* original suggested qty */,
                acceptedQty: confirmQty,
                source: confirmSource
            )
        }
    }
} message: {
    let stock = getShopStock(partId: confirmingPart?.id ?? 0)
    Text("Suggested: \(confirmQty). Shop stock: \(stock). Adjust if needed.")
}
```

### Step 2: Companion feedback service method

In `PartsService.swift`, add a method to record suggestion acceptance:

```swift
/// Record that a companion suggestion was accepted, training the rules system.
public func recordCompanionFeedback(
    sourcePartId: Int64,   // the part that triggered the suggestion
    targetPartId: Int64,   // the suggested part
    suggestedQty: Int,     // what the system suggested
    acceptedQty: Int,      // what the user actually added
    source: String          // "companion" or "ai"
) throws {
    try db.writer.write { dbConn in
        // 1. Add +1 point to the co-occurrence pair
        try dbConn.execute(sql: """
            UPDATE co_occurrence_pairs SET
                points = points + 1,
                updated_at = datetime('now')
            WHERE (part_a_id = ? AND part_b_id = ?)
               OR (part_b_id = ? AND part_a_id = ?)
            """, arguments: [sourcePartId, targetPartId, sourcePartId, targetPartId])

        // If no pair exists, create one
        let updated = dbConn.changesCount
        if updated == 0 {
            try dbConn.execute(sql: """
                INSERT INTO co_occurrence_pairs (part_a_id, part_b_id, points, co_occurrence_count, confidence, created_at, updated_at)
                VALUES (?, ?, 1, 1, 0.5, datetime('now'), datetime('now'))
                """, arguments: [sourcePartId, targetPartId])
        }

        // 2. If AI suggestion accepted, it starts earning points toward becoming a companion rule
        if source == "ai" {
            // The co-occurrence pair was just created/updated above
            // Over time, if enough users accept this AI suggestion,
            // it'll reach the threshold for becoming a real companion rule
            // (handled by the auto-discovery engine in 19J)
        }

        // 3. Log the qty ratio for learning
        // If user adjusted qty, the system can learn the right ratio over time
        // Store in a lightweight feedback table or just use the co-occurrence points
    }
}
```

### Step 3: Wire feedback into addToCart from suggestions

Update the suggestion row's [+ Add] button to go through the confirm dialog:

```swift
// In suggestionRow, replace direct addToCart with:
Button {
    prepareSuggestionConfirm(partId: pid, suggestedQty: suggestedQty, source: icon == "🔗" ? "companion" : "ai")
} label: {
    Text("+ Add \(suggestedQty)")
}
```

### Step 4: Record feedback after confirmation

```swift
private func recordSuggestionFeedback(partId: Int64, suggestedQty: Int, acceptedQty: Int, source: String) {
    guard let contextPartId = suggestionContextPartId,
          let service = appCore.partsService else { return }
    do {
        try service.recordCompanionFeedback(
            sourcePartId: contextPartId,
            targetPartId: partId,
            suggestedQty: suggestedQty,
            acceptedQty: acceptedQty,
            source: source
        )
    } catch {
        // Non-critical — don't show error to user
        print("[Feedback] Failed to record: \(error)")
    }
}
```

## Important Notes

- The feedback is non-critical — if it fails, don't show an error. The user's cart action should never be blocked by a feedback failure.
- AI suggestions that get accepted start earning co-occurrence points. Over time, they can become real companion rules through the auto-discovery engine (19J).
- The quantity confirmation dialog lets users adjust the suggested qty. The system records both the suggested and accepted qty to learn better ratios.
- Check if `co_occurrence_pairs` table exists (from 19A migration). If not, this feedback recording will need to be adapted or the table created.

## Success Criteria

- [ ] Confirm dialog shows when accepting a suggestion
- [ ] User can adjust quantity before adding
- [ ] Shows stock level in dialog
- [ ] recordCompanionFeedback method adds points to co-occurrence pairs
- [ ] AI suggestions create new co-occurrence pairs when accepted
- [ ] Feedback failures don't block user actions
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 30E.**
