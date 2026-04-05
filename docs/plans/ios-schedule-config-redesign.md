# iOS Schedule Config Page Redesign Plan

## What This Does (Plain English)
The Schedule Config page is currently "just a usable calendar" — it's missing almost everything defined in the scheduling plan. This plan adds the missing config fields additively (the base layout is fine, just needs content).

## Why We Need This
Managers can't define shift hours, set overtime rules, add holiday dates, or create role-based shift templates. The scheduling system can't function properly without these config options.

## Current State
- `IOSScheduleConfigPage.swift` exists — has basic calendar UI
- `SchedulingService` has basic config methods
- Missing: shift templates, holiday calendar, overtime rules, role-aware shifts, schedule exception types

## Owner Decisions Applied
- **Additive redesign** — base layout is good, add missing fields (not a full rebuild)
- **Role-aware** — different shift templates for different job hats (not one global schedule)
- **"Almost everything" missing** — full plan spec needs to be implemented

## Missing Fields to Add

### 1. Company Work Hours
- Default start time (e.g., 7:00 AM)
- Default end time (e.g., 5:00 PM)
- Default lunch break (paid/unpaid, duration)
- Default work days (M/T/W/Th/F/Sa/Su checkboxes)
- Default overtime threshold (e.g., >8h/day or >40h/week)

### 2. Role-Based Shift Templates
Per job hat (role):
- Shift name (e.g., "Journeyman Field", "Apprentice Shop")
- Work days
- Start/end time
- Break configuration
- Overtime rule (same as company default or custom)
- Can create multiple templates per role

### 3. Holiday Calendar
- Add named holidays (name + date)
- Mark as paid or unpaid
- Recurring holidays (annual recurrence option)
- Sync with system calendar option (future — not blocking)

### 4. Schedule Exception Types
- Predefined exception types: time_off, sick, personal, jury_duty, FMLA, military, bereavement
- Custom exception types (admin can add)
- Each type: is it paid?, does it count toward overtime?, accrual rules

### 5. Dispatch Rules
- Min notice required before shift assignment (e.g., 24h)
- Max hours per day (for automatic overtime flagging)
- Require manager confirmation to override overtime limit

### 6. Supervisor Role
- Assign supervisor hat(s) — supervisors see their team's schedule, not all employees
- Supervisor can approve time-off requests for their team

## Files to Modify

### Core — SchedulingService
**File:** `core/Sources/WiredPartCore/Services/SchedulingService.swift`

New/missing methods:
- `getCompanyScheduleConfig() throws -> ScheduleConfig`
- `updateCompanyScheduleConfig(_: ScheduleConfig) throws`
- `getShiftTemplates() throws -> [ShiftTemplate]`
- `createShiftTemplate(_: ShiftTemplate) throws`
- `updateShiftTemplate(_: ShiftTemplate) throws`
- `deleteShiftTemplate(id: Int64) throws`
- `getHolidays(year: Int) throws -> [Holiday]`
- `addHoliday(_: Holiday) throws`
- `removeHoliday(id: Int64) throws`

New DB Migration (check if already exists):
```sql
CREATE TABLE IF NOT EXISTS schedule_config (
    id INTEGER PRIMARY KEY,
    default_start_time TEXT,
    default_end_time TEXT,
    default_work_days TEXT,  -- JSON array e.g. ["mon","tue","wed","thu","fri"]
    overtime_daily_threshold REAL DEFAULT 8.0,
    overtime_weekly_threshold REAL DEFAULT 40.0,
    lunch_paid INTEGER DEFAULT 0,
    lunch_minutes INTEGER DEFAULT 30,
    updated_at TEXT
);

CREATE TABLE IF NOT EXISTS shift_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hat_id INTEGER REFERENCES user_hats(id),  -- NULL = applies to all
    template_name TEXT NOT NULL,
    start_time TEXT,
    end_time TEXT,
    work_days TEXT,
    overtime_daily_threshold REAL,
    created_at TEXT
);

CREATE TABLE IF NOT EXISTS company_holidays (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    holiday_date TEXT NOT NULL,
    is_paid INTEGER DEFAULT 1,
    is_recurring INTEGER DEFAULT 0,
    created_at TEXT
);
```

### iOS UI — Schedule Config Page
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSScheduleConfigPage.swift`

Add sections:
1. **Work Hours** — form fields for default start/end/days/lunch/overtime
2. **Shift Templates** — list of templates with + button, role picker, time pickers
3. **Holiday Calendar** — list of holidays with + button, date picker, paid toggle
4. **Dispatch Rules** — min notice, max hours, manager override toggle
5. **Supervisor Roles** — hat picker for supervisor-level hats

Xcode prompt: `PE-031-schedule-config.md`

## Data Flow
Manager opens Schedule Config → sees current company defaults
Manager taps "Add Shift Template" → picks hat, sets hours → `createShiftTemplate()` called
Manager adds holidays → `addHoliday()` called
When dispatching: system checks `getShiftTemplates()` for the assigned employee's hat → applies default hours → flags overtime

## Priority
Medium — doesn't block current use but is needed before scheduling is truly functional.
