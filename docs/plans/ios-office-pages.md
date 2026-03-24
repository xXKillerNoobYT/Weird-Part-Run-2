# iOS Office Pages — Design Plan

## Navigation
Office (Admin HQ): Dashboard, Approvals, Manage Jobs, Spending, Warehouse Exec, Pipeline, Teams, Deletions, Custom Reports, Company Settings, Orders

## Key Design Decisions

### Office = Manager/Admin Command Center
Not a report viewer — surfaces things that need decisions, approvals, and oversight. The administrative hub, HR of the program.

### Dashboard — Daily Briefing
- Smart cards: Approvals Pending, Working Today, JPOs Pending, Payment Overdue, Parts Below MIN, Maintenance Due, Callbacks Overdue, Warranty Expiring
- AI Daily Briefing (cached 1hr): morning snapshot summarizing workers, jobs, issues, upcoming items
- Push notification at 7 AM: "Your daily briefing is ready"
- "Needs Your Attention" section with priority colors
- Today's Schedule (dispatched workers/teams)
- Financial Snapshot (hat-gated): this week vs last week, this month vs last month with trend arrows
- Background Tasks status (forecast recalc, companion discovery, audit scan, sync status)

### Priority Color Timeline (PROGRAM-WIDE)
- Green: No action needed
- Yellow: Due within 4 days (warning)
- Orange: Due within 24 hours (act soon)
- Red: OVERDUE (past deadline)
- Gray: Completed/resolved

### Unified Approvals Page
ALL approval types in one sorted queue (oldest first):
- JPO approvals (from Orders)
- Deletion approvals (from Warehouse/Parts)
- Tool edit verifications (from Tools)
- Warranty classifications (from Jobs)
- Schedule changes
- Time-off requests
Smart cards filter by type. Each item shows inline action buttons.
Items also remain accessible on their source pages.

### Spending Summary
Summary view in Office, full detail in Reports → Financial.
Week-over-week AND month-over-month comparisons with trend arrows.

### Office Chat Channel
Auto-created channel for office/admin staff coordination.
Separate from job chats. Office info only.

### Other Office Features
- Pending callbacks (from pipeline)
- Expiring certifications (30/60/90 days)
- Insurance renewals
- Contract deadlines
- Audit confidence overview
- Overdue fleet inspections
- Period close status (ready to close pay period?)
- Unread Q&A escalations (questions that reached Office level)

### Code Quality
Office is clean — no GRDB, all service-based. Design enhancement only.
