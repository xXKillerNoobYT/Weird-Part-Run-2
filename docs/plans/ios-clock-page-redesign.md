# iOS Clock Page Redesign

> **Page:** `IOSClockPage.swift` (~580 lines)
> **Nav:** Dashboard → Clock tab
> **Status:** Design CONFIRMED (2026-03-21)

## Current State

The Clock page handles clock in/out with GPS-sorted job selection. Shop/Warehouse is always pinned first. QR scanner for job codes. Questionnaire on clock-out.

### Bugs Fixed
- SQL query used wrong column names (`address` → `address_line1+city`, `latitude/longitude` → `gps_lat/gps_lng`) — committed directly

### Remaining Issues
- `import GRDB` — raw SQL instead of service methods
- `#if os(iOS)` platform guard
- No Lunch/Break/Supply Run buttons (only on Daily Report)
- No elapsed time ticker
- No Switch Job (must clock out/in separately)
- Clock Out button too small

## Design Decisions

### 1. Switch Job (one-action)
When clocked into Job A, a "Switch Job" button shows the job picker. Selecting Job B in one action: clocks out of A → immediately clocks into B. No intermediate state.

### 2. Lunch/Break Timer
- User taps Lunch or Break → Clock OUT (this is off-the-clock time)
- Timer system: user sets duration for the day (15/30/45/60 min picker)
- Timer counts down while on break
- Notification at 5 min remaining
- Notification at 0 min "Break's over!"
- Clock page shows "Clock back in" prompt with timer status
- Duration setting persists for the day (don't ask every time)

### 3. Supply Run (stays clocked in)
- **Different from Lunch/Break** — user stays clocked in, activity state changes
- Manual start: "Start Supply Run" button when clocked in
- Manual stop: "End Supply Run" button when on supply run
- Geofence integration: confirms or corrects geofence detection
  - Geofence detects leaving → prompt: "Supply Run?" [Confirm] [No, Still Working]
  - Geofence detects return → prompt: "Back from Supply Run?" [Yes] [Still Out]
- Removes system false positives by letting user confirm/deny
- Clock keeps running the whole time — supply run is billable time

### 4. Elapsed Time Ticker
- Live "2h 15m" counter next to "Since: 8:14 AM"
- Updates every minute
- Shows on the clocked-in status card

### 5. 15-Minute Rounding (Reports)
- Company setting in Office/Settings
- Rounds clock in/out times to nearest 15 minutes **on reports only**
- Actual database timestamps stay precise (to the second)
- Setting: `clock_rounding_minutes` — default 0 (no rounding), options: 0, 5, 6, 10, 15
- Applied when generating timesheets, labor reports, bookkeeper exports

### 6. Clocked-In UI Layout

```
┌─ Current Status ──────────────────────────┐
│ 🟢 Clocked In                              │
│ Job: Smith Residence (#J-2024-042)         │
│ Since: 8:14 AM  ·  2h 15m elapsed         │
│                                             │
│ ┌──────┐ ┌──────┐ ┌────────────┐           │
│ │ 🍴   │ │ ☕   │ │ 🚚         │           │
│ │Lunch │ │Break │ │Supply Run  │           │
│ └──────┘ └──────┘ └────────────┘           │
│                                             │
│ [🔄 Switch Job]                             │
│ [🔴 Clock Out]                              │
└─────────────────────────────────────────────┘
```

### 7. Supply Run Active UI

```
┌─ Current Status ──────────────────────────┐
│ 🟢 Clocked In — 🚚 Supply Run             │
│ Job: Smith Residence (#J-2024-042)         │
│ Since: 8:14 AM  ·  2h 15m elapsed         │
│ Supply run started: 10:20 AM (9m ago)      │
│                                             │
│ [🚚 End Supply Run]                         │
│ [🔴 Clock Out]                              │
└─────────────────────────────────────────────┘
```

### 8. On Break UI

```
┌─ On Break ────────────────────────────────┐
│ ☕ Break Time                               │
│ Timer: 22 min remaining                    │
│ ████████████░░░░░░░ (73%)                  │
│                                             │
│ [🟢 Clock Back In]                          │
└─────────────────────────────────────────────┘
```

## Technical Notes

- `import GRDB` must be removed — jobs query should go through `JobsService`
- Supply run needs a new field on labor_entries or a new `activity_state` column: "working", "supply_run"
- Break timer uses local notification scheduling (`UNUserNotificationCenter`)
- Elapsed time ticker: `Timer.publish(every: 60)` → `.onReceive()`
- Switch Job: calls `clockOut(entryId:)` then immediately `clockIn(jobId:)` in sequence
- 15-min rounding: `AppSettings` key `clock_rounding_minutes`, applied in report generation service methods only

## 9. Labor Law Compliance — Break/Lunch System

### UPDATED DESIGN: Breaks are PAID time (stay clocked in)

**Previous assumption was wrong.** Breaks and the paid portion of lunch are on-the-clock time. Only the unpaid portion of lunch clocks the user out.

### 4-Tier Break Policy Structure

| Tier | What | Who Controls |
|------|------|-------------|
| 1. State Required — Paid | Minimum breaks the state REQUIRES and employer MUST pay for | Pre-loaded from Dept of Labor data |
| 2. State Required — Offered (Unpaid) | Breaks the state REQUIRES to be offered but not paid | Pre-loaded from Dept of Labor data |
| 3. Company Extra — Paid | Beyond state requirements — company PAYS for this | Company admin edits |
| 4. Company Extra — Offered (Unpaid) | Beyond state requirements — offered but not paid | Company admin edits |

### Bonus System (Tier 5)
- Optional, per area (lunch and breaks tracked separately)
- Rewards employees for sticking to state-level minimums when company offers more
- Example: company offers 60 min paid lunch, state requires 30 min → $5/day bonus for taking only 30 min
- Configured in Office/Settings

### Combined Breakdown (Tier 6)
- Read-only chart showing all tiers combined per area
- Shows: total paid time, total offered time, bonus potential
- Helps employees and managers understand actual entitlements

### State Labor Law Database
- Pre-loaded: all 50 US states + DC
- Source: US Department of Labor
- Date-stamped: "Data as of: [date programmed]"
- Manual backup: company can manually edit if data is wrong/outdated
- User-created: custom entries for special situations
- Future app updates can refresh state data

### Break Budget System
- Breaks per day are per-DAY, not per-job
- User can take more or fewer breaks as long as total time ≤ paid budget
- Example: 2×15 min paid → user can take 3×10 min instead
- Clock keeps running during paid breaks
- Only unpaid lunch portion clocks user out

### Clock-Out Questionnaire — Missed Breaks
- "Did you take your breaks today?" → Yes / Forgot / Partial
- If forgot or partial: checkbox which ones missed
- Report sent to Office for resolution
- If "yes" but no break buttons were hit: auto-fill records at default times for compliance

### Break States on Clock Page
- **Paid break:** Status = "On Break", clock keeps running, counts against daily break budget
- **Paid lunch:** Status = "On Lunch", clock keeps running, counts against paid lunch allocation
- **Unpaid lunch:** Status = "Unpaid Lunch", CLOCKED OUT, timer counts remaining time
- **Transition:** When paid lunch time expires → prompt to clock back in or continue unpaid

## Prompt Chain

| Prompt | What |
|--------|------|
| 25A | Clock cleanup: remove GRDB, service layer, platform guards |
| 25B | Break policy migration: state_labor_laws table, break_policies table, 4-tier settings, seed US state data |
| 25C | Break/Lunch on Clock: paid break state, paid/unpaid lunch transition, break budget tracking |
| 25D | Supply Run state: activity_state field, start/stop, geofence confirm |
| 25E | Switch Job + elapsed ticker + Clock Out redesign |
| 25F | Clock-out questionnaire: missed break detection, office reporting |
| 25G | Break Policy Settings UI: 6 charts, state picker, company overrides, bonuses |
| 25H | 15-min rounding setting (Office/Settings + report services) |
| 25I | Break compliance auto-fill on timesheets/reports |
