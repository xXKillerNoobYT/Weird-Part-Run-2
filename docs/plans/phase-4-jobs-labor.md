# Phase 4: Jobs & Labor — Full Implementation Plan

## Context

Phase 4 brings the Jobs module to life — the core field-work system. Users need to:
- See active jobs with addresses and GPS navigation
- Clock in/out with location tracking
- Answer customizable end-of-day questions (global + per-job one-time questions)
- Attach photos during clock-out
- Have daily reports auto-generated at midnight into locked notebook sections

The `jobs` table is referenced throughout the existing codebase (`stock_movements.job_id`, `job_lead_elevations`, warehouse location lookups) but doesn't exist yet. This phase creates it and builds the full job lifecycle.

**Additionally**, this plan covers:
- Updating `docs/implementation-plan.md` with undocumented work done since Phase 3
- Establishing a `docs/plans/` filing convention for all future plans
- Outlining advanced features for Phases 5–12

---

## Pre-Implementation: Housekeeping

### 1. Establish Plan Filing Convention

**Rule:** All plans save to `docs/plans/` with descriptive names. The master plan stays at `docs/implementation-plan.md`.

- Create `docs/plans/` directory
- Save this plan as `docs/plans/phase-4-jobs-labor.md`
- Update `CLAUDE.md` with the convention:
  ```
  ## Plan Filing
  - Master plan: `docs/implementation-plan.md`
  - Phase/feature plans: `docs/plans/<name>.md`
  - Always save plans to docs/ — never leave them only in .claude/plans/
  ```

### 2. Update `docs/implementation-plan.md` — Document Undocumented Work

Features built since Phase 3 that aren't in the plan:

| Feature | Migration | Files | Phase Label |
|---------|-----------|-------|-------------|
| Companions system (rules, suggestions, co-occurrence, feedback) | 007 | `companions.py` router, `companions_service.py`, `companions_repo.py`, `CompanionsPage.tsx` | Phase 3.5 |
| Part Alternatives (substitute/upgrade/compatible links) | 007 | `alternatives_repo.py`, `AlternativesSection.tsx`, `LinkAlternativeModal.tsx` | Phase 3.5 |
| Office / Warehouse Exec view | — | `WarehouseExecPage.tsx`, inline editable exec spreadsheet | Phase 3.5 |
| QR Scanner Bubble (movement wizard Step 2) | — | `QRScannerBubble.tsx`, `qr-utils.ts` | Phase 3.5 |
| QR Label Modal (inventory grid) | — | `QRLabelModal.tsx`, `is_qr_tagged` in inventory query | Phase 3.5 |
| Bin Location | 008 | `bin_location` column on `parts` | Phase 3.5 |
| Part Detail Panel | — | `PartDetailPanel.tsx` in categories tree | Phase 2.5 |
| Brand-Color Panel | — | `BrandColorPanel.tsx` | Phase 2.5 |

---

## Phase 4: Jobs & Labor — Implementation

### Overview

```
Phase 4 Deliverables:
├── Migration 009: jobs, job_parts, labor_entries
├── Migration 010: clock_out_questions, clock_out_responses, daily_reports, one_time_questions
├── Backend: JobService, LaborService, QuestionnaireService, ReportGenerationService
├── Backend: APScheduler for midnight report generation
├── Frontend: Full jobs feature module (8+ pages/components)
├── Frontend: Clock in/out flow with GPS + questionnaire
└── Frontend: Daily report viewer (locked notebook section)
```

---

### Step 1: Database Migration — `009_jobs_and_labor.sql`

