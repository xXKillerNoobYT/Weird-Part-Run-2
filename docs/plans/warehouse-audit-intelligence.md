# Warehouse Audit Intelligence System — Design Plan

> **Status:** Design CONFIRMED (2026-03-22)
> **Scope:** Audit page, confidence system, organization rating, user rating, progressive onboarding
> **Dependencies:** Warehouse Locations (floor plan), Forecasting (confidence tie-in), Movements (Movement Decay Factor)

---

## Progressive Warehouse Integration (5 Levels → User Journey)

The warehouse grows with the company. No big-bang setup required.

| Level | Name | What's Done | Time to Complete |
|-------|------|-------------|-----------------|
| 0 | Just Parts | Quick Count — parts with counts, no locations | 1 afternoon |
| 1 | General Floor Plan | Room outline + major zones on grid | 30 min |
| 2 | Storage Units Placed | Shelves, racks, etc. placed + named on floor plan | 30 min |
| 3 | Shelves Configured | Levels + areas entered, stickers written (one unit at a time) | 1-2 weeks |
| 4 | Parts Assigned | Parts migrated from "no location" to specific areas | 1-2 weeks |
| 5 | Bins + Fine Detail | Bins within areas, full warehouse management | Ongoing |

**Key rule:** Each level adds value without requiring the next. A company can stay at Level 2 forever if that's all they need.

**Quick Count mode:** Skips levels 1-3. Just scan/search parts and enter counts. Location optional. Parts can be migrated to areas later when the floor plan is built.

**Save & Exit at every step.** Progress persists. User can leave and come back tomorrow.

---

## 10-Level Parts Reliability Scale (0-10, per part per location)

| Level | Name | Description | Confidence Behavior |
|-------|------|-------------|-------------------|
| 0 | NOT IN WAREHOUSE | Catalog-only, not stocked here. Neutral — doesn't count against ratings. | 0% always (no count exists) |
| 1 | DISCOVERED | Found during count. Single unverified count. No location. | Starts at 50% |
| 2 | LOCATED | Assigned to at least one area. Still unverified. | 50% (needs first audit) |
| 3 | FIRST AUDIT | Counted twice (initial + audit). Verified. | 100% after audit, decays ~3mo to 80% |
| 4 | TRACKED | Home area set. Labels match. No duplicates being consolidated. | 100% after audit, decays ~3mo |
| 5 | MANAGED | MIN/TARGET/MAX set. 90+ days history. Stocking rules active. | Decay ~4mo to 80% |
| 6 | OPTIMIZED | Auto-add unlocked. All org requirements + recommended met. 2 clean audits. | Decay ~6mo |
| 7 | RELIABLE | 6+ months consistent. Confidence rarely <90%. No misplacements 3mo. | Decay ~9mo |
| 8 | CERTIFIED | 12+ months. 4+ clean audits. Variance always neutral. Area org 8+. | Decay ~11mo |
| 9 | AUTONOMOUS | Slowest decay (1 year). Zero misplacements 6mo. Minimal human touch. | Decay 12mo |
| 10 | PERFECT | Theoretical. Momentarily achieved after clean audit. Always decays back to 9. | Instant decay to 9 |

### Level 0 Rules (Special)
- **NOT negative** — just means "we don't stock this part here"
- **Does NOT count against warehouse rating**
- **Auto-jumps to Level 1 when:** target set, return can't go to supplier, PO delivers to warehouse, manual add
- **Drops back to 0 when:** all stock depleted + no target, marked "do not restock" + stock=0, manager removes

### Level Progression
- UP: Meet the requirements for the next level
- DOWN: Misplacement found, count variance >5%, confidence hits 0%, labels wrong/missing

---

## Part Confidence System

### Core Mechanics
- **Scale:** 0% to 100%
- **Uncounted parts:** 0% (Level 0)
- **Newly added (first count, unverified):** 50% (Level 1-2)
- **After first audit (verified):** +55% (caps at 100%)
- **Minimum confidence:** 0.01% (never absolute zero for counted parts)
- **Audit trigger:** Default 80% threshold (configurable)

