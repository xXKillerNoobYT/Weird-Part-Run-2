# 33E — Wire PO Detail Placeholder Sheets

> **Chain position:** **33E** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

IOSPODetailPage has 6 action sheet stubs showing "Coming Soon":
1. Contact Supplier → should open supplier bridge channel
2. Update ETA → should show date picker and update expected delivery
3. Double Order → should create new PO with different supplier for remaining items
4. Report Issue → should create quality report linked to PO
5. Receipt History → should show receiving timeline
6. Contact Job Creator → should open DM/chat with the person who made the JPO

## Task

Wire each stub to actual functionality. For supplier bridge, use the ChatService supplier channel methods. For others, create simple but functional sheets.

## Success Criteria

- [ ] All 6 "Coming Soon" placeholders replaced with working functionality
- [ ] Contact Supplier opens/creates a supplier bridge channel
- [ ] Update ETA saves new date to PO
- [ ] Receipt History shows receiving session timeline
- [ ] Project builds with no errors
