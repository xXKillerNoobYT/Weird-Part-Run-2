# 37C — Organization Audit Tab

> **Chain position:** 37A → 37B → **37C** → 37D
> **Prerequisite:** 37A (organization ratings + consolidation tables exist)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Task

Create the Organization tab on IOSAuditPage. Separate from count audit — focuses on warehouse organization quality.

### Organization Tab Layout
- Organization rating per area/shelf/unit with 0-10 score
- Consolidation suggestions with voting (parts in multiple areas)
- Monthly schedule triggers
- Movement suggestions
- "While you're here" org questions (shown during movements, not here)

### Consolidation Voting
- System detects same part in 3+ areas
- Shows suggestion card: "Copper Fittings in A01, A04, B02 — pick best home?"
- Users vote for preferred area
- Manager can override
- If ignored 3 times → escalate with required reason
- Applied decision: returns route to chosen area, pulls from non-chosen first

### Organization Checklist per Area
When doing an org audit of an area:
- Labels accurate? [Yes/No]
- Parts in right spots? [Yes/No]
- Area overcrowded? [Yes/No]
- Bins properly assigned? [Yes/No]
- Any misplaced parts? [Yes/+ Report]

### Rating Display
- Per-area org rating (0-10)
- Per-unit aggregate
- Per-row aggregate
- Warehouse overall org score

## Success Criteria
- [ ] Organization tab separate from count tab
- [ ] Consolidation voting with manager override
- [ ] Per-area org checklist
- [ ] Rating rollup: area → unit → row → warehouse
- [ ] Escalation after 3 ignores
- [ ] Project builds with no errors
