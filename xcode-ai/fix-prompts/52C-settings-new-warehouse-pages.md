# Prompt 52C — Settings: New Warehouse Pages

> **Area:** Settings → Warehouse group
> **Dependencies:** 52A (grouped navigation with stub routes)
> **What the user sees:** No way to configure forecasting, organization, or audit behavior.
> **What this fixes:** Creates 3 new functional settings pages.

---

## Task

Create 3 new settings pages in the Warehouse group. Each page reads/writes settings using `SettingsService`.

---

## Page 1: Forecast Settings (`IOSForecastSettingsPage.swift`)

### Per-Location-Type Defaults Section

Picker at top: Location Type — Shop, Truck, Trailer

For each location type, show:

| Setting | Shop Default | Truck Default | Trailer Default |
|---------|-------------|---------------|-----------------|
| Calculation method | ADU (Average Daily Usage) | APW (Average Per Window) | APW |
| Lookback period (days) | 90 | 42 (6 weeks) | 42 |
| Min data days required | 14 | 7 | 7 |
| APW window (weeks) | — | 2 | 2 |

- ADU vs APW toggle per location type
- APW window picker: 1, 2, 3, 4, 5, 6 weeks (only visible when APW selected)
- Lookback period: number field
- Min data days: number field

### Multiplier Settings Section

For Common parts:
- MIN multiplier: decimal field, default 1.0
- TARGET multiplier: decimal field, default 1.5
- MAX multiplier: decimal field, default 2.0

For Critical parts:
- MIN multiplier: decimal field, default 1.5
- TARGET multiplier: decimal field, default 2.0
- MAX multiplier: decimal field, default 3.0

Note text: "MIN = usage × multiplier. TARGET = usage × multiplier. MAX = usage × multiplier."

### Free Space Settings Section

- "Suppress recommendations when free space below": slider 0-100%, default 20%
- "Free space rating scale": info text explaining 1-5 scale
- Note: "Locations with low free space won't receive 'add new part' recommendations"

### Auto-Recalculation Section

- "Auto-recalculate daily": toggle, default on
- "Recalculation time": time picker, default 2:00 AM
- "Category change suggestion interval (months)": number stepper, default 6

### Settings Keys

Use prefix `forecast_` for all keys. Per-location-type keys use pattern: `forecast_{location_type}_{setting}` (e.g., `forecast_shop_method`, `forecast_truck_apw_window`).

---

## Page 2: Organization Thresholds (`IOSOrganizationThresholdsPage.swift`)

### Confidence Decay Section

- "Base decay rate (% per day)": decimal field, default 0.1
- "Movement decay factor": decimal field, default 0.5
- Note: "Confidence decreases daily. Moving parts increases decay (things may have been misplaced)."

### Audit Triggers Section

- "Audit trigger threshold (%)": slider 0-100%, default 80%
- "Max recommendations per day": number stepper 1-10, default 1
- "Recommendation cooldown (days)": number stepper 7-180, default 60
- Note: "When a location's confidence drops below threshold, an audit is recommended."

### Consolidation Section

- "Consolidation voting timeout (days)": number stepper 1-30, default 7
- "Min votes required": number stepper 1-5, default 2
- "Auto-approve unanimous votes": toggle, default on

### Organization Rating Section

- "Target organization score (%)": slider 0-100%, default 85%
- "Show organization score on dashboard": toggle, default on
- "Include in daily report": toggle, default off

### Settings Keys

Use prefix `org_` for all keys.

---

## Page 3: Audit Settings (`IOSAuditSettingsPage.swift`)

### General Section

- "Enable auto-audit scheduling": toggle, default on
- "Default audit type": picker (Full Count, Cycle Count, Spot Check), default Cycle Count
- "Max concurrent audits": number stepper 1-5, default 1

### Speed Mode Section

- "Allow speed mode": toggle, default on
- "Speed mode requires QR scan": toggle, default on
- "Speed mode time limit (seconds per item)": number stepper 3-30, default 10

### Multi-User Section

- "Multi-user verification threshold": number stepper 1-5, default 2
- Note: "Number of independent counts required before accepting an audit result"
- "Misplacement penalty multiplier": decimal field, default 1.5
- Note: "Multiplier applied to confidence decay when items are found misplaced"

### History Section

- "Keep audit history (months)": number stepper 1-36, default 12
- "Auto-archive completed audits": toggle, default on
- "Include audit results in daily report": toggle, default off

### Settings Keys

Use prefix `audit_` for all keys.

---

## Shared Patterns

All 3 pages follow the same patterns as 52B:
- `@State private var isLoading`, `loadError`, `saveError`
- Load in `.task { }`, save on change
- Form-based layout, grouped sections
- Help button in toolbar
- `.navigationTitle` + `.navigationBarTitleDisplayMode(.inline)`

## Build target

iOS only. Must compile. Start prompt 52D next.
