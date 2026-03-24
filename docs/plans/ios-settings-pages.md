# iOS Settings Pages — Design Plan

## Navigation (Grouped like iOS Settings)
Settings:
- General (About, Themes, Notifications, App Config)
- Company (Company Profiles, Billing/Pay, PDF, Payment Tracking NEW)
- Operations (Break/Lunch Policy NEW, Tool Policies NEW, Pre-Trip Checklists NEW, Dispatch Preferences NEW)
- Warehouse (Forecast Config NEW, Organization Thresholds NEW, Audit Settings NEW)
- Sync & Devices (Sync, Bluetooth, Device Management, Bootstrap)
- Security (Security Admin, Key Management, Audit Log)
- Data (Backups, Export, Database Reset)
- AI & Integrations (AI Config, Integrations, Supplier Bridge)
- Templates (Daily Reports NEW, Job Estimation Questions NEW, Report Templates NEW, Clock-Out Questions)
- Advanced (Update Protocol, Remote Sync, Shared Channels)

## Key Design Decisions

### Settings Search
iOS-style search at top of settings list. Type "Bluetooth" → jumps to that page. Searches page names and key setting labels.

### Settings Sync Rules
- Company settings → sync to ALL devices (break policy, billing, tool policies, etc.)
- Personal settings → sync to user's devices only (themes, notifications)
- Device settings → DO NOT sync (device name, Bluetooth, local paths)

### 8 Simulated Features → Make Functional
- Backups: real file I/O, actual SQLite copy
- Data Export: real CSV/JSON file writing with share sheet
- Update Protocol: check bootstrap server for updates
- AI Config: actual Foundation Models availability detection
- Sync Now: real sync attempt when sync is configured

### New Settings Pages Needed (from design sessions)
1. Break/Lunch Policy: 4-tier state/company, bonuses, auto-fill, state presets
2. Forecast Settings: per-location ADU/APW, multipliers, free space ratings
3. Payment Tracking: enable/disable, terms default, overdue threshold
4. Dispatch Preferences: AI dispatch toggles, flex pool permissions, pipeline targets
5. Pre-Trip Checklist: customizable items per vehicle/trailer type
6. Tool Policies: max checkout duration, overdue notification, auto-maintenance, trade timeout
7. Warehouse Thresholds: confidence decay rates, audit frequency, organization targets
8. Daily Report Templates: office-configurable report sections and format
9. Job Estimation Questions: question groups with stage awareness, AI learning toggles
10. Report Templates: saved custom report configurations

### Code Quality
Settings is architecturally clean — no GRDB, all service-based. No bugs to fix, just design enhancement and new pages.

---

## Detailed Wireframes — New Pages

### 1. Break/Lunch Policy (Operations → Break/Lunch Policy)

4-tier system covering state-mandated and company-optional breaks/lunches. State presets auto-fill labor law minimums. Bonus section incentivizes workers to take exactly the state minimum (no more).

