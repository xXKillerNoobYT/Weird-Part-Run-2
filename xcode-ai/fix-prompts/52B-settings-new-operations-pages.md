# Prompt 52B — Settings: New Operations Pages

> **Area:** Settings → Operations group
> **Dependencies:** 52A (grouped navigation with stub routes)
> **What the user sees:** No way to configure break/lunch, tool, pre-trip, or dispatch policies.
> **What this fixes:** Creates 4 new functional settings pages.

---

## Task

Create 4 new settings pages in the Operations group. Each page reads/writes settings using `SettingsService` (key-value pairs with `getStringSetting`/`setStringSetting`/`getIntSetting`/`setIntSetting`/`getBoolSetting`/`setBoolSetting`).

---

## Page 1: Break/Lunch Policy (`IOSBreakLunchPolicyPage.swift`)

### 4-Tier System

Display as a form with 4 sections, each with a toggle and duration picker:

| Tier | Label | Description | Default |
|------|-------|-------------|---------|
| State Required Paid | "State-mandated paid breaks" | Legally required, company pays | Off |
| State Required Offered | "State-mandated unpaid breaks" | Legally required, employee's time | Off |
| Company Extra Paid | "Company paid breaks" | Above legal minimum, company pays | Off |
| Company Extra Offered | "Company unpaid breaks" | Above legal minimum, employee's time | Off |

Each tier when enabled shows:
- Duration picker: 10, 15, 20, 30, 45, 60 minutes
- Trigger threshold: "After X hours worked" (number field, default 4.0 for paid, 5.0 for unpaid)
- Count per shift: 1, 2, 3 (default 1)

### Bonus Config Section

- Toggle: "Offer break skip bonus" (default off)
- When enabled: bonus amount per skipped break (dollar field, default $5.00)
- Note text: "Workers who skip eligible breaks receive this bonus per skip"

### State Presets Section

- Picker: "Load State Preset" with all 50 US states + DC
- When selected, auto-fill the 4 tiers based on that state's labor law
- Show confirmation: "Load [State] break requirements? This will overwrite current settings."
- Pre-loaded state data (hardcoded dictionary):
  - California: 10min paid break per 4hrs, 30min unpaid meal per 5hrs
  - New York: No mandated rest breaks, 30min unpaid meal per 6hrs
  - Washington: 10min paid per 4hrs, 30min unpaid per 5hrs
  - Oregon: 10min paid per 4hrs, 30min unpaid per 6hrs
  - (Include all 50 states — use real state labor law data)

### Auto-Fill Section

- Toggle: "Auto-fill breaks on clock-out" (default on)
- When enabled, clock-out questionnaire pre-populates break times based on hours worked

### Settings Keys

Use prefix `break_lunch_` for all keys:
- `break_lunch_state_required_paid_enabled`, `break_lunch_state_required_paid_duration`, `break_lunch_state_required_paid_trigger_hours`, `break_lunch_state_required_paid_count`
- Same pattern for other 3 tiers
- `break_lunch_skip_bonus_enabled`, `break_lunch_skip_bonus_amount`
- `break_lunch_state_preset`
- `break_lunch_auto_fill_enabled`

---

## Page 2: Tool Policies (`IOSToolPoliciesPage.swift`)

### Checkout Limits Section

- "Max checkout duration (days)": number field, default 30
- "Overdue notification (days before due)": number field, default 7
- "Auto-extend on active job": toggle, default on (auto-extends if worker still clocked into the job)

### Condition Checks Section

- "Require condition check on checkout": toggle, default on
- "Require condition check on return": toggle, default on
- "Require photo on damage report": toggle, default off

### Maintenance Section

- "Auto-schedule maintenance after X checkouts": number field, default 50
- "Maintenance reminder (days before due)": number field, default 14

### Trade Section

- "Allow tool trades between workers": toggle, default on
- "Trade timeout (days)": number field, default 7
- "Require condition check on trade": toggle, default on

### Settings Keys

Use prefix `tool_policy_` for all keys.

---

## Page 3: Pre-Trip Checklists (`IOSPreTripChecklistPage.swift`)

### Checklist Editor

Three default sections, each with a list of items that can be added/removed/reordered:

**Exterior** (default items):
- Tires & wheels, Lights & signals, Mirrors, Body damage, Fluid leaks, Hitch/coupler, Safety chains, Mud flaps

**Interior** (default items):
- Seat & seatbelt, Horn, Wipers & washers, Gauges & warning lights, HVAC, Fire extinguisher, First aid kit

**Equipment** (default items):
- Ladder rack, Tool boxes secured, Load secured, PPE present

### Per Vehicle Type

- Picker at top: "Vehicle Type" — All, Truck, Van, Car, Trailer
- Each vehicle type can have its own checklist (overrides default)
- "Use Default" toggle per vehicle type (when on, inherits from All)

### Item Management

- Swipe to delete items
- "+" button to add custom items to any section
- Long-press to reorder within section
- Add Section button to create new custom sections

### Settings Keys

Store as JSON in `prettrip_checklist_config` setting key.

---

## Page 4: Dispatch Preferences (`IOSDispatchPreferencesPage.swift`)

### AI Dispatch Section

- "Enable AI dispatch suggestions": toggle, default on
- "AI learning from dispatcher picks": toggle, default on
- "Show AI confidence scores": toggle, default off

### Flex Pool Section

- "Enable flex pool self-assign": toggle, default off
- "Require manager approval for self-assign": toggle, default on (only visible when self-assign enabled)

### Pipeline Targets Section

- "Start Anytime target": number stepper, default 3
- "Schedule Needed target": number stepper, default 2
- "Favorite GC target": number stepper, default 1
- Note: "Target = minimum number of jobs in each pipeline stage"

### Scheduling Section

- "Default dispatch view": picker (Day, Week, Month), default Week
- "Show crew history (months)": number stepper, default 3
- "Crew continuity weight": picker (Low, Medium, High), default Medium

### Settings Keys

Use prefix `dispatch_` for all keys.

---

## Shared Patterns

All 4 pages follow these patterns:
- `@State private var isLoading = true` with ProgressView overlay
- `@State private var loadError: String?` with ContentUnavailableView
- `@State private var saveError: String?` with error banner
- Load settings in `.task { }`, save on change with `.onChange` or explicit Save button
- `.navigationTitle("Page Name")` + `.navigationBarTitleDisplayMode(.inline)`
- Help button in toolbar (`.toolbar { ToolbarItem(placement: .topBarTrailing) { helpButton } }`)
- Form-based layout with grouped sections

## Build target

iOS only. Must compile. Start prompt 52C next.
