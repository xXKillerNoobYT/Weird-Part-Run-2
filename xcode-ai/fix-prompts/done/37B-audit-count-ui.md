# 37B — Audit Count Tab UI (Daily Audit Flow)

> **Chain position:** 37A → **37B** → 37C → 37D
> **Prerequisite:** 37A (confidence tables + service methods exist)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Task

Rebuild the Count Audit tab on IOSAuditPage with the full daily audit flow. See `docs/plans/warehouse-audit-intelligence.md` (Daily Audit Flow section).

### Page Layout
- Smart cards: Audit Now (<80%) / Soon (80-90%) / Good (90%+) / No Location
- Warehouse score bar (0-10 composite): Confidence · Organization · Team
- Audit queue grouped by shelf, sorted by lowest confidence area first
- Recently completed section
- Setup progress bar (if not Level 5)

### Audit Queue
- Grouped by shelf (Area → Shelf → Row walking path)
- Shows ALL parts below 85% at each area
- [Audit This Shelf →] button per shelf group

### Count Flow
- System count HIDDEN during counting (user can't copy)
- After submit: reveals system expected vs user counted vs variance
- Variance within 5% dollar value = NEUTRAL (no confidence change)
- Exact match = BONUS (slows decay)
- Over 5% = PENALTY (speeds decay, more frequent audits)
- Options on variance: Accept count / Count again / Report issue

### Speed Mode
- Auto-triggers when area has QR code
- Camera pops up for next area after each completion
- [+ Found Misplaced Part] button during speed audit
- Misplaced parts: cart (sort later) or quick fix (scan QR at correct spot)
- Quick fix: enter qty ADDED + full count at destination

### Quick Audit (Movement-Triggered)
- Shows when user is at any area for any reason + parts ≤85% confidence
- Once per area per day
- [Yes — Count Now] or [Not Right Now]
- Ties into movements page as a prompt

## Success Criteria
- [ ] Smart cards as filters (program standard)
- [ ] Hidden system counts during counting
- [ ] Variance result with neutral/bonus/penalty
- [ ] Speed mode auto-triggers with QR
- [ ] Misplaced part cart + quick fix
- [ ] Audit queue grouped by walking path
- [ ] Project builds with no errors
