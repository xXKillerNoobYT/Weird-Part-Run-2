# Deployment Master Plan — V1.0 Customer-Ready Release

> **Date:** 2026-03-06 (revised 2026-03-09)
> **Goal:** Package Wired-Part as a **fully offline-capable** application where every device (shop computers, iPads, iPhones, Android phones) runs the full program with its own local database and syncs via Bluetooth.
> **Scope:** Phases 1–10 (complete) + Phase 11 Reports (planned) + offline data layer + Bluetooth sync + packaging + sideloading
> **Approach:** Full program on every device. 100% local-first. Bluetooth mesh sync between all devices. Shop computer is truth anchor but also a BT peer.
> **Related docs:** `Device Sync management.md`, `Mobile device bootstrap.md`, `Update protocol.md`, `phase-13-sync-bluetooth.md`

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [V1.0 Release Checklist](#2-v10-release-checklist)
3. [Shop Server Package](#3-shop-server-package)
4. [Offline Data Layer (TypeScript)](#4-offline-data-layer-typescript)
5. [Sync Engine (Device ↔ Shop)](#5-sync-engine-device--shop)
6. [Capacitor Mobile Apps](#6-capacitor-mobile-apps)
7. [iOS Distribution (Free Sideloading)](#7-ios-distribution-free-sideloading)
8. [Android Distribution (APK Sideload)](#8-android-distribution-apk-sideload)
9. [Desktop Browser Access](#9-desktop-browser-access)
10. [Production Hardening](#10-production-hardening)
11. [Build Scripts & Automation](#11-build-scripts--automation)
12. [Customer Setup Guide](#12-customer-setup-guide)
13. [Execution Order](#13-execution-order)

---

## 1. Architecture Overview

**Every device runs the full program.** The shop computer is the truth anchor and handles conflict resolution, but field devices are self-sufficient — they work offline, create orders, clock in/out, move stock, everything — with no network dependency.

```
┌─────────────────────────────────────────────────────────┐
│                    SHOP COMPUTER                         │
│                  (Windows or Mac)                         │
│                                                          │
│  ┌──────────────────┐  ┌──────────────────────────────┐ │
│  │  FastAPI Backend  │  │  Built Frontend (static)     │ │
│  │  (Python 3.12)   │  │  (React/Vite bundle)         │ │
│  │  Port 8000       │  │  Served by FastAPI            │ │
│  │                  │  │  at /                         │ │
│  │  SQLite DB       │  │                              │ │
│  │  (TRUTH ANCHOR)  │  │                              │ │
│  │  APScheduler     │  │                              │ │
│  │  Sync Endpoint   │  │                              │ │
│  └──────────────────┘  └──────────────────────────────┘ │
│                                                          │
│  LAN IP: e.g. 192.168.1.100:8000                        │
└────────────────────┬────────────────────────────────────┘
                     │ LAN / Wi-Fi (sync when available)
        ┌────────────┼────────────────┐
        │            │                │
   ┌────▼─────┐ ┌───▼──────┐  ┌─────▼───────┐
   │  iPad    │ │  iPhone   │  │  Android    │
   │          │ │           │  │             │
   │ React UI │ │ React UI  │  │ React UI    │
   │ TS Data  │ │ TS Data   │  │ TS Data     │
   │  Layer   │ │  Layer    │  │  Layer      │
   │ SQLite   │ │ SQLite    │  │ SQLite      │
   │ (local)  │ │ (local)   │  │ (local)     │
   │          │ │           │  │             │
   │ WORKS    │ │ WORKS     │  │ WORKS       │
   │ OFFLINE  │ │ OFFLINE   │  │ OFFLINE     │
   └──────────┘ └───────────┘  └─────────────┘
        │            │                │
   ┌────▼─────┐ ┌───▼──────┐  ┌─────▼───────┐
   │ Desktop  │ │  Mac      │  │  Windows    │
   │ Browser  │ │ Browser   │  │  Browser    │
   │ (hits    │ │ (hits     │  │  (hits      │
   │  shop    │ │  shop     │  │   shop      │
   │  server) │ │  server)  │  │   server)   │
   └──────────┘ └───────────┘  └─────────────┘
```

### How It Works

**Mobile devices (Capacitor apps):**
1. Run the **full frontend** with a **lean field-worker backend** — React UI + TypeScript data layer + SQLite database
2. The mobile data layer is a **subset** of the shop's Python backend — only the services field workers need (jobs, clock, stock, orders, tools, notebooks)
3. All operations (CRUD, clock in/out, orders, movements) write to the **local database**
4. When device connects to the shop Wi-Fi, the **sync engine** pushes changes up and pulls changes down
5. If the shop is unreachable — no problem, everything still works
6. Native features: camera (QR scanning, photos), GPS (clock-in/out), notifications
7. Admin features (cost tracking, approvals, PDF reports) are **not on the device** — those are shop-only

**Shop computer:**
1. Runs the **Python FastAPI backend** (already built — no changes to business logic)
2. Serves the **built frontend** as static files for desktop browsers on the LAN
3. Hosts the **sync API** — receives changes from mobile devices, sends back updates
4. Is the **truth anchor** — resolves conflicts, generates reports, runs APScheduler
5. The authoritative database that all devices eventually converge with

**Desktop browsers:**
1. Hit the shop server directly at `http://<shop-ip>:8000`
2. Standard web app — requires LAN connection (these machines are always at the shop)
3. No offline capability needed (they're literally sitting next to the server)

### Why This Architecture

- **Field workers aren't always on Wi-Fi.** They're on job sites, in trucks, underground. The app must work without any network.
- **Full read AND write offline.** Workers can create orders, clock in/out, move stock, update notebooks — all offline. Everything syncs when devices are in Bluetooth range.
- **No network infrastructure needed.** Bluetooth sync means no Wi-Fi setup, no router config, no shop URL. Devices just find each other.
- **Mesh propagation.** Data spreads naturally: Worker A syncs with Worker B on-site → Worker B returns to shop → shop gets everyone's data. Even if a worker hasn't been to the shop in a week, their data arrives via other workers.
- **One shared UI codebase.** React frontend is identical everywhere. Only the data access layer switches between "local SQLite" (mobile/Capacitor) and "HTTP API" (desktop browser at shop).

### V1.0 Architecture (Revised 2026-03-09)

**Key change:** Bluetooth sync is now V1.0, not V2.0. LAN/HTTP sync is deferred — devices talk to each other and to the shop computer via Bluetooth. This eliminates the need for shop URL configuration, CORS setup, and network infrastructure. Devices just need to be in BT range of each other or the shop.

| Capability | V1.0 | V2.0 |
|-----------|------|------|
| Device has local database | ✅ | ✅ |
| Full offline read/write | ✅ | ✅ |
| Sync with shop over LAN | ❌ (deferred) | ✅ |
| Sync via Bluetooth | ✅ | ✅ |
| Device-to-device sync (mesh) | ✅ | ✅ |
| Device pairing (QR code) | ✅ | ✅ |
| Encrypted sync (PGP) | ✅ | ✅ |
| Bootstrap app (App Store shell) | ❌ | ✅ |
| Multi-PC shop cluster | ❌ | ✅ |
| LAN sync (HTTP fallback) | ❌ | ✅ |
| Auto-update via mesh | ❌ | ✅ |

---

## 2. V1.0 Release Checklist

Everything that must be done before the first customer deployment.

### 2.1 Feature Completion

| Item | Status | Plan File | Notes |
|------|--------|-----------|-------|
| Phases 1–10 | ✅ Complete | Various | Core app fully built (Python backend) |
| Phase 11: Reports & Pre-Billing | 📋 Planned | `phase-11-reports-prebilling.md` | 4 stub pages → real pages, 4 stub endpoints → real data |
| Legacy Cleanup | 📋 Planned | `legacy-cleanup-plan.md` | Delete ~5 superseded pages, clean routes |

### 2.2 Offline Architecture (Status as of 2026-03-09)

| Item | Status | Notes |
|------|--------|-------|
| TypeScript data layer (12 services) | ✅ Done | Auth, jobs, labor, movement, notebooks, orders, parts, warehouse, fleet, scheduling, tools, chat — all fully implemented (~120KB of real SQL logic) |
| SQLite schema (TS migrations) | ✅ Done | 7 migration files (~70KB SQL), covers all 70+ tables. Auto-runs on app init |
| Capacitor SQLite plugin | ✅ Done | `@capacitor-community/sqlite` installed, `db.ts` wrapper, lazy singleton connection |
| Base repository (generic CRUD) | ✅ Done | `base-repo.ts` — getById, findAll, count, insert, update, delete. All writes auto-track changes |
| Change tracking (`_change_log`) | ✅ Done | `change-tracker.ts` — logs INSERT/UPDATE/DELETE per row, tracks old values, 30-day retention |
| Environment detection | ✅ Done | `environment.ts` — `isCapacitor()`, `isBrowser()`, `getPlatform()`, `getApiBaseUrl()` |
| API adapter pattern | ⚠️ Defined but not wired | `adapter.ts` exists with `adaptedRequest(httpFn, localFn?)`. **Only `auth.ts` uses it** (4 calls). The other ~300 API calls in 22 files still hardcode HTTP — this is the critical remaining work |
| Auth flow (local) | ✅ Done | PIN login against local SQLite, user picker, device login fallback |
| App initialization | ✅ Done | `init.ts` + `AuthGate.tsx` — inits DB, runs migrations, starts auth on Capacitor boot |
| Capacitor iOS project | ✅ Done | Xcode builds clean, 9 plugins, Info.plist permissions, sandbox fixed |
| Sync engine (HTTP — device side) | ✅ Done | `sync-engine.ts` — push/pull/ack over HTTP, exponential backoff, state management. **Will be replaced with BT transport** |
| Sync API (shop side — HTTP) | ⬜ Deferred | Was for LAN sync. **Replaced by BT sync in V1.0** |
| **Bluetooth sync engine** | ⬜ Not started | See `phase-13-sync-bluetooth.md`. Replaces HTTP sync. Needs: BLE plugin, handshake, gossip protocol, encrypted data exchange |
| **BT device pairing** | ⬜ Not started | QR code pairing, certificate exchange, company verification |
| **Crypto service** | ⬜ Not started | Key generation, certificate signing, AES-256-GCM session encryption |
| Conflict resolution | ✅ Done (logic) | Last-writer-wins via timestamp comparison in change tracker |
| Sync status UI | ⬜ Not started | Banner showing "Synced" / "X changes pending" / "Syncing..." |

**Critical path to "works 100% local":**
1. ⚠️ **Wire API adapter** — route ~300 API calls through `adaptedRequest()` in 22 files (mechanical but large — estimated 2-3 days)
2. ⚠️ **Fix merge conflict** in `auth.ts` lines 98-109
3. Then the app runs fully offline on any device with zero network dependency

**Critical path to "syncs via Bluetooth":**
4. Install `@capacitor-community/bluetooth-le` + `capacitor-secure-storage-plugin`
5. Build `bt-service.ts` (BLE scanning, connection, handshake)
6. Build `crypto-service.ts` (key generation, certificate verification, session encryption)
7. Replace HTTP transport in sync-engine with BT transport
8. Build pairing flow (QR code from shop → device scans → certificate exchange)
9. Build gossip protocol (undelivered change propagation between peers)
10. Build SyncStatusPage + SyncIndicator + BluetoothPage UI

### 2.3 Quality & Testing

| Item | Status | Plan File | Notes |
|------|--------|-----------|-------|
| Critical path tests | 📋 Planned | `testing-strategy.md` | Auth, orders, clock, receiving, movements |
| Offline mode tests | ⬜ | | Verify all CRUD works with no network |
| Sync round-trip tests | ⬜ | | Create on device → sync → verify on shop → sync back |
| Conflict resolution tests | ⬜ | | Same record edited on 2 devices → shop resolves |
| Cross-browser testing | ⬜ | This plan | Safari + Chrome on all platforms |
| Responsive audit | ⬜ | Feature audit files | All 60+ pages at 4 breakpoints |

### 2.4 Production Hardening

| Item | Status | Notes |
|------|--------|-------|
| Static file serving from FastAPI | ⬜ | Mount `frontend/dist` at `/` for desktop browsers |
| Production CORS config | ⬜ | Allow `<shop-ip>:8000` + Capacitor origins |
| Secret key management | ⬜ | Generate random SECRET_KEY at install |
| Error handling & logging | ⬜ | Structured logging to file, graceful error pages |
| Database backup script | ⬜ | Scheduled SQLite backup to `backups/` folder |
| App icons & splash screens | ⬜ | Real logo for Capacitor builds |
| PWA manifest (browser fallback) | ⬜ | For desktop "Add to Home Screen" |

### 2.5 Packaging & Distribution

| Item | Status | Notes |
|------|--------|-------|
| Shop server startup script (Windows) | ⬜ | PowerShell script or Windows Service |
| Shop server startup script (Mac) | ⬜ | Shell script or launchd plist |
| Capacitor project initialized | ✅ Done | iOS platform scaffolded, 9 plugins, Xcode builds clean (2026-03-09) |
| iOS build → free sideloading | ⬜ | Sideloadly + AltServer (free). Mac + Xcode ready. |
| Android build → APK | ⬜ | Can build from any OS with Android Studio |
| Sideloading guide | ⬜ | `docs/plans/sideloading-guide.md` |
| Customer setup guide | ⬜ | End-to-end install instructions for the shop owner |

---

## 3. Shop Server Package

The shop server is the heart of the system. It runs on a Windows PC or Mac and serves all devices.

### 3.1 Production Mode Backend

**Current (dev mode):**
```bash
cd backend
uvicorn app.main:app --reload --port 8000
```

**Production mode:**
```bash
cd backend
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2 --log-level info
```

Key changes for production:
- `--host 0.0.0.0` — Listen on all network interfaces (not just localhost)
- `--workers 2` — Handle concurrent requests (SQLite WAL mode supports this)
- No `--reload` — Don't watch for file changes
- `--log-level info` — Structured logging, not debug noise

### 3.2 Serve Frontend Static Files from FastAPI

Add to `backend/app/main.py` after router registration:

```python
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pathlib import Path

# Serve built frontend static files
FRONTEND_DIST = Path(__file__).parent.parent.parent / "frontend" / "dist"

if FRONTEND_DIST.exists():
    # Serve static assets (JS, CSS, images)
    app.mount("/assets", StaticFiles(directory=FRONTEND_DIST / "assets"), name="static")

    # Catch-all: serve index.html for client-side routing
    @app.get("/{full_path:path}")
    async def serve_spa(full_path: str):
        """Serve the React SPA for any non-API route."""
        file_path = FRONTEND_DIST / full_path
        if file_path.is_file():
            return FileResponse(file_path)
        return FileResponse(FRONTEND_DIST / "index.html")
```

### 3.3 Frontend Build for Production

```bash
cd frontend
npm run build
# Output: frontend/dist/
```

The Vite build produces optimized static files in `frontend/dist/` that FastAPI serves.

### 3.4 Windows Startup Script

`scripts/start-server.ps1`:
```powershell
# Wired-Part Server Startup Script (Windows)
# Run this to start the shop server

$ErrorActionPreference = "Stop"
$ROOT = Split-Path $PSScriptRoot -Parent

Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Wired-Part Shop Server" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan

# 1. Check Python
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host "ERROR: Python not found. Install Python 3.12+ from python.org" -ForegroundColor Red
    exit 1
}

# 2. Check/create virtual environment
$venvPath = Join-Path $ROOT "backend\.venv"
if (-not (Test-Path $venvPath)) {
    Write-Host "Creating virtual environment..." -ForegroundColor Yellow
    python -m venv $venvPath
    & "$venvPath\Scripts\pip.exe" install -r (Join-Path $ROOT "backend\requirements.txt")
}

# 3. Build frontend if needed
$distPath = Join-Path $ROOT "frontend\dist"
if (-not (Test-Path $distPath)) {
    Write-Host "Building frontend..." -ForegroundColor Yellow
    Set-Location (Join-Path $ROOT "frontend")
    npm install
    npm run build
}

# 4. Detect LAN IP
$lanIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -notmatch "^169\."
} | Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  Server starting at:" -ForegroundColor Green
Write-Host "    Local:   http://localhost:8000" -ForegroundColor White
Write-Host "    Network: http://${lanIp}:8000" -ForegroundColor White
Write-Host ""
Write-Host "  Field devices connect to: http://${lanIp}:8000" -ForegroundColor Yellow
Write-Host ""

# 5. Start the server
Set-Location (Join-Path $ROOT "backend")
& "$venvPath\Scripts\uvicorn.exe" app.main:app --host 0.0.0.0 --port 8000 --workers 2 --log-level info
```

### 3.5 Mac Startup Script

`scripts/start-server.sh`:
```bash
#!/bin/bash
# Wired-Part Server Startup Script (Mac/Linux)

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "═══════════════════════════════════════════"
echo "  Wired-Part Shop Server"
echo "═══════════════════════════════════════════"

# 1. Check Python
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 not found. Install Python 3.12+ from python.org"
    exit 1
fi

# 2. Check/create virtual environment
VENV="$ROOT/backend/.venv"
if [ ! -d "$VENV" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -r "$ROOT/backend/requirements.txt"
fi

# 3. Build frontend if needed
if [ ! -d "$ROOT/frontend/dist" ]; then
    echo "Building frontend..."
    cd "$ROOT/frontend"
    npm install
    npm run build
fi

# 4. Detect LAN IP
LAN_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')

echo ""
echo "  Server starting at:"
echo "    Local:   http://localhost:8000"
echo "    Network: http://${LAN_IP}:8000"
echo ""
echo "  Field devices connect to: http://${LAN_IP}:8000"
echo ""

# 5. Start the server
cd "$ROOT/backend"
"$VENV/bin/uvicorn" app.main:app --host 0.0.0.0 --port 8000 --workers 2 --log-level info
```

### 3.6 Auto-Start on Boot (Optional)

**Windows**: Create a Scheduled Task that runs `start-server.ps1` at login
**Mac**: Create a LaunchAgent plist in `~/Library/LaunchAgents/`

Instructions in the Customer Setup Guide.

---

## 4. Offline Data Layer (TypeScript)

This is the core V1.0 architectural work. The frontend needs a **local data access layer** so mobile devices can run the field-worker workflow without any network connection. This is a **lean subset** of the Python backend — only the services field workers actually need. Admin features (cost tracking, approvals, PDF generation, reports) stay shop-only.

### 4.1 How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                    REACT FRONTEND (same on all devices)          │
│                                                                  │
│  Components call:  useQuery('parts', () => api.parts.list())    │
│                                                                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                     ┌───────▼───────┐
                     │  API Adapter  │  ← detects environment
                     └───┬───────┬───┘
                         │       │
          ┌──────────────▼──┐ ┌──▼──────────────┐
          │  HTTP Client    │ │  Local Data      │
          │  (Desktop       │ │  Layer           │
          │   browsers)     │ │  (Capacitor      │
          │                 │ │   mobile apps)   │
          │  axios →        │ │                  │
          │  shop:8000/api  │ │  TS Services →   │
          │                 │ │  SQLite (local)  │
          └─────────────────┘ └──────────────────┘
```

**On desktop browsers:** API calls go to `http://<shop-ip>:8000/api` via axios (same as current behavior).

**On Capacitor mobile apps:** API calls are intercepted by the adapter layer and routed to local TypeScript services that read/write from the device's local SQLite database. No network needed.

### 4.2 The API Adapter Pattern

The key abstraction — the frontend doesn't know or care whether it's talking to a remote server or a local database.

**`frontend/src/api/adapter.ts`:**
```typescript
import { isCapacitorApp } from '../lib/platform';
import * as httpClient from './http-client';   // existing axios-based client
import * as localClient from './local-client'; // new: local SQLite client

/**
 * Returns the correct API implementation based on platform.
 * - Desktop browsers → HTTP calls to shop server
 * - Capacitor mobile → local TypeScript services + SQLite
 */
export function getApi() {
  if (isCapacitorApp()) {
    return localClient;
  }
  return httpClient;
}
```

**Frontend components don't change.** They call `api.parts.list()` and the adapter routes it to the right implementation.

### 4.3 Capacitor SQLite Setup

```bash
cd frontend
npm install @capacitor-community/sqlite
npx cap sync
```

**`frontend/src/lib/local-db.ts`:**
```typescript
import { CapacitorSQLite, SQLiteConnection, SQLiteDBConnection } from '@capacitor-community/sqlite';

const sqlite = new SQLiteConnection(CapacitorSQLite);
let db: SQLiteDBConnection | null = null;

export async function getDb(): Promise<SQLiteDBConnection> {
  if (db) return db;
  
  db = await sqlite.createConnection(
    'wiredpart',          // database name
    false,                // encrypted
    'no-encryption',      // mode
    1,                    // version
    false                 // readonly
  );
  await db.open();
  await runMigrations(db);
  return db;
}

async function runMigrations(db: SQLiteDBConnection): Promise<void> {
  // Create version tracking table
  await db.execute(`
    CREATE TABLE IF NOT EXISTS _migrations (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      applied_at TEXT DEFAULT (datetime('now'))
    )
  `);
  
  // Run each migration if not already applied
  for (const migration of migrations) {
    const result = await db.query(
      'SELECT 1 FROM _migrations WHERE name = ?', [migration.name]
    );
    if (!result.values?.length) {
      await db.execute(migration.sql);
      await db.run(
        'INSERT INTO _migrations (name) VALUES (?)', [migration.name]
      );
    }
  }
}
```

### 4.4 TypeScript Service Layer Structure

Lean field-worker backend — only the services needed for offline mobile use. Admin/office features (cost tracking, approvals, PDF generation, reports, scheduler) are shop-only and NOT ported.

```
frontend/src/local/
├── db.ts                    # SQLite connection manager
├── migrations/              # SQL migration files (ported from Python)
│   ├── index.ts            # Migration runner
│   ├── 001_foundation.ts
│   ├── 002_parts_and_inventory.ts
│   ├── ...                 # Only tables needed for mobile features
│   └── 027_phase10_permissions.ts
├── services/               # Field-worker business logic
│   ├── auth-service.ts     # P0: PIN auth, user lookup
│   ├── job-service.ts      # P0: Job CRUD, status
│   ├── labor-service.ts    # P0: Clock in/out
│   ├── movement-service.ts # P0: Stock movements
│   ├── order-service.ts    # P1: JPO create/edit
│   ├── notebook-service.ts # P1: Entries + tasks
│   ├── warehouse-service.ts# P1: Inventory read
│   ├── tool-service.ts     # P1: Checkout/return
│   ├── parts-service.ts    # P2: Catalog lookup (read-only)
│   ├── fleet-service.ts    # P2: Vehicle info (read-only)
│   └── scheduling-service.ts # P2: My schedule (read-only)
├── repos/                  # Data access
│   ├── base-repo.ts
│   ├── jobs-repo.ts
│   ├── labor-repo.ts
│   ├── stock-repo.ts
│   ├── orders-repo.ts
│   └── ...                 # ~8-10 repos (field-worker subset)
├── change-tracker.ts       # Logs all writes for sync
└── local-client.ts         # Implements the same API surface as http-client.ts
```

**NOT ported to mobile (shop-only):**
- `cost-tracking-service` — admin analytics, FIFO/LIFO calculations
- `approval-service` — office workflow
- `report-service` — pre-billing, timesheets, exports
- `pdf-service` — reportlab PDF generation
- `companion-service` — lower priority, can be added later
- `scheduler` — APScheduler background jobs
- `notification-service` — shop generates/pushes, device reads

This keeps the mobile data layer **small and focused**. The shop handles the heavy admin logic. Field workers get what they need: jobs, clocking, stock, orders, tools, notebooks.

Every write to the local database also logs to a change tracking table. This is how the sync engine knows what to send to the shop.

**`_change_log` table (created in migration):**
```sql
CREATE TABLE IF NOT EXISTS _change_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id TEXT NOT NULL,           -- UUID of this device
  table_name TEXT NOT NULL,          -- e.g. 'jobs', 'labor_entries', 'stock'
  record_id INTEGER NOT NULL,        -- PK of the changed record
  operation TEXT NOT NULL,           -- 'INSERT', 'UPDATE', 'DELETE'
  changed_fields TEXT,               -- JSON of field:value pairs that changed
  old_values TEXT,                   -- JSON of previous values (for conflict resolution)
  timestamp TEXT NOT NULL DEFAULT (datetime('now')),
  synced INTEGER NOT NULL DEFAULT 0, -- 0 = pending, 1 = confirmed by shop
  sync_batch_id TEXT                 -- NULL until synced, then the batch UUID
);

CREATE INDEX idx_change_log_unsynced ON _change_log(synced, timestamp);
CREATE INDEX idx_change_log_table ON _change_log(table_name, record_id);
```

**`frontend/src/local/change-tracker.ts`:**
```typescript
import { getDb } from './db';
import { getDeviceId } from '../lib/device-identity';

export async function trackChange(
  tableName: string,
  recordId: number,
  operation: 'INSERT' | 'UPDATE' | 'DELETE',
  changedFields?: Record<string, any>,
  oldValues?: Record<string, any>
): Promise<void> {
  const db = await getDb();
  await db.run(
    `INSERT INTO _change_log (device_id, table_name, record_id, operation, changed_fields, old_values)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [
      getDeviceId(),
      tableName,
      recordId,
      operation,
      changedFields ? JSON.stringify(changedFields) : null,
      oldValues ? JSON.stringify(oldValues) : null,
    ]
  );
}

export async function getPendingChanges(): Promise<ChangeLogEntry[]> {
  const db = await getDb();
  const result = await db.query(
    'SELECT * FROM _change_log WHERE synced = 0 ORDER BY timestamp ASC'
  );
  return result.values || [];
}

export async function markSynced(ids: number[], batchId: string): Promise<void> {
  const db = await getDb();
  const placeholders = ids.map(() => '?').join(',');
  await db.run(
    `UPDATE _change_log SET synced = 1, sync_batch_id = ? WHERE id IN (${placeholders})`,
    [batchId, ...ids]
  );
}
```

### 4.6 Example: Local Job Service

Shows how a Python service translates to TypeScript for local use:

**Python (`backend/app/services/job_service.py`):**
```python
async def create_job(self, data: JobCreate, user_id: int) -> dict:
    job = await self.repo.create({...data.dict(), "created_by": user_id})
    # Create job notebook from template...
    return job
```

**TypeScript (`frontend/src/local/services/job-service.ts`):**
```typescript
import { getDb } from '../db';
import { trackChange } from '../change-tracker';

export async function createJob(data: JobCreate, userId: number): Promise<Job> {
  const db = await getDb();
  
  const result = await db.run(
    `INSERT INTO jobs (name, address, city, state, zip, status, job_type, created_by, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, datetime('now'), datetime('now'))`,
    [data.name, data.address, data.city, data.state, data.zip, data.jobType, userId]
  );
  
  const jobId = result.changes?.lastId;
  
  // Track the change for sync
  await trackChange('jobs', jobId, 'INSERT', data);
  
  // Create notebook from template (same logic as Python)
  await createJobNotebook(jobId);
  
  // Fetch and return the created job
  return getJob(jobId);
}
```

### 4.7 Service Porting Priority

Not all services are equally critical for field workers. Port in this order:

| Priority | Service | Why | Endpoints to Port |
|----------|---------|-----|------------------|
| **P0** | auth | Can't use the app without login | PIN auth, user lookup |
| **P0** | jobs (core CRUD) | Most-used feature in the field | Create, list, detail, status |
| **P0** | labor (clock) | Workers need this daily | Clock in, clock out, my clock |
| **P0** | movement | Moving stock is core job | Validate, preview, execute |
| **P1** | orders | Field workers create orders | JPO create, list, detail |
| **P1** | notebooks | Daily task tracking | Entries CRUD, tasks CRUD |
| **P1** | warehouse (read) | Inventory lookup | Dashboard, inventory grid, search |
| **P1** | tools (checkout) | Field tool tracking | Checkout, return, my tools |
| **P2** | parts (read) | Catalog lookup | List, detail, search, hierarchy |
| **P2** | fleet (read) | Vehicle info | My vehicle, assignments |
| **P2** | scheduling | View assignments | My schedule, dispatch board |
| **P3** | questionnaire | Clock-out questions | Bundle, answer |
| **P3** | companions | Order suggestions | Generate, list |
| **P3** | reports | Read-only on device | Daily report view |
| **SHOP ONLY** | cost tracking | Admin feature | *(not ported — shop-only)* |
| **SHOP ONLY** | approvals | Office feature | *(not ported — shop-only)* |
| **SHOP ONLY** | PDF generation | Needs reportlab | *(not ported — shop-only)* |
| **SHOP ONLY** | APScheduler | Server background jobs | *(not ported — shop-only)* |

**P0 services** = Workers can't function without them. Port these first.
**P1 services** = Daily workflow. Port these second.
**P2 services** = Useful but read-mostly. Port third.
**P3 services** = Nice to have. Port last.
**SHOP ONLY** = Desktop/admin features that only run at the shop.

### 4.8 Migration Porting Strategy

The 27 SQL migrations need to work with `@capacitor-community/sqlite`. Strategy:

1. **Same SQL** — The migrations are standard SQLite DDL. Most work as-is.
2. **Port to TypeScript files** — Each migration becomes a TS module exporting `{ name: string, sql: string }`.
3. **Run on first launch** — When the Capacitor app starts, the migration runner applies any un-applied migrations.
4. **On update** — New app version may include new migrations. They run automatically on next launch.

```typescript
// frontend/src/local/migrations/001_foundation.ts
export const migration = {
  name: '001_foundation',
  sql: `
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE,
      display_name TEXT NOT NULL,
      pin_hash TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'worker',
      ...
    );
    -- (rest of 001_foundation.sql content)
  `
};
```

---

## 5. Sync Engine (Device ↔ Shop)

The sync engine is how mobile devices stay in sync with the shop's truth-anchor database. For V1.0, sync happens **over LAN/Wi-Fi only** (V2.0 adds Bluetooth mesh).

### 5.1 Sync Protocol Overview

```
┌──────────────┐                          ┌──────────────┐
│    DEVICE    │                          │     SHOP     │
│              │                          │              │
│  1. Detect   │    Wi-Fi connected       │              │
│     shop on  │ ──────────────────────>  │              │
│     LAN      │                          │              │
│              │                          │              │
│  2. Send     │   POST /api/sync/push    │  3. Receive  │
│     pending  │ ──────────────────────>  │     changes, │
│     changes  │                          │     resolve  │
│              │                          │     conflicts│
│              │                          │              │
│  5. Apply    │   Response: changes      │  4. Send     │
│     remote   │ <──────────────────────  │     changes  │
│     changes  │                          │     since    │
│              │                          │     last     │
│  6. Mark     │   POST /api/sync/ack     │     sync     │
│     synced   │ ──────────────────────>  │              │
│              │                          │  7. Mark     │
│              │                          │     delivered│
└──────────────┘                          └──────────────┘
```

### 5.2 Device Identity

Each device gets a persistent UUID on first launch:

```typescript
// frontend/src/lib/device-identity.ts
import { Preferences } from '@capacitor/preferences';
import { v4 as uuid } from 'uuid';

let deviceId: string | null = null;

export async function getDeviceId(): Promise<string> {
  if (deviceId) return deviceId;
  
  const stored = await Preferences.get({ key: 'device_id' });
  if (stored.value) {
    deviceId = stored.value;
    return deviceId;
  }
  
  deviceId = uuid();
  await Preferences.set({ key: 'device_id', value: deviceId });
  return deviceId;
}
```

### 5.3 Shop-Side Sync API (Python)

New endpoints on the FastAPI backend:

```python
# backend/app/routers/sync.py

@router.post("/api/sync/push")
async def sync_push(payload: SyncPushPayload):
    """
    Receive changes from a device.
    Returns: changes the device hasn't seen yet + conflict resolutions.
    """
    device_id = payload.device_id
    changes = payload.changes          # list of change_log entries
    last_sync_at = payload.last_sync_at  # device's last successful sync timestamp
    
    # 1. Apply device's changes to shop DB (with conflict resolution)
    applied, conflicts = await sync_service.apply_device_changes(device_id, changes)
    
    # 2. Gather shop changes since device's last sync
    shop_changes = await sync_service.get_changes_since(last_sync_at, exclude_device=device_id)
    
    # 3. Return everything the device needs
    return {
        "applied": len(applied),
        "conflicts": conflicts,          # list of {record, shop_version, resolution}
        "shop_changes": shop_changes,     # changes device needs to apply locally
        "sync_batch_id": str(uuid4()),
        "server_time": datetime.utcnow().isoformat(),
    }

@router.post("/api/sync/ack")
async def sync_ack(payload: SyncAckPayload):
    """Device confirms it applied the shop's changes."""
    await sync_service.mark_device_synced(payload.device_id, payload.sync_batch_id)
    return {"status": "ok"}

@router.get("/api/sync/status/{device_id}")
async def sync_status(device_id: str):
    """Check a device's sync state (for admin dashboard)."""
    return await sync_service.get_device_status(device_id)
```

### 5.4 Shop-Side Change Tracking

The shop also needs a change log so it can tell devices "here's what changed since your last sync":

```sql
-- Added to shop's migrations
CREATE TABLE IF NOT EXISTS _shop_change_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_device_id TEXT,              -- NULL if shop-originated, device_id if from device
  table_name TEXT NOT NULL,
  record_id INTEGER NOT NULL,
  operation TEXT NOT NULL,
  changed_fields TEXT,
  timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS _device_registry (
  device_id TEXT PRIMARY KEY,
  device_name TEXT,
  platform TEXT,                      -- 'ios', 'android', 'web'
  last_sync_at TEXT,
  last_sync_batch_id TEXT,
  registered_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_shop_changes_time ON _shop_change_log(timestamp);
CREATE INDEX idx_shop_changes_source ON _shop_change_log(source_device_id);
```

### 5.5 Conflict Resolution (V1.0 — Simple)

For V1.0, conflict resolution is **last-writer-wins** with the shop as tiebreaker:

| Scenario | Resolution |
|----------|-----------|
| Device A edits record, shop has no changes | Device A wins — apply change |
| Shop edits record, device A has no changes | Shop wins — device applies change |
| Device A and Device B both edit same record | Last timestamp wins. If tie, shop's version wins. |
| Device creates record with same ID as shop | Shop's version wins. Device record gets new ID. |
| Device deletes record that shop also edited | Delete wins (tombstone). Shop applies delete. |

**Conflict log:** Every conflict is logged for admin review:
```sql
CREATE TABLE IF NOT EXISTS _conflict_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  record_id INTEGER NOT NULL,
  device_a_id TEXT,
  device_b_id TEXT,
  resolution TEXT NOT NULL,         -- 'device_a_wins', 'device_b_wins', 'shop_wins', 'merged'
  device_a_values TEXT,             -- JSON
  device_b_values TEXT,             -- JSON
  resolved_values TEXT,             -- JSON
  resolved_at TEXT DEFAULT (datetime('now'))
);
```

### 5.6 Sync Triggers

When does sync happen?

| Trigger | Behavior |
|---------|----------|
| App launch (Capacitor) | Check for shop on LAN → sync if reachable |
| App returns to foreground | Check for shop on LAN → sync if reachable |
| Manual "Sync Now" button | User taps sync icon in header → immediate sync |
| Periodic background | Every 5 minutes while app is open, if shop is reachable |
| Shop connection detected | `@capacitor/network` fires → auto-sync |

### 5.7 Sync Status UI

Header bar indicator showing sync state:

```
┌─────────────────────────────────────────────┐
│ 🟢 Synced                          [👤 Roy] │  ← All caught up
│ 🟡 3 changes pending               [👤 Roy] │  ← Offline, changes queued
│ 🔄 Syncing...                      [👤 Roy] │  ← Actively syncing
│ 🔴 Shop unreachable (14 pending)   [👤 Roy] │  ← Can't reach shop
└─────────────────────────────────────────────┘
```

Tapping the indicator opens a sync detail panel:
- Last sync time
- Pending changes count
- Shop connection status
- "Sync Now" button
- Sync history log

### 5.8 Photo & File Sync Strategy

Photos (clock-out, job site, notebook attachments) need special handling because they're binary blobs — too large for the `_change_log` JSON-based row sync.

**V1.0 approach — data URL inline (simple, sufficient for low volume):**

1. **Photos are stored as base64 data URLs** in text columns (e.g., `answer_text` for clock-out photos, `attachment_data` for notebooks).
2. **Client-side resize** to ~800px max dimension, JPEG 80% quality — keeps each photo under ~150KB.
3. **Standard sync** — photos travel as part of the row's `changed_fields` JSON in `_change_log`. No separate binary sync.
4. **Acceptable trade-off:** A typical sync batch might have 2-5 photos = ~500KB-750KB. Over LAN Wi-Fi this transfers in under a second.

**Limitations (acceptable for V1.0):**
- No high-resolution photo archive — but field photos don't need it.
- Photos increase `_change_log` row sizes — but SQLite handles large TEXT values fine.
- Each photo syncs once per device — but with ~5 devices, this is manageable.

**V2.0 upgrade path (if needed):**
- Add a `_file_store` table with content-addressed hashing (SHA-256).
- Sync protocol gains a `POST /api/sync/files` endpoint for chunked binary upload.
- Row data stores only the hash reference; files sync separately.
- Bluetooth mesh uses chunked transfer (16KB blocks) with resumable progress.

**Tables with photo/file data to sync:**
| Table | Column | Content |
|-------|--------|---------|
| `clock_out_responses` | `answer_text` | Photo data URLs from clock-out questions |
| `notebook_entries` | `content` | May contain embedded images |
| `tool_maintenance_records` | `notes` | May reference photo evidence |

---

## 6. Capacitor Mobile Apps

Capacitor wraps the React frontend + TypeScript data layer + SQLite into native iOS and Android apps. Each app is **fully self-contained** — it works with no network.

### 6.1 Initialize Capacitor

```bash
cd frontend

# Install Capacitor core + plugins
npm install @capacitor/core @capacitor/cli
npm install @capacitor/app @capacitor/camera @capacitor/geolocation
npm install @capacitor/haptics @capacitor/status-bar @capacitor/splash-screen
npm install @capacitor/network @capacitor/preferences
npm install @capacitor-community/sqlite

# Initialize
npx cap init "Wired-Part" "com.wiredpart.app"

# Add platforms
npx cap add ios
npx cap add android
```

### 6.2 Capacitor Configuration

`frontend/capacitor.config.ts`:
```typescript
import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.wiredpart.app',
  appName: 'Wired-Part',
  webDir: 'dist',
  
  server: {
    androidScheme: 'https',
    // No remote URL — app runs entirely from local bundle + local SQLite
  },
  
  plugins: {
    SplashScreen: {
      launchShowDuration: 2000,
      backgroundColor: '#1e293b',
      showSpinner: true,
      spinnerColor: '#3B82F6',
    },
    CapacitorSQLite: {
      iosDatabaseLocation: 'Library/CapacitorDatabase',
      iosIsEncryption: false,
      androidIsEncryption: false,
    },
  },
};

export default config;
```

### 6.3 First Launch Flow

When a mobile device launches the app for the first time:

1. **SQLite database created** — migrations run automatically
2. **Device ID generated** — persistent UUID stored in Preferences
3. **Shop connection screen** — "Enter your shop's IP address" (or scan QR from shop computer)
4. **Initial sync** — pulls ALL data from shop (full database download for first sync)
5. **Login screen** — user selects their name, enters PIN (validated against local DB)
6. **Ready to use** — app works fully offline from this point

### 6.4 Shop IP Configuration

The mobile app needs to know where the shop is for sync. This is configured once (not needed for daily use — only for sync).

**`frontend/src/lib/shop-config.ts`:**
```typescript
import { Preferences } from '@capacitor/preferences';

export async function getShopUrl(): Promise<string | null> {
  const result = await Preferences.get({ key: 'shop_url' });
  return result.value;
}

export async function setShopUrl(url: string): Promise<void> {
  await Preferences.set({ key: 'shop_url', value: url.replace(/\/$/, '') });
}

export async function isShopReachable(): Promise<boolean> {
  const url = await getShopUrl();
  if (!url) return false;
  try {
    const response = await fetch(`${url}/api/health`, { 
      signal: AbortSignal.timeout(3000) 
    });
    return response.ok;
  } catch {
    return false;
  }
}
```

### 6.5 Build & Sync

```bash
cd frontend

# Build the web app
npm run build

# Copy built files to native projects  
npx cap sync

# Open in Xcode (Mac only — for iOS builds)
npx cap open ios

# Open in Android Studio
npx cap open android
```

### 6.6 Native Plugin Usage

| Feature | Plugin | Current Web Implementation | Capacitor Enhancement |
|---------|--------|---------------------------|----------------------|
| QR Scanning | `@capacitor/camera` | `html5-qrcode` | Native camera, faster |
| Clock-in GPS | `@capacitor/geolocation` | `navigator.geolocation` | Background location, better accuracy |
| Notifications | `@capacitor/local-notifications` | In-app only | Push even when backgrounded |
| Photos | `@capacitor/camera` | `<input type="file">` | Native camera + gallery |
| Network Status | `@capacitor/network` | None | Detect shop reachable → auto-sync |
| Local Storage | `@capacitor/preferences` | `localStorage` | Persistent across updates |
| SQLite | `@capacitor-community/sqlite` | None (new) | Full offline database |

---

## 7. iOS Distribution (Free Sideloading)

> **Production cost:** $0 — uses a free Apple ID, no Apple Developer Program needed.
> **Tools:** Sideloadly (free, Mac + Windows), AltServer (free, auto-refresh over Wi-Fi)
> **Limitation:** Free-signed apps expire every 7 days. AltServer on the shop computer auto-refreshes over Wi-Fi so workers never notice.

### 7.1 How It Works

Apple allows installing apps on iOS devices outside the App Store using a free Apple ID for code signing. The tradeoff is a 7-day signing window, but this is handled automatically:

1. **Build** the IPA on a Mac (Xcode + free Apple ID) — only needed on first build or updates
2. **Install** via Sideloadly from Mac or Windows (USB cable to device)
3. **Auto-refresh** via AltServer running on the shop computer — re-signs over Wi-Fi every 7 days

Since workers connect to shop Wi-Fi daily, the 7-day refresh is invisible.

### 7.2 Prerequisites

| Tool | Platform | Cost | Purpose |
|------|----------|------|---------|
| **Xcode** | Mac only | Free | Compile the iOS binary (one-time or on updates) |
| **Sideloadly** | Mac + Windows | Free | Sign IPA + install on device via USB |
| **AltServer** | Mac + Windows | Free | Auto-refresh 7-day signing over Wi-Fi |
| **Free Apple ID** | — | Free | Code signing identity |
| **USB cable** | — | — | Initial install per device |

- Sideloadly: [sideloadly.io](https://sideloadly.io)
- AltServer: [altstore.io](https://altstore.io)
- Free Apple ID: [appleid.apple.com](https://appleid.apple.com)

### 7.3 Build the IPA (Mac — First Build or Updates)

```bash
cd frontend

# 1. Build frontend (includes lean TS data layer)
npm run build

# 2. Sync to native project
npx cap sync ios

# 3. Open in Xcode
npx cap open ios
```

In Xcode:
1. Select the `App` target → Signing & Capabilities
2. Check **"Automatically manage signing"**
3. Set Team to your **free Apple ID** (Xcode → Settings → Accounts → Add Apple ID if needed)
4. Set Bundle Identifier to `com.wiredpart.app`
5. Product → Archive (takes 2-5 minutes)
6. In the Organizer window: **Distribute App** → select **Development** → Next → Export
7. Save the `.ipa` file somewhere easy to find (e.g., Desktop)

This IPA file is what you install on devices. Transfer it to the Windows machine if you're installing from there (USB drive, shared folder, etc.).

### 7.4 Install on Each Device (Mac or Windows)

Using **Sideloadly** ([sideloadly.io](https://sideloadly.io)):

1. Connect the iPhone or iPad to the computer via **USB cable**
2. Open Sideloadly
3. Drag the `WiredPart.ipa` file into the Sideloadly window
4. Enter your **free Apple ID** and password
5. Click **Start** — Sideloadly signs the app and pushes it to the device
6. On the device: Settings → General → VPN & Device Management → tap your Apple ID email → **Trust**
7. Launch **Wired-Part** → works immediately with a local database
8. Connect to shop Wi-Fi → scan QR code or enter shop IP for sync setup
9. Initial sync pulls all data from shop → device is populated. Done! ✅

Repeat for each iPhone/iPad. Takes 2-3 minutes per device.

### 7.5 Auto-Refresh with AltServer (Shop Computer)

Free-signed apps expire after 7 days. **AltServer** handles this automatically:

1. Install AltServer on the **shop computer**:
   - **Mac:** Download from [altstore.io](https://altstore.io) → drag to Applications → launch
   - **Windows:** Download AltServer for Windows → install → launch
2. AltServer runs in the **system tray** (Windows) or **menu bar** (Mac)
3. Sign in with the **same free Apple ID** used to sign the app
4. When workers' iOS devices connect to shop Wi-Fi, AltServer automatically refreshes the app signing in the background

**That's it.** As long as AltServer is running on the shop computer and workers connect to shop Wi-Fi at least once every 7 days, the signing never expires.

### 7.6 The 7-Day Limit — What to Expect

| Scenario | What Happens |
|----------|-------------|
| Worker comes to shop daily or weekly | AltServer refreshes automatically. They never notice. |
| Worker in the field for 5 days | Fine — still within 7-day window. |
| Worker in the field for 8+ days | App stops launching after day 7. **Data is NOT lost.** Connect to shop Wi-Fi → AltServer refreshes → app works again with all data intact. |
| Shop computer is off for a week | No refresh happens. Re-start AltServer → devices refresh on next Wi-Fi connection. |

**Important:** The local SQLite database is **never** affected by signing expiry. Only the ability to *launch* the app is interrupted. All data is always safe.

### 7.7 Updating the iOS App

When you have a new version of Wired-Part:

1. **Rebuild on Mac:** Build → cap sync → Xcode archive → export IPA (same as §7.3)
2. **Re-sideload:** Open new IPA in Sideloadly → install on each device via USB
3. Local database and all data is **preserved** — new migrations run on first launch
4. AltServer will auto-refresh the new version going forward

---

## 8. Android Distribution (APK Sideload)

### 8.1 Prerequisites

- **Android Studio** installed (free — any OS)
- A signing key (Android Studio creates one)

### 8.2 Build APK

```bash
cd frontend

# 1. Build frontend (includes TS data layer)
npm run build

# 2. Sync to native project
npx cap sync android

# 3. Open in Android Studio
npx cap open android
```

In Android Studio:
1. Build → Generate Signed Bundle/APK → APK
2. Create or select a signing key
3. Build variant: Release
4. Output: `frontend/android/app/build/outputs/apk/release/app-release.apk`

### 8.3 Distribute APK

**Simple method**:
- Email the APK to workers
- Share via Google Drive, Dropbox, or AirDrop-equivalent
- Share via USB cable
- Host on the shop server at `http://<shop-ip>:8000/download/wiredpart.apk`

**Install on device**:
1. Settings → Security → "Install from Unknown Sources" (enable for your file manager/browser)
2. Open the APK file → Install
3. Launch Wired-Part → **works immediately** (offline with local database)
4. Connect to shop Wi-Fi → app auto-syncs when reachable

### 8.4 Updates

When you build a new APK:
- Same distribution method (email, Drive, USB)
- Workers install the new APK over the old one (local database preserved)
- New migrations run automatically on first launch after update
- Consider: host the latest APK on the shop server for one-click updates

---

## 9. Desktop Browser Access

Desktop users (Windows PCs, Macs at the shop) don't need an app — they use a web browser and talk directly to the shop server.

### 9.1 Access URL

Open Chrome, Safari, Edge, or Firefox:
```
http://<shop-ip>:8000
```

Example: `http://192.168.1.100:8000`

### 9.2 "Add to Desktop" (Optional PWA)

For a more app-like experience, desktop users can:
- Chrome: ⋮ menu → "Install Wired-Part..." → Creates desktop shortcut
- Safari: Not supported (Mac users just bookmark it)
- Edge: ... menu → Apps → Install this site as an app

This requires a PWA `manifest.json` (see Production Hardening section).

### 9.3 Desktop vs Mobile Data Path

| | Desktop Browser | Mobile (Capacitor) |
|---|---|---|
| **Data source** | Shop server via HTTP API | Local SQLite via TS data layer |
| **Network required?** | Yes — always on shop LAN | No — works fully offline |
| **Sync needed?** | No — reads/writes directly | Yes — syncs when on shop Wi-Fi |
| **Admin features** | Full access (cost tracking, reports, approvals) | Field-worker subset |

Desktop users are always at the shop, always on the LAN. They never need offline capability.

---

## 10. Production Hardening

### 10.1 Environment Variables (`.env`)

Production `.env` at project root:
```env
# Security — Generate a real secret key!
SECRET_KEY=<generate-with: python -c "import secrets; print(secrets.token_hex(32))">
DEFAULT_ADMIN_PIN=<your-chosen-pin>

# Database
DATABASE_PATH=./wiredpart.db

# CORS — Allow local network, Capacitor origins, and sync requests
CORS_ORIGINS=["http://localhost:8000","http://192.168.1.100:8000","capacitor://localhost","http://localhost","https://localhost"]

# Server
BACKEND_HOST=0.0.0.0
BACKEND_PORT=8000
```

**CORS for Capacitor offline apps**: Capacitor apps send requests from `capacitor://localhost` (iOS) or `https://localhost` (Android). Both must be in CORS_ORIGINS. These origins are used when the app syncs with the shop — local SQLite reads don't involve CORS at all.

### 10.2 Static File Serving

Modify `backend/app/main.py` to serve the built frontend:

```python
# After all router registration, before health check
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

FRONTEND_DIST = Path(__file__).resolve().parent.parent.parent / "frontend" / "dist"

if FRONTEND_DIST.exists():
    # Serve Vite's hashed assets
    app.mount("/assets", StaticFiles(directory=str(FRONTEND_DIST / "assets")), name="assets")

    # Serve other static files (icons, manifest, etc.)
    @app.get("/manifest.json")
    async def manifest():
        return FileResponse(FRONTEND_DIST / "manifest.json")

    @app.get("/favicon.ico")
    async def favicon():
        return FileResponse(FRONTEND_DIST / "favicon.ico")

    # SPA catch-all — must be LAST
    @app.get("/{full_path:path}")
    async def spa_catchall(full_path: str):
        file = FRONTEND_DIST / full_path
        if file.is_file() and ".." not in full_path:
            return FileResponse(file)
        return FileResponse(FRONTEND_DIST / "index.html")
```

### 10.3 PWA Manifest

`frontend/public/manifest.json`:
```json
{
  "name": "Wired-Part",
  "short_name": "Wired-Part",
  "description": "Field service management for electrical contractors",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#1e293b",
  "theme_color": "#3B82F6",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

Add to `frontend/index.html` `<head>`:
```html
<link rel="manifest" href="/manifest.json" />
<link rel="apple-touch-icon" href="/icons/icon-192.png" />
<meta name="theme-color" content="#3B82F6" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
```

### 10.4 Database Backup (Shop)

`scripts/backup-db.ps1` (Windows):
```powershell
$DB = Join-Path $PSScriptRoot "..\backend\wiredpart.db"
$BACKUP_DIR = Join-Path $PSScriptRoot "..\backups"
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd_HHmm"

if (-not (Test-Path $BACKUP_DIR)) { New-Item -ItemType Directory -Path $BACKUP_DIR }

Copy-Item $DB "$BACKUP_DIR\wiredpart_$TIMESTAMP.db"
Write-Host "Backup saved: wiredpart_$TIMESTAMP.db"

# Keep only last 30 backups
Get-ChildItem $BACKUP_DIR -Filter "*.db" | Sort-Object CreationTime -Descending |
  Select-Object -Skip 30 | Remove-Item
```

### 10.5 Logging to File

Add to production startup:
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2 --log-level info \
  --access-log --log-config logging.ini
```

Or use Python's built-in file handler in `main.py`:
```python
import logging
from logging.handlers import RotatingFileHandler

file_handler = RotatingFileHandler("logs/wiredpart.log", maxBytes=10_000_000, backupCount=5)
file_handler.setFormatter(logging.Formatter("%(asctime)s | %(levelname)s | %(name)s | %(message)s"))
logging.getLogger().addHandler(file_handler)
```

### 10.6 Server Info Endpoint + QR Code

Endpoint for mobile device pairing (initial sync setup):

```python
@app.get("/api/server-info", tags=["System"])
async def server_info(request: Request):
    """Return server info for mobile device setup."""
    import socket
    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)
    return {
        "hostname": hostname,
        "local_ip": local_ip,
        "port": settings.BACKEND_PORT,
        "url": f"http://{local_ip}:{settings.BACKEND_PORT}",
        "version": settings.APP_VERSION,
    }
```

The shop computer displays a QR code at `http://localhost:8000/setup` that mobile devices scan to auto-configure the shop URL for syncing. This is a one-time setup — after the initial sync, the device works independently.

---

## 11. Build Scripts & Automation

### 11.1 Full Build Script (Windows)

`scripts/build-all.ps1`:
```powershell
# Build everything — frontend (with TS data layer) + backend + Capacitor sync
param(
    [switch]$SkipMobile
)

$ROOT = Split-Path $PSScriptRoot -Parent

Write-Host "Building Wired-Part..." -ForegroundColor Cyan

# 1. Build frontend (includes TS data layer + local services)
Write-Host "`n[1/4] Building frontend + offline data layer..." -ForegroundColor Yellow
Set-Location "$ROOT/frontend"
npm ci
npm run build

# 2. Install backend deps
Write-Host "`n[2/4] Installing backend dependencies..." -ForegroundColor Yellow
Set-Location "$ROOT/backend"
if (-not (Test-Path ".venv")) { python -m venv .venv }
& ".venv/Scripts/pip.exe" install -r requirements.txt -q

# 3. Sync Capacitor (if not skipping mobile)
if (-not $SkipMobile) {
    Write-Host "`n[3/4] Syncing Capacitor (copies built app + SQLite plugin to native projects)..." -ForegroundColor Yellow
    Set-Location "$ROOT/frontend"
    npx cap sync

    Write-Host "`n[4/4] Mobile projects ready:" -ForegroundColor Green
    Write-Host "  iOS:     cd frontend && npx cap open ios" -ForegroundColor White
    Write-Host "  Android: cd frontend && npx cap open android" -ForegroundColor White
} else {
    Write-Host "`n[3/4] Skipping mobile builds" -ForegroundColor Gray
    Write-Host "[4/4] Skipped" -ForegroundColor Gray
}

Write-Host "`nBuild complete!" -ForegroundColor Green
Write-Host "Start shop server: .\scripts\start-server.ps1" -ForegroundColor White
```

### 11.2 Full Build Script (Mac/Linux)

`scripts/build-all.sh`:
```bash
#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKIP_MOBILE=${1:-false}

echo "Building Wired-Part..."

# 1. Frontend (includes TS data layer + local services)
echo -e "\n[1/4] Building frontend + offline data layer..."
cd "$ROOT/frontend"
npm ci
npm run build

# 2. Backend
echo -e "\n[2/4] Installing backend dependencies..."
cd "$ROOT/backend"
[ ! -d ".venv" ] && python3 -m venv .venv
.venv/bin/pip install -r requirements.txt -q

# 3. Capacitor
if [ "$SKIP_MOBILE" != "--skip-mobile" ]; then
    echo -e "\n[3/4] Syncing Capacitor..."
    cd "$ROOT/frontend"
    npx cap sync

    echo -e "\n[4/4] Mobile projects ready:"
    echo "  iOS:     cd frontend && npx cap open ios"
    echo "  Android: cd frontend && npx cap open android"
fi

echo -e "\nBuild complete!"
echo "Start shop server: ./scripts/start-server.sh"
```

---

## 12. Customer Setup Guide

Step-by-step for setting up a new customer from scratch.

### 12.1 Shop Computer Setup (30 minutes)

**Prerequisites:**
- Windows 10/11 PC or Mac (any recent macOS)
- Python 3.12+ installed ([python.org/downloads](https://python.org/downloads))
- Node.js 20+ installed ([nodejs.org](https://nodejs.org))
- Git installed (to clone the repo)

**Steps:**

1. **Clone the repo:**
   ```bash
   git clone https://github.com/xXKillerNoobYT/Weird-Part-Run-2.git
   cd Weird-Part-Run-2
   ```

2. **Create `.env` file:**
   ```bash
   cp .env.example .env
   # Edit .env — set SECRET_KEY and DEFAULT_ADMIN_PIN
   ```

3. **Build everything:**
   ```bash
   # Windows:
   .\scripts\build-all.ps1 -SkipMobile

   # Mac:
   ./scripts/build-all.sh --skip-mobile
   ```

4. **Start the server:**
   ```bash
   # Windows:
   .\scripts\start-server.ps1

   # Mac:
   ./scripts/start-server.sh
   ```

5. **Verify:** Open `http://localhost:8000` in a browser. You should see the login screen.

6. **Note the LAN IP** displayed by the startup script (e.g., `192.168.1.100:8000`).

7. **Set up initial data:** Log in as admin, create employee accounts, add job sites, configure warehouse locations.

### 12.2 Mobile Device Setup (5 minutes per device)

**iOS (via Sideloadly — free):**
1. Connect the iPhone/iPad to the computer via USB cable
2. Open **Sideloadly** → drag in the `WiredPart.ipa` → enter free Apple ID → install
3. On device: Settings → General → VPN & Device Management → Trust the profile
4. Launch Wired-Part → **works immediately with an empty local database**
5. Connect to shop Wi-Fi → scan QR code from shop computer (at `http://<shop-ip>:8000/setup`)
6. Initial sync pulls all data from shop → device is now populated
7. **AltServer** on the shop computer auto-refreshes the 7-day signing over Wi-Fi
8. Device works fully offline from this point

**Android (via APK):**
1. Share the `wiredpart.apk` file (email, Drive, USB)
2. On the device: Settings → Security → Enable "Install from Unknown Sources"
3. Open the APK → Install → Open
4. App launches with empty local database → **ready to use immediately**
5. Connect to shop Wi-Fi → scan QR code or enter shop IP
6. Initial sync pulls all data → device is populated. Done.

**Desktop (browser — always at the shop):**
1. Open Chrome/Safari/Edge
2. Navigate to `http://192.168.1.100:8000` (use your actual shop IP)
3. Bookmark it. Done.

**Key difference from traditional apps:** Mobile devices don't _need_ the shop to function. They sync when they can, but they work independently. A worker can install the app at home, drive to a job site with no Wi-Fi, clock in, create orders, log labor — all offline. When they drive back to the shop and connect to Wi-Fi, everything syncs automatically.

### 12.3 First Login

1. At the login screen, select the Admin user
2. Enter the default PIN (set in `.env`)
3. Go to Settings → create employee accounts, assign hats (roles)
4. Each employee gets a user profile and picks a PIN
5. Devices auto-remember the last logged-in user

### 12.4 Network Requirements

**Shop computer:**
- Must have a **static LAN IP** (configure in router settings or DHCP reservation)
- Firewall: Port 8000 must be open for inbound LAN connections
  - Windows: Windows Defender Firewall → Inbound Rules → New Rule → Port 8000 → Allow
  - Mac: System Preferences → Security → Firewall → Allow uvicorn

**Mobile devices:**
- Do NOT need constant network to function (that's the whole point)
- Need shop Wi-Fi access for sync (or hotspot to shop)
- Sync happens automatically when shop is reachable
- If shop is unreachable, device keeps working — changes queue up locally

**Desktop browsers:**
- Must be on the same LAN as the shop computer
- Need constant network (they talk directly to the shop server)

---

## 13. Execution Order

Everything in the order it should be done. Each step has clear criteria for "done." The offline data layer is the largest new work item.

### Phase A: Pre-Deployment (Features & Cleanup)

| # | Task | Depends On | Done When | Est. Time |
|---|------|-----------|-----------|-----------|
| 1 | **Phase 11: Reports & Pre-Billing** | — | 4 stub pages replaced with working reports, backend endpoints return real data | 3-4 days |
| 2 | **Legacy Cleanup** | — | Superseded pages deleted, routes cleaned, no dead code | 0.5 day |
| 3 | **Critical Path Tests** | 1, 2 | Auth, orders, clock, receiving, movements all pass automated tests | 2 days |

### Phase B: Offline Data Layer (The Big One)

| # | Task | Depends On | Done When | Est. Time |
|---|------|-----------|-----------|-----------|
| 4 | **API Adapter Layer** | — | `adapter.ts` routes calls to HTTP or local client based on platform detection | 1 day |
| 5 | **Capacitor SQLite Setup** | — | `@capacitor-community/sqlite` installed, connection manager working, migrations runner ported | 2 days |
| 6 | **TS Data Layer: P0 Services** | 4, 5 | Auth, jobs core CRUD, labor clock, movement execute — all working against local SQLite | 4-5 days |
| 7 | **TS Data Layer: P1 Services** | 6 | Orders, notebooks, warehouse read, tools checkout — working locally | 3-4 days |
| 8 | **TS Data Layer: P2 Services** | 7 | Parts read, fleet read, scheduling read — working locally | 2-3 days |
| 9 | **Change Tracking** | 5 | `_change_log` table populated on every local write, `getPendingChanges()` returns correct data | 1 day |

### Phase C: Sync Engine

| # | Task | Depends On | Done When | Est. Time |
|---|------|-----------|-----------|-----------|
| 10 | **Shop-Side Sync API** | 9 | `POST /api/sync/push`, `POST /api/sync/ack`, `GET /api/sync/status` — working endpoints | 2 days |
| 11 | **Shop-Side Change Tracking** | 10 | `_shop_change_log` populated on all shop writes, can query changes since timestamp | 1 day |
| 12 | **Device Sync Engine** | 9, 10 | Push local changes, pull shop changes, apply both directions, mark synced | 3 days |
| 13 | **Conflict Resolution** | 12 | Last-writer-wins working, conflict log populated, edge cases handled | 1-2 days |
| 14 | **Initial Sync (Full Download)** | 12 | New device can pull entire database from shop on first sync | 1 day |
| 15 | **Sync Status UI** | 12 | Header indicator (🟢🟡🔴🔄), detail panel, "Sync Now" button | 1 day |

### Phase D: Packaging & Distribution

| # | Task | Depends On | Done When | Est. Time |
|---|------|-----------|-----------|-----------|
| 16 | **Production Hardening** | 1 | Static file serving, CORS, secret key, logging, backups configured | 1 day |
| 17 | **PWA Manifest + Icons** | 16 | `manifest.json` in place, real app icons, splash screens | 0.5 day |
| 18 | **Capacitor Init & Config** | 8 | Capacitor project with iOS + Android, `capacitor.config.ts` set up | 0.5 day |
| 19 | **Startup Scripts** | 16 | Windows + Mac scripts start server correctly with LAN IP display | 0.5 day |
| 20 | **Cross-Platform Testing** | 15, 18 | All pages verified at 4 breakpoints, offline mode tested, sync round-trip verified | 3 days |
| 21 | **iOS Sideload Build** | 18, 20 | IPA built, installed via Sideloadly, AltServer configured, first launch + initial sync works | 1 day |
| 22 | **Android APK Build** | 18, 20 | Signed APK built, installable, first launch + initial sync works | 0.5 day |
| 23 | **Customer Setup Guide** | All above | Written guide tested with fresh install on clean machine | 0.5 day |

### Summary

| Phase | Tasks | Est. Time |
|-------|-------|-----------|
| A: Pre-Deployment | Reports, cleanup, critical tests | 5.5-6.5 days |
| B: Offline Data Layer | Adapter, SQLite, lean TS field-worker services, change tracking | 13-16 days |
| C: Sync Engine | Shop API, device sync, conflicts, initial sync, UI | 9-11 days |
| D: Packaging | Hardening, Capacitor, testing, builds, guide | 7 days |
| **TOTAL** | | **~34-40 days** |

**Note:** Phases A and the early parts of B/D can overlap (e.g., legacy cleanup while starting the API adapter). The mobile backend is intentionally lean (field-worker subset only) — admin features stay shop-only. Realistic calendar time with parallelization: **~28-32 days**.

### Dependencies Diagram

```
Phase 11 ──┬──→ Critical Tests
            │
Legacy ─────┘

API Adapter ──┬──→ P0 Services ──→ P1 Services ──→ P2-P3 Services
              │
SQLite Setup ─┴──→ Change Tracking ──→ Shop Sync API ──→ Device Sync ──→ Conflicts
                                                           │                │
                                                      Initial Sync     Sync Status UI
                                                           │                │
Production ──→ PWA/Icons ──→ Capacitor Init ──────────→ Testing ──→ iOS Build
Hardening    │                                              │       │
             └──→ Startup Scripts                           │       └→ Android Build
                                                            │              │
                                                            └──────→ Customer Guide
```

---

## Appendix A: File Changes Required

### Backend Changes

| File | Change |
|------|--------|
| `backend/app/main.py` | Add static file serving for `frontend/dist`, add `/api/server-info` endpoint |
| `backend/app/config.py` | Add `BACKEND_HOST`, `BACKEND_PORT` settings (already exist) |
| `backend/app/routers/sync.py` | **New** — Sync push/ack/status endpoints |
| `backend/app/services/sync_service.py` | **New** — Apply device changes, gather shop changes, conflict resolution |
| `backend/app/repositories/sync_repo.py` | **New** — _shop_change_log, _device_registry, _conflict_log queries |
| `backend/app/models/sync.py` | **New** — SyncPushPayload, SyncAckPayload, ChangeLogEntry models |
| `backend/app/migrations/028_sync_tables.sql` | **New** — _shop_change_log, _device_registry, _conflict_log tables |
| `.env` | Production values for SECRET_KEY, CORS_ORIGINS |
| `.env.example` | Template file with placeholder values |
| `backend/app/routers/reports.py` | Replace stub endpoints with real data (Phase 11) |
| `backend/app/services/report_service.py` | Add pre-billing, timesheet, labor overview logic (Phase 11) |

### Frontend Changes — Existing Files

| File | Change |
|------|--------|
| `frontend/capacitor.config.ts` | **New** — Capacitor configuration |
| `frontend/src/api/adapter.ts` | **New** — Routes API calls to HTTP client or local client |
| `frontend/src/lib/platform.ts` | **New** — `isCapacitorApp()`, `isDesktopBrowser()` |
| `frontend/src/lib/shop-config.ts` | **New** — Shop URL for sync (Preferences-based) |
| `frontend/src/lib/device-identity.ts` | **New** — Persistent device UUID |
| `frontend/src/api/client.ts` | Update to use adapter pattern |
| `frontend/src/components/SyncStatus.tsx` | **New** — Header sync indicator + detail panel |
| `frontend/src/components/ShopSetup.tsx` | **New** — First-time shop URL configuration (QR scan or manual entry) |
| `frontend/index.html` | Add manifest link, apple-touch-icon, theme-color meta tags |
| `frontend/public/manifest.json` | **New** — PWA manifest |
| `frontend/public/icons/*` | **New** — App icons at various sizes |
| Reports pages (×4) | Replace stubs with real report UIs (Phase 11) |

### Frontend Changes — New Offline Data Layer (`frontend/src/local/`)

| File | Purpose |
|------|---------|
| `local/db.ts` | SQLite connection manager + migration runner |
| `local/change-tracker.ts` | Logs all writes to `_change_log` |
| `local/local-client.ts` | Implements same API surface as `http-client.ts` |
| `local/sync-engine.ts` | Push/pull with shop, conflict handling, auto-sync triggers |
| `local/migrations/index.ts` | Migration list + runner |
| `local/migrations/001_foundation.ts` | Ported from `001_foundation.sql` |
| `local/migrations/...` (×27) | One file per existing SQL migration |
| `local/migrations/028_sync_tables.ts` | Change log + device identity tables |
| `local/repos/base-repo.ts` | Generic CRUD with change tracking |
| `local/repos/parts-repo.ts` | Parts, categories, types queries |
| `local/repos/stock-repo.ts` | Stock levels, movements |
| `local/repos/jobs-repo.ts` | Jobs CRUD |
| `local/repos/labor-repo.ts` | Clock in/out, labor entries |
| `local/repos/orders-repo.ts` | JPO/PO CRUD |
| `local/repos/...` (~15 repos) | One per domain |
| `local/services/auth-service.ts` | PIN auth against local DB |
| `local/services/job-service.ts` | Job CRUD + notebook creation |
| `local/services/labor-service.ts` | Clock in/out + entries |
| `local/services/movement-service.ts` | Stock movements |
| `local/services/order-service.ts` | JPO create/edit |
| `local/services/notebook-service.ts` | Entries + tasks |
| `local/services/warehouse-service.ts` | Dashboard + inventory read |
| `local/services/tool-service.ts` | Checkout/return |
| `local/services/...` (~15 services) | One per domain |

### New Scripts

| File | Purpose |
|------|---------|
| `scripts/start-server.ps1` | Windows shop server startup |
| `scripts/start-server.sh` | Mac/Linux shop server startup |
| `scripts/build-all.ps1` | Full build (frontend + data layer + Capacitor sync) |
| `scripts/build-all.sh` | Full build (Mac/Linux) |
| `scripts/backup-db.ps1` | Database backup with rotation |
| `scripts/backup-db.sh` | Database backup (Mac/Linux) |

### New Docs

| File | Purpose |
|------|---------|
| `docs/plans/sideloading-guide.md` | Step-by-step iOS + Android sideloading instructions |
| `.env.example` | Template .env for new installations |

---

## Appendix B: Platform Compatibility Matrix

| Feature | Win (Chrome) | Mac (Safari) | Mac (Chrome) | iPad (Safari) | iPad (Cap) | iPhone (Cap) | Android (Cap) |
|---------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| All pages render | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Touch targets ≥44px | N/A | N/A | N/A | ✅ | ✅ | ✅ | ✅ |
| No horizontal overflow | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Dark/light mode | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| QR scanning | ✅* | ✅* | ✅* | ✅ | ✅ | ✅ | ✅ |
| GPS clock-in/out | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Camera for photos | ✅* | ✅* | ✅* | ✅ | ✅ | ✅ | ✅ |
| Push notifications | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Offline capable** | ❌ | ❌ | ❌ | ❌ | **✅** | **✅** | **✅** |
| **Local SQLite DB** | ❌ | ❌ | ❌ | ❌ | **✅** | **✅** | **✅** |
| **Auto-sync with shop** | N/A | N/A | N/A | N/A | **✅** | **✅** | **✅** |

✅ = Works, ❌ = Not available, ✅* = Requires webcam/USB camera

**Desktop browsers** connect directly to the shop server — they don't need offline or sync because they're always on the LAN.

---

## Appendix C: What's NOT in V1.0 (Deferred to V2.0+)

| Feature | Why Deferred | Plan File |
|---------|-------------|-----------|
| Bluetooth mesh sync | Massive feature — requires native BLE modules, gossip protocol, device-to-device pairing | `Device Sync management.md` |
| Multi-PC shop cluster | Requires shop-to-shop sync, shared truth, merge conflicts at scale | `Device Sync management.md` |
| Q&A / Chat | New module entirely — escalation chains, cross-company RFI | `Q&A Part of the App` |
| Supplier portal | Multi-company pairing, remote sync, dynamic IP recovery | `The supplier's rep welcome too Idea.md` |
| AI integration | LM Studio connection, 30 read-only tools | Not yet planned |
| PGP device security | Per-device key pairs, encrypted sync payloads, company isolation | `Device security protocols.md` |
| Auto-update pipeline | Shop-originated, mesh-propagated updates | `Update protocol.md` |
| Bootstrap app (App Store) | Tiny pairing app that downloads real program from shop, no dependency on App Store for updates | `Mobile device bootstrap.md` |
| Device log retention (3mo/1yr) | Device prunes old data, shop keeps 1 year → needs retention engine | `Device Sync management.md` |

### What IS in V1.0 (formerly planned for V2.0)

| Feature | V1.0 Implementation |
|---------|---------------------|
| **Offline-first** | Full program on every device with local SQLite + TypeScript data layer |
| **Device sync** | LAN-only HTTP push/pull between device and shop |
| **Conflict resolution** | Last-writer-wins with shop as tiebreaker, conflict log for admin review |
| **Change tracking** | `_change_log` on device, `_shop_change_log` on shop |

All deferred features have detailed design documents in `docs/plans/` and can be built incrementally after V1.0 is deployed and stable. The V1.0 offline architecture is designed to be the **foundation** that V2.0's Bluetooth mesh and bootstrap app build on top of.