```sql
-- ═══ JOBS ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_number TEXT NOT NULL UNIQUE,
    job_name TEXT NOT NULL,
    customer_name TEXT NOT NULL,
    -- Address & GPS
    address_line1 TEXT,
    address_line2 TEXT,
    city TEXT,
    state TEXT,
    zip TEXT,
    gps_lat REAL,
    gps_lng REAL,
    -- Status & Classification
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','on_hold','completed','cancelled')),
    priority TEXT NOT NULL DEFAULT 'normal'
        CHECK (priority IN ('low','normal','high','urgent')),
    job_type TEXT NOT NULL DEFAULT 'service'
        CHECK (job_type IN ('service','new_construction','remodel','maintenance','emergency')),
    -- Financial
    billing_rate REAL,              -- $/hr for this job
    estimated_hours REAL,
    -- People
    lead_user_id INTEGER REFERENCES users(id),
    -- Metadata
    start_date TEXT,
    due_date TEXT,
    completed_date TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ═══ JOB PARTS (consumption tracking) ════════════════════
CREATE TABLE IF NOT EXISTS job_parts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    part_id INTEGER NOT NULL REFERENCES parts(id),
    qty_consumed INTEGER NOT NULL DEFAULT 0,
    qty_returned INTEGER NOT NULL DEFAULT 0,
    unit_cost_at_consume REAL,
    unit_sell_at_consume REAL,
    consumed_by INTEGER REFERENCES users(id),
    consumed_at TEXT NOT NULL DEFAULT (datetime('now')),
    notes TEXT
);
CREATE INDEX idx_job_parts_job ON job_parts(job_id);

-- ═══ LABOR ENTRIES ═══════════════════════════════════════
CREATE TABLE IF NOT EXISTS labor_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    -- Clock times
    clock_in TEXT NOT NULL,
    clock_out TEXT,
    -- Calculated
    regular_hours REAL,
    overtime_hours REAL,
    drive_time_minutes INTEGER DEFAULT 0,
    -- Location
    clock_in_gps_lat REAL,
    clock_in_gps_lng REAL,
    clock_out_gps_lat REAL,
    clock_out_gps_lng REAL,
    -- Photos
    clock_in_photo_path TEXT,
    clock_out_photo_path TEXT,
    -- Status
    status TEXT NOT NULL DEFAULT 'clocked_in'
        CHECK (status IN ('clocked_in','clocked_out','edited','approved')),
    edited_by INTEGER REFERENCES users(id),
    approved_by INTEGER REFERENCES users(id),
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_labor_user ON labor_entries(user_id);
CREATE INDEX idx_labor_job ON labor_entries(job_id);
CREATE INDEX idx_labor_date ON labor_entries(clock_in);
```

### Step 2: Database Migration — `010_clockout_and_reports.sql`

