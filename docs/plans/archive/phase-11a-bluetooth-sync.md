# Phase 11A: Bluetooth RFCOMM Sync (Windows PC ↔ PC)

> **Status:** ✅ Complete  
> **Started:** 2026-03-08  
> **Completed:** 2026-03-08  
> **Depends on:** Phase 3 (Sync infrastructure), Phase 10 (Scheduling)

---

## Overview

Two Windows PCs — the **shop computer** (primary / truth anchor) and a **field computer** (secondary) — sync data over Bluetooth RFCOMM when within range. This enables fully offline field work with automatic synchronization when the field worker returns to the shop.

**Key design decisions:**

1. **Zero third-party BT dependencies** — uses Windows Winsock2 `AF_BTH` via Python `ctypes`. No pybluez, bleak, or native extensions.
2. **RFCOMM TCP tunnel** — Bluetooth is exposed as a transparent localhost TCP proxy. Secondary's sync job hits `localhost:9000` → BT RFCOMM → primary's `localhost:8000` (FastAPI). Zero changes to existing 25+ sync endpoints.
3. **Role is location-based, not device-based** — whichever PC is at the shop is primary. Configurable in settings.
4. **Backend-to-backend sync** — the frontend is NOT involved in transport. It only manages pairing and monitors tunnel status.
5. **Graceful degradation** — on non-Windows or missing BT adapter, all endpoints return "not available" without crashing.

---

## Architecture

```
┌─────────────────┐                    ┌──────────────────┐
│  FIELD PC        │                    │  SHOP PC          │
│  (secondary)     │                    │  (primary)        │
│                  │    BT RFCOMM       │                   │
│  FastAPI :8000   │◄──────────────────►│  FastAPI :8000    │
│  Tunnel  :9000   │    (encrypted)     │  (truth anchor)   │
│                  │                    │                   │
│  bt_sync_job     │                    │                   │
│  (every 120s)    │                    │                   │
│  hits :9000      │──► BT ──► :8000 ──►│  /api/sync/*      │
│  push/pull       │                    │  (existing sync)  │
└─────────────────┘                    └──────────────────┘
```

**Tunnel modes:**
- **Primary (shop):** Listens for RFCOMM connections → forwards incoming HTTP to local `:8000`
- **Secondary (field):** Connects via RFCOMM → opens local `:9000` TCP server → forwards to BT → remote `:8000`

---

## Files Created / Modified

### Execution Layer (Layer 3)
| File | Purpose |
|------|---------|
| `execution/bt_windows.py` | Windows BT RFCOMM primitives via ctypes/Winsock2 — discovery, RFCOMM listen/accept/connect, framed I/O, heartbeat |
| `execution/bt_tunnel.py` | `BtTunnel` class — bidirectional RFCOMM TCP tunnel with auto-reconnect, stats tracking, heartbeat, exponential backoff |

### Backend (Layer 2)
| File | Purpose |
|------|---------|
| `backend/app/migrations/057_bluetooth_pairing.sql` | Tables: `bt_paired_devices`, `bt_connection_log`, `_bt_sync_state`. Settings seeds. Permission seed. |
| `backend/app/models/bluetooth.py` | Pydantic v2 request/response models for all BT endpoints |
| `backend/app/repositories/bluetooth_repo.py` | Direct DB access for paired devices, connection log, settings (standalone — not BaseRepo) |
| `backend/app/services/bluetooth_service.py` | Orchestration — wraps execution scripts, manages singleton tunnel, handles scan/pair/connect/disconnect |
| `backend/app/services/bt_sync_job.py` | APScheduler job — secondary PC pushes local changes and pulls shop changes through BT tunnel |
| `backend/app/routers/bluetooth.py` | 11 API endpoints under `/api/bluetooth/*` with `manage_bluetooth` permission |

### Backend Integration
| File | Change |
|------|--------|
| `backend/app/main.py` | Added `"app.routers.bluetooth"` to `ROUTER_MODULES` |
| `backend/app/scheduler.py` | Added `bt_sync_via_tunnel_job` async function + `IntervalTrigger(seconds=120)` registration |

### Frontend
| File | Purpose |
|------|---------|
| `frontend/src/api/bluetooth.ts` | TypeScript API client — types + functions for all 11 BT endpoints |
| `frontend/src/features/settings/pages/BluetoothPage.tsx` | Complete rewrite — PC RFCOMM pairing UI with 5 tabs (Status, Paired, Scan, History, Config) |
| `frontend/src/features/settings/pages/SyncPage.tsx` | Added `BluetoothSyncCard` — live tunnel status, paired device info, sync stats on the Sync & Devices page |

---

## API Endpoints (11 total)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/bluetooth/availability` | Check BT hardware availability |
| GET | `/api/bluetooth/scan` | Discover nearby BT devices (duration param) |
| GET | `/api/bluetooth/paired` | List paired devices with live connection status |
| POST | `/api/bluetooth/pair` | Pair with a discovered device (generates 6-digit code) |
| DELETE | `/api/bluetooth/pair/{id}` | Unpair (deactivate) a device |
| POST | `/api/bluetooth/connect` | Start RFCOMM tunnel to paired device |
| POST | `/api/bluetooth/disconnect` | Stop tunnel (logs stats) |
| GET | `/api/bluetooth/status` | Get tunnel state + transfer stats |
| GET | `/api/bluetooth/log` | Connection history (paginated) |
| GET | `/api/bluetooth/config` | Current BT settings |
| PUT | `/api/bluetooth/config` | Update BT settings |

---

## Database Tables

### `bt_paired_devices`
- `id`, `device_id`, `bt_address` (unique among active), `display_name`, `role` (primary/secondary)
- `pairing_code`, `is_active`, `last_connected_at`, `last_sync_at`, `paired_at`

### `bt_connection_log`
- Session-level logging: connect/disconnect times, bytes sent/received, requests forwarded, changes synced
- Duration calculated via `julianday()` diff

### `_bt_sync_state`
- Key-value store for sync tracking (`last_push_at`, `last_pull_at`, etc.)

### Settings (seeded)
- `bt_enabled`, `bt_device_role`, `bt_auto_connect`, `bt_sync_interval`, `bt_tunnel_port`

---

## Sync Flow (Secondary PC)

Every 120 seconds, `bt_sync_job` runs on the secondary:

1. Check tunnel is connected (skip if not)
2. Generate stable `device_id` from hostname + MAC
3. Register device with shop via `POST /api/sync/device/register`
4. Query local `_shop_change_log` for changes since last push
5. `POST /api/sync/push` — send local changes to shop
6. `GET /api/sync/pull?since={timestamp}` — get shop changes
7. Apply shop changes locally (INSERT OR REPLACE / UPDATE / DELETE)
8. `POST /api/sync/ack` — acknowledge receipt
9. Update `_bt_sync_state` timestamps

---

## Verification Results

| Check | Result |
|-------|--------|
| TypeScript `tsc -b` | ✅ Zero errors |
| Vite production build | ✅ Success (17.8s) |
| Python syntax (all 7 files) | ✅ All compile |
| Pre-existing tests | Not re-run (no sync test changes) |

---

## Future Enhancements

- **Auto-connect on proximity** — detect paired device entering BT range, auto-start tunnel
- **Encryption** — RFCOMM already encrypted at protocol level; could add app-level PGP per Phase 11 plan
- **Multi-device mesh** — extend from 2-device to N-device BT sync (deferred to Phase 11: Sync & Bluetooth)
- **Connection quality monitoring** — RSSI-based signal strength display on BT card
- **Selective sync** — configure which tables/data categories sync over BT (bandwidth optimization)
