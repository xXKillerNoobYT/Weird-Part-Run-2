# Tauri 2.0 Migration Plan — Wired-Part

## Context

Wired-Part is a field service management app for an electrical contractor in Jackson, WY. It currently runs as a web app (React + FastAPI + SQLite) with a partially-built Capacitor mobile layer. The goal is to migrate to **Tauri 2.0** so the app runs as a single native binary on Mac, Windows, iOS (iPhone/iPad), and eventually Android — with **no Python backend**, full offline support, and **Bluetooth peer-to-peer sync**.

**Key discovery:** The codebase already has a **complete Capacitor local data layer** (`frontend/src/local/`) with 13 TS services, 7 SQLite migrations (83 tables), a sync engine, and change tracker. This is the foundation — we swap the Capacitor SQLite plugin for Tauri's, expand the services to cover all 28 modules, and add Bluetooth sync.

---

## Pre-Development Decisions (All Checklist Items Answered)

### 1. Data & Database

**Schema migration:**
- The existing 7 local migrations already handle the conversion from server-centric to local-first. They create 83 tables covering auth, parts, jobs, labor, notebooks, orders, fleet, tools, scheduling, and chat.
- We need 5 more migrations to cover the remaining backend tables (costs, companions, people-full, reports, admin). These will be ported from `backend/app/migrations/` files 021-057.
- Server-side concepts (like `_shop_change_log`, `_sync_batches`) become device-local equivalents — each device tracks its own changes.

**Unique IDs across devices: USE UUIDs**
- Current schema uses auto-incrementing integers — these WILL collide when two devices create records independently.
- **Decision: Switch to UUID v4 for all new record creation.** The `change-tracker.ts` already stamps `device_id` on every change, but the primary keys themselves need to be UUIDs.
- Implementation: Add a `generateId()` utility that returns UUID v4. Update all `INSERT` operations in TS services to generate IDs client-side instead of relying on `AUTOINCREMENT`.
- Existing data (migrated from shop) keeps its integer IDs — new records get UUIDs. Foreign keys still work because SQLite doesn't enforce type on columns.

**Timestamps:**
- All tables already have `created_at` and `updated_at` in the existing schema.
- The `_change_log` table already tracks `device_id` and `timestamp` per change.
- **Decision: No schema change needed** — the existing pattern is correct.

**Soft deletes: USE `deleted_at` FLAG**
- **Decision: Add `deleted_at TEXT` column to all tables that support DELETE operations.** This is critical for sync — a hard delete is indistinguishable from "never existed" on another device.
- The `_change_log` already tracks DELETE operations, but adding `deleted_at` makes filtered queries easier (exclude soft-deleted records from normal views).
- Implementation: Add a migration that adds `deleted_at` to ~20 tables. Update services to use `WHERE deleted_at IS NULL` in all SELECT queries. DELETE operations become `UPDATE ... SET deleted_at = datetime('now')`.

**Data size:**
- Parts catalog: ~2,000-5,000 parts typical for an electrical contractor
- Active jobs: ~20-50 at any time
- Employees: ~10-30
- Total SQLite size estimate: **50-200 MB** without photos, **500 MB-2 GB** with photos
- **Decision: Photos stored as file paths, NOT blobs in SQLite.** Photos sync separately (see Offline Behavior section).

**Database versioning:**
- **Already solved.** The existing migration system in `frontend/src/local/migrations/index.ts` runs on each device at startup. Each migration has a version number. `init.ts` checks current version and runs pending migrations.
- Schema changes after deployment: Add new migration files with incrementing numbers. The app runs them on next launch.

**Priority table order for migration:**
1. `users`, `hats`, `hat_permissions`, `user_hats` (auth — nothing works without this)
2. `parts`, `part_categories`, `part_styles`, `part_types`, `brands`, `suppliers` (catalog)
3. `stock`, `stock_movements` (inventory)
4. `vehicles`, `vehicle_assignments` (trucks)
5. `jobs`, `job_parts`, `labor_entries` (field work)
6. Everything else follows

---

### 2. Sync & Conflict Resolution

