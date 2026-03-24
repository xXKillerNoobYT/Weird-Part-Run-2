# iOS Reports Pages — Design Plan

## Navigation (Categorized)
Reports: Labor (Timesheets, Labor Overview, Daily Reports Summary), Financial (Spending, Profitability, Pre-Billing, Bookkeeper Export), Fleet (Fuel Costs, Maintenance Trends, Mileage/Cost Per Mile, Vehicle Utilization), Warehouse (Inventory Value, Backorders by supplier/brand, Turnover Rates), Scheduling (Crew Utilization, Dispatch Efficiency, Pipeline Status), Custom Reports (Report Builder), Shared Reports (public links)

## Key Design Decisions

### Every Report Page Gets
- Smart cards at top
- [Export PDF] + [Export CSV] in toolbar
- Help button
- Standard filter bar (program-wide standard)

### Standard Filter Bar (PROGRAM-WIDE — applies to ALL pages with date-relevant data)
Quick filters: This Week, Last Week, This Period, Last Period, This Month, Custom
Custom range: From/To date pickers
Plus page-specific filters (Job, Employee, Vehicle, Supplier, Status, etc.)
This applies to Reports, Orders, Warehouse movements, Fleet logs, Scheduling, Notebooks, Chat history, Audit logs — everywhere.

### 15-Minute Rounding on Timesheets
Company setting. Shows both actual and rounded times side by side when enabled.
Actual: 7:02 AM — 4:28 PM (9h 26m)
Rounded: 7:00 AM — 4:30 PM (9h 30m)

### Period Locking
Already implemented in Phase 8. Verify working in prompts.

### Report Builder (V1 — Simple)
Pick report type → Pick fields → Pick filters → Generate
Not a full BI tool — configurable views of existing data.

### Fleet Reports (NEW — in Reports section, not Fleet)
- Fuel costs by vehicle
- Maintenance cost trends
- Mileage / cost per mile over time
- Vehicle utilization (days in use vs idle)

### Warehouse Reports (NEW)
- Inventory value
- Backorders by supplier and brand
- Turnover rates

### Scheduling Reports (NEW)
- Crew utilization
- Dispatch efficiency
- Pipeline status

### Code Quality
Reports is architecturally clean — zero GRDB imports, all using ReportsService. Design enhancement only.
