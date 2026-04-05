# PE-032 — Schedule Config Page: Add Missing Fields (Additive)

**GitHub Issue:** #29
**Plan:** `docs/plans/ios-schedule-config-redesign.md`
**Priority:** Medium — scheduling system can't be configured properly without these fields

---

## Context

`IOSScheduleConfigPage.swift` exists with a basic calendar UI. Almost all the fields defined in the scheduling plan are missing. The owner confirmed this is **additive** — the base layout is good, we just need to add all the missing content. No full rebuild needed.

---

## Owner Decisions (from Q&A)

- **Additive** — add missing fields to the existing page layout
- **Role-aware** — different shift templates per job hat (not one global schedule)
- Everything in the plan spec needs to be implemented

---

## Task 1 — Company Work Hours Section

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSScheduleConfigPage.swift`

Add a "Company Work Hours" section (collapsible `DisclosureGroup` or `Section` in a `Form`):

```
Company Work Hours
├─ Default Start Time       [7:00 AM]  (DatePicker, hour/min only)
├─ Default End Time         [5:00 PM]  (DatePicker, hour/min only)
├─ Default Lunch Break      [30 min unpaid]  (Picker: 0/15/30/45/60 min + Paid/Unpaid toggle)
├─ Work Days                [M] [T] [W] [Th] [F] [Sa] [Su]  (checkbox row)
└─ Overtime Threshold       [8h/day] or [40h/week]  (Picker)
```

Save via `SchedulingService.saveCompanyWorkHours(...)` — create this method if missing.

---

## Task 2 — Role-Based Shift Templates Section

Add a "Shift Templates" section:

1. List of existing shift templates (fetched from `SchedulingService.getShiftTemplates()`)
2. Each row: template name + hat name + start–end time summary
3. Tap → `ShiftTemplateEditSheet`
4. `+` button → create new template

**ShiftTemplateEditSheet:**
```
Template Name      [Journeyman Field]
Job Hat            [Picker: all hats]
Work Days          [checkboxes]
Start Time         [DatePicker]
End Time           [DatePicker]
Break Config       [same options as company default]
Overtime Rule      [Use Company Default] or [Custom...]
```

Add to `SchedulingService`:
```swift
public func getShiftTemplates() throws -> [ShiftTemplateRow]
public func saveShiftTemplate(_ template: ShiftTemplateRow) throws
public func deleteShiftTemplate(id: Int64) throws
```

And a `shift_templates` DB table migration if it doesn't exist:
```sql
CREATE TABLE IF NOT EXISTS shift_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    hat_id INTEGER REFERENCES hats(id) ON DELETE SET NULL,
    work_days TEXT NOT NULL,  -- JSON array: ["mon","tue","wed","thu","fri"]
    start_time TEXT NOT NULL, -- "HH:MM"
    end_time TEXT NOT NULL,   -- "HH:MM"
    break_minutes INTEGER DEFAULT 30,
    break_paid INTEGER DEFAULT 0,
    overtime_rule TEXT DEFAULT 'company_default',
    created_at TEXT DEFAULT (datetime('now'))
);
```

---

## Task 3 — Holiday Calendar Section

Add a "Holidays" section:

1. List of defined holidays (name, date, paid/unpaid indicator)
2. `+` button → `HolidayEditSheet`:
   - Name field
   - Date picker
   - `Paid` / `Unpaid` toggle
   - `Recurring annually` toggle

Add to `SchedulingService`:
```swift
public func getHolidays() throws -> [HolidayRow]
public func saveHoliday(_ holiday: HolidayRow) throws
public func deleteHoliday(id: Int64) throws
```

And a `company_holidays` table migration if missing.

---

## Task 4 — Dispatch Rules Section

Add a "Dispatch Rules" section:

```
Minimum Notice Before Assignment    [24 hours]  (Stepper or Picker)
Maximum Hours Per Day (flag overtime) [10 hours]
Require Manager Approval to Override Overtime   [Toggle]
```

Save via `SchedulingService.saveDispatchRules(...)`.

---

## Task 5 — Supervisor Role Section

Add a "Supervisor Settings" section:

```
Supervisor Hats    [multi-select hat picker]
  └─ Selected hats: [Foreman], [Lead]
Supervisors see:   [Their team's schedule only]
Supervisors can approve time-off for their team: [Toggle]
```

---

## Verification Checklist

- [ ] Company Work Hours section visible and editable
- [ ] Shift Templates section: list, create, edit, delete
- [ ] Holiday Calendar: add/remove holidays with paid/unpaid flags
- [ ] Dispatch Rules section: min notice + max hours + override approval
- [ ] Supervisor Role: hat selection for supervisor role
- [ ] All changes persist after app restart
- [ ] Build: 0 errors, 0 warnings
- [ ] Tests: new service methods have basic coverage
