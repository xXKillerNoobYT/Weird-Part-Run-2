# Page-by-Page Rebuild Enforcer

## Purpose
Systematically rebuild every page in the iOS app to meet the $700/mo + $20/user product standard. Works through pages one at a time, verifying each against the program review GitHub issues (#52-#66) and the 15 cross-cutting standards.

## Schedule
- **When:** Daily at 4:00 PM (after usability-enforcer at 2:00 PM)
- **Duration:** Works on 1-3 pages per run
- **Priority:** Focus on the CURRENT page until it passes ALL checks before moving to next

## Page Rebuild Order (Priority)
Work through pages in this order. Each page must PASS before moving to the next.

### Tier 1 — Revenue Core (Do First)
1. Parts Catalog Page
2. Parts Forecasting Page
3. Jobs List Page
4. Job Detail Dashboard
5. Clock In/Out Page
6. JPO Creation (3-Panel)
7. JPO List Page
8. Procurement Planner

### Tier 2 — Operations
9. Purchase Orders List + Detail
10. Warehouse Dashboard
11. Warehouse Movements
12. Warehouse Locations/Floor Plan
13. Sorting/Receiving
14. Staging Page
15. Audit System

### Tier 3 — People & Admin
16. People Dashboard
17. Employee Detail
18. Customer Detail
19. Contacts + Contact Detail
20. Teams + Hats + Permissions
21. Office Dashboard
22. Unified Approvals

### Tier 4 — Scheduling & Fleet
23. Schedule Calendar
24. Dispatch Board
25. Pipeline (Short + Long Term)
26. Fleet Dashboard + My Vehicle
27. Vehicle Detail
28. Pre-Trip Inspections

### Tier 5 — Communication & Docs
29. Chat (Unified Inbox)
30. Q&A + RFI
31. Notebooks List + Detail
32. Block Editor + Templates
33. Panel Schedule Builder
34. Daily Reports

### Tier 6 — Tools & Settings
35. Tools Dashboard + Detail
36. Kit Management
37. Tool Trade + Maintenance
38. Settings (all categories)
39. Reports (all categories)

### Tier 7 — Cross-Cutting
40. Standard Filter Bar (all pages)
41. Help Button (all pages)
42. Save & Exit patterns (all forms)
43. QR Integration (per module)
44. First-Time Use / Onboarding

## Per-Page Verification Checklist

For EACH page, verify ALL of the following:

### A. Code Quality
- [ ] No `import GRDB` in UI file
- [ ] No `#if os(iOS)` platform guards
- [ ] Uses service layer exclusively
- [ ] Single `.sheet(item:)` with ActiveSheet enum
- [ ] `@State loadError` with ErrorStateView display
- [ ] No `print()` for errors (use proper error handling)
- [ ] No force casts (`as!`) or force unwraps (`!`)
- [ ] No empty catch blocks

### B. UI Standards
- [ ] Smart card filters (not old chip bars) on list pages
- [ ] Help button with page-specific content
- [ ] 44px minimum touch targets
- [ ] Pull-to-refresh (`.refreshable`) on lists
- [ ] Search (`.searchable`) where appropriate
- [ ] Empty state view (not ContentUnavailableView)
- [ ] Loading state (ProgressView)
- [ ] Error state (ErrorStateView with retry)
- [ ] Priority colors are time-based (not label-based)

### C. Forms & Actions
- [ ] [Save & Exit] + [Save & Add Another] on creation forms
- [ ] [Save] + [Cancel] on edit forms (with unsaved warning)
- [ ] Delete confirmation on destructive actions
- [ ] Inline error feedback in forms
- [ ] Save button disabled + spinner during save
- [ ] Hat-gated actions (never hardcoded roles)

### D. Data Integrity
- [ ] All SQL column names verified against `AppDatabase+Migrations.swift`
- [ ] `isTableNotFoundError` catches both "no such table" AND "no such column"
- [ ] FK constraints respected (seed parent rows in tests)
- [ ] Soft delete queries filter `deleted_at IS NULL`
- [ ] Service methods have proper error handling

### E. Feature Completeness
- [ ] All CRUD operations functional (not stubs)
- [ ] Navigation works (links resolve, back button works)
- [ ] Data loads correctly from service layer
- [ ] Matches the design in `docs/plans/` for this page
- [ ] AI integration point exists (context sent to AI panel)
- [ ] QR scan integration where applicable

### F. Cross-Cutting
- [ ] Standard filter bar (if applicable)
- [ ] Auto-fill job context (when clocked in, if applicable)
- [ ] Audit trail for data changes
- [ ] Proper first-time/empty state guidance

## Process Per Run

1. **Read tracker** (`docs/page-rebuild-tracker.md`) to find current page
2. **Read the plan** for that page from `docs/plans/`
3. **Read the actual code** for the page
4. **Run verification checklist** (A through F)
5. **Fix issues** found (code changes)
6. **Run build** (`cd core && swift build`)
7. **Run tests** (`cd core && swift test`)
8. **Update tracker** with results
9. **If page passes:** Mark complete, move to next page
10. **If page fails:** Log remaining issues, continue next run

## Tracker Format

Update `docs/page-rebuild-tracker.md` with:

```markdown
## Current Page: [Page Name]
## Status: IN PROGRESS / PASS / BLOCKED

### Progress
| Page | Status | Issues Found | Issues Fixed | Remaining | Date |
|------|--------|-------------|-------------|-----------|------|
| Parts Catalog | PASS | 5 | 5 | 0 | 2026-04-03 |
| Jobs List | IN PROGRESS | 8 | 3 | 5 | 2026-04-03 |
```

## Integration with Other Agents
- **usability-enforcer** (2PM): Finds cross-cutting issues
- **page-rebuild-enforcer** (4PM): Fixes page-by-page
- **hunt-fix-verify** (6AM): Catches regressions
- **test-coverage-maintenance** (7AM): Ensures tests cover fixes
- **github-issues-sync** (11AM/5PM): Updates GitHub issues with progress
