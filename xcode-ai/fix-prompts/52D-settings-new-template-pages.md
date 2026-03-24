# Prompt 52D — Settings: New Template Pages

> **Area:** Settings → Templates group
> **Dependencies:** 52A (grouped navigation with stub routes)
> **What the user sees:** No way to configure daily report format, estimation questions, or saved report configs.
> **What this fixes:** Creates 3 new functional settings pages.

---

## Task

Create 3 new settings pages in the Templates group. These manage configurable templates that affect how reports and questionnaires work across the app.

---

## Page 1: Daily Report Templates (`IOSDailyReportTemplatesPage.swift`)

### Section Editor

Display a list of report sections that can be toggled on/off and reordered.

Default sections (in order):
1. **Hours Summary** — always on, cannot disable (locked toggle)
2. **Jobs Worked** — always on, cannot disable
3. **To-Do Progress** — default on
4. **Safety Notes** — default off (optional)
5. **Weather Conditions** — default off (optional)
6. **Equipment Used** — default off (optional)
7. **Materials Used** — default on
8. **Photos** — default on
9. **Worker Notes** — default on
10. **AI Summary** — default on

Each section row shows:
- Toggle (on/off)
- Section name
- Drag handle for reorder (long-press to reorder)
- Lock icon if mandatory (Hours Summary, Jobs Worked)

### AI Instructions Section

- "AI summary instructions": multi-line TextField
- Placeholder: "Summarize the day's work focusing on progress, issues, and next steps..."
- Default: "Summarize today's work concisely. Highlight completed tasks, any issues encountered, and work planned for tomorrow."

### Preview Section

- "Preview Report" button that shows a mock daily report with the current section order and toggles applied
- Uses placeholder data to show what the report will look like

### Settings Keys

Store as JSON in `daily_report_template` setting key.

---

## Page 2: Job Estimation Questions (`IOSJobEstimationQuestionsPage.swift`)

### Question Groups

Display question groups in a list. Each group has a name and contains questions.

Default groups:
1. **Site Access** — "Parking available?", "Elevator access?", "Stairs involved?"
2. **Scope** — "Number of rooms/areas?", "Approximate square footage?"
3. **Existing Conditions** — "Existing system age?", "Condition of existing?"
4. **Special Requirements** — "Permits required?", "Weekend work needed?", "Night work needed?"

### Group Management

- "+" button to add new group (name field)
- Swipe to delete group (confirmation alert)
- Long-press to reorder groups

### Per-Question Properties

Tap a question to edit:
- **Name**: text field (the question text)
- **Type**: picker — Number, Picker, Toggle (Yes/No), Text, Unknown ("?")
- **Stage**: multi-select — Bid, Pre-Start, During, Punch List
  - Questions only appear during their assigned stages
- **Required**: toggle (default off)
- **Picker options**: only visible when type = Picker, list of options with add/remove

### Question Management Within Group

- "+" button within each group to add question
- Swipe to delete question
- Long-press to reorder within group

### AI Learning Section

- "AI question suggestions": toggle, default on
- "Minimum jobs before AI suggests": number stepper, default 15
- Note: "After enough jobs, AI suggests new questions based on patterns in estimate accuracy."
- "Show rejected question history": navigation link to list of AI-rejected questions

### Settings Keys

Store as JSON in `job_estimation_questions` setting key.

---

## Page 3: Report Templates (`IOSReportTemplatesPage.swift`)

### Template List

Display saved report templates. Each template is a saved configuration for generating reports.

Each template shows:
- Name
- Report type (Timesheet, Labor, Spending, Profitability, Fleet, Warehouse)
- Last used date
- Shared indicator (if shared with team)

### Create/Edit Template

Tap "+" or tap existing template to edit. Sheet with:

- **Name**: text field
- **Report Type**: picker (Timesheet, Labor Overview, Spending, Profitability, Fleet, Warehouse)
- **Selected Fields**: based on report type, checkboxes for which columns to include
  - Timesheet fields: Employee, Date, Job, Hours, Overtime, Break Time, Notes
  - Labor fields: Employee, Total Hours, Jobs, Average Hours/Day, Overtime %
  - Spending fields: Category, Supplier, Amount, PO Count, Trend
  - (etc. per report type)
- **Default Filters**:
  - Date range preset: This Week, Last Week, This Period, Last Period, This Month, Custom
  - Job filter: All, Specific Job picker
  - Employee filter: All, Specific Employee picker, Team picker
- **Share with team**: toggle (default off)

### Template Actions

- Swipe to delete (confirmation)
- Duplicate template (long-press menu)
- "Generate Report" button → navigates to Reports with template applied

### Settings Keys

Store as JSON array in `report_templates` setting key.

---

## Shared Patterns

All 3 pages follow the same patterns as 52B/52C:
- `@State private var isLoading`, `loadError`, `saveError`
- Load in `.task { }`, save on change
- Form-based layout, grouped sections
- Help button in toolbar
- `.navigationTitle` + `.navigationBarTitleDisplayMode(.inline)`

## Build target

iOS only. Must compile. Start prompt 52E next.