```
┌─ Break/Lunch Policy ─────────────────────────────────────────────────┐
│                                                                       │
│  ┌─ State Compliance ──────────────────────────────────────────────┐  │
│  │  State: [California              ▼]                             │  │
│  │  Source: US Dept of Labor, as of 2026-01-15                     │  │
│  │  [🔄 Update Data]  [✏️ Manual Edit]                             │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌─ Standard Work Day (8 hr) ──────────────────────────────────────┐  │
│  │                                                                   │ │
│  │  TIER 1: State Required — Paid                                    │ │
│  │  ┌──────────────────────────────────────────────────────────┐     │ │
│  │  │  Lunch Duration       [30 min         [-][+]]            │     │ │
│  │  │  Break Count          [2              [-][+]]            │     │ │
│  │  │  Break Duration       [10 min         [-][+]]            │     │ │
│  │  └──────────────────────────────────────────────────────────┘     │ │
│  │                                                                   │ │
│  │  TIER 2: State Required — Offered (Unpaid)                        │ │
│  │  ┌──────────────────────────────────────────────────────────┐     │ │
│  │  │  Lunch Duration       [  0 min        [-][+]]            │     │ │
│  │  │  Break Count          [0              [-][+]]            │     │ │
│  │  │  Break Duration       [  0 min        [-][+]]            │     │ │
│  │  └──────────────────────────────────────────────────────────┘     │ │
│  │                                                                   │ │
│  │  TIER 3: Company Extra — Paid                                     │ │
│  │  ┌──────────────────────────────────────────────────────────┐     │ │
│  │  │  Lunch Duration       [  0 min        [-][+]]            │     │ │
│  │  │  Break Count          [1              [-][+]]            │     │ │
│  │  │  Break Duration       [15 min         [-][+]]            │     │ │
│  │  └──────────────────────────────────────────────────────────┘     │ │
│  │                                                                   │ │
│  │  TIER 4: Company Extra — Offered (Unpaid)                         │ │
│  │  ┌──────────────────────────────────────────────────────────┐     │ │
│  │  │  Lunch Duration       [  0 min        [-][+]]            │     │ │
│  │  │  Break Count          [0              [-][+]]            │     │ │
│  │  │  Break Duration       [  0 min        [-][+]]            │     │ │
│  │  └──────────────────────────────────────────────────────────┘     │ │
│  └───────────────────────────────────────────────────────────────────┘│
│                                                                       │
│  ┌─ Extended Work Day (10 hr) ─────────────────────────────────────┐  │
│  │  (Same 4-tier layout as above, separate values)                  │ │
│  │  Tier 1: Lunch [30 min]  Breaks [3 × 10 min]                    │ │
│  │  Tier 2: ...                                                     │ │
│  │  Tier 3: ...                                                     │ │
│  │  Tier 4: ...                                                     │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Combined Totals Chart ─────────────────────────────────────────┐  │
│  │                         8-hr Day    10-hr Day                    │ │
│  │  Paid Lunch             30 min      30 min                      │ │
│  │  Unpaid Lunch            0 min       0 min                      │ │
│  │  Paid Breaks        3 × 10 min  4 × 10 min                     │ │
│  │  Unpaid Breaks           0 min       0 min                      │ │
│  │  ──────────────────────────────────────────                      │ │
│  │  Total Paid Break Time  60 min      70 min                      │ │
│  │  Total Unpaid Time       0 min       0 min                      │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Bonuses ───────────────────────────────────────────────────────┐  │
│  │  Reward workers for sticking to state minimums                   │ │
│  │                                                                   │ │
│  │  Lunch Bonus                                                     │ │
│  │  Reward if lunch ≤ state minimum  [🔘 ON ]                      │ │
│  │  Bonus amount per day             [$5.00       ]                 │ │
│  │                                                                   │ │
│  │  Break Bonus                                                     │ │
│  │  Reward if breaks ≤ state minimum [🔘 ON ]                      │ │
│  │  Bonus amount per day             [$3.00       ]                 │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Report Settings ──────────────────────────────────────────────┐   │
│  │  Auto-fill breaks on reports        [🔘 ON ]                    │  │
│  │                                                                  │  │
│  │  Default Break Times                                             │  │
│  │    Morning break    [10:00 AM     ]                              │  │
│  │    Lunch            [12:00 PM     ]                              │  │
│  │    Afternoon break  [ 3:00 PM     ]                              │  │
│  │                                                                  │  │
│  │  15-minute rounding for reports     [🔘 OFF]                    │  │
│  │  ℹ️ Rounds clock times on reports only. Actual DB times stay     │  │
│  │    precise to the second.                                        │  │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

**State picker presets:** All 50 US states pre-loaded with labor law defaults. Selecting a state auto-fills Tier 1 and Tier 2 with that state's legal minimums. Company tiers (3 & 4) always start at zero. Each preset is date-stamped with the source date.

---

### 2. Tool Policies (Operations → Tool Policies)

Company-wide rules for tool checkout, maintenance cycles, and trade/lost workflows. All settings sync company-wide.

```
┌─ Tool Policies ──────────────────────────────────────────────────────┐
│                                                                       │
│  ┌─ Checkout Rules ────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Max checkout duration            [30 days      [-][+]]         │  │
│  │  ℹ️ Tools checked out longer than this are flagged overdue.      │  │
│  │                                                                  │  │
│  │  Overdue notification after       [ 7 days      [-][+]]         │  │
│  │  ℹ️ Days after due date before notifying manager.                │  │
│  │                                                                  │  │
│  │  Require condition check on checkout  [🔘 ON ]                  │  │
│  │  ℹ️ Worker must rate tool condition before taking it.            │  │
│  │                                                                  │  │
│  │  Require condition check on return    [🔘 ON ]                  │  │
│  │  ℹ️ Worker must rate tool condition when returning it.           │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Maintenance ───────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Auto-schedule maintenance after  [20 checkouts [-][+]]         │  │
│  │  ℹ️ Tool is flagged for maintenance after this many uses.        │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Trades ────────────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Trade request timeout            [ 7 days      [-][+]]         │  │
│  │  ℹ️ Pending trade requests auto-expire after this period.        │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Lost/Stolen Reporting ─────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Company-owned tools                                             │  │
│  │  ℹ️ Manager decides outcome (replace, charge, write off).        │  │
│  │                                                                  │  │
│  │  Personal tools                                                  │  │
│  │  ℹ️ Owner decides. Company tracks for insurance purposes only.   │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Permissions ───────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Edit tool details without permission  [🔘 OFF]                 │  │
│  │  ℹ️ When OFF, edits create a "pending verification" record       │  │
│  │    that a manager must approve. Prevents unauthorized changes    │  │
│  │    to tool values, serial numbers, or ownership.                 │  │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