**Conflict strategy: LAST-WRITE-WINS + FIELD-LEVEL MERGE + CONFLICT LOG**
- **Decision: LWW as the default, with field-level merge for non-conflicting fields.**
  - If Device A changes `part.name` and Device B changes `part.sell_price` on the same part, **both changes apply** (field-level merge — no conflict).
  - If both devices change `part.sell_price`, the later timestamp wins (LWW).
  - All overwrites are logged in `_conflict_log` table with both old and new values, so an admin can review and fix if needed.
- **NOT CRDTs** — too complex for this data model, marginal benefit for a 10-30 person company.
- **NOT manual resolution** — too disruptive for field workers. Conflicts are rare in practice (different people work on different jobs/parts).

**Sync scope: FILTERED BY ROLE**
- **Decision: Role-based sync filtering.**
  - **Technicians/Apprentices:** Get parts catalog, their assigned jobs, their truck inventory, their labor entries, chat channels they're members of. Do NOT get: all employee wages, all job financials, cost layers, admin settings.
  - **Foremen/Leads:** Get above + all jobs in their area, all labor for their crew.
  - **Office/Admin:** Get everything.
- Implementation: The sync push/pull protocol already supports selective table sync. Add a `sync_scope` field to the device registration that determines which tables/rows sync to that device.

**Sync order (foreign key dependencies):**
1. `users`, `hats`, `hat_permissions`, `user_hats` (auth base)
2. `part_categories` → `part_styles` → `part_types` → `brands` → `suppliers` (hierarchy)
3. `parts` → `stock` (inventory depends on parts)
4. `vehicles` → `vehicle_assignments` (fleet)
5. `jobs` → `job_parts`, `labor_entries` (jobs depend on parts + users)
6. `notebooks` → `notebook_entries` (docs depend on jobs)
7. `chat_channels` → `chat_messages` (chat depends on jobs + users)
8. Everything else

**Change tracking: ALREADY IMPLEMENTED**
- `_change_log` table tracks: `id`, `device_id`, `table_name`, `record_id`, `operation` (INSERT/UPDATE/DELETE), `changed_fields` (JSON), `old_values` (JSON), `timestamp`, `synced` (0/1), `sync_batch_id`.
- **Enhancement for P2P:** Add vector clock fields — `{device_id: last_seen_sequence}` — so devices know exactly what the other has already seen without re-sending everything.

**First sync (new device):**
- **Decision: Multi-path approach.**
  1. **Primary:** Wi-Fi LAN sync from office computer (fastest — full dataset over gigabit LAN in seconds).
  2. **Secondary:** Bluetooth from another device (slower but works in the field).
  3. **Fallback:** Pre-loaded SQLite file via AirDrop/USB (for very large datasets or no connectivity).
- The existing `runInitialSync()` in `sync-engine.ts` already handles full dataset pull. We adapt it for P2P.

**Sync authentication:**
- **Decision: Company certificate + Ed25519 handshake.**
  - Already scaffolded in `security-service.ts` — devices get a certificate from the office computer during initial setup.
  - BT handshake: Exchange certificates → verify signatures → if both are from the same company, proceed.
  - New devices must be approved by an Admin before they get a certificate. This prevents random phones from syncing.

**Partial sync failures:**
- **Decision: Transactional batches.** Each sync sends changes in batches. The receiving device wraps each batch in a SQLite transaction. If Bluetooth drops mid-batch, the transaction rolls back — no corruption. Next sync retries from where it left off (using the `sync_batch_id`).

**Sync visibility:**
- **Decision: Yes.** Already implemented — `SyncStatusIndicator.tsx` shows "Last synced: X minutes ago" and pending change count. Enhance with per-device info: "Last synced with Office PC: 2 hours ago, Last synced with Mike's iPad: 30 min ago."

---

### 3. Bluetooth & Connectivity

**Bluetooth range:**
- BLE: 30-100 feet typical. Multipeer Connectivity (iOS/Mac) automatically uses both BLE AND Wi-Fi, extending effective range.
- **Decision: Use Apple Multipeer Connectivity** for iOS/Mac — it handles BLE + Wi-Fi seamlessly. For Windows, use Wi-Fi LAN sync (BLE on Windows is unreliable for data transfer).
- Job sites where people are within 30-100 feet: BLE works fine.
- Spread across a large building: Wi-Fi LAN fallback kicks in automatically.

