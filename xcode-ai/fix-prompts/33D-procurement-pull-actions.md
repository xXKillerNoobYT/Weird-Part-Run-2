# 33D — Procurement Pull Action Execution

> **Chain position:** **33D** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

The Procurement page has pull option buttons but they're wired to TODO stubs. The options use TARGET amount with these rules:

1. **Pull to Target + Order Remaining** — always available, RECOMMENDED
2. **Pull All from Shelf + Order Remaining** — only if shelf has enough for full order
3. **Pull to MIN + Order Remaining** — if pulling full order drops below MIN
4. **"+ order remaining" only shows if an order is being made** — if no order needed, simplify
5. **Over MAX: force pull** at least enough to bring below MAX

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSProcurementPage.swift`
- `core/Sources/WiredPartCore/Services/OrdersService.swift` (may need execution method)

## Task

Wire the pull option buttons to actually create warehouse movements and adjust order quantities. The recommended option ("Pull to Target") should be visually highlighted with accent color.

## Success Criteria

- [ ] Pull buttons create actual pending warehouse movements
- [ ] Order quantities adjust based on what was pulled
- [ ] "Pull to Target" highlighted as recommended
- [ ] Over-MAX parts force a pull option
- [ ] "+ order remaining" hidden when no order needed
- [ ] Project builds with no errors