---

### 3. Pre-Trip Checklist Config (Operations → Pre-Trip Checklists)

Customizable inspection checklists per vehicle and trailer type. Sections are expandable/collapsible. Items can be reordered via drag handles.

```
┌─ Pre-Trip Checklist Config ──────────────────────────────────────────┐
│                                                                       │
│  ┌─ Vehicle/Trailer Type ──────────────────────────────────────────┐  │
│  │  [🚛 Vehicles ▼]  [🚚 Trailers]                                │  │
│  │                                                                  │  │
│  │  Vehicle Type: [Pickup Truck        ▼]                          │  │
│  │  [📋 Copy from another type...]                                 │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ ▼ Exterior ────────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  ☰  [Tires & Wheels                    ]  Required [🔘 ON ]    │  │
│  │  ☰  [Lights — headlights, tail, turn   ]  Required [🔘 ON ]    │  │
│  │  ☰  [Mirrors — side & rear             ]  Required [🔘 ON ]    │  │
│  │  ☰  [Body damage / dents               ]  Required [🔘 OFF]    │  │
│  │  ☰  [Fluid leaks under vehicle         ]  Required [🔘 ON ]    │  │
│  │  ☰  [License plate visible & current   ]  Required [🔘 ON ]    │  │
│  │                                                                  │  │
│  │  [+ Add Exterior Item]                                          │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ ▶ Interior (6 items) ─────────────────────────────── collapsed ┐  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ ▶ Equipment (4 items) ────────────────────────────── collapsed ┐  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Tie-In ────────────────────────────────────────────────────────┐  │
│  │  ℹ️ Pre-trip inspection is prompted during clock-in when a       │  │
│  │    vehicle is assigned. Workers complete the checklist before    │  │
│  │    their shift begins.                                           │  │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

**Trailer tab:** Identical layout but with trailer-specific defaults (hitch, chains, load securement, trailer lights, ramp/gate).

---

### 4. Dispatch Preferences (Operations → Dispatch Preferences)

Controls how the AI dispatch system suggests crew assignments and how flex pool workers can self-assign.

```
┌─ Dispatch Preferences ──────────────────────────────────────────────┐
│                                                                       │
│  ┌─ AI Dispatch ───────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  AI dispatch suggestions             [🔘 ON ]                  │  │
│  │  ℹ️ AI recommends crew assignments based on skills, location,    │  │
│  │    job history, and GC preferences.                              │  │
│  │                                                                  │  │
│  │  AI learning from dispatcher picks   [🔘 ON ]                  │  │
│  │  ℹ️ AI observes which suggestions dispatchers accept/reject      │  │
│  │    and adjusts future recommendations. Requires 30+ dispatches   │  │
│  │    to become effective.                                          │  │
│  │                                                                  │  │
│  │  Suggestion count                    [ 3           [-][+]]      │  │
│  │  ℹ️ Number of crew options AI presents per dispatch slot.        │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Flex Pool ─────────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Flex pool self-assign for workers   [🔘 OFF]                  │  │
│  │  ℹ️ When ON, workers with the "flex_dispatch" hat permission     │  │
│  │    can claim open jobs from the dispatch board themselves.        │  │
│  │    When OFF, only dispatchers can assign.                        │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Pipeline Targets ─────────────────────────────────────────────┐   │
│  │  ℹ️ Minimum jobs to keep in each pipeline stage. Dispatch board  │  │
│  │    warns when counts drop below these thresholds.                │  │
│  │                                                                  │  │
│  │  "Start Anytime" minimum            [ 3           [-][+]]      │  │
│  │  "Schedule Needed" minimum          [ 2           [-][+]]      │  │
│  │  Favorite GC jobs in pipeline       [ 1           [-][+]]      │  │
│  │  ℹ️ Ensure at least N jobs from preferred GCs are queued.        │  │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

---

### 5. Forecast Config (Warehouse → Forecast Config)

Per-location-type forecasting parameters. Controls how MIN/TARGET/MAX stock levels are calculated.

