# 38A — Break/Lunch Labor Compliance System

> **Chain position:** **38A** → 38B
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

Full break/lunch compliance system per the Clock page design review. See `docs/plans/ios-warehouse-pages.md` is NOT the right plan — this was discussed in the conversation. Key design:

- 4-tier system: State Required Paid, State Required Offered (Unpaid), Company Extra Paid, Company Extra Offered
- State labor law presets (all 50 US states, date-stamped)
- Bonuses for sticking to state minimums
- Break = PAID (on the clock, status change only). Lunch has paid + unpaid portions.
- Supply Run = different from break (stays clocked in, activity status change)
- Clock-out questionnaire asks about missed breaks
- 15-minute rounding on reports (company setting)

## Task

### Migration: break_policies
```sql
CREATE TABLE break_policies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    state_code TEXT,  -- 'WY', 'CO', etc. NULL for company custom
    policy_type TEXT NOT NULL,  -- 'state_required_paid', 'state_required_offered', 'company_extra_paid', 'company_extra_offered'
    work_day_hours INTEGER NOT NULL DEFAULT 8,
    lunch_minutes INTEGER NOT NULL DEFAULT 30,
    break_count INTEGER NOT NULL DEFAULT 2,
    break_minutes INTEGER NOT NULL DEFAULT 15,
    data_source TEXT,  -- 'us_dept_of_labor', 'manual', 'custom'
    data_date TEXT,  -- when the data was last verified
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Migration: break_bonuses
```sql
CREATE TABLE break_bonuses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    policy_id INTEGER NOT NULL REFERENCES break_policies(id),
    bonus_type TEXT NOT NULL,  -- 'short_lunch', 'skip_break'
    bonus_amount REAL NOT NULL DEFAULT 0.0,
    description TEXT,
    is_enabled INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Migration: break_records
```sql
CREATE TABLE break_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    labor_entry_id INTEGER REFERENCES labor_entries(id),
    break_type TEXT NOT NULL,  -- 'lunch_paid', 'lunch_unpaid', 'break', 'supply_run'
    started_at TEXT NOT NULL,
    ended_at TEXT,
    duration_minutes INTEGER,
    is_paid INTEGER NOT NULL DEFAULT 1,
    auto_filled INTEGER NOT NULL DEFAULT 0,  -- generated for compliance, not user-triggered
    timer_duration_minutes INTEGER,  -- what the user set for their timer
    created_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Migration: company_break_settings
```sql
CREATE TABLE company_break_settings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    state_code TEXT NOT NULL DEFAULT 'WY',
    rounding_minutes INTEGER NOT NULL DEFAULT 15,  -- round clock in/out on REPORTS only
    rounding_enabled INTEGER NOT NULL DEFAULT 0,
    auto_fill_breaks INTEGER NOT NULL DEFAULT 1,  -- generate break records for compliance
    default_morning_break TEXT DEFAULT '10:00',
    default_lunch TEXT DEFAULT '12:00',
    default_afternoon_break TEXT DEFAULT '14:30',
    updated_at TEXT DEFAULT (datetime('now'))
);
```

### Seed State Data
Pre-load Wyoming labor law defaults:
- State required paid: 30 min lunch + 2×15 min breaks per 8hr day
- Mark data_source as 'us_dept_of_labor', data_date as current date

### Service Methods (JobsService or new BreakService)
- `getBreakPolicy(stateCode:dayHours:)` → combined 4-tier policy
- `getBreakBonuses(policyId:)` → [BreakBonus]
- `startBreak(userId:type:timerMinutes:)` → BreakRecord
- `endBreak(recordId:)` → updates duration
- `getBreakRecordsForDay(userId:date:)` → [BreakRecord]
- `calculateBreakCompliance(userId:date:)` → compliance summary
- `autoFillBreaksForDay(userId:date:)` → generates break records at default times
- `getRoundedTime(time:roundingMinutes:)` → rounded time for reports
- `getCompanyBreakSettings()` → CompanyBreakSettings
- `updateCompanyBreakSettings(...)` → saves

### ConflictResolver
Add new tables to whitelist.

## Success Criteria
- [ ] 4 new tables + Wyoming seed data
- [ ] 4-tier policy model (state paid, state offered, company paid, company offered)
- [ ] Break records track paid vs unpaid
- [ ] Auto-fill for compliance reporting
- [ ] 15-minute rounding for reports (data stays precise)
- [ ] Service methods for full break lifecycle
- [ ] Project builds with no errors