```sql
-- ═══ CLOCK-OUT QUESTION TEMPLATES (global, boss-managed) ═══
CREATE TABLE IF NOT EXISTS clock_out_questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_text TEXT NOT NULL,
    answer_type TEXT NOT NULL DEFAULT 'text'
        CHECK (answer_type IN ('text','yes_no','photo')),
    is_required INTEGER NOT NULL DEFAULT 1,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    -- Metadata
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed default electrician questions
INSERT INTO clock_out_questions (question_text, answer_type, is_required, sort_order) VALUES
    ('Have you entered the parts you used today?', 'yes_no', 1, 1),
    ('What are you planning on tomorrow?', 'text', 1, 2),
    ('Do we have the parts you need?', 'yes_no', 1, 3),
    ('Have you coordinated tomorrow work?', 'yes_no', 1, 4),
    ('Any safety concerns or hazards observed?', 'text', 0, 5),
    ('Is the job site clean and secured?', 'yes_no', 1, 6),
    ('Any equipment issues to report?', 'text', 0, 7),
    ('Did you complete your planned scope today?', 'yes_no', 0, 8);

-- ═══ ONE-TIME PER-JOB QUESTIONS ══════════════════════════
CREATE TABLE IF NOT EXISTS one_time_questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    target_user_id INTEGER REFERENCES users(id),  -- NULL = ask everyone on the job
    question_text TEXT NOT NULL,
    answer_type TEXT NOT NULL DEFAULT 'text'
        CHECK (answer_type IN ('text','yes_no','photo')),
    -- Lifecycle
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','answered','expired','cancelled')),
    -- Who/when
    created_by INTEGER NOT NULL REFERENCES users(id),
    answered_by INTEGER REFERENCES users(id),
    answer_text TEXT,
    answer_photo_path TEXT,
    shown_at_clock_in INTEGER NOT NULL DEFAULT 0,  -- was it displayed at clock-in?
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    answered_at TEXT
);
CREATE INDEX idx_otq_job ON one_time_questions(job_id);
CREATE INDEX idx_otq_target ON one_time_questions(target_user_id);

-- ═══ CLOCK-OUT RESPONSES (answers to global questions) ═══
CREATE TABLE IF NOT EXISTS clock_out_responses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    labor_entry_id INTEGER NOT NULL REFERENCES labor_entries(id),
    question_id INTEGER NOT NULL REFERENCES clock_out_questions(id),
    -- Answer
    answer_text TEXT,
    answer_bool INTEGER,           -- for yes_no type
    photo_path TEXT,               -- optional photo per answer
    answered_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_cor_labor ON clock_out_responses(labor_entry_id);

-- ═══ DAILY REPORTS (auto-generated at midnight) ══════════
CREATE TABLE IF NOT EXISTS daily_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    report_date TEXT NOT NULL,     -- YYYY-MM-DD
    -- Generated content (JSON blob — rendered as locked notebook page)
    report_json TEXT NOT NULL,     -- Full structured report data
    -- Status
    status TEXT NOT NULL DEFAULT 'generated'
        CHECK (status IN ('generated','reviewed','locked')),
    generated_at TEXT NOT NULL DEFAULT (datetime('now')),
    reviewed_by INTEGER REFERENCES users(id),
    reviewed_at TEXT,
    UNIQUE(job_id, report_date)
);
CREATE INDEX idx_dr_job_date ON daily_reports(job_id, report_date);
```

---

### Step 3: Backend — Services

**New files:**

| File | Responsibility |
|------|---------------|
| `backend/app/services/job_service.py` | Job CRUD, status lifecycle, address/GPS |
| `backend/app/services/labor_service.py` | Clock in/out, hours calc, GPS capture, labor queries |
| `backend/app/services/questionnaire_service.py` | Global questions CRUD, one-time questions, clock-out response capture |
| `backend/app/services/report_service.py` | Daily report generation, JSON assembly, midnight scheduler |

**Key service methods:**

```python
# labor_service.py
class LaborService:
    async def clock_in(self, user_id, job_id, gps_lat, gps_lng, photo_path) -> LaborEntry
    async def clock_out(self, labor_entry_id, gps_lat, gps_lng, photo_path, responses) -> LaborEntry
    async def get_active_clock(self, user_id) -> LaborEntry | None  # who is currently clocked in?
    async def get_labor_for_job(self, job_id, date_from, date_to) -> list[LaborEntry]
    async def get_labor_for_user(self, user_id, date_from, date_to) -> list[LaborEntry]

# questionnaire_service.py
class QuestionnaireService:
    async def get_global_questions(self) -> list[ClockOutQuestion]
    async def upsert_global_question(self, question) -> ClockOutQuestion
    async def reorder_questions(self, ordered_ids) -> None
    async def get_pending_one_time_questions(self, job_id, user_id) -> list[OneTimeQuestion]
    async def create_one_time_question(self, job_id, target_user_id, text, type, created_by)
    async def answer_one_time_question(self, question_id, answer, user_id)
    async def get_clock_out_bundle(self, job_id, user_id) -> ClockOutBundle
        # Returns: global questions + unanswered one-time questions

# report_service.py
class ReportService:
    async def generate_daily_report(self, job_id, report_date) -> DailyReport
    async def generate_all_pending_reports(self) -> list[DailyReport]
        # Called by midnight scheduler
    async def get_report(self, job_id, report_date) -> DailyReport | None
    async def get_reports_for_job(self, job_id) -> list[DailyReport]
```

**Daily Report JSON structure:**

