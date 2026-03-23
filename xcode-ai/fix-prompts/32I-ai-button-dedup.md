# 32I — AI Button Deduplication: One Per Page Only

> **Chain position:** **32I** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. The AI assistant is accessed via ONE floating orange button (bottom right corner)
2. This button is managed by `IOSMainView.swift` — it's a GLOBAL overlay
3. Individual pages should NOT add their own AI buttons in toolbars or elsewhere
4. Pages CAN post context notifications (`.xxxPageActive`) — that's fine, keep those
5. Pages should NOT have sparkles/AI buttons that duplicate the global floating button

## Instructions

Search ALL files in `Weird Parts IOS/Weird Parts IOS/Features/` for:
- `"sparkles"` (SF Symbol commonly used for AI buttons)
- `showAIAssistant`
- `aiAssistant`
- `IOSAIAssistantPanel`

If any page has its own AI button that opens the AI panel SEPARATE from the global floating button, REMOVE IT. The global button in IOSMainView handles everything.

**KEEP:**
- Context notification posting (`.onAppear { postContext() }`)
- `@State private var catalogContext` or similar context states
- Notification listeners in IOSAIAssistantPanel

**REMOVE:**
- Toolbar buttons with sparkles/brain icons that open AI
- Any `.sheet` that presents IOSAIAssistantPanel from within a page
- Duplicate AI floating buttons

## Known Files to Check

1. PartsCompanionsPage.swift — has sparkles toolbar button (from 19K)
2. PartsCatalogPage.swift — may have AI toolbar button (from 13E)
3. Any other page that added AI buttons during prompts 16I, 17H, 19K, 23B

## Success Criteria

- [ ] Zero AI buttons in any Feature page toolbar
- [ ] Global floating orange button (IOSMainView) is the ONLY way to access AI
- [ ] All page context notifications still work
- [ ] Project builds with no errors