### Daily Decay
```
Base daily decay: 0.066% (hits 80% in ~3 months at Level 3-4)

Modifiers that SLOW decay (better tracking):
× 0.75  Clean audit history
× 0.80  No misplacements
× 0.90  Organization requirements met
× 0.85  All recommended criteria met

Modifiers that SPEED UP decay (worse tracking):
× 1.50  Misplacement found
× 2.00  Count variance > 5% dollar value
× 1.20  High Movement Decay Factor
× 1.30  Multiple locations (not consolidated)

Result ranges:
Best case (Level 9):  0.030%/day → 1 year to 80%
Default (Level 3-4):  0.066%/day → 3 months to 80%
Problem part:         0.198%/day → ~5 weeks to 80%
Worst case:           0.310%/day → ~2 weeks to 80%
```

### Dollar Value Threshold (Neutral Zone)
- **Percentage-based:** Within 5% of total area value = NEUTRAL (no confidence change)
- **Exact match (100% accurate):** BONUS — slows decay rate, capping at 1-year to 80%
- **Over 5% variance:** PENALTY — speeds decay, gets audited more often, cap at 2-week cycle

### Movement Decay Factor
- More movements between audits = faster confidence decay
- Each unverified movement adds to the factor
- Quick verification count during a movement resets the factor