```json
{
  "job_id": 5,
  "job_name": "Smith Residence Rewire",
  "report_date": "2026-02-24",
  "workers": [
    {
      "user_id": 3,
      "display_name": "Mike Johnson",
      "clock_in": "07:15",
      "clock_out": "16:30",
      "regular_hours": 8.0,
      "overtime_hours": 1.25,
      "drive_time_minutes": 45,
      "clock_in_gps": { "lat": 33.123, "lng": -96.456 },
      "clock_out_gps": { "lat": 33.123, "lng": -96.456 },
      "responses": [
        { "question": "Have you entered the parts you used today?", "type": "yes_no", "answer": true },
        { "question": "What are you planning on tomorrow?", "type": "text", "answer": "Finish panel upgrade, start kitchen circuit" },
        { "question": "Do we have the parts you need?", "type": "yes_no", "answer": false, "photo": "uploads/abc123.jpg" }
      ],
      "one_time_responses": [
        { "question": "Check voltage on Panel B", "answer": "120/240V confirmed, all good" }
      ]
    }
  ],
  "parts_consumed": [
    { "part_name": "Outlet Decora GFI White", "qty": 4, "unit_cost": 12.50, "total": 50.00 },
    { "part_name": "12/2 Romex (ft)", "qty": 150, "unit_cost": 0.45, "total": 67.50 }
  ],
  "summary": {
    "total_labor_hours": 9.25,
    "total_parts_cost": 117.50,
    "total_labor_cost": 462.50,
    "worker_count": 1
  }
}
```

---

### Step 4: Backend — Scheduler (APScheduler)

**Install:** Add `apscheduler` to `requirements.txt`

**File:** `backend/app/scheduler.py`

```python
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

scheduler = AsyncIOScheduler()

async def midnight_report_job():
    """Generate daily reports for all jobs that had activity today."""
    db = await get_connection()
    try:
        svc = ReportService(db)
        reports = await svc.generate_all_pending_reports()
        logger.info(f"Generated {len(reports)} daily reports")
    finally:
        await db.close()

def start_scheduler():
    scheduler.add_job(
        midnight_report_job,
        CronTrigger(hour=0, minute=5),  # 12:05 AM to ensure all clock-outs are in
        id="daily_reports",
        replace_existing=True,
    )
    scheduler.start()
```

**Integration in `main.py`:**
```python
@app.on_event("startup")
async def startup():
    await init_db()
    await _seed_admin_pin()
    start_scheduler()  # NEW

@app.on_event("shutdown")
async def shutdown():
    scheduler.shutdown()  # NEW
```

**Catch-up logic:** On startup, check for any missed reports (e.g., server was down at midnight). Generate them for any date with labor activity but no report.

---

### Step 5: Backend — API Routes

**File:** `backend/app/routers/jobs.py` (replace stubs)

```
JOBS:
  GET    /api/jobs/active                    — Active jobs list (filterable)
  POST   /api/jobs                           — Create job
  GET    /api/jobs/{id}                      — Job detail
  PUT    /api/jobs/{id}                      — Update job
  PATCH  /api/jobs/{id}/status               — Change status

LABOR:
  POST   /api/jobs/{id}/clock-in             — Clock in to job (GPS + photo)
  POST   /api/jobs/clock-out                 — Clock out (GPS + photo + responses)
  GET    /api/jobs/{id}/labor                — Labor entries for job
  GET    /api/jobs/my-clock                  — Current user's active clock entry
  GET    /api/jobs/{id}/labor/{entry_id}     — Single labor entry detail

PARTS:
  GET    /api/jobs/{id}/parts                — Parts consumed on job
  POST   /api/jobs/{id}/parts/consume        — Record part consumption

QUESTIONS:
  GET    /api/jobs/questions/global           — List global clock-out questions
  POST   /api/jobs/questions/global           — Create/update global question
  PUT    /api/jobs/questions/global/reorder   — Reorder questions
  DELETE /api/jobs/questions/global/{id}      — Deactivate question
  GET    /api/jobs/{id}/questions/one-time    — One-time questions for job
  POST   /api/jobs/{id}/questions/one-time    — Create one-time question
  POST   /api/jobs/questions/one-time/{id}/answer — Answer one-time question
  GET    /api/jobs/{id}/clock-out-bundle      — Get all questions for clock-out flow

REPORTS:
  GET    /api/jobs/{id}/reports               — Daily reports for job
  GET    /api/jobs/{id}/reports/{date}        — Specific daily report
  POST   /api/jobs/reports/generate-now       — Manual trigger (admin)
```