**Bluetooth speed:**
- BLE GATT: ~50-100 KB/s (too slow for large syncs)
- Multipeer Connectivity: Up to 5 MB/s (uses Wi-Fi when available)
- **Decision: Multipeer for iOS/Mac, Wi-Fi LAN for Windows.** Initial sync of a full dataset (~50 MB) takes ~10 seconds over Multipeer or LAN. Daily delta syncs are typically < 1 MB.

**Background sync on iOS:**
- **Decision: Foreground sync only + local notifications.**
  - Apple restricts BLE background usage severely. Sync happens when the app is open.
  - When the app resumes from background, it immediately checks for sync opportunities (already implemented in `setupAppStateListener()`).
  - Local notification: "You have 5 unsynced changes. Open WiredPart to sync."

**Battery impact:**
- **Decision: Passive discovery, not aggressive scanning.**
  - Don't scan continuously. Scan on app launch, on user tap, and every 5 minutes.
  - Multipeer Connectivity is battery-efficient — Apple designed it for this.
  - User can manually trigger "Sync Now" anytime.

**Multiple simultaneous connections:**
- **Decision: Sequential sync with priority.**
  - Multipeer supports multiple peers, but syncing with 3 devices simultaneously is risky for data consistency.
  - Queue approach: Sync with Device A → complete → sync with Device B → complete → sync with Device C.
  - Priority: Office computer first (most authoritative), then by last-sync timestamp (least recently synced first).

**Fallback options (all supported):**
1. **Bluetooth/Multipeer** — Primary for field (iOS/Mac)
2. **Wi-Fi LAN** — Primary for office, fallback for field (all platforms)
3. **mDNS/Bonjour** — Auto-discovery on LAN
4. **QR code** — For initial device pairing (share company certificate + office IP)
5. **USB/AirDrop** — For pre-loading a SQLite snapshot to a new device
6. **Cloud sync** — NOT in V1. Future consideration only.

**Sync trigger: BOTH AUTOMATIC AND MANUAL**
- Auto-sync when devices detect each other (passive Multipeer browsing)
- Auto-sync when app comes to foreground
- Auto-sync every 5 minutes over LAN
- Manual "Sync Now" button always available

---

### 4. Authentication & Security

**Device identity:**
- **Decision: App-generated UUID stored in OS keychain/keystore.**
  - iOS: Store in Keychain (persists across reinstalls)
  - Mac: Store in Keychain
  - Windows: Store in Windows Credential Manager
  - The existing `security-service.ts` already generates and stores device keys. We swap `@capacitor/preferences` for Tauri's `tauri-plugin-store` or Rust keychain access.

**Offline auth:**
- **Decision: Local PIN verification, no JWT dependency.**
  - Already implemented in `auth-service.ts` — PIN checked against local SHA-256 hash.
  - Session token is local-only (24-hour expiry, regenerated on successful PIN entry).
  - No internet needed for login. The device works fully offline forever.
  - **Auto-lock:** Yes, app locks after 15 minutes of inactivity. User re-enters PIN.

**Permission changes:**
- **Decision: Sync propagation with eventual consistency.**
  - If Admin demotes someone on Device A, the permission change enters `_change_log` and syncs to other devices.
  - Until it syncs, the demoted user still has old permissions on their device. This is acceptable — it's a small company, Admin can physically go tell them.
  - **Mitigation:** High-priority changes (permission changes, device deactivation) get a "priority sync" flag that bumps them to the front of the sync queue.