```
┌─ Forecast Config ────────────────────────────────────────────────────┐
│                                                                       │
│  ┌─ Location Type ─────────────────────────────────────────────────┐  │
│  │  [🏭 Shop]  [🚛 Truck]  [🚚 Trailer]                          │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ════════════════════ Showing: 🏭 Shop ═════════════════════════════  │
│                                                                       │
│  ┌─ Usage Calculation ─────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Usage unit                          Daily (ADU)                │  │
│  │  ℹ️ Shop uses Average Daily Usage. Trucks/trailers use           │  │
│  │    Average Per-Week (APW).                                       │  │
│  │                                                                  │  │
│  │  Lookback period                    [365 days     [-][+]]       │  │
│  │  ℹ️ How far back to look when calculating usage rates.           │  │
│  │                                                                  │  │
│  │  Minimum data required              [ 90 days     [-][+]]       │  │
│  │  ℹ️ Parts with less history than this won't get forecasts.       │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Stock Level Multipliers ───────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Common Parts (regular usage)                                    │  │
│  │    MIN  =  ADU ×  [ 7 days          [-][+]]                    │  │
│  │    TGT  =  ADU ×  [14 days          [-][+]]                    │  │
│  │    MAX  =  ADU ×  [30 days          [-][+]]                    │  │
│  │                                                                  │  │
│  │  Critical Parts (cannot run out)                                 │  │
│  │    MIN  =  ADU ×  [14 days          [-][+]]                    │  │
│  │    TGT  =  ADU ×  [30 days          [-][+]]                    │  │
│  │    MAX  =  ADU ×  [60 days          [-][+]]                    │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Free Space Suppression ────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Suppress threshold                 [ 3 / 10      [-][+]]      │  │
│  │  ℹ️ Don't suggest adding parts to a location if its free         │  │
│  │    space rating is at or below this value.                       │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Recommendation Settings ──────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  Max recommendations per day        [ 1           [-][+]]      │  │
│  │  ℹ️ Limits daily recommendation notifications to prevent         │  │
│  │    alert fatigue.                                                │  │
│  │                                                                  │  │
│  │  Recommendation cooldown            [60 days      [-][+]]      │  │
│  │  ℹ️ After dismissing a recommendation, don't suggest the same    │  │
│  │    part again for this period.                                   │  │
│  │                                                                  │  │
│  │  Auto-approve threshold             [80 %         [-][+]]      │  │
│  │  ℹ️ Recommendations above this certainty level are auto-         │  │
│  │    approved without manager review.                              │  │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

**Tab switching:** Truck tab shows APW-based multipliers with shorter defaults (lookback 180d, min data 60d). Trailer tab mirrors truck but with separate values.

---

### 6. Warehouse Organization Thresholds (Warehouse → Organization Thresholds)

Controls the confidence system, consolidation voting, and misplacement penalties that drive warehouse self-organization.

```
┌─ Warehouse Organization Thresholds ──────────────────────────────────┐
│                                                                       │
│  ┌─ Confidence Settings ──────────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  Base decay rate                     0.2% / day  (calculated)   │  │
│  │  ℹ️ Confidence decays automatically. Not editable — derived      │  │
│  │    from audit frequency and part movement patterns.              │  │
│  │                                                                  │  │
│  │  Audit trigger threshold            [80 %         [-][+]]      │  │
│  │  ℹ️ Areas below this confidence get flagged for full audit.      │  │
│  │                                                                  │  │
│  │  Quick audit prompt threshold       [85 %         [-][+]]      │  │
│  │  ℹ️ Areas below this but above audit trigger get "quick          │  │
│  │    check" prompts when workers pass through.                     │  │
│  │                                                                  │  │
│  │  New part starting confidence        50%          (fixed)       │  │
│  │  ℹ️ Newly added parts start at 50% confidence until audited.     │  │
│  │                                                                  │  │
│  │  Audit confidence boost              +55%         (fixed)       │  │
│  │  ℹ️ A successful audit boosts the area to ~100% confidence       │  │
│  │    (capped at 100%).                                             │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Organization Settings ────────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  Consolidation voting timeout       [ 7 days      [-][+]]      │  │
│  │  ℹ️ How long a consolidation suggestion stays open for           │  │
│  │    warehouse team to vote on before auto-resolving.              │  │
│  │                                                                  │  │
│  │  Escalation after ignored           [ 3 times     [-][+]]      │  │
│  │  ℹ️ If a suggestion is ignored N times, escalate to manager.     │  │
│  │                                                                  │  │
│  │  Common → Critical threshold        [ 6 months    [-][+]]      │  │
│  │  ℹ️ Parts unused for this long are flagged as candidates for     │  │
│  │    reclassification from common to critical review.              │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Misplacement Settings ────────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  Decay multiplier for misplaced     [ 1.5×        [-][+]]      │  │
│  │  ℹ️ Parts found in wrong locations decay confidence faster       │  │
│  │    by this multiplier.                                           │  │
│  │                                                                  │  │
│  │  Movement decay factor              [🔘 ON ]                   │  │
│  │  Movement decay amount              [ 2 %         [-][+]]      │  │
│  │  ℹ️ Each time a part is moved, reduce confidence by this         │  │
│  │    amount (moving increases uncertainty).                        │  │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