---

### Step 6: Frontend — Feature Module

```
frontend/src/features/jobs/
├── components/
│   ├── JobCard.tsx                — Job card with address, status, navigate button
│   ├── JobForm.tsx                — Create/edit job form
│   ├── ClockInOutButton.tsx       — Floating clock button (GPS + photo capture)
│   ├── ClockOutFlow.tsx           — Multi-step: questions → photos → confirm
│   ├── QuestionCard.tsx           — Single question renderer (text/yes_no/photo)
│   ├── OneTimeQuestionBanner.tsx  — Banner shown at clock-in for pending one-time Qs
│   ├── DailyReportView.tsx        — Read-only rendered report (locked notebook page)
│   ├── QuestionManager.tsx        — Admin: drag-to-reorder global questions CRUD
│   ├── OneTimeQuestionForm.tsx    — Boss: add one-time question to a job
│   └── LaborTable.tsx             — Labor entries table with filters
├── pages/
│   ├── ActiveJobsPage.tsx         — REPLACE stub: job list with filters + job cards
│   ├── MyClockPage.tsx            — NEW: active clock view or "clock into a job" list
│   ├── JobReportsListPage.tsx     — NEW: all reports across jobs, date-filtered
│   ├── JobDetailPage.tsx          — NEW: sub-tabs: Overview, Labor, Parts, Reports, One-Time Qs
│   ├── DailyReportView.tsx        — NEW: read-only rendered report (locked notebook page)
│   └── ClockOutQuestionsSettingsPage.tsx — NEW: boss manages global questions (in Settings)
└── stores/
    └── clock-store.ts             — Zustand: active clock state, GPS polling
```

---

### Step 7: Frontend — Clock-Out Flow (The Core UX)

**Clock-In Flow:**
1. User taps "Clock In" on a job card or detail page
2. Browser requests GPS permission → captures location
3. Optional: camera opens for clock-in photo
4. One-time question banner appears if any pending for this user + job
5. User is now clocked in — `clock-store.ts` tracks active clock

**During the Day:**
- One-time questions can be answered from a notification-style banner
- If unanswered, they persist until clock-out

**Clock-Out Flow (multi-step):**
1. **Step 1 — Questions**: All global questions displayed as cards (text input, yes/no toggle, optional photo per question). Any unanswered one-time questions appear below with a "One-Time" badge.
2. **Step 2 — Review**: Summary of answers, GPS location captured, optional clock-out photo
3. **Step 3 — Confirm**: "Clock Out" button. All required questions must be answered.
4. **POST** to `/api/jobs/clock-out` with GPS, photo, and all responses

**"Take Me There" Button:**
- On job cards in the list: small map icon next to address
- On job detail page: prominent "Navigate" button
- Both open `https://www.google.com/maps/dir/?api=1&destination={lat},{lng}` (works on all devices, opens native maps app on mobile)
- Fallback to address string if no GPS coordinates

---

### Step 8: Frontend — Navigation Changes

**Current Jobs tabs (navigation.ts):** `Active Jobs`, `Templates`
**New Jobs tabs after update:** `Active Jobs`, `My Clock`, `Reports`, `Templates`

**`navigation.ts` changes:**
- Jobs module: **add** `My Clock` and `Reports` tabs. Keep existing `Templates` stub.
  - `{ id: 'my-clock', label: 'My Clock', path: '/jobs/my-clock' }`
  - `{ id: 'reports', label: 'Reports', path: '/jobs/reports', permission: 'view_reports' }`
