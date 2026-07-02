# WiredPart v1.0 — Testing Requirements & Verification Procedures

> **Document Owner:** QA Lead
> **Last Updated:** 2026-07-01 (metrics refresh, GitHub #1334)
> **Scope:** Complete testing strategy covering unit, integration, E2E, UI, performance, and security testing
> **Standard:** Production-grade quality for enterprise deployment
> **Paperclip staging update:** This remains the quality gate reference. The stage order and active/planned status live in `docs/plans/staged-paperclip-goals.md`.
> **Docs upgrade tracking:** GitHub [#942](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/942), Paperclip `WEI-3096` / `WEI-3099`; QA review `WEI-3100`.

For current command examples, local runner expectations, and handoff template, start with [`docs/QA-PROCESS.md`](QA-PROCESS.md). This file remains the detailed test-standard reference.

---

## 1. Test Architecture

### 1.1 Test Pyramid

```
          ┌─────────────┐
          │  Manual QA   │  ← Device testing, UX review, exploratory
          │  (~50 cases) │
         ─┼─────────────┼─
         ┌┴─────────────┴┐
         │   UI Tests     │  ← XCUITest, SwiftUI previews
         │  (~100 cases)  │
        ─┼───────────────┼─
        ┌┴───────────────┴┐
        │  Integration     │  ← E2E workflows, cross-service, sync
        │  (~150 tests)    │
       ─┼─────────────────┼─
       ┌┴─────────────────┴┐
       │   Unit Tests       │  ← Service methods, models, utilities
       │   (~300 tests)     │
       └───────────────────┘
```

### 1.2 Test Framework

- **Framework:** Swift Testing (modern, `@Suite` / `@Test` / `#expect()` macros)
- **NOT XCTest** — although XCUITest is used for UI tests
- **Database:** In-memory GRDB (`AppDatabase.openInMemoryDatabase()`) for all core tests
- **Isolation:** Every test creates a fresh database — no shared state between tests
- **Helper:** `E2ETestHelpers.TestEnvironment` provides the core services (22 total in the package) + admin user

### 1.3 Test Execution

```bash
# Run all core tests
cd core && swift test

# Run specific test suite
cd core && swift test --filter "AuthServiceTests"

# Run with verbose output
cd core && swift test --verbose

# List all tests
cd core && swift test list
```

**Expected output (as of 2026-07-01 — counts grow over time; treat as minimums):** `✔ Test run with 2224 tests in 67 suites passed after ~113 seconds.`

---

## 2. Core Service Test Requirements

### 2.1 Test Coverage Matrix

Every service MUST have tests covering:

| Category | Description | Required |
|----------|-------------|----------|
| **CRUD** | Create, Read, Update, Delete for each entity | YES |
| **Validation** | Invalid input, missing required fields, constraint violations | YES |
| **Business Rules** | Domain-specific logic (pricing calculations, compliance, etc.) | YES |
| **Edge Cases** | Empty datasets, null values, boundary values, large datasets | YES |
| **Error Paths** | What happens when DB is corrupted, table missing, FK violation | YES |
| **Integration** | Cross-service workflows that depend on this service | RECOMMENDED |

### 2.2 Service-by-Service Requirements

#### AuthService (83 tests across AuthServiceTests + E2EAuthBootstrapTests — COMPLETE)
- [x] Seed first admin with all 7 default hats
- [x] Prevent double-seeding
- [x] PIN hashing (bcrypt) and verification
- [x] Token generation and parsing
- [x] Invalid token rejection
- [x] User profile retrieval
- [x] Permission checking (has/doesn't have)
- [x] Active users listing
- [x] Wrong PIN rejection

#### PartsService (~339 tests across 8 parts test files — COMPLETE)
- [x] Category CRUD (create, list, get, update, delete)
- [x] Part hierarchy (category → style → type)
- [x] Part CRUD with all fields
- [x] Brand management
- [x] Supplier management
- [x] Pricing tiers and rules
- [x] Stock level tracking
- [x] Part search and filtering
- [x] Import/export data format

#### WarehouseService (~283 tests across 7 warehouse test files — COMPLETE)
- [x] Floor plan CRUD
- [x] Storage unit hierarchy (unit → level → area → bin)
- [x] Part assignment to areas
- [x] Location code generation
- [x] Movement wizard (source → destination → confirm)
- [x] Receiving sessions (create → scan items → complete)
- [x] Staging boxes (create → fill → close → reopen → delete)
- [x] Audit V2 sessions (start → count items → submit → review)
- [x] Part confidence scoring and decay
- [x] Warehouse ratings (user + organization)
- [x] Consolidation votes
- [x] Misplaced parts (log + resolve)
- [x] Trailer lifecycle + location history
- [x] Onboarding wizard (start → steps → complete)
- [x] Inventory/backorder/turnover reports

#### JobsService (160 tests across JobsServiceTests + E2EJobsLaborTests — COMPLETE)
- [x] Job CRUD with all fields
- [x] Job status transitions
- [x] Labor entry management (clock in/out)
- [x] Daily report linking
- [x] Job search and filtering

#### OrdersService (125 tests across OrdersServiceTests + E2EOrdersTests — COMPLETE)
- [x] JPO (Job Parts Order) CRUD + line items
- [x] PO (Purchase Order) CRUD + line items
- [x] JPO → PO conversion workflow
- [x] Procurement planner logic
- [x] Return management
- [x] Price history tracking
- [x] Supplier linking

#### FleetService (71 tests + shared E2EFleetPeopleTests — COMPLETE)
- [x] Vehicle CRUD
- [x] Driver assignment
- [x] Maintenance record management
- [x] Mileage tracking
- [x] Fuel log entries
- [x] Inspection templates
- [x] Trailer management

#### PeopleService (80 tests + shared E2EFleetPeopleTests — COMPLETE)
- [x] Employee CRUD
- [x] Customer/Contractor CRUD
- [x] Contact management
- [x] Team management
- [x] Hat (role) assignment
- [x] Certification tracking
- [x] Skills and wage management

#### SchedulingService (177 tests — COMPLETE)
- [x] Schedule entry CRUD
- [x] Dispatch management
- [x] Time-off requests (create, approve, deny)
- [x] Weekly availability
- [x] Template management
- [x] Conflict detection
- [x] Calendar view data generation

#### ChatService (60 tests + shared E2ECrossServiceTests — COMPLETE)
- [x] Channel creation
- [x] Message sending and receiving
- [x] Q&A thread management
- [x] RFI creation
- [x] Escalation workflow

#### NotebooksService (69 tests across NotebooksServiceTests + PanelScheduleTests — COMPLETE)
- [x] Notebook CRUD
- [x] Section management
- [x] Entry CRUD (text, checklist, photo)
- [x] Template management
- [x] Job notebook linking
- [x] Todo stage tracking

#### ToolsService (117 tests — COMPLETE)
- [x] Tool CRUD with all properties
- [x] Kit management (create, add tools, verify)
- [x] Checkout/return workflow
- [x] Maintenance scheduling and recording
- [x] Maintenance type management
- [x] Admin dashboard data

#### ReportsService (50 tests + shared E2ESettingsReportsTests — COMPLETE)
- [x] Report generation for each type
- [x] Period locking
- [x] Bookkeeper export format
- [x] Chart data generation

#### SettingsService (62 tests + shared E2ESettingsReportsTests — COMPLETE)
- [x] Company settings CRUD
- [x] Theme management
- [x] Notification preferences
- [x] Feature flags

#### DashboardService (57 tests — COMPLETE)
- [x] KPI summary (empty + with data)
- [x] Certification/vehicle alerts
- [x] Daily report generation
- [x] Full dashboard data aggregation
- [x] Budget alerts
- [x] Labor hours/clock/chart data
- [x] Stock/spending chart data
- [x] Active jobs picker
- [x] Employee count

#### BreakService (26 tests — COMPLETE)
- [x] Break policy CRUD (state-based)
- [x] Break bonus management + toggle
- [x] Start/end breaks
- [x] Active break detection
- [x] Break records for day
- [x] Company break settings
- [x] Compliance calculation
- [x] Time rounding logic

#### WishlistService (38 tests — COMPLETE)
- [x] Item CRUD
- [x] Status workflow (pending → approved → sent_to_procurement)
- [x] Dismiss and reopen
- [x] Status counts
- [x] Filter by status

#### BackgroundTaskService (9 tests — COMPLETE)
- [x] Task lifecycle (start → complete/fail)
- [x] Recent tasks ordering
- [x] Type filtering
- [x] Running tasks detection
- [x] 24-hour summary aggregation
- [x] Cleanup (old entries + stale tasks)

#### JobEstimationService (27 tests — COMPLETE)
- [x] Question CRUD
- [x] Stage-filtered questions
- [x] Question update and rejection
- [x] Response submission (including "unknown")
- [x] Estimate calculation
- [x] Results (latest + all)
- [x] Weekly and end-of-job reviews
- [x] Question effectiveness metrics
- [x] Monthly capacity calculation
- [x] Historical average

#### DailyReportGenerator (8 tests — COMPLETE)
- [x] Empty report generation (no data)
- [x] Today's jobs listing
- [x] Report metadata correctness

#### DeviceResetService (22 tests — COMPLETE)
- [x] Full device reset
- [x] Selective data reset
- [x] Reset verification

---

## 3. Sync & Infrastructure Tests

### 3.1 Sync Engine Tests
- [x] Change tracking (insert, update, delete events)
- [x] Pending count tracking
- [x] Mark synced operations
- [x] Max sequence calculation

### 3.2 Conflict Resolution Tests
- [x] LWW (last-write-wins) for same-field conflicts
- [x] Field-level merge for different-field changes
- [x] Conflict logging

### 3.3 Binary Sync Tests
- [x] Chunk round-trip (encode → decode)
- [x] CRC32 integrity verification
- [x] Corruption detection
- [x] Transfer progress tracking
- [x] Magic bytes validation

### 3.4 Peer & Connectivity Tests
- [x] Peer discovery lifecycle
- [x] Peer manager state machine
- [x] Sync priority queue ordering
- [x] LAN sync server endpoints

### 3.5 Crypto Tests
- [x] Ed25519 key generation and signing
- [x] Certificate verification
- [x] Encryption/decryption round-trip

---

## 4. AI/Vision Tests

### 4.1 QR Codec Tests
- [x] QR code generation
- [x] QR code parsing
- [x] Edge cases (empty, special characters)

### 4.2 OCR Processor Tests
- [x] Text extraction from images
- [x] Quantity extraction
- [x] PO number extraction
- [x] Empty input handling

### 4.3 Image Matcher Tests
- [x] Feature extraction
- [x] Match scoring

### 4.4 Text Predictor Tests
- [x] Text prediction
- [x] Confidence scoring

---

## 5. iOS UI Test Plan

### 5.1 Authentication Flow

| Test | Steps | Expected | Priority |
|------|-------|----------|----------|
| Fresh install | Launch app → Verify onboarding appears | Company setup wizard shown | P0 |
| Company setup | Enter company name + admin PIN → Submit | Admin created, redirected to dashboard | P0 |
| Login with correct PIN | Select user → Enter PIN → Submit | Dashboard loads | P0 |
| Login with wrong PIN | Select user → Enter wrong PIN → Submit | Error shown, no login | P0 |
| Logout | Tap user menu → Logout | Returns to user picker | P0 |
| Device pairing | Navigate to pairing → Search for peers | Peer list shown (or "no peers" message) | P1 |

### 5.2 Per-Module UI Tests

For each of the 14 feature modules, verify:

1. **Navigation** — Tab/sidebar navigation reaches the module
2. **List view** — Data loads (or empty state shown)
3. **Create** — "Add" button opens sheet, form validates, submit creates record
4. **Detail** — Tap item opens detail view with correct data
5. **Edit** — Edit button opens form, changes save correctly
6. **Delete** — Delete shows confirmation, removes record, list updates
7. **Search/Filter** — Search bar filters results correctly
8. **Dark mode** — All views render correctly in dark appearance
9. **Landscape** — iPad landscape layout doesn't break

### 5.3 Critical Interaction Tests

| Test | Module | Priority |
|------|--------|----------|
| QR code scan | Scanning | P0 |
| Clock in with GPS | Jobs/Clock | P0 |
| Movement wizard (4 steps) | Warehouse | P0 |
| JPO creation (multi-line) | Orders | P0 |
| Pre-trip inspection flow | Fleet | P1 |
| Warehouse onboarding wizard (6 steps) | Warehouse | P1 |
| Report builder | Reports | P1 |
| Template builder | Scheduling | P2 |
| Companion sandbox | Parts | P2 |

---

## 6. Performance Test Plan

### 6.1 Benchmark Suite

| Test | Setup | Target | Tool |
|------|-------|--------|------|
| Cold launch | Kill app → Launch | < 2s | Xcode Instruments |
| 10,000 parts scroll | Seed 10K parts → Open catalog → Scroll | 60 fps, no drops | Instruments |
| Search 10K parts | Seed 10K parts → Type search query | < 300ms results | Instruments |
| Dashboard KPI load | Seed realistic data → Open dashboard | < 1s | Instruments |
| Full sync (1000 records) | Create 1000 changes → Trigger sync | < 30s | Manual timer |
| Memory under load | Use app for 1 hour with periodic operations | < 150 MB peak | Instruments |

### 6.2 Stress Tests

| Test | Description | Target |
|------|-------------|--------|
| Rapid navigation | Switch between all 14 modules rapidly 100 times | No crashes, no leaks |
| Rapid create/delete | Create and delete 100 records in quick succession | No data corruption |
| Large form submit | Fill all fields on largest form with max-length text | Submits without crash |
| Simultaneous sync | 3 devices syncing with same shop simultaneously | No data loss |
| Background/foreground | Background app 50 times during operations | State preserved |

---

## 7. Security Test Plan

### 7.1 Authentication Tests

| Test | Steps | Expected |
|------|-------|----------|
| Brute force PIN | Try 10 wrong PINs rapidly | Account locked after 5 attempts |
| Session expiry | Set clock forward 25 hours | Session invalid, re-login required |
| Token tampering | Modify token string | Token rejected, forced logout |
| Permission escalation | Worker tries admin API | Operation denied at service layer |
| Device revocation | Revoke device → Sync | Device shows "disabled" screen |

### 7.2 Data Security Tests

| Test | Steps | Expected |
|------|-------|----------|
| SQL injection | Input `'; DROP TABLE users; --` in text fields | Input treated as text, no execution |
| XSS in text fields | Input `<script>alert(1)</script>` | Rendered as plain text |
| File path traversal | Input `../../etc/passwd` in file fields | Rejected or sandboxed |
| DB access from another app | Attempt to read DB file from separate app | iOS sandbox blocks access |
| Pasteboard leakage | Copy sensitive data → Switch apps | No PII in pasteboard |

### 7.3 Sync Security Tests

| Test | Steps | Expected |
|------|-------|----------|
| Unauthorized device sync | Unknown device attempts sync | Rejected (no valid certificate) |
| Man-in-the-middle | Intercept LAN sync traffic | Traffic encrypted, MITM fails |
| Replay attack | Capture and replay sync packets | Rejected (sequence number check) |
| Certificate revocation | Revoke device cert → Attempt sync | Sync denied |

---

## 8. Regression Test Procedure

### 8.1 Before Every Release

1. `cd core && swift test` — All 2,224+ tests must pass
2. Run full XCUITest suite — All UI tests must pass
3. Manual smoke test on physical iPhone + iPad
4. Dark mode spot check on 5 random pages
5. Sync test between 2 physical devices
6. Verify no new Xcode build warnings (SwiftLint is not currently configured in this repo — see the tools table)

### 8.2 Before Every PR Merge

1. `swift test` passes locally
2. No new warnings in build
3. New/changed code has corresponding test coverage
4. PR reviewed by 2 engineers

### 8.3 Weekly Regression

1. Full manual QA pass on all 14 feature modules
2. Performance benchmark comparison against baseline
3. 24-hour soak test on iPad (background + periodic usage)
4. Review crash logs from TestFlight (if active)

---

## 9. Bug Severity Definitions

| Severity | Definition | Example | Release Blocker? |
|----------|-----------|---------|------------------|
| **P0 — Critical** | Data loss, crash on core workflow, security vulnerability | DB corruption on sync, crash on clock-in | YES |
| **P1 — High** | Core feature broken, workaround exists but painful | Search returns wrong results, sheet won't dismiss | YES |
| **P2 — Medium** | Feature partially broken, reasonable workaround | Sort order wrong, dark mode color off | NO (must be triaged) |
| **P3 — Low** | Cosmetic, minor UX annoyance | Extra padding, typo in label | NO |
| **P4 — Trivial** | Improvement suggestion, not a bug | "Would be nice if..." | NO |

**Release rule:** Zero open P0/P1 bugs. All P2 triaged with documented decision (fix, defer, or won't fix).

---

## 10. Test Environment Requirements

### 10.1 Hardware

| Device | Purpose | Required |
|--------|---------|----------|
| Mac (Apple Silicon) | Build, run Xcode, simulators | YES |
| iPhone (physical) | UI testing, camera, GPS, BT | YES |
| iPad (physical) | Tablet layout, multitasking | YES |
| Second iOS device | Sync testing (BT + LAN) | YES |
| Wi-Fi router | LAN sync testing | YES |

### 10.2 Software

| Tool | Version | Purpose |
|------|---------|---------|
| Xcode | 26.2+ (repo verified with 26.5) | Build, test, profile |
| Swift | 6.0+ | Compilation |
| iOS Simulator | iOS 26.2+ (matches app deployment target) | Automated testing |
| Instruments | Latest | Performance profiling |
| SwiftLint | Not currently configured (no `.swiftlint.yml` / CI) — optional; use Xcode's built-in warnings | Code quality |
| TestFlight | Latest | Beta distribution |

### 10.3 Test Data

| Dataset | Records | Purpose |
|---------|---------|---------|
| Minimal | 1 user, 1 part, 1 job | Smoke test |
| Standard | 50 users, 500 parts, 20 jobs, 10 vehicles | Feature testing |
| Large | 200 users, 10,000 parts, 100 jobs, 50 vehicles | Performance testing |
| Stress | 500 users, 50,000 parts, 500 jobs | Stress testing |

---

*This document is maintained by the QA Lead and must be updated when new features are added or test requirements change.*
