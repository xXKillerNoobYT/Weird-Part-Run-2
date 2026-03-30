# 36D — Warehouse Onboarding Wizard (Progressive Setup)

> **Chain position:** 36A → 36B → 36C → **36D**
> **Prerequisite:** 36A-C (floor plan system exists)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Task

### Create WarehouseOnboardingWizard

A 6-step guided setup that appears when no warehouse data exists. See `docs/plans/warehouse-audit-intelligence.md` (Progressive Warehouse Integration section).

**Step 1: Define Space** — room name + measurements + key features (doors, walkways, office)
**Step 2: Place Units** — drag storage units onto the grid (uses 36B floor plan editor)
**Step 3: Number Everything** — sticker checklist with auto-generated codes
**Step 4: Walk the Floor** — area-by-area, identify parts (search/scan/add new)
**Step 5: Count Everything** — system counts HIDDEN, user enters counts per area
**Step 6: Set Targets** — MIN/TARGET/MAX with AI suggestions from forecast data

### Key Features
- Save & Exit at every step (progress persists)
- Skip for Now on any area or part
- Quick Count mode skips steps 1-3 (just count, no floor plan)
- AI pre-fills category/style/type when adding new parts
- Progress bar shows step X of 6 + percentage within step
- Two entry points: [Start Full Setup] and [Quick Count Only]
- "Add New Part" inline form during walk-through (Step 4)
- Level 0 parts shown as "No Loc." for migration to Level 4

### Onboarding Progress Table
```sql
CREATE TABLE warehouse_onboarding_progress (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    floor_plan_id INTEGER REFERENCES warehouse_floor_plans(id),
    current_step INTEGER NOT NULL DEFAULT 1,
    step1_complete INTEGER NOT NULL DEFAULT 0,
    step2_complete INTEGER NOT NULL DEFAULT 0,
    step3_complete INTEGER NOT NULL DEFAULT 0,
    step4_progress TEXT,  -- JSON: which areas walked
    step5_progress TEXT,  -- JSON: which parts counted
    step6_progress TEXT,  -- JSON: which parts have targets
    started_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT,
    updated_at TEXT DEFAULT (datetime('now'))
);
```

## Success Criteria
- [ ] 6-step wizard with progress bar
- [ ] Save & Exit at every step
- [ ] Quick Count mode (skip floor plan)
- [ ] New part creation inline during walk-through
- [ ] AI suggestions for targets in Step 6
- [ ] Onboarding progress persisted to database
- [ ] Completion screen with summary
- [ ] Project builds with no errors