---

### 7. Audit Settings (Warehouse → Audit Settings)

Controls automated audit scheduling, multi-user verification rules, and the onboarding progression system.

```
┌─ Audit Settings ─────────────────────────────────────────────────────┐
│                                                                       │
│  ┌─ Automation ────────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Auto-audit scheduling              [🔘 ON ]                   │  │
│  │  ℹ️ System automatically schedules audits for areas that fall     │  │
│  │    below the confidence threshold.                               │  │
│  │                                                                  │  │
│  │  Speed mode                                                      │  │
│  │  ℹ️ Activates automatically when warehouse areas have QR codes   │  │
│  │    assigned. Workers scan QR → confirm contents → audit done.    │  │
│  │    No manual configuration needed.                               │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Verification ─────────────────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  Multi-user verification            [🔘 ON ]                   │  │
│  │  ℹ️ When ON, audits for low-confidence areas require a second    │  │
│  │    person to verify counts.                                      │  │
│  │                                                                  │  │
│  │  Multi-user threshold               [60 %         [-][+]]      │  │
│  │  ℹ️ Parts below this confidence level require 2-person audit.    │  │
│  │    Parts above this can be audited solo.                         │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Penalties ─────────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Misplacement penalty               [ 1.5× decay  [-][+]]      │  │
│  │  ℹ️ When an audit discovers parts in wrong locations,            │  │
│  │    confidence decays at this multiplied rate.                     │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Notifications ────────────────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  Monthly free space notification    [🔘 ON ]                   │  │
│  │  ℹ️ Monthly reminder showing free space ratings across all       │  │
│  │    warehouse areas. Helps identify overcrowded zones.            │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Onboarding Progress ──────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  Current Level: Level 3 of 5                                    │  │
│  │  ████████████████░░░░░░░░  60%                                  │  │
│  │                                                                  │  │
│  │  ✅ Level 1: Basic inventory entry                               │  │
│  │  ✅ Level 2: Bin locations assigned                               │  │
│  │  ✅ Level 3: QR codes deployed                                    │  │
│  │  ⬜ Level 4: First full audit complete                            │  │
│  │  ⬜ Level 5: Confidence system active (30+ days data)             │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Danger Zone ───────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  [🗑️ Reset Warehouse Organization Data]                         │  │
│  │  ℹ️ Clears all confidence scores, audit history, and             │  │
│  │    organization suggestions. Inventory data is NOT affected.     │  │
│  │    This cannot be undone.                                        │  │
│  │                                                                  │  │
│  │  ⚠️ Requires typing "RESET" to confirm.                          │  │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

---

### 8. Daily Report Templates (Templates → Daily Reports)

Office staff configure what sections appear in daily reports and how AI compiles them.

```
┌─ Daily Report Templates ─────────────────────────────────────────────┐
│                                                                       │
│  ┌─ Template List ─────────────────────────────────────────────────┐  │
│  │                                                                  │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │  │
│  │  │  ⭐ Standard Daily Report                     [Default]    │  │  │
│  │  │  Full report with all sections · 10 sections              │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │  │
│  │  │  Quick Summary                                             │  │  │
│  │  │  Time + work completed only · 3 sections                  │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │  │
│  │  │  Safety-Focus Report                                       │  │  │
│  │  │  Adds safety observations section · 7 sections            │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │                                                                  │  │
│  │  [+ New Template]                                               │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ════════════ Template Editor: Standard Daily Report ════════════════  │
│                                                                       │
│  ┌─ Sections (drag ☰ to reorder) ─────────────────────────────────┐  │
│  │                                                                  │  │
│  │  ☰  [🔘 ON ]  Time Summary                                     │  │
│  │  ☰  [🔘 ON ]  Work Completed                                   │  │
│  │  ☰  [🔘 ON ]  In Progress                                      │  │
│  │  ☰  [🔘 ON ]  Parts Used                                       │  │
│  │  ☰  [🔘 ON ]  Q&A                                              │  │
│  │  ☰  [🔘 ON ]  Issues                                           │  │
│  │  ☰  [🔘 ON ]  User Notes                                       │  │
│  │  ☰  [🔘 OFF]  Safety Observations                              │  │
│  │  ☰  [🔘 OFF]  Weather                                          │  │
│  │  ☰  [🔘 ON ]  Equipment Used                                   │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ AI Compilation Instructions ──────────────────────────────────┐   │
│  │                                                                  │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │  │
│  │  │  Summarize work completed in bullet points. Group by       │  │  │
│  │  │  area (e.g. rough-in, trim). Flag any safety concerns.     │  │  │
│  │  │  Keep total report under 500 words.                        │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │  ℹ️ These instructions guide AI when auto-compiling reports      │  │
│  │    from clock entries, Q&A responses, and notes.                 │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  [👁️ Preview]  [💾 Save]                                             │
└───────────────────────────────────────────────────────────────────────┘
```

---

### 9. Job Estimation Questions (Templates → Job Estimation Questions)

Question groups organized by the stage at which they become known. Each group contains typed questions that feed into job estimation AI.

```
┌─ Job Estimation Questions ───────────────────────────────────────────┐
│                                                                       │
│  ┌─ Question Groups ──────────────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │  │
│  │  │  📋 Bid Stage Questions                                    │  │  │
│  │  │  Known at: Bid · 8 questions                              │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │  │
│  │  │  📋 Pre-Start Questions                                    │  │  │
│  │  │  Known at: Pre-start · 5 questions                        │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │  │
│  │  │  📋 During-Job Questions                                   │  │  │
│  │  │  Known at: During · 3 questions                           │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │  │
│  │  │  📋 Punch List Questions                                   │  │  │
│  │  │  Known at: Punch List · 2 questions                       │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │                                                                  │  │
│  │  [+ Add Group]                                                  │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ═══════════════ Editing: Bid Stage Questions ═══════════════════════  │
│                                                                       │
│  ┌─ Questions (drag ☰ to reorder) ────────────────────────────────┐  │
│  │                                                                  │  │
│  │  ☰  1. [Square footage of work area          ]                  │  │
│  │        Type: [Number     ▼]  Required [🔘 ON ]                  │  │
│  │                                                                  │  │
│  │  ☰  2. [Number of stories                    ]                  │  │
│  │        Type: [Number     ▼]  Required [🔘 ON ]                  │  │
│  │                                                                  │  │
│  │  ☰  3. [Construction type                    ]                  │  │
│  │        Type: [Picker     ▼]  Required [🔘 ON ]                  │  │
│  │        Options: New Build, Remodel, Renovation, Addition        │  │
│  │                                                                  │  │
│  │  ☰  4. [Union job?                           ]                  │  │
│  │        Type: [Toggle     ▼]  Required [🔘 OFF]                  │  │
│  │                                                                  │  │
│  │  ☰  5. [Special conditions / notes           ]                  │  │
│  │        Type: [Text       ▼]  Required [🔘 OFF]                  │  │
│  │                                                                  │  │
│  │  ...                                                             │  │
│  │                                                                  │  │
│  │  [+ Add Question]                                               │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ AI Smart Questions ───────────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  Smart Questions                    [🔘 OFF]                   │  │
│  │  ℹ️ AI analyzes completed jobs to suggest new questions that     │  │
│  │    correlate with estimation accuracy. Requires 15+ completed   │  │
│  │    jobs with estimation data.                                    │  │
│  │                                                                  │  │
│  │  Status: 8 of 15 jobs needed                                    │  │
│  │  ████████░░░░░░░░  53%                                          │  │
│  │                                                                  │  │
│  │  ┌─ Rejected Suggestions ──────────────────────────────────┐    │  │
│  │  │  (none yet)                                              │    │  │
│  │  │  ℹ️ Suggestions you dismiss appear here. Tap [Reconsider] │   │  │
│  │  │    to bring one back.                                    │    │  │
│  │  └─────────────────────────────────────────────────────────┘    │  │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

