# WiredPart iOS — Xcode AI Instructions

> **READ THIS FILE** at the start of every conversation. It tells you what the project is, how it's built, what patterns to follow, and what mistakes to avoid. This is your persistent memory.

---

## What This App Is

**WiredPart** is a construction/trade business management app for electricians and similar trades. It manages jobs, employees, parts inventory, warehouse operations, fleet/vehicles, tools, orders/procurement, scheduling, reports, chat, and notebooks.

**Who uses it:** Field workers (clock in/out, scan QR codes, file reports), warehouse staff (receive shipments, move stock, audit), office staff (approve orders, manage jobs, run reports), and managers (scheduling, budgets, team oversight).

---

## Platform Architecture

**One codebase, multiple platforms.** The iOS app (`Weird Parts IOS/`) uses a shared Swift package (`core/Sources/WiredPartCore/`) for all data logic. The same core package can be used by macOS.

| Layer | Technology | What It Does |
|-------|-----------|-------------|
| **UI** | SwiftUI (iOS 17+) | All views, navigation, design system |
| **State** | `AppCore` (ObservableObject) | Central state holder, all services, current user, permissions |
| **Services** | `WiredPartCore` Swift package | 15 service files — AuthService, JobsService, PartsService, etc. |
| **Database** | GRDB + SQLite | 23 migrations, ~130 tables, local-only (no cloud) |
| **Sync** | Apple Multipeer Connectivity + LAN HTTP | BT/Wi-Fi P2P between devices, LAN sync with shop computer |
| **AI** | Apple Foundation Models (macOS 26+) | On-device text prediction, tools integration |
| **QR/OCR** | VisionKit DataScannerViewController | Camera-based QR scanning, OCR text extraction |
| **Location** | CoreLocation | GPS for clock-in, geofencing for job transitions |

### Key Architectural Rule

All data is **local-first, offline-capable**. No cloud dependency. Devices sync peer-to-peer over Bluetooth and Wi-Fi when in range. The shop computer acts as a sync anchor.

---

## Sync Architecture (Bluetooth + LAN)

- **Transport:** Apple Multipeer Connectivity (BT/Wi-Fi P2P) for iOS↔iOS and iOS↔Mac. LAN HTTP (Axum server) for desktop sync anchor.
- **Conflict resolution:** Last-Writer-Wins (LWW) + field-level merge. Vector clocks per device.
- **Change tracking:** `_change_log` table records every INSERT/UPDATE/DELETE with sequence numbers.
- **Device trust:** Ed25519 certificate-based authentication. Devices exchange public keys during pairing.
- **Binary transfer:** 16KB chunked frames with CRC32 checksums for images/attachments.
- **Sync priority:** P0 = conflict resolution metadata, P1 = user-facing records, P2 = historical data, P3 = analytics, P4 = binary attachments.
- **Privacy:** Text prediction history (`_text_history`) is NEVER synced — local only.

### Current State

The sync infrastructure in the iOS app is **stubbed**. `IOSSyncManager.syncNow()` and `startPeerDiscovery()` are fake sleeps. The `SyncEngine`, `MultipeerManager`, `PeerManager`, `ConflictResolver`, and `ChangeTracker` classes exist in the core package with real implementations, but the iOS UI layer doesn't call them yet. Real sync integration is planned for a future phase.

---

## QR Code System

**Payload v2 schema:**
```json
{
  "app": "wiredpart",
  "version": 2,
  "type": "part | job | supplier | bin | vehicle | tool | employee | po",
  "id": 42,
  "code": "ELB-90-2IN-WHT",
  "meta": { "name": "2\" White 90 Elbow", "category": "Fittings" }
}
```

**8 entity types** with auto-fill across modules. Core codec: `QRCodec.swift`. iOS scanner: `IOSQRScanner.swift` (VisionKit DataScannerViewController). Auto-fill pipeline: `QRAutoFillService`.

**Backward compat:** v1 QR codes (no `type` field) default to `type: "part"`. Non-WiredPart QR codes display raw text and offer catalog search.