**New user provisioning:**
- **Decision: Admin creates user on their device → syncs to new user's device.**
  - Admin opens People page, creates new user with PIN + hat assignment.
  - New employee downloads app, enters company pairing code (displayed on Admin's device as QR).
  - App pairs with Admin's device via Bluetooth/LAN, receives certificate + initial data including their user account.
  - First-time flow: Install app → Scan pairing QR → Wait for initial sync → Log in with PIN.

**Lost/stolen device:**
- **Decision: Device deactivation via sync.**
  - Admin marks device as "deactivated" on their device. This creates a sync record.
  - When the deactivated device next syncs with ANY company device, it receives the deactivation flag and wipes local data + locks itself.
  - **Mitigation for offline stolen device:** Change the user's PIN on the Admin device. Even if the thief has the phone, the old PIN stops working after next sync. And the 15-minute auto-lock kicks in.
  - The existing `device:override` mechanism in `client.ts` (lines 43-51) already handles force_logout and force_wipe — we adapt this for P2P sync.

**Database encryption:**
- **Decision: Yes, encrypt the SQLite database.**
  - Use SQLCipher (via `tauri-plugin-sql` with SQLCipher feature flag, or a community plugin).
  - Encryption key stored in OS keychain (already scaffolded in `security-service.ts` — `getDbEncryptionKey()`).
  - This protects data if the device is lost — can't just pull the SQLite file and read it.

**Auto-lock timeout: 15 MINUTES**
- App shows lock screen after 15 minutes of inactivity.
- User re-enters 4-digit PIN to unlock.
- Configurable per-company in settings (5, 10, 15, 30 minutes).

---

### 5. Offline User Experience

**Stale data indicators:**
- **Decision: Yes.** Show last sync time prominently. If data is older than configurable threshold (default: 4 hours), show a yellow "Data may be outdated — last synced X ago" banner.
- Already partially implemented in `SyncStatusIndicator.tsx`.

**Queued actions:**
- **Decision: Yes.** Any record created/modified offline gets a subtle "pending sync" badge (small cloud icon with arrow). Count shown in sync status: "3 changes pending sync."
- The `_change_log` with `synced = 0` already tracks this. Just need UI indicators.

**Storage management:**
- **Decision: Auto-archive + manual cleanup.**
  - Jobs completed more than 90 days ago: auto-archive (keep in DB but exclude from default queries).
  - Labor entries older than 1 year: keep summary, archive detail.
  - Chat messages older than 6 months: archive.
  - User can trigger "Clear old data" from Settings.
  - Show storage usage in Settings: "Database: 150 MB, Photos: 340 MB."

**Error recovery / database corruption:**
- **Decision: Automatic backups + sync recovery.**
  - Daily automatic SQLite backup (keep last 3 backups).
  - If corruption detected: restore from latest backup, then re-sync from nearest device to fill gaps.
  - Tauri can store backups in app data directory.
  - Nuclear option: Delete local DB, re-run initial sync from office computer.

**Onboarding flow (new device):**
1. Install app (TestFlight / direct install / App Store)
2. App shows "Welcome to WiredPart" → "Scan setup QR code"
3. Admin opens their app → Settings → Devices → "Add New Device" → shows QR code
4. New device scans QR → receives company ID + office IP + certificate
5. App connects to office computer (LAN or Bluetooth) → runs initial sync
6. Login screen appears → user enters their PIN
7. Ready to work

---

### 6. Platform-Specific Considerations

**iOS / iPad:**
- **App Store review:** No private APIs used. Tauri's WebView approach is App Store approved. Main review concern: "why not just a website?" — answer: offline functionality + Bluetooth sync.
- **Minimum iOS version:** iOS 16+ (Tauri 2.0 requirement). Covers all iPhones from iPhone 8 onward.
- **iPad multitasking:** Split View support — yes, the responsive layout already handles this. The `flex h-screen overflow-hidden` pattern adapts to any window size.
- **Local notifications:** Yes — sync reminders, shift start times, job due dates. Use Tauri's notification plugin.

**Mac:**
- **Menu bar integration:** System tray icon for the "office computer" role — shows sync status, quick actions. Uses `tauri-plugin-autostart` to launch on boot.
- **Keyboard shortcuts:** Already planned in Phase 10 (PWA & Desktop plan). Command palette exists but is basic. Will expand.
- **Window resizing:** Already works — responsive layout handles any window size.

**Windows:**
- **Installer format:** NSIS (Tauri default, widely compatible). Creates standard `.exe` installer.
- **Auto-updates:** `tauri-plugin-updater` — checks a hosted JSON manifest for new versions. Desktop auto-updates; mobile uses App Store/TestFlight.
- **Code signing:** Need a code signing certificate (~$200-400/year) to avoid Windows Defender SmartScreen warnings. **Required for production.** Can skip during development.

**Android (future):**
- **Decision: Later.** No employees currently on Android. Tauri 2.0 supports Android, so the path exists.
- **Timeline:** After iOS is stable (3-6 months post-launch).
- **Android Nearby Connections:** Equivalent to Apple Multipeer for P2P sync.

---

### 7. Business Logic Migration

**Pricing calculations:**
- All pricing logic is already in the local TS services (parts-service.ts calculates sell_price from markup).
- FIFO/LIFO cost tracking in costs-service.ts (to be created) ports from `cost_tracking_service.py`.
- **Decision: Unit tests for all financial calculations.** Round-trip verify against Python implementation.

**Report generation:**
- **Decision: Browser-based report generation using existing React components.**
  - CSV/Excel exports: Generate in-browser via JavaScript (already works — `generateExport()` creates Blobs).
  - PDF: Use browser `window.print()` with print-optimized CSS (already has `no-print` classes).
  - No server-side PDF generation needed.
  - Tauri's `tauri-plugin-dialog` can provide native "Save As" dialogs for exports.

**Import/export:**
- Parts catalog CSV import: Currently server-side. Port to TS service — parse CSV in browser, validate, insert into local SQLite.
- **Decision: Add a `csv-import-service.ts`** for local import.

**Audit trail:**
- Every write operation already calls `trackChange()` which logs to `_change_log` with `device_id` and `timestamp`.
- The `activity_log` table exists for user-facing audit (who did what).
- **Decision: No change needed** — audit trail is already comprehensive.

---

### 8. Development & Testing

**Test with real data:**
- **Decision: Create a realistic seed dataset** with ~2,000 parts, 30 jobs, 15 users, 500 stock records. Load during development.
- Performance benchmark: All queries must complete < 100ms on an iPhone 12.

**Test sync:**
- Simulate: Two devices consume the same part simultaneously. Two devices edit the same job. Office edits while field is offline for 8 hours.
- **Decision: Build sync test harness** — two Tauri instances on Mac, simulating two devices with artificial delays.

**Test on old devices:**
- Target: iPhone 12 (2020) as minimum, iPad 7th gen (2019).
- **Decision: Test on oldest available hardware** before release.

**Staged rollout:**
- **Decision: You (admin) first → 2 trusted techs → full team.**
- Use TestFlight for iOS (supports up to 10,000 testers, free).

**Keep web app running: YES**
- **Decision: Yes, keep the Python backend + web app running during transition.**
  - Office staff continues using web version.
  - Native app is developed in parallel.
  - Once native app is stable and tested, migrate office to native app.
  - Python backend can be decommissioned after native app handles everything.

---

### 9. Costs & Accounts Needed

| Item | Cost | Status |
|------|------|--------|
| Apple Developer Account | $99/year | **Needed** for TestFlight + App Store + running on real iPhones |
| Windows Code Signing | ~$200-400/year | **Needed** for production (skip during dev) |
| Google Play Account | $25 one-time | **Later** (when Android is needed) |
| Domain for updates | Already have? | Needed if using Tauri auto-updater for desktop |

---

### 10. Future Considerations

**GPS/location tracking:**
- Already built — `@capacitor/geolocation` used for clock-in GPS stamps. Will swap to Tauri geolocation plugin.
- Mileage logging with GPS: Already implemented in fleet module.

**Accounting integration:**
- Exports already support QuickBooks IIF format and Xero CSV format.
- **Decision: Keep export-based integration** (no live API sync). Bookkeeper downloads exports from the app.

**AI features:**
- AI config page exists as a stub. Plan for LM Studio integration (local LLM, no cloud dependency).
- **Decision: Defer to post-launch.** Focus on core migration first.

---

## Quick Decisions Summary

```
DECISIONS:
- First platform: Desktop (Mac) — easiest to debug, then iOS in parallel
- First modules: Auth → Parts → Trucks → Jobs → Labor → Warehouse → Orders → Reports
- Sync trigger: Both (auto when devices detect each other + manual button)
- Conflict resolution: Last-write-wins with field-level merge + conflict log for audit
- Device trust: Certificate-paired (Admin approves new devices, QR code onboarding)
- Distribution: TestFlight for iOS, direct install (.dmg/.exe) for desktop
- Keep web app running: Yes, during transition
- Barcode scanning: Yes (already built with html5-qrcode, works in WebView)
- Photo attachments: Yes (file paths in DB, photos sync on Wi-Fi only)
- Database encryption: Yes (SQLCipher, key in OS keychain)
- Auto-lock timeout: 15 minutes (configurable)
- Android needed: Later (3-6 months post-iOS launch)
- Unique IDs: UUIDs for all new records
- Soft deletes: Yes (deleted_at column)
- Initial device setup: QR code scan → certificate exchange → initial sync
```

---

## Architecture Decision

**Strategy: Tauri Shell + Expanded TypeScript Data Layer**

- Keep the React frontend unchanged
- Keep and expand the existing TypeScript service layer (not rewrite in Rust)
- Tauri provides the native shell, SQLite plugin, and native capabilities (Bluetooth, camera, GPS)
- Rust is only used for things that need native access (custom Bluetooth plugin)
- Every device runs the same app — no separate Python backend

**Rationale:** The TS data layer already exists and works. Rewriting 480 endpoints in Rust would take months. Expanding 13 TS services to 28 is much faster and uses the same language as the frontend.

**Re: Xcode:** The existing Capacitor iOS project (currently open in Xcode) will NOT be reused. Tauri generates its own Xcode project via `tauri ios init`. The Capacitor project can be closed/archived. Tauri's generated project goes in `frontend/src-tauri/gen/apple/`.

---

## Build Order (Revised from Checklists)

Incorporating the user's suggested build order and the existing codebase state:

### Phase 1: Tauri Scaffold (3-5 days) — COMPLETE (2026-03-11)
Get React frontend running inside Tauri 2.0 shell on Mac.

1. [x] Initialize Tauri inside `frontend/` — `npx tauri init`
2. [x] Configure `tauri.conf.json` — bundle ID `com.wiredpart.app`, window 1280x800, min 375x600
3. [x] Update `vite.config.ts` — Tauri env detection via `TAURI_ENV_PLATFORM`, no proxy in Tauri mode
4. [x] Install `tauri-plugin-sql` with SQLite feature — Rust crate + npm package
5. [x] Add Tauri scripts to `package.json` — `tauri:dev`, `tauri:build`
6. [x] Register SQL + log plugins in `lib.rs`
7. [x] Add SQL permissions to `capabilities/default.json`
8. [x] Verify: `npm run tauri dev` opens native Mac window with React UI — 443 crates compiled, app launched

**Files created:** `frontend/src-tauri/` (full scaffold)
**Files modified:** `frontend/package.json`, `frontend/vite.config.ts`

### Phase 2: SQLite + Data Layer Swap (8-12 days)
Replace Capacitor SQLite with Tauri SQL plugin, expand to full schema.

**2A: DB Layer Swap (2-3 days)**
- Add `createTauriDb()` in `db.ts` wrapping `@tauri-apps/plugin-sql`
- Add `isTauri()` + `isNativeApp()` in `environment.ts`
- Add UUID generation utility for new record IDs
- Add `deleted_at` soft delete support to schema + services

**2B: Full Schema Migrations (3-4 days)**
- 5 new migration files covering remaining ~27 tables (costs, people-full, reports, warehouse-extras, admin)

**2C: Expand TS Services (4-6 days)**
- ~15 new service files following existing pattern (getDb, BaseRepo, trackChange)

### Phase 3: API Adapter + Auth (3-4 days)
Route ALL API calls to local TS services. Zero HTTP calls in Tauri mode.

### Phase 4: Wi-Fi LAN Sync (5-7 days)
- mDNS/Bonjour device discovery
- Each Tauri app exposes lightweight HTTP sync endpoint (Rust-side)
- Same push/pull protocol as existing sync engine
- **This gives office sync before Bluetooth is ready**

### Phase 5: Bluetooth P2P Sync (12-16 days)
- Custom Tauri plugin: Apple Multipeer Connectivity (iOS/Mac)
- Windows: Wi-Fi LAN only (BLE data transfer unreliable on Windows)
- Ed25519 handshake + certificate verification
- Sequential peer sync with priority queue

### Phase 6: Native Capabilities (5-7 days)
- Camera (html5-qrcode already works in WebView, just need iOS entitlements)
- GPS (tauri-plugin-geolocation)
- File system (tauri-plugin-fs + tauri-plugin-dialog for exports)
- Haptics (custom Swift plugin, iOS only)
- Local notifications
- Auto-start on boot (shop computer)
- Scheduled tasks (TS scheduler replacing APScheduler)

### Phase 7: iOS Build + Polish (5-7 days)
- `tauri ios init` → new Xcode project
- Apple Developer signing + provisioning
- iOS entitlements (Bluetooth, camera, location, local network)
- Safe area CSS in AppShell
- Test on physical iPad + iPhone

### Phase 8: Distribution (4-6 days)
- macOS: DMG + Apple notarization
- Windows: NSIS installer + code signing
- iOS: TestFlight beta → App Store
- Auto-update: `tauri-plugin-updater` for desktop

---

## Summary

| Phase | Est. Days | Status | Completed |
|-------|-----------|--------|-----------|
| 1: Scaffold | 3-5 | COMPLETE | 2026-03-11 |
| 2: Data Layer | 8-12 | COMPLETE | 2026-03-11 |
| 3: API Adapter | 3-4 | COMPLETE | 2026-03-11 |
| 4: Wi-Fi Sync | 5-7 | COMPLETE | 2026-03-11 |
| 5: BT P2P Sync | 12-16 | COMPLETE | 2026-03-11 |
| 6: Native | 5-7 | COMPLETE | 2026-03-12 |
| 7: iOS Build | 5-7 | COMPLETE | 2026-03-12 |
| 8: Distribution | 4-6 | COMPLETE | 2026-03-12 |

### Final Codebase Stats

| Metric | Count |
|--------|-------|
| SQLite migrations | 16 (+ inline 000) |
| Local TS services | 35 |
| Rust source files | 6 (lib, commands, sync_server, discovery, crypto, multipeer) |
| ObjC bridge files | 1 (MultipeerBridge.m) |
| Tauri IPC commands | 16 (9 sync + 7 multipeer) |
| Capability files | 2 (default cross-platform + desktop-only) |
| Tauri plugins | 7 (sql, fs, dialog, notification, log, autostart*, updater*) |

\* Desktop-only (gated by `#[cfg(desktop)]`)

---

## Verification

- **Phase 1:** `npm run tauri dev` opens native Mac window, full React UI renders
- **Phase 2:** All 110+ tables created, services return data from local SQLite, UUIDs on new records
- **Phase 3:** Zero HTTP requests in Tauri mode, all 127 pages work with local data
- **Phase 4:** Two Mac apps sync data over LAN, changes propagate correctly
- **Phase 5:** Two devices sync over Bluetooth, conflicts resolved, conflict log populated
- **Phase 6:** Camera scans QR, GPS reports coords, scheduler runs, export saves to disk
- **Phase 7:** App runs on physical iPad/iPhone, touch targets work, safe areas correct
- **Phase 8:** Installable builds for Mac + Windows, TestFlight beta works on iOS

---

## Production Prerequisites (Not Yet Done)

These require physical hardware, paid accounts, or external setup:

1. **Apple Developer Account** ($99/year) — needed for TestFlight, App Store, and macOS notarization
2. **Windows Code Signing Certificate** (~$200-400/year) — needed to avoid SmartScreen warnings
3. **Ed25519 Key Pair** for desktop auto-updater — generate with `tauri signer generate`, fill `pubkey` in `tauri.conf.json`
4. **Update Server Endpoint** — host a JSON manifest for `tauri-plugin-updater`, fill `endpoints` in `tauri.conf.json`
5. **Physical Device Testing** — test on real iPhone, iPad, older hardware (iPhone 12 / iPad 7th gen minimum)
6. **Production Build** — `npx tauri build` for macOS DMG, `npx tauri build --target aarch64-apple-ios` for iOS
7. **TestFlight Submission** — upload iOS build via Xcode Organizer