---

### 10. Report Templates (Templates → Report Templates)

Saved custom report configurations that can be shared across the team and launched with one tap.

```
┌─ Report Templates ───────────────────────────────────────────────────┐
│                                                                       │
│  ┌─ Saved Templates ──────────────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │  │
│  │  │  📊 Weekly Labor Summary                                   │  │  │
│  │  │  Type: Labor Report · 6 fields · Last used: Mar 20        │  │  │
│  │  │  👥 Shared with team                                       │  │  │
│  │  │  [▶ Run Report]  [✏️ Edit]  [🗑️]                           │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │  │
│  │  │  📊 Monthly Parts Usage                                    │  │  │
│  │  │  Type: Inventory Report · 8 fields · Last used: Mar 15    │  │  │
│  │  │  🔒 Personal                                               │  │  │
│  │  │  [▶ Run Report]  [✏️ Edit]  [🗑️]                           │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │  │
│  │  │  📊 Job Cost Rollup — Active Jobs                          │  │  │
│  │  │  Type: Cost Report · 12 fields · Last used: Mar 18        │  │  │
│  │  │  👥 Shared with team                                       │  │  │
│  │  │  [▶ Run Report]  [✏️ Edit]  [🗑️]                           │  │  │
│  │  └────────────────────────────────────────────────────────────┘  │  │
│  │                                                                  │  │
│  │  [+ Create Template]                                            │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ══════════════ Template Editor: Weekly Labor Summary ════════════════ │
│                                                                       │
│  ┌─ Report Type ──────────────────────────────────────────────────┐   │
│  │  Type: [Labor Report            ▼]                              │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Fields (check to include) ────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  ☑️  Employee Name                                               │  │
│  │  ☑️  Job Name                                                    │  │
│  │  ☑️  Hours Worked                                                │  │
│  │  ☑️  Overtime Hours                                              │  │
│  │  ☑️  Break Time                                                  │  │
│  │  ☑️  Pay Rate                                                    │  │
│  │  ⬜  GPS Coordinates                                             │  │
│  │  ⬜  Clock-In Method (QR/GPS/Manual)                             │  │
│  │  ⬜  Questionnaire Responses                                     │  │
│  │  ⬜  Notes                                                       │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Default Filters ──────────────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  Date Range:  [Last 7 Days       ▼]                             │  │
│  │  Job Filter:  [All Active Jobs   ▼]                             │  │
│  │  Employee:    [All Employees     ▼]                             │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─ Sharing ──────────────────────────────────────────────────────┐   │
│  │                                                                  │  │
│  │  Share with team                    [🔘 ON ]                   │  │
│  │  ℹ️ When ON, all office users can see and run this template.     │  │
│  │    When OFF, only you can see it.                                │  │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  [💾 Save]  [▶ Run Report]                                           │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Settings Sync Scope Reference

Every setting falls into one of three sync scopes:
- **Company** = syncs to ALL devices via `_change_log`
- **Personal** = syncs to the current user's devices only
- **Device** = stays on this device, never syncs

### 1. Break/Lunch Policy

| Setting | Scope | Sync |
|---------|-------|------|
| Selected state | Company | Sync to all |
| State labor law data cache | Company | Sync to all |
| Tier 1 (State Required Paid) — all fields | Company | Sync to all |
| Tier 2 (State Required Offered) — all fields | Company | Sync to all |
| Tier 3 (Company Extra Paid) — all fields | Company | Sync to all |
| Tier 4 (Company Extra Offered) — all fields | Company | Sync to all |
| Standard vs Extended day configs | Company | Sync to all |
| Lunch bonus enabled | Company | Sync to all |
| Lunch bonus amount | Company | Sync to all |
| Break bonus enabled | Company | Sync to all |
| Break bonus amount | Company | Sync to all |
| Auto-fill breaks on reports | Company | Sync to all |
| Default break times (morning/lunch/afternoon) | Company | Sync to all |
| 15-minute rounding for reports | Company | Sync to all |

### 2. Tool Policies

| Setting | Scope | Sync |
|---------|-------|------|
| Max checkout duration | Company | Sync to all |
| Overdue notification days | Company | Sync to all |
| Require condition check on checkout | Company | Sync to all |
| Require condition check on return | Company | Sync to all |
| Auto-maintenance after X checkouts | Company | Sync to all |
| Trade request timeout | Company | Sync to all |
| Edit-without-permission toggle | Company | Sync to all |

### 3. Pre-Trip Checklist Config

| Setting | Scope | Sync |
|---------|-------|------|
| Checklist items per vehicle type | Company | Sync to all |
| Checklist items per trailer type | Company | Sync to all |
| Item required toggles | Company | Sync to all |
| Item sort order | Company | Sync to all |
| Section definitions (Exterior/Interior/Equipment) | Company | Sync to all |

### 4. Dispatch Preferences

| Setting | Scope | Sync |
|---------|-------|------|
| AI dispatch suggestions toggle | Company | Sync to all |
| AI learning from dispatcher picks | Company | Sync to all |
| Suggestion count | Company | Sync to all |
| Flex pool self-assign toggle | Company | Sync to all |
| Pipeline target: Start Anytime minimum | Company | Sync to all |
| Pipeline target: Schedule Needed minimum | Company | Sync to all |
| Pipeline target: Favorite GC in pipeline | Company | Sync to all |

### 5. Forecast Config

| Setting | Scope | Sync |
|---------|-------|------|
| Usage unit per location type (ADU/APW) | Company | Sync to all |
| Lookback period per location type | Company | Sync to all |
| Minimum data required per location type | Company | Sync to all |
| Common parts multipliers (MIN/TGT/MAX) per type | Company | Sync to all |
| Critical parts multipliers (MIN/TGT/MAX) per type | Company | Sync to all |
| Free space suppress threshold | Company | Sync to all |
| Max recommendations per day | Company | Sync to all |
| Recommendation cooldown | Company | Sync to all |
| Auto-approve threshold | Company | Sync to all |

### 6. Warehouse Organization Thresholds

| Setting | Scope | Sync |
|---------|-------|------|
| Audit trigger threshold | Company | Sync to all |
| Quick audit prompt threshold | Company | Sync to all |
| Consolidation voting timeout | Company | Sync to all |
| Escalation after ignored suggestions | Company | Sync to all |
| Common to Critical threshold | Company | Sync to all |
| Decay multiplier for misplaced parts | Company | Sync to all |
| Movement decay factor toggle | Company | Sync to all |
| Movement decay amount | Company | Sync to all |

### 7. Audit Settings

| Setting | Scope | Sync |
|---------|-------|------|
| Auto-audit toggle | Company | Sync to all |
| Multi-user verification toggle | Company | Sync to all |
| Multi-user threshold | Company | Sync to all |
| Misplacement penalty multiplier | Company | Sync to all |
| Monthly free space notification | Company | Sync to all |
| Onboarding level progress | Company | Sync to all |

### 8. Daily Report Templates

| Setting | Scope | Sync |
|---------|-------|------|
| Template list (names, descriptions) | Company | Sync to all |
| Default template selection | Company | Sync to all |
| Section enable/disable per template | Company | Sync to all |
| Section sort order per template | Company | Sync to all |
| AI compilation instructions per template | Company | Sync to all |

### 9. Job Estimation Questions

| Setting | Scope | Sync |
|---------|-------|------|
| Question groups (names, stages) | Company | Sync to all |
| Questions (text, type, required, sort order) | Company | Sync to all |
| Smart Questions toggle | Company | Sync to all |
| Rejected suggestions list | Company | Sync to all |

### 10. Report Templates

| Setting | Scope | Sync |
|---------|-------|------|
| Shared templates (shared=true) | Company | Sync to all |
| Personal templates (shared=false) | Personal | Sync to user's devices |
| Template fields and filters | Same as parent template | Matches template scope |
| Last used date | Device | No sync |

### Cross-Reference: Existing Settings Scopes

| Page | Setting Examples | Scope | Sync |
|------|-----------------|-------|------|
| About | App version, build | Device | No sync |
| Themes | Dark mode, accent color | Personal | Sync to user's devices |
| Notifications | Sound, vibration, quiet hours | Personal | Sync to user's devices |
| App Config | Language, date format | Personal | Sync to user's devices |
| Company Profiles | Company name, address, logo | Company | Sync to all |
| Billing/Pay | Pay periods, OT rules | Company | Sync to all |
| PDF | Logo, header, footer text | Company | Sync to all |
| Payment Tracking | Enable, terms, overdue threshold | Company | Sync to all |
| Sync | Sync interval, server URL | Device | No sync |
| Bluetooth | BT enabled, device name | Device | No sync |
| Device Management | Device list, pairing | Device | No sync |
| Security Admin | Password policy, 2FA | Company | Sync to all |
| Key Management | PGP keys, certificates | Device | No sync |
| Audit Log | View-only, retention period | Company | Sync to all |
| Backups | Backup path, schedule | Device | No sync |
| Export | Export format preferences | Personal | Sync to user's devices |
| Database Reset | Reset options | Device | No sync |
| AI Config | Model selection, API keys | Device | No sync |
| Integrations | Connected services | Company | Sync to all |
| Supplier Bridge | Supplier API configs | Company | Sync to all |
| Clock-Out Questions | Question list, required flags | Company | Sync to all |
| Update Protocol | Update server URL | Device | No sync |
| Remote Sync | Remote server config | Device | No sync |
| Shared Channels | Channel subscriptions | Company | Sync to all |