- Settings module: **add** `Clock-Out Questions` tab
  - `{ id: 'questions', label: 'Clock-Out Questions', path: '/settings/questions', permission: 'manage_settings' }`

**`App.tsx` new routes (keep existing `/jobs/active` and `/jobs/templates`):**
```
/jobs/my-clock        → MyClockPage (shows active clock or "not clocked in" state)
/jobs/reports         → JobReportsListPage (all jobs' reports, date-filterable)
/jobs/:id             → JobDetailPage (sub-tabs: Overview, Labor, Parts, Reports, One-Time Qs)
/jobs/:id/report/:date → DailyReportView (single day's locked report)
/settings/questions   → ClockOutQuestionsSettingsPage
```

**New pages needed:**
- `MyClockPage.tsx` — If clocked in: shows active job detail with timer + clock-out button. If not: shows "Not clocked in" with list of jobs to clock into.
- `JobReportsListPage.tsx` — Date picker + list of generated reports across all jobs, grouped by date.
- `JobDetailPage.tsx` — Full job view with sub-tabs (Overview, Labor, Parts, Reports, One-Time Qs). The sub-tabs are rendered as an internal tab bar within the page, NOT as sidebar tabs.
- `DailyReportView.tsx` — Read-only rendered report for a specific job + date.

---

### Step 9: Verification

1. **Create a job** with address → verify job card shows address + navigate icon
2. **"Take Me There"** → verify Google Maps opens with correct destination
3. **Clock in** → verify GPS captured, one-time question banner shows
4. **Answer one-time question** mid-day → verify it disappears from banner
5. **Clock out** → verify all global questions + remaining one-time questions appear
6. **Complete clock-out** → verify labor entry created with GPS, hours calculated
7. **Wait for midnight** (or trigger manually) → verify daily report generated
8. **View daily report** → verify all workers, answers, parts, costs displayed
9. **Boss edits global questions** → verify new questions appear on next clock-out
10. **Boss adds one-time question** → verify it shows for target user at clock-in
11. **Console errors** → zero across all new pages
12. **TypeScript** → `tsc --noEmit` clean
13. **Vite build** → passes

---

## Phases 5–12: Detailed Plans with Advanced Features

### Phase 5: Orders & Procurement
**Core:** Full PO lifecycle, procurement planner, returns wizard
**Advanced features:**
- **Smart reorder alerts** — When a part hits reorder point, auto-draft a PO with optimal supplier selection
- **Supplier scorecard dashboard** — Real-time reliability, cost trends, lead time graphs per supplier
- **Price history tracking** — Track cost changes over time, alert on >10% price increases
- **Multi-job consolidation engine** — Combine orders across jobs to hit volume discount brackets
- **Barcode scanning for receiving** — Scan parts as they arrive off the truck, auto-match to PO line items
- **Split delivery handling** — Partial receives with backorder tracking