### Quick Verification Count (Movement Trigger)
- When pulling/placing a part and confidence is ≤85%
- System prompts: "Quick count? You're here — verify the count."
- If user counts → confidence resets to 100%, audit timer resets
- If user skips → nothing changes, movement proceeds normally
- Above 85% → no prompt (don't annoy the user)

### First Audit Double-Count
- New parts start at 50% confidence
- 50% is below the 80% trigger → auto-queued for audit
- First audit gives +55% → 100% (capped)
- Confidence then decays to 80% → second audit triggered
- Two verified counts on different days = reliable baseline

---

## Organization Rating (0-10, per area/unit/shelf)

### What Counts

**Requirements (must ALL be met for auto-add unlock):**
- ☑ Part is in its HOME area (not scattered)
- ☑ No duplicate parts across areas (unless job-ready units, staging, incoming, returns)
- ☑ Labels/stickers accurate and present
- ☑ Bins properly assigned or in proper shelf area if no bin

**Recommended (system recommends turning on auto-add once met):**
- ☑ Similar parts near each other (copper fittings all on Shelf A)
- ☑ Area not overcrowded (below MAX)
- ☑ 2 clean audits in a row

**NOTE:** If below MIN and forecasting auto-add is ON for that part → below MIN doesn't count against organization rating (the system is handling it).

### How Rating Goes UP
- Audits MUST happen for rating to go up (even if things look good)
- Activities improve the reality (consolidations, movements, labeling)
- Both: audits confirm what activities improved
- At Level 5+ organization: QR code scans must be able to confirm placement

### Consolidation Suggestions — Soft Enforcement

When same part exists in 3+ areas:
1. **Soft suggestion** appears for any user at those areas: "Pick the best home?"
2. **Users vote** — not everyone needs to answer. Majority wins.
3. **OR Manager overrides** with a direct pick.
4. **System applies decision:** returns route to chosen area, outbound pulls from non-chosen areas first
5. **Over time:** non-chosen areas empty naturally
6. **If ignored 3 times:** escalate to manager with required reason for dismissal

**Job-ready units are EXEMPT from consolidation.** Packout bins for job loading keep their parts — that's intentional duplication.

---

## Forecasting Auto-Add Unlock Requirements

For a part to have auto-add to wishlist ENABLED:

**ALL requirements must be met:**
1. Part is in its HOME area (not scattered)
2. No duplicate areas (unless job-ready/staging/incoming/returns)
3. Labels/stickers accurate and present
4. Bins properly assigned or in proper shelf area

**If ALL requirements met:** Auto-add UNLOCKS (can be enabled). Default OFF.

**If ALL requirements + ALL recommended met:** System RECOMMENDS turning it on.

**Recommended criteria:**
1. Similar parts near each other
2. Area not overcrowded (below MAX)
3. 2 clean audits in a row

---

## Job-Ready Unit Flags

- **Unit type flag:** Packouts are always "job-ready"
- **Per-bin flag:** Any specific bin can be marked as "job-ready kit"
- **Tools:** Also job-ready by default
- **Job-ready units are EXEMPT from consolidation suggestions**

### Kit/Unit Return Flow
- Parts (consumable): Audit count + restock depleted parts
- Tools (non-consumable): Kit return checklist (verify all items present)
- Both use the return checklist designed earlier

---

## User Rating (0-10)

### Actions That Affect Rating
- Accurate audit counts (accuracy ↑ = rating ↑)
- Number of audits completed (effort)
- Parts placed in correct locations after movements
- Following the guided movement wizard properly
- Speed of audits (efficiency)
- Reporting issues/problems proactively
- Proactively fixing misplaced parts (moving them to correct location)

### Visibility
- **Leaderboard:** Visible to ALL users — shows name + number only (gamification)
- **Detailed breakdown:** Visible to MANAGERS only (hat-locked) — shows per-category scores + trends + training suggestions

### Training Guidance (progressive)
1. **Start with C:** Simpler tasks first (count big obvious items before small screws)
2. **Then B:** Pair with a high-rated user for buddy audits
3. **Then A (last resort):** AI suggests specific training topics

---

## Overall Warehouse Rating (0-10)

**Combination of:**
- Part confidence (average across all tracked parts)
- Organization rating (average across all areas)
- User ratings (team average)
- Shelf utilization (only kicks in once shelves are mostly labeled + organized)
- Misplacement count (brings rating down)
- Label accuracy (very important)
- Response time (how quickly audit triggers get completed)
- Stock health (parts below MIN or above MAX)

**Stock health special rules:**
- Above MAX = worse than below MIN (taking up space we don't have)
- Below MIN with pending PO = NEUTRAL (it's being handled)
- Below MIN with forecasting auto-add ON + part on wishlist = NEUTRAL (system is handling it)

**Where displayed:** Warehouse Dashboard only (not global Dashboard)

**Shelf utilization:** Does NOT count until shelves are mostly labeled and organized. Prevents penalizing a warehouse that's still being set up.

**Turnover rate:** Low turnover is NOT bad — might be a hard-to-find part or seasonal. Just means: audit less often, keep lower count, be careful not to over-order.

---

## Onboarding Flow Details

### Entry Points
1. **Full Setup** — 6-step guided process (room → units → numbers → walk → count → targets)
2. **Quick Count** — Skip layout, just scan/search parts and enter counts + optional location

### Floor Plan
- Manual measurements only (no camera-based approach — narrow aisles, measuring tape is easy)
- Grid-based with drag-and-drop units
- Long press / right click to rotate 90° or show front face
- Areas marked as "Other" (office, doors, walkways, bathroom, loading dock, etc.)

### Sticker System
- Phase 1: Sharpie + plain stickers with handwritten numbers
- Phase 2: QR code stickers (upgrade later)
- Stickers identify LOCATIONS, not parts. Parts move, locations don't.
- Arrow ↑ = default for everything. Arrow ↓ = only Ground Zero items.

### Progressive Migration
- Level 0 parts (no location) show as "No Loc." smart card on audit page
- Level 4 flow lets users assign unlocated parts to areas during walk-through
- "Assign Here" button in the walk-through shows unassigned parts for quick assignment

### Storage Unit Configuration
- One unit at a time (don't have to do all at once)
- Each unit: name, dimensions, levels, areas per level
- Sticker checklist generated automatically after configuration
- Row assignment for physical navigation