---

## Database Schema (23 Migrations, ~130 Tables)

Key tables by domain:

| Domain | Tables |
|--------|--------|
| **Auth** | `users`, `hats`, `hat_permissions`, `user_hats`, `devices`, `settings` |
| **Parts** | `part_categories`, `part_styles`, `part_types`, `part_colors`, `brands`, `suppliers`, `parts`, `brand_supplier_links`, `part_supplier_links`, `stock`, `stock_movements` |
| **Jobs** | `jobs`, `job_parts`, `labor_entries`, `daily_reports`, `job_team_members`, `clock_out_questions`, `clock_out_responses` |
| **Orders** | `job_parts_orders`, `jpo_line_items`, `purchase_orders`, `po_line_items`, `returns`, `order_status_history` |
| **Warehouse** | `warehouse_locations`, `stock_entries`, `receiving_sessions`, `staging_zones`, `staging_items` |
| **Fleet** | `vehicles`, `vehicle_assignments`, `fuel_logs`, `mileage_logs`, `maintenance_records` |
| **Tools** | `tools`, `kit_templates`, `tool_movements`, `tool_maintenance_records` |
| **People** | `certifications`, `wage_history`, `employee_notes`, `user_skills`, `employee_teams`, `customers`, `general_contractors` |
| **Scheduling** | `employee_default_schedules`, `schedule_exceptions`, `job_dispatch`, `dispatch_templates`, `pto_policies`, `pto_transactions` |
| **Chat** | `chat_channels`, `chat_messages`, `qa_threads`, `rfi_objects` |
| **Notebooks** | `notebook_templates`, `notebooks`, `notebook_sections`, `notebook_entries` |
| **Sync** | `_change_log`, `_conflict_log`, `_vector_clock`, `_device_registry` |
| **AI** | `_text_history`, `part_image_features`, `image_match_history` |

---

## Key Files

| File | What It Does |
|------|-------------|
| `App/AppCore.swift` | Central state. All services, current user, permissions. `@EnvironmentObject` everywhere. |
| `App/LocationManager.swift` | GPS wrapper. `getCurrentLocation()` returns `CLLocationCoordinate2D?` |
| `App/GeofenceManager.swift` | Monitors CLCircularRegion around clocked-in job. Fires `didExitJobRegion`. |
| `Navigation/IOSMainView.swift` | Root view. Tab bar + sidebar layout. Sheet presentation via enum. |
| `Navigation/IOSContentRouter.swift` | URL-path → View routing. Every page has a path like `/dashboard/clock`. |
| `Navigation/NavigationConfig.swift` | Module + tab definitions. Controls sidebar structure. |
| `core/Services/DashboardService.swift` | KPI queries, cert/vehicle alerts, daily report counts. |
| `core/Services/AuthService.swift` | PIN auth, user CRUD, permissions. |
| `core/Services/JobsService.swift` | Jobs, labor entries, clock in/out, daily reports. |
| `core/Services/PartsService.swift` | Parts hierarchy, brands, suppliers, stock, pricing, companions. |
| `core/Services/WarehouseService.swift` | Stock movements, receiving, audit, staging. |
| `core/Database/AppDatabase+Migrations.swift` | All 23 migrations. Schema source of truth. |

---

## Coding Standards

### 1. Error Handling — NEVER Swallow Errors

```swift
// BAD
catch { print("[Page] Error: \(error)") }

// GOOD
catch { loadError = error.localizedDescription; isLoading = false }
```

### 2. Sheets — ONE `.sheet` Per View Level

Use `.sheet(item:)` with an enum when multiple sheets are needed on the same view. Always reload data when sheet closes via `onSave` callback or `.onChange`.

### 3. UI States — Loading + Error + Empty + Content

Every data-loading view MUST handle all four states. Use `ErrorStateView` and `EmptyStateView` from `Shared/`.

### 4. No Placeholder Text

Never show "Phase X" or "TODO" to users. Use `EmptyStateView` with a clear user-facing message.

