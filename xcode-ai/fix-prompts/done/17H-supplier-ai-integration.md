# 17H — Supplier AI Integration (Read-Only)

> **Chain position:** 17A → 17B → 17C → 17D → 17E → 17F → 17G → **17H**
> **Prerequisite:** 17G complete
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Every page in the app gets AI assistant integration. For the Suppliers page, the AI should be able to **provide information** about suppliers but NOT edit them. The AI should answer questions like:

- "Which supplier has the best on-time rate?"
- "Show me all suppliers for brand X"
- "What's our account number with ABC Supply?"
- "Compare quality scores between these suppliers"
- "Who supplies the most parts?"

This follows the same AI panel pattern used on other pages (see 13E for the Catalog AI pattern, 16I for the Pricing AI pattern).

**Key files:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift` — add AI button + panel
- `Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift` — existing AI panel component
- `core/Sources/WiredPartCore/AI/FoundationModelsService.swift` — AI service

## Task

### Step 1: Add AI context method for suppliers

In `PartsService.swift`, add a method that builds a text context string the AI can use:

```swift
// =========================================================================
// MARK: - 15. Supplier AI Context
// =========================================================================

/// Build a context string about suppliers for AI queries.
/// Returns a summary the AI assistant can reference when answering questions.
public func buildSupplierAIContext() throws -> String {
    try db.writer.read { dbConn in
        var context = "SUPPLIER DATA:\n\n"

        // All active suppliers with scores
        let suppliers = try Row.fetchAll(dbConn, sql: """
            SELECT s.*,
                (SELECT COUNT(*) FROM part_suppliers WHERE supplier_id = s.id AND deleted_at IS NULL) AS part_count,
                (SELECT COUNT(*) FROM brand_suppliers WHERE supplier_id = s.id AND deleted_at IS NULL) AS brand_count,
                (SELECT COUNT(*) FROM purchase_orders WHERE supplier_id = s.id AND deleted_at IS NULL) AS po_count
            FROM suppliers s
            WHERE s.deleted_at IS NULL
            ORDER BY s.name ASC
            """)

        context += "Total suppliers: \(suppliers.count)\n"
        let activeCount = suppliers.filter { ($0["is_active"] as Int?) == 1 }.count
        context += "Active: \(activeCount), Inactive: \(suppliers.count - activeCount)\n\n"

        for s in suppliers {
            let name: String = s["name"] ?? ""
            let isActive: Int = s["is_active"] ?? 1
            context += "--- \(name) \(isActive == 1 ? "" : "[INACTIVE]") ---\n"

            if let acct: String = s["account_number"], !acct.isEmpty {
                context += "  Account #: \(acct)\n"
            }
            if let contact: String = s["contact_name"], !contact.isEmpty {
                context += "  Contact: \(contact)\n"
            }
            if let phone: String = s["phone"], !phone.isEmpty {
                context += "  Phone: \(phone)\n"
            }
            if let email: String = s["email"], !email.isEmpty {
                context += "  Email: \(email)\n"
            }
            if let method: String = s["delivery_method"], !method.isEmpty {
                context += "  Delivery: \(method)\n"
            }
            if let days: String = s["delivery_days"], !days.isEmpty {
                context += "  Delivery Days: \(days)\n"
            }

            // Scores
            let quality: Double? = s["quality_score"]
            let onTime: Double? = s["on_time_rate"]
            let reliability: Double? = s["reliability_score"]
            if let q = quality { context += "  Quality Score: \(String(format: "%.0f%%", q))\n" }
            if let o = onTime { context += "  On-Time Rate: \(String(format: "%.0f%%", o))\n" }
            if let r = reliability { context += "  Reliability: \(String(format: "%.0f%%", r))\n" }

            // Counts
            let partCount: Int = s["part_count"] ?? 0
            let brandCount: Int = s["brand_count"] ?? 0
            let poCount: Int = s["po_count"] ?? 0
            context += "  Parts: \(partCount), Brands: \(brandCount), POs: \(poCount)\n"

            if let rep: String = s["rep_name"], !rep.isEmpty {
                context += "  Sales Rep: \(rep)\n"
            }
            if let notes: String = s["notes"], !notes.isEmpty {
                context += "  Notes: \(notes)\n"
            }
            context += "\n"
        }

        return context
    }
}
```

### Step 2: Add AI button and panel to PartsSuppliersPage

Add state for the AI panel:

```swift
@State private var showAIPanel = false
@State private var aiContext = ""
```

Add an AI button to the toolbar:

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        HStack(spacing: 12) {
            Button {
                Task {
                    if aiContext.isEmpty, let service = appCore.partsService {
                        aiContext = (try? service.buildSupplierAIContext()) ?? ""
                    }
                    showAIPanel.toggle()
                }
            } label: {
                Image(systemName: "sparkles")
            }
            Button { activeSheet = .addSupplier } label: {
                Image(systemName: "plus")
            }
        }
    }
}
```

Add the AI panel overlay or sheet. If `IOSAIAssistantPanel` is used as a slide-over panel:

```swift
.overlay(alignment: .trailing) {
    if showAIPanel {
        IOSAIAssistantPanel(
            context: aiContext,
            systemPrompt: """
                You are an assistant for a construction supply business. You have access to supplier data.
                Answer questions about suppliers, their performance scores, contact info, and relationships.
                You can compare suppliers, find the best performer, identify suppliers for specific needs.
                You are READ-ONLY — you cannot modify supplier data. If asked to change something,
                tell the user to use the edit button on the supplier card instead.
                Be concise and helpful. Format numbers and percentages clearly.
                """,
            onDismiss: { showAIPanel = false }
        )
        .transition(.move(edge: .trailing))
    }
}
```

If `IOSAIAssistantPanel` uses a different API (check the existing implementation), match that pattern. The key parts are:
1. Pass the supplier context string
2. Include a system prompt that emphasizes READ-ONLY
3. Provide a dismiss callback

### Step 3: Refresh AI context when data changes

After any supplier CRUD operation (add/edit/delete), clear the cached context so it rebuilds on next open:

```swift
// After loadData() completes, or in the onSave/onDelete callbacks:
aiContext = ""  // Force rebuild on next AI panel open
```

## Important Notes

- The AI is **READ-ONLY** for the suppliers page. It can answer questions and provide information but cannot create, edit, or delete suppliers. The system prompt must make this clear.
- AI context is built lazily — only when the user first opens the panel. This avoids a database query on every page load.
- Context is invalidated (`aiContext = ""`) after any CRUD operation so stale data isn't shown.
- Check how `IOSAIAssistantPanel` is used on other pages (e.g., `PartsCatalogPage.swift` from prompt 13E) and match that exact API. The panel may take different parameters than shown above.
- The context string includes ALL suppliers (active and inactive) so the AI can answer "show me inactive suppliers" queries.
- Supplier notes are included in context so the AI can reference them.

## Success Criteria

- [ ] `buildSupplierAIContext` produces readable text summary of all suppliers
- [ ] AI button (sparkles icon) appears in toolbar
- [ ] AI panel opens with supplier context
- [ ] AI can answer questions about supplier scores, contacts, counts
- [ ] AI refuses edit/delete requests, directs to edit button
- [ ] Context refreshes after CRUD operations
- [ ] Panel dismisses properly
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 17H Results (YYYY-MM-DD)
- Service: buildSupplierAIContext (all suppliers with scores, counts, contacts)
- AI panel: read-only, toolbar sparkles button, lazy context loading
- Context invalidation on CRUD
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding.**