### Phase 6: Trucks (Full)
**Core:** Truck CRUD, inventory per truck, tools tracking, maintenance, mileage
**Advanced features:**
- **Truck GPS tracking** — Real-time truck location on a map (via driver's phone GPS during clock-in)
- **Tool checkout/return system** — QR-based tool tracking (who has what, when was it returned)
- **Maintenance prediction** — Based on mileage + service history, predict next oil change, tire rotation
- **Fuel cost tracking** — Log fuel purchases, calculate cost-per-mile
- **Truck load optimization** — Suggest optimal truck loading based on tomorrow's job parts needs
- **Inter-truck transfers** — Move tools/parts between trucks via the movement wizard

### Phase 7: People (Full)
**Core:** Employee detail, certifications, hat management, permission matrix
**Advanced features:**
- **Certification expiry alerts** — Warn 30/60/90 days before certs expire (electrician license, OSHA, etc.)
- **Skills matrix** — Track who's qualified for what (panel work, underground, high voltage)
- **Availability calendar** — PTO, sick days, scheduled training
- **Emergency contact quick-dial** — One-tap call from the employee card
- **Performance dashboard** — Hours worked, jobs completed, audit accuracy per worker
- **Wage history** — Track pay rate changes over time with effective dates

### Phase 8: Reports & Export
**Core:** Pre-billing bundles, timesheets, labor overview, CSV/PDF export
**Advanced features:**
- **Auto-generated pre-billing packets** — PDF bundle: labor timesheet + parts consumed + cost summary per job
- **Period locking** — Lock a billing period so no backdated changes can be made
- **Profitability analysis** — Job profit margins: (billed hours × rate) − (labor cost + parts cost)
- **Trend charts** — Labor hours, parts consumption, cost trends over weeks/months
- **Bookkeeper export format** — Custom CSV mapping to match the bookkeeper's accounting software
- **Email reports** — Schedule weekly/monthly email summaries to boss/bookkeeper

### Phase 9: Chat
**Core:** Per-job group chat, DMs, mentions, timeline integration
**Advanced features:**
- **Photo/file sharing in chat** — Share job site photos, PDFs, sketches inline
- **Voice messages** — Record and send audio clips (faster than typing on job site)
- **@mentions with notifications** — Tag specific people, push notification
- **Read receipts** — Know when messages are seen
- **Chat search** — Full-text search across all conversations
- **Pinned messages** — Pin important info (codes, gate access, customer notes)

### Phase 10: AI Integration
**Core:** LM Studio connection, read-only tools, audit/admin/reminder agents
**Advanced features:**
- **Natural language inventory queries** — "How many GFI outlets do we have?" → instant answer
- **Smart scheduling suggestions** — Based on job priority, worker skills, and drive distances
- **Anomaly detection** — Flag unusual patterns (sudden stock drops, overtime spikes, missing clock-outs)
- **Report summarization** — AI summary of daily/weekly reports for the boss
- **Photo analysis** — Analyze job site photos for safety compliance
- **Predictive ordering** — Based on job pipeline + historical consumption, predict future parts needs

### Phase 11: PWA & Desktop
**Core:** Service worker, offline caching, Electron/Tauri wrapper
**Advanced features:**
- **Offline-first architecture** — Full app works without internet, syncs when reconnected
- **Push notifications** — Native push for messages, alerts, reminders
- **Home screen install** — PWA prompt for mobile devices
- **Auto-update** — Desktop app checks for updates and applies silently
- **Keyboard shortcuts** — Power-user shortcuts for common actions
- **System tray** — Desktop app runs in background, shows notification count

### Phase 12: Sync
**Core:** File-based sync (Drive/OneDrive), conflict detection, mobile offline queue
**Advanced features:**
- **Real-time collaboration** — Multiple users editing simultaneously with conflict resolution
- **Selective sync** — Choose which jobs/data to sync to mobile (save bandwidth)
- **Sync health dashboard** — Monitor sync status, conflicts, queue depth
- **Automatic backup** — Nightly SQLite backup to cloud storage
- **Cross-device clipboard** — Copy a part on desktop, paste on mobile
- **Audit trail for sync** — Track every sync event for debugging

---

## Deferred Tasks (Found in Code, Organized by Phase)

### Phase 4 (this phase — will be resolved)
- `warehouse.py` line ~512: Truck location lookup uses try/catch fallback (`"Truck #1"`) — needs real trucks table
- `warehouse.py` line ~532: Job location lookup uses try/catch fallback — needs real jobs table
- `InventoryGridPage.tsx` line 93: `handleSpotCheck` is empty (`// TODO: Navigate to audit page`)
- `dashboard.py`: Dashboard returns hardcoded zeros — needs real KPI queries

### Phase 5
- All `orders.py` router stubs (5 endpoints)

### Phase 6
- All `trucks.py` router stubs (5 endpoints)
- `warehouse/ToolsPage.tsx` stub ("Phase 6 tool tracking")

### Phase 7
- All `people.py` router stubs (3 endpoints)

### Phase 8
- All `reports.py` router stubs (4 endpoints)

### General (resolve any phase)
- `TopBar.tsx`: "Notification bell (stub)" — needs notification system
- `settings/SyncPage.tsx`: stub
- `settings/AiConfigPage.tsx`: stub
- `settings/DeviceManagementPage.tsx`: stub
- Dashboard page shows static/mocked KPI data

---

## Implementation Order (Phase 4 Steps)

| # | Task | Depends On |
|---|------|-----------|
| 1 | Create `docs/plans/` directory, save this plan, update CLAUDE.md with filing convention | — |
| 2 | Update `docs/implementation-plan.md` with Phase 3.5 undocumented work | — |
| 3 | Write migration `009_jobs_and_labor.sql` | — |
| 4 | Write migration `010_clockout_and_reports.sql` | 3 |
| 5 | Install `apscheduler`, create `scheduler.py` | — |
| 6 | Create `JobService` + `LaborService` | 3 |
| 7 | Create `QuestionnaireService` | 4 |
| 8 | Create `ReportService` + scheduler integration | 4, 5 |
| 9 | Replace job router stubs with real endpoints | 6, 7, 8 |
| 10 | Add frontend types to `types.ts` | 9 |
| 11 | Add API client functions to `api/jobs.ts` | 10 |
| 12 | Create `clock-store.ts` (Zustand) | — |
| 13 | Build `ActiveJobsPage` with job cards + "Take Me There" | 11 |
| 14 | Build `JobDetailPage` with sub-tabs | 11 |
| 15 | Build `ClockInOutButton` + GPS capture | 12 |
| 16 | Build `ClockOutFlow` (question cards, responses, confirm) | 15 |
| 17 | Build `OneTimeQuestionBanner` + mid-day answering | 16 |
| 18 | Build `DailyReportView` (locked report renderer) | 11 |
| 19 | Build `ClockOutQuestionsSettingsPage` (admin question manager) | 11 |
| 20 | Build `QuestionManager` with drag-to-reorder | 19 |
| 21 | Build `OneTimeQuestionForm` (boss adds per-job questions) | 14 |
| 22 | Update navigation.ts + App.tsx routes | 13-21 |
| 23 | Fix deferred tasks: dashboard KPIs, warehouse job/truck lookups | 9 |
| 24 | TypeScript check + Vite build + full visual verification | All |

---

## Critical Files to Modify

| File | Changes |
|------|---------|
| `backend/app/migrations/009_jobs_and_labor.sql` | NEW — jobs, job_parts, labor_entries |
| `backend/app/migrations/010_clockout_and_reports.sql` | NEW — questions, responses, reports |
| `backend/app/services/job_service.py` | NEW — job CRUD + status lifecycle |
| `backend/app/services/labor_service.py` | NEW — clock in/out + hours calculation |
| `backend/app/services/questionnaire_service.py` | NEW — question management + response capture |
| `backend/app/services/report_service.py` | NEW — daily report generation |
| `backend/app/scheduler.py` | NEW — APScheduler midnight cron |
| `backend/app/routers/jobs.py` | REPLACE stubs with full endpoints |
| `backend/app/models/jobs.py` | NEW — Pydantic models for all job entities |
| `backend/app/main.py` | ADD scheduler startup/shutdown |
| `backend/requirements.txt` | ADD `apscheduler` |
| `frontend/src/features/jobs/` | NEW — entire feature module |
| `frontend/src/stores/clock-store.ts` | NEW — active clock Zustand store |
| `frontend/src/api/jobs.ts` | NEW — all job API client functions |
| `frontend/src/lib/types.ts` | ADD job, labor, question, report types |
| `frontend/src/lib/navigation.ts` | UPDATE jobs module tabs |
| `frontend/src/App.tsx` | ADD job routes |
| `docs/implementation-plan.md` | UPDATE with Phase 3.5 + Phase 4 details |
| `CLAUDE.md` | ADD plan filing convention |