### 5. Concurrency

`Task { @MainActor in }` — never `DispatchQueue.main.asyncAfter`. No `fatalError()` in production paths.

### 6. CRUD — Every List Needs Add/Edit/Delete

### 7. Service Access

```swift
guard let service = appCore.jobsService else {
    isLoading = false; loadError = "Service unavailable"; return
}
```

---

## Known Issues (Updated 2026-03-18)

### Fixed (Prompt 01)
- CategoriesEditorPanel, CategoriesTreeView, IOSMainView, PartsCatalogPage, PartsSuppliersPage, PartsBrandsPage, PartsCompanionsPage — all converted to single `.sheet(item:)` enum pattern
- IOSClockPage, LaborPage, IOSVehicleDetailPage — added `.onChange` data reload on dismiss

### Still Open
- Sync layer is stubbed (IOSSyncManager, SyncWaitingView, DevicePairingView)
- AppCore uses IUOs (`db!`, `authService!`, `settingsService!`)
- ~25 pages print errors to console instead of showing to user
- ~10 pages have infinite spinner bug (guard-let-else-return without clearing isLoading)
- ~30 pages are read-only where CRUD is expected
- Security: PIN hashing uses fixed salt, invalid token magic string

---

## File Structure

```
Weird Parts IOS/
├── App/              ← AppCore, entry point, LocationManager, GeofenceManager
├── Auth/             ← Login, onboarding, device pairing, sync waiting
├── Navigation/       ← Tab bar, routing, content router, user menu
├── Features/
│   ├── Dashboard/    ← Overview (KPIs + clock banner), Clock, Daily Report, QR Scanner
│   ├── Jobs/         ← Job list, detail (9 tabs), labor, daily reports, questionnaire
│   ├── Parts/        ← Catalog, categories tree, brands, suppliers, pricing, companions
│   ├── Warehouse/    ← Inventory grid, movements wizard, receiving, audit, staging
│   ├── Orders/       ← JPOs, POs, procurement, returns, unified order form, approvals
│   ├── Fleet/        ← Vehicles, trailers, fuel, mileage, maintenance, inspections
│   ├── People/       ← Employees, customers, contractors, contacts, teams, hats
│   ├── Scheduling/   ← Dispatch, calendar, time off, templates, availability
│   ├── Notebooks/    ← Job notebooks, general notebooks, templates
│   ├── Chat/         ← Channels, messages, Q&A, RFI
│   ├── Tools/        ← Registry, kits, checkouts, maintenance, admin
│   ├── Reports/      ← Timesheets, labor, spending, profitability, pre-billing, exports
│   ├── Office/       ← Manage jobs, warehouse exec, spending dashboard
│   └── Settings/     ← 25+ settings pages (sync, BT, AI, themes, security, etc.)
├── DesignSystem/     ← DS tokens (spacing, colors, typography), styles, components
├── Shared/           ← EmptyState, ErrorState, FormSheet, SearchableList, StatusBadge
├── Scanning/         ← IOSQRScanner, IOSOCRScanner, DocumentScan, CameraMatch
├── Sync/             ← IOSSyncManager (stubbed), IOSPeerBrowser, IOSSyncStatusView
├── AI/               ← AI assistant panel, text editor, availability banner
└── WebFallback/      ← Fallback web view for features not yet native

core/Sources/WiredPartCore/
├── Database/         ← AppDatabase, migrations, BaseRepository
├── Models/           ← Domain models (Parts, Jobs, Orders, Fleet, etc.)
├── Services/         ← 15 service files (the data layer)
├── Sync/             ← SyncEngine, MultipeerManager, ConflictResolver, ChangeTracker
├── AI/               ← FoundationModelsService, TextPredictor, AITools
├── QR/               ← QRCodec, QRGenerator, QRScannerAdapter
├── OCR/              ← OCRProcessor, OCRScannerAdapter
└── ImageMatch/       ← ImageFeatureAdapter, ImageMatcher
```
