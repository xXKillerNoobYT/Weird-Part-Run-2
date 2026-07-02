# WiredPart — What The App Can Do

> Last updated: 2026-07-01 (GitHub #1334)
> Purpose: Master feature overview of the current native iOS app, written for beta testers and the owner. For build/test instructions see [SETUP.md](SETUP.md); for the beta walkthrough see [BETA-TESTER-GUIDE.md](BETA-TESTER-GUIDE.md).
>
> The earlier React/FastAPI edition of this document (2026-03-06) described a retired architecture and is preserved in git history.

---

## 1) What WiredPart Is

WiredPart is an offline-first field-service operations app for an electrical contracting shop. Everything — parts, jobs, orders, people, schedules, reports — lives in a local database on your iPhone or iPad. No internet or cloud account is required; nearby company devices sync directly with each other.

It is a native SwiftUI app backed by a shared Swift core (`WiredPartCore`) that owns all business rules and data.

## 2) Current Build At A Glance

<!-- Verification commands (run from repo root, 2026-07-01):
  Feature folders: ls "Weird Parts IOS/Weird Parts IOS/Features/"
  Services:        ls core/Sources/WiredPartCore/Services/   (22 services across 26 Swift files)
  Migrations:      grep -c 'registerMigration(' core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift
  Core tests:      cd core && swift test   (2224 tests in 67 suites)
-->

| Metric | Value |
|--------|-------|
| Platform | iOS (iPhone + iPad), deployment target iOS 26.2 |
| Feature areas | 14 feature modules + onboarding, scanning, sync, and AI surfaces |
| Functional pages | ~87 |
| Core services | 22 (in `core/Sources/WiredPartCore/Services/`) |
| Database migrations | 109 (`000_change_log` → `105_job_records_local_first`) |
| Core test suite | 2,224 tests in 67 suites, all passing |
| Sync | Multipeer Connectivity (Bluetooth/Wi-Fi peer-to-peer) + LAN, local-first |
| AI | Apple Foundation Models (on-device), Vision + AVFoundation for QR/OCR |

---

## 3) Feature Areas

Each area below maps to a folder in `Weird Parts IOS/Weird Parts IOS/Features/`. Bullets describe what a user can do today.

### Dashboard
- See company KPIs at a glance (jobs, labor, stock, spending) and tap any card for a detail breakdown.
- Read the auto-generated daily report for the day's activity.
- Jump straight into a QR scan from the dashboard to look up a part or location.

### Parts
- Browse and search the full parts catalog; manage the category → style → type → color hierarchy in a tree editor.
- Manage brands and suppliers, including linking parts to preferred suppliers.
- Set pricing with cascade edits, bulk edits, per-part overrides, and pricing rules.
- Run demand forecasting with configurable settings, and manage companion-part rules (parts that travel together) with a sandbox to test rules safely.
- Import and export parts data (CSV/XLSX), preview OCR-based imports, and view a part's full history. "Smart delete" warns about anything still referencing a part.

### Warehouse
- Set up your warehouse with a guided onboarding wizard: zones, shelves, bins, areas, walking paths, and part placement on a floor-plan grid.
- Move stock with the guided Movement Wizard — source, destination, confirm — so every transfer is deliberate and logged.
- Receive shipments, stage pulled parts in boxes, and sort returns.
- Run inventory audits (personal and organization-wide) with counting sessions, summaries, and a verification leaderboard.
- View the live inventory grid, movement history, and warehouse settings; track trailers as mobile locations.

### Orders
- Create Job Parts Orders (JPOs) from the field, including multi-line orders with bulk hold selection.
- Convert JPOs to Purchase Orders in the office; view PO details, generate PO PDFs, and send them to suppliers.
- Plan purchases with the procurement planner; keep a wishlist of wanted items with an approval workflow.
- Receive shipments against orders, stage incoming parts, and process returns.

### Jobs
- Create and manage jobs with statuses, locations, and per-job detail tabs.
- Clock in and out with GPS, track labor entries, and answer clock-out questionnaires.
- Estimate jobs with a question-driven estimation flow and review estimates weekly and at job end.
- Read auto-generated daily reports and job-level report summaries.

### Fleet
- Manage vehicles and trailers, assign drivers, and see "My Truck" for your own assignment.
- Run pre-trip inspections against configurable checklists.
- Track maintenance schedules and records, fuel logs, and mileage.
- View trailer locations and truck tool assignments; a telematics page summarizes vehicle activity.

### Tools
- Keep a registry of company tools with detail pages and QR labels.
- Check tools out and back in; group tools into kits and run kit verification.
- Schedule and record tool maintenance; admins get a tools dashboard and policy controls.

### People
- Manage employees (certifications, skills, wages) with detail pages.
- Keep customer, contractor, and contact directories.
- Organize people into teams; assign hats (roles) and manage the permission matrix that controls what each hat can do.

### Scheduling
- Plan work on a schedule calendar; create schedule entries and dispatch crews to jobs.
- Manage short-term and long-term pipelines, plus a flex pool for unassigned capacity.
- Handle time-off requests, weekly availability, and subcontractor schedules.
- Build reusable schedule and dispatch templates.

### Reports
- Labor overview, timesheets, and profitability reports.
- Spending reports, pre-billing, and bookkeeper exports for accounting handoff.
- Fleet reports (fuel cost, maintenance trends, mileage summary, utilization), scheduling reports (crew utilization, dispatch efficiency, pipeline), and warehouse reports (backorder, inventory value, turnover).
- A report builder for custom reports, share/export utilities, and a public (shareable) report view.

### Notebooks
- Keep general and job-linked notebooks with sections and entries (text, checklists, photos).
- Start notebooks from templates; add entries quickly from the field.
- Build panel schedules with a dedicated builder.

### Chat
- Message in channels (including per-job channels) with threaded conversations.
- Ask formal Q&A questions with an escalation timeline so questions do not get lost.
- Raise and track RFIs (requests for information).

### Office
- Office dashboard for administrative oversight.
- Manage jobs in bulk, approve orders and requests in one unified approvals queue.
- Watch company spending on a spending dashboard; configure estimation settings; executive warehouse view.

### Settings
- Company profile, themes (light/dark), notifications, and app configuration.
- Security and device administration: device management, key management, security admin, audit log, database reset, backups, and data export.
- Sync controls: peer sync page, Bluetooth, remote sync, shared channels, and sync scope.
- Deep workflow configuration: break/lunch policies, clock-out questions, daily report templates, dispatch preferences, forecast settings, job stage templates, organization thresholds, PDF settings, pre-trip checklists, report templates, supplier bridge, tool policies, and update protocol.
- AI configuration for the on-device assistant.

---

## 4) Cross-Cutting Capabilities

These live outside the feature folders (`Scanning/`, `Sync/`, `Auth/`, `AI/`) and are used throughout the app.

### Scanning (QR + OCR)
- Scan QR codes to jump to parts, locations, and tools; print QR labels.
- Scan paper documents with the camera; OCR extracts text (quantities, PO numbers) and offers auto-fill.
- Camera-based part matching helps identify a part from a photo.

### Sync & Devices
- Local-first: the app is fully functional with zero connectivity.
- Nearby company devices discover each other (Multipeer Connectivity over Bluetooth/Wi-Fi) and sync changes peer-to-peer.
- Sync conflicts are detected, classified, and surfaced for review — including an AI-assisted conflict resolution view.
- Every change is tracked in a change log for reliable merging; device trust uses Ed25519 keys.

### Onboarding & Sign-In
- First launch offers two paths: **Create New Business** or **Join Existing Business** (pair with a device that already has the company data).
- New businesses set up an admin account (name + PIN) and can follow an 8-step company setup wizard: company profile, employees, hats, first job, parts, warehouse, break/lunch policy, done.
- Joining devices pair and wait while the initial sync completes.
- Sign-in is PIN-based (with biometric support); a module tour and walkthrough introduce the app.

### AI (On-Device)
- An AI assistant panel powered by Apple Foundation Models — everything runs on the device, nothing leaves it.
- AI-assisted text editing and availability-aware surfaces that only appear when the device supports them.

---

## 5) What WiredPart Does NOT Do (Current Scope)

- No cloud backend, cloud accounts, or internet sync — sync is between nearby company devices only.
- iOS only (an experimental macOS scheme exists in the workspace, but Apple platforms are the only target).
- No third-party analytics or tracking; all data stays on company devices.

See [BETA-TESTER-GUIDE.md](BETA-TESTER-GUIDE.md) for beta-specific known limitations.

---

## 6) Source-of-Truth Files

- Feature pages: `Weird Parts IOS/Weird Parts IOS/Features/` (14 folders)
- Business rules and data: `core/Sources/WiredPartCore/` (services, database, sync, AI)
- Plans and design decisions: `docs/plans/`
- Release gates: [RELEASE-READINESS-CHECKLIST.md](RELEASE-READINESS-CHECKLIST.md), [TESTING-REQUIREMENTS.md](TESTING-REQUIREMENTS.md)
