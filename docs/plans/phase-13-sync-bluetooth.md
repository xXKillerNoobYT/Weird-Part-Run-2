# Phase 11: Sync Engine & Bluetooth Mesh

> **Date:** 2026-03-07
> **Status:** 📋 Planned
> **Architecture docs:** `docs/plans/Device Sync management.md` (498 lines), `docs/plans/Device security protocols.md` (322 lines)
> **Dependencies:** V1.0 LAN sync working (deployment Phase B ✅), all data tables finalized, Chat (Phase 9)
> **Estimated work:** 16-24 days (complex — BT mesh, encryption, multi-device sync, device management console)
> **Architecture:** Extends V1.0 LAN sync with Bluetooth mesh for field-to-field sync without shop connectivity.

---

## Vision

V1.0 gives us **LAN sync** — devices push/pull data when connected to the shop's local network. This works for the daily pattern: workers come to the shop in the morning, sync, go to jobs, return in the evening, sync again.

Phase 11 adds **Bluetooth mesh sync** — devices sync with each other directly in the field. This means:
- A worker who hasn't been to the shop in a week still gets updates (via other workers who have)
- Messages, clock events, and parts usage propagate through the crew without internet
- Data reaches the shop faster (any device that visits the shop carries everyone's changes)

### Prime Directive (from architecture doc)

> If data has not been confirmed as delivered to the shop, ANY device that encounters it MUST carry it and MUST sync it with every device within range until delivery is confirmed.

---

## System Principles

1. **Shop is truth anchor** — resolves conflicts, confirms delivery, holds full history
2. **Core data on all devices** — all active job data stored on every device
3. **Media delivery is mandatory** — devices may choose what media to *keep* permanently but MUST carry undelivered media temporarily
4. **Weekly convergence guarantee** — even without direct shop contact, mesh ensures convergence within ~1 week
5. **Company-scoped** — devices only sync with same-company devices (PGP verification)
6. **Append-only sync** — no data is ever deleted during sync, only marked as delivered

---

## Database Schema

### Migration: `030_sync_bluetooth.sql`

```sql
-- ═══════════════════════════════════════════════════
-- Enhanced Change Log (extends existing _change_log)
-- ═══════════════════════════════════════════════════

-- Delivery tracking per device
CREATE TABLE IF NOT EXISTS _sync_delivery_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    change_log_id INTEGER NOT NULL,                -- references _change_log.id
    delivered_to_device_id TEXT NOT NULL,           -- UUID of receiving device
    delivered_at TEXT DEFAULT (datetime('now')),
    delivery_method TEXT CHECK(delivery_method IN ('lan', 'bluetooth', 'relay')),
    UNIQUE(change_log_id, delivered_to_device_id)
);

-- Track which devices have confirmed delivery to shop
CREATE TABLE IF NOT EXISTS _sync_shop_confirmations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    change_log_id INTEGER NOT NULL,
    confirmed_at TEXT DEFAULT (datetime('now')),
    confirmed_by_device_id TEXT NOT NULL            -- which device delivered it to shop
);

-- ═══════════════════════════════════════════════════
-- Device Registry
-- ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY,                            -- UUID
    device_name TEXT,                               -- "Roy's iPhone", "Shop PC 1"
    device_type TEXT CHECK(device_type IN ('phone', 'tablet', 'desktop', 'shop')),
    platform TEXT,                                  -- iOS, Android, Windows, macOS
    primary_user_id INTEGER REFERENCES users(id),
    company_id TEXT NOT NULL,                       -- company scope
    public_key TEXT NOT NULL,                       -- device's public key (PGP)
    certificate TEXT,                               -- company-signed certificate
    certificate_expiry TEXT,
    last_sync_at TEXT,                              -- last successful sync with shop
    last_seen_at TEXT,                              -- last seen by any device
    is_shop_device INTEGER DEFAULT 0,              -- 1 = shop PC, 0 = field device
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- ═══════════════════════════════════════════════════
-- Company Keys (shop-only table)
-- ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS company_keys (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    company_id TEXT NOT NULL UNIQUE,
    company_name TEXT NOT NULL,
    root_key_encrypted TEXT NOT NULL,               -- encrypted with shop master password
    sync_key TEXT NOT NULL,                         -- derived from root, used for device comms
    created_at TEXT DEFAULT (datetime('now'))
);

-- ═══════════════════════════════════════════════════
-- Bluetooth Encounter Log
-- ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS bt_encounters (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    local_device_id TEXT NOT NULL,
    remote_device_id TEXT NOT NULL,
    encounter_start TEXT NOT NULL,
    encounter_end TEXT,
    changes_sent INTEGER DEFAULT 0,                 -- count of changes pushed
    changes_received INTEGER DEFAULT 0,             -- count of changes pulled
    bytes_transferred INTEGER DEFAULT 0,
    signal_strength INTEGER,                        -- RSSI value
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_bt_encounters_devices 
    ON bt_encounters(local_device_id, remote_device_id, encounter_start);

-- ═══════════════════════════════════════════════════
-- Media Delivery Tracking
-- ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _media_delivery (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    media_hash TEXT NOT NULL,                       -- SHA-256 of media file
    media_path TEXT NOT NULL,                       -- original path
    media_size_bytes INTEGER NOT NULL,
    origin_device_id TEXT NOT NULL,                 -- device that created the media
    delivered_to_shop INTEGER DEFAULT 0,            -- 1 = shop has it
    shop_confirmed_at TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_media_delivery_pending 
    ON _media_delivery(delivered_to_shop) WHERE delivered_to_shop = 0;

-- ═══════════════════════════════════════════════════
-- Sync Session Log (audit trail)
-- ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS sync_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_type TEXT CHECK(session_type IN ('lan_push', 'lan_pull', 'bt_sync', 'shop_cluster')),
    local_device_id TEXT NOT NULL,
    remote_device_id TEXT NOT NULL,
    started_at TEXT NOT NULL,
    completed_at TEXT,
    status TEXT DEFAULT 'in_progress' CHECK(status IN ('in_progress', 'completed', 'failed', 'partial')),
    changes_sent INTEGER DEFAULT 0,
    changes_received INTEGER DEFAULT 0,
    media_sent INTEGER DEFAULT 0,
    media_received INTEGER DEFAULT 0,
    bytes_total INTEGER DEFAULT 0,
    error_message TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

  -- ═══════════════════════════════════════════════════
  -- Device Error Logging + Health Telemetry
  -- ═══════════════════════════════════════════════════
  CREATE TABLE IF NOT EXISTS device_error_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    severity TEXT NOT NULL CHECK(severity IN ('info', 'warning', 'error', 'critical')),
    error_type TEXT NOT NULL CHECK(error_type IN ('js_exception', 'api_failure', 'sync_failure', 'storage_warning', 'bt_error', 'auth_error')),
    message TEXT NOT NULL,
    stack_trace TEXT,
    context TEXT,                                  -- JSON context
    app_version TEXT,
    os_version TEXT,
    free_storage_mb INTEGER,
    battery_percent INTEGER,
    resolved INTEGER DEFAULT 0,
    resolved_by INTEGER REFERENCES users(id),
    resolved_at TEXT,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_device_error_log_device_time
    ON device_error_log(device_id, created_at DESC);

  CREATE TABLE IF NOT EXISTS device_health_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    app_version TEXT,
    os_version TEXT,
    free_storage_mb INTEGER,
    total_storage_mb INTEGER,
    db_size_mb INTEGER,
    media_cache_mb INTEGER,
    battery_percent INTEGER,
    battery_charging INTEGER DEFAULT 0,
    connection_type TEXT CHECK(connection_type IN ('wifi', 'cellular', 'bluetooth', 'none')),
    pending_sync_count INTEGER DEFAULT 0,
    pending_media_count INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_device_health_device_time
    ON device_health_snapshots(device_id, created_at DESC);

  -- ═══════════════════════════════════════════════════
  -- Device Storage Preferences
  -- ═══════════════════════════════════════════════════
  CREATE TABLE IF NOT EXISTS device_storage_config (
    device_id TEXT PRIMARY KEY,
    data_retention TEXT NOT NULL DEFAULT 'active_jobs' CHECK(data_retention IN ('all_history', 'active_jobs', 'last_30_days')),
    media_cache_mb INTEGER NOT NULL DEFAULT 1024,
    keep_media_days INTEGER NOT NULL DEFAULT 30,
    auto_cleanup_enabled INTEGER DEFAULT 1,
    updated_at TEXT DEFAULT (datetime('now'))
  );

  -- Device admin override flags
  ALTER TABLE devices ADD COLUMN is_disabled INTEGER DEFAULT 0;
  ALTER TABLE devices ADD COLUMN disabled_reason TEXT;
  ALTER TABLE devices ADD COLUMN force_logout INTEGER DEFAULT 0;
  ALTER TABLE devices ADD COLUMN force_wipe INTEGER DEFAULT 0;
  ALTER TABLE devices ADD COLUMN config_version INTEGER DEFAULT 1;
```

---

## Backend Implementation (TypeScript — Lean Mobile Data Layer)

### Sync Engine Core: `sync-engine.ts`

The sync engine runs on every device (shop has Python version, mobile has TS version).

```typescript
interface SyncEngine {
    // Core sync loop
    startLANSync(): void;           // Periodic sync with shop over HTTP
    startBTScan(): void;            // Scan for nearby BT devices
    stopAll(): void;
    
    // Change tracking
    getUndeliveredChanges(): Change[];        // Changes not yet confirmed by shop
    getChangesSince(lastSyncId: number): Change[];  // For push to other devices
    applyRemoteChanges(changes: Change[]): void;    // Apply received changes
    
    // Media handling
    getUndeliveredMedia(): MediaItem[];
    storeTemporaryMedia(media: MediaItem): void;
    confirmMediaDelivered(hash: string): void;
    
    // Delivery tracking
    markDeliveredTo(changeId: number, deviceId: string, method: string): void;
    isDeliveredToShop(changeId: number): boolean;
}
```

### Bluetooth Service: `bt-service.ts`

Manages Bluetooth Low Energy (BLE) scanning and data exchange.

```typescript
interface BTService {
    // Discovery
    startScanning(): void;                  // Scan for nearby devices
    stopScanning(): void;
    getVisibleDevices(): BTDevice[];
    
    // Connection
    connectToDevice(deviceId: string): Promise<BTConnection>;
    disconnectDevice(deviceId: string): void;
    
    // Handshake (company verification)
    performHandshake(connection: BTConnection): Promise<HandshakeResult>;
    // 1. Exchange company_id + device certificates
    // 2. Verify certificates against company_sync_key
    // 3. If mismatch → reject, log attempt, disconnect
    // 4. If match → establish encrypted session
    
    // Data exchange
    pushChanges(connection: BTConnection, changes: Change[]): Promise<void>;
    pullChanges(connection: BTConnection, sinceId: number): Promise<Change[]>;
    pushMedia(connection: BTConnection, media: MediaItem[]): Promise<void>;
    pullMedia(connection: BTConnection, hashes: string[]): Promise<MediaItem[]>;
    
    // Gossip protocol
    exchangeDeliveryStatus(connection: BTConnection): Promise<void>;
    // Compare what each device knows about shop delivery status
    // Update local delivery tracking based on peer's knowledge
}
```

### Encryption Service: `crypto-service.ts`

Handles all encryption operations using the Web Crypto API (+ Capacitor plugins for keystore).

```typescript
interface CryptoService {
    // Key management
    generateDeviceKeypair(): Promise<CryptoKeyPair>;
    storeKeys(keypair: CryptoKeyPair): Promise<void>;  // Secure storage
    getPublicKey(): Promise<string>;                     // PEM format
    
    // Certificate operations
    requestCertificate(shopUrl: string, publicKey: string): Promise<Certificate>;
    verifyCertificate(cert: Certificate, companySyncKey: string): boolean;
    
    // Session encryption (for BT and LAN)
    deriveSessionKey(localPrivate: CryptoKey, remotePubKey: string, companySyncKey: string): Promise<CryptoKey>;
    encrypt(data: ArrayBuffer, sessionKey: CryptoKey): Promise<ArrayBuffer>;
    decrypt(data: ArrayBuffer, sessionKey: CryptoKey): Promise<ArrayBuffer>;
    
    // Data at rest
    encryptForStorage(data: string): Promise<string>;
    decryptFromStorage(data: string): Promise<string>;
}
```

### Device Pairing Flow

```
1. New device installs app
2. User enters shop URL (or scans QR code from shop)
3. Device generates keypair
4. Device sends {device_id, public_key, platform, device_name} to shop via LAN
5. Shop verifies user auth → assigns company_id
6. Shop signs device certificate: {device_id, company_id, public_key, expiry}
7. Device stores: company_id, certificate, shop_public_key, company_sync_key
8. Device is now paired — can sync with shop + other company devices
```

### Gossip Protocol

When two devices meet via Bluetooth:

```
1. BLE scan detects nearby device advertising same service UUID
2. Connect + perform handshake (exchange certs, verify company match)
3. Exchange sync metadata:
   - "My last shop sync was at: [timestamp]"
   - "I have changes up to ID: [id]"
   - "I have undelivered changes: [count]"
   - "I know shop has confirmed up to: [id]"
4. Exchange undelivered changes (both directions)
5. Exchange undelivered media (both directions, prioritized by size: small first)
6. Update delivery tracking:
   - If peer has fresher shop confirmation → update local records
   - Mark all exchanged changes as "delivered_to" this peer
7. Log encounter in bt_encounters table
8. Disconnect (or maintain connection if still in range)
```

### Multi-PC Shop Cluster

From the architecture doc: the shop may have multiple PCs/Macs on the same LAN.

```
- Any shop PC can accept sync from field devices
- Shop PCs sync with each other automatically (LAN discovery)
- If two shop PCs conflict → most recent timestamp wins (same as field sync)
- Shop PCs keep 1-year sync log (field devices keep 3 months)
- When a shop PC comes online after being off → reconciles with other shop PCs first
```

---

## Backend Implementation (Python — Shop Side)

### Service: `sync_service.py` (extend existing)

```python
class SyncService:
    # Existing V1.0 LAN sync methods (keep)
    async def push_changes(self, device_id: str, changes: list[dict]) -> dict
    async def pull_changes(self, device_id: str, since_id: int) -> list[dict]
    
    # New: Device management
    async def pair_device(self, device_info: dict, user_id: int) -> dict
    async def revoke_device(self, device_id: str) -> None
    async def list_devices(self) -> list[dict]
    async def get_device_sync_status(self) -> list[dict]  # last sync time per device
    
    # New: Media sync
    async def receive_media(self, device_id: str, media_hash: str, media_data: bytes) -> dict
    async def get_pending_media(self, device_id: str) -> list[dict]  # media device doesn't have yet
    async def confirm_media_received(self, device_id: str, hashes: list[str]) -> None
    
    # New: Shop cluster sync
    async def discover_shop_peers(self) -> list[str]  # other shop PCs on LAN
    async def sync_with_peer(self, peer_url: str) -> dict
    
    # New: Certificate management
    async def sign_device_certificate(self, device_id: str, public_key: str) -> str
    async def verify_device_certificate(self, certificate: str) -> bool
    async def rotate_company_keys(self) -> dict  # periodic key rotation
```

### Router: `sync_router.py` (extend existing)

```
# Existing V1.0 endpoints (keep)
POST /api/sync/push      — Device pushes changes to shop
GET  /api/sync/pull       — Device pulls changes from shop

# New: Device management
POST   /api/sync/devices/pair       — Pair new device
DELETE /api/sync/devices/{id}       — Revoke device
GET    /api/sync/devices            — List all paired devices
GET    /api/sync/devices/status     — Sync status dashboard

# New: Device admin console
GET    /api/devices                           — Device list with health + sync summary
GET    /api/devices/{id}                      — Full device detail
PUT    /api/devices/{id}                      — Rename device / update metadata
PUT    /api/devices/{id}/primary-user         — Reassign primary user
GET    /api/devices/{id}/storage              — Get storage config + current usage
PUT    /api/devices/{id}/storage              — Update retention/cache settings
GET    /api/devices/{id}/errors               — Device error timeline
POST   /api/devices/{id}/errors               — Device reports error batch
PUT    /api/devices/errors/{error_id}/resolve — Resolve an error
POST   /api/devices/{id}/force-logout         — End current device session
POST   /api/devices/{id}/force-wipe           — Mark device for wipe on next check-in
POST   /api/devices/{id}/disable              — Disable device (lost/stolen)
POST   /api/devices/{id}/enable               — Re-enable disabled device
POST   /api/devices/{id}/force-sync           — Flag immediate sync on next check-in
POST   /api/devices/{id}/push-config          — Increment config_version for config refresh
GET    /api/keys/status                        — Company key health + rotation status
GET    /api/devices/{id}/certificate          — Certificate details/expiry
POST   /api/devices/{id}/certificate/reissue  — Force cert reissue

# New: Media sync
POST   /api/sync/media/upload       — Upload media blob
GET    /api/sync/media/pending       — Get list of media device is missing
POST   /api/sync/media/confirm       — Confirm device received media

# New: Certificate
POST   /api/sync/cert/sign           — Sign device certificate
POST   /api/sync/cert/verify         — Verify a certificate

# New: Shop cluster
POST   /api/sync/cluster/discover    — Find other shop PCs
POST   /api/sync/cluster/sync        — Trigger inter-shop sync
```

---

## Frontend Implementation

### Navigation

Add "Sync" section to Settings (gear icon) or as a top-level admin page:

```
Settings → Sync & Devices:
  ├── Sync Status      — Dashboard showing all devices, last sync, data freshness
  ├── Device Management — Primary user, storage, health, overrides (office only)
  ├── Error Log        — Unified device error timeline (office only)
  ├── Keys & Certs     — Certificate expiry + key status (office only)
  ├── Bluetooth        — BT settings, nearby devices, encounter log
  └── Shop Cluster     — Multi-shop-PC status (office only)
```

### Page: `SyncStatusPage.tsx`

**Layout:**
- **My Device card:** Device ID, last shop sync, pending changes count, pending media count
- **Other Devices list:** Each device shows:
  - Name, type icon, primary user
  - Last sync with shop (timestamp + "X hours ago")
  - Last seen by any device (BT encounter)
  - Pending changes indicator (green = synced, yellow = pending, red = stale)
- **Sync actions:** "Sync Now" button (triggers immediate LAN push/pull)
- **Data freshness indicator:** "All data is current" or "3 changes pending upload"

### Page: `DeviceManagementPage.tsx` (office/admin only)

**Layout:**
- **Device list:** Name | Type | Platform | Primary User | Last Sync | Pending Changes | Storage | Health | Actions
- **Primary user management:** Reassign ownership; primary user is preference anchor for the device
- **Storage controls:** Data retention mode, media cache limit, clear cache, auto-clean toggle
- **Actions per device:** Rename | Revoke | Force Logout | Force Sync | Disable/Enable | Force Wipe
- **Pair new device button:** Shows QR code with shop URL + pairing token
- **Active sessions:** Show any currently-in-progress sync sessions

### Page: `DeviceErrorLogPage.tsx` (office/admin only)

**Layout:**
- **Unified timeline:** Time | Device | Severity | Error Type | Message
- **Filters:** severity, device, date range, error type
- **Detail drawer:** full stack trace + context JSON + environment snapshot
- **Actions:** Resolve selected, resolve all for a device, export CSV

### Page: `KeyManagementPage.tsx` (office/admin only)

**Layout:**
- **Company key status:** Key age, last rotation, next scheduled rotation
- **Certificate table:** Device | Expiry | Status | Reissue action
- **Auto-renewal panel:** success/failure log for cert renewals

### Page: `BluetoothPage.tsx`

**Layout:**
- **BT status:** On/Off toggle, scanning indicator
- **Nearby devices:** List of detected company devices (after handshake verification)
  - Name, signal strength bar, last encounter, data exchangeable
- **Encounter history:** Last 50 BT encounters (collapsible)
  - Device | Time | Duration | Changes Sent | Changes Received | Bytes
- **Settings:**
  - Auto-sync when devices detected (on/off)
  - Media sync over BT (on/off — large files may be slow)
  - Background scanning interval (1 min / 5 min / 15 min)

### Component: `SyncIndicator.tsx` (global — header bar)

Small indicator in the app header showing sync status:
- ✅ Green dot: All synced with shop
- 🟡 Yellow dot: Pending changes (tap to see count)
- 🔴 Red dot: Sync error or device not synced in 24+ hours
- Spinning: Sync in progress

### Component: `DeviceOverrideHandler.tsx` (global)

Listens for auth responses indicating admin override flags:
- `FORCE_LOGOUT` → clear auth token, return to login screen
- `FORCE_WIPE` → clear local SQLite/cache/session, force device re-registration flow

Ensures manual overrides from Device Management page execute safely on next check-in.

---

## Capacitor Plugins Required

```
@capacitor-community/bluetooth-le     — BLE scanning + connections
@capacitor/filesystem                  — Local media storage
@capawesome/capacitor-file-picker      — File selection
capacitor-secure-storage-plugin        — Keychain/Keystore for keys
```

Note: BLE on iOS requires Background Modes capability (bluetooth-central) for background scanning.

---

## Storage Rules

### Active Jobs
- **All devices** store full core data for all active jobs
- This is non-negotiable — every device must have complete context

### Completed/On-Hold Jobs
- **Optional** on field devices (user preference)
- **Always** on shop PCs (full history)
- When a job status changes to completed → devices can purge after next shop sync confirms

### Media
- **Permanent storage:** Controlled by device primary user's preferences
  - "Keep all photos" / "Keep last 30 days" / "Keep none" (texts/data only)
- **Temporary mandatory storage:** Undelivered media MUST be stored regardless of preferences
  - Media stays until shop confirms receipt
  - Only then can preferences be applied (purge if outside preference window)

### Sync Logs
- **Field devices:** 3 months retention
- **Shop PCs:** 1 year retention

### Device Error Logs
- **Field devices:** keep local error queue until upload confirmed
- **Shop:** retain uploaded `device_error_log` for 6 months (configurable)

### Device Health Snapshots
- Devices post health every 15 minutes while app is active
- Shop keeps 48-hour high-resolution snapshots + daily aggregates beyond 48h

---

## Security Model

### Company Isolation
- Each company has a unique `company_id` + `company_root_key`
- Every sync starts with certificate exchange and verification
- Mismatched company → handshake fails → no data exchange → log attempt
- Even in a shared office/yard, two companies' devices cannot sync

### Encryption in Transit
- **LAN (field↔shop):** TLS-like with mutual auth using device certificates
- **Bluetooth (field↔field):** Session key derived from `company_sync_key + both device_ids`, encrypted with AES-256-GCM

### Encryption at Rest
- **Devices:** OS-level secure storage (Keychain/Keystore) for keys, encrypted SQLite DB
- **Shop PCs:** Full DB encryption with company_root_key derivative

### Key Rotation
- Device certificates expire (90 days default)
- Devices must renew certificate at next shop sync
- Company sync key rotated annually (all devices get new key at next shop sync)

### Key Management UX
- Certificate lifecycle should be mostly automatic; Device Management page is for visibility and exception handling
- Warn admins at 30-day and 7-day expiry windows
- Provide manual reissue only for compromised/lost/replaced devices

---

## Conflict Resolution

**Strategy: Last-Writer-Wins (same as V1.0)**

- Each change carries a timestamp
- When two devices modify the same record → most recent timestamp wins
- Shop is final arbiter for ties
- Chat messages are append-only → no conflicts
- Q&A escalations: if two people escalate simultaneously → both escalation messages kept, thread level = highest

**Edge cases handled:**
- Same user on two devices (borrowed device scenario) → both changes apply, last wins
- Media hash collision → SHA-256 makes this effectively impossible
- Clock skew between devices → trust shop time as canonical, devices sync their clocks on LAN sync

---

## Success Criteria

- [ ] Devices pair with shop via QR code + certificate exchange
- [ ] LAN sync pushes/pulls all pending changes when on shop network
- [ ] Bluetooth scanning discovers nearby company devices
- [ ] BT handshake verifies company identity before data exchange
- [ ] Undelivered changes propagate via BT mesh (gossip protocol)
- [ ] Undelivered media carried temporarily regardless of storage preferences
- [ ] Media delivered to shop and confirmed before local purge allowed
- [ ] Device sync status visible on dashboard (last sync, pending count)
- [ ] Device Management page supports primary-user reassignment
- [ ] Per-device storage policy configurable (retention + media cache)
- [ ] Device error logs auto-upload and are visible in unified timeline
- [ ] Device health telemetry (storage/battery/version/pending sync) visible per device
- [ ] Manual overrides work: force logout, disable/enable, force wipe, force sync flag
- [ ] Override flags are enforced at auth middleware on next check-in
- [ ] Key/certificate dashboard shows expiry and supports manual reissue
- [ ] Multi-shop-PC cluster syncs between PCs automatically
- [ ] Company isolation prevents cross-company sync
- [ ] Encryption in transit (TLS for LAN, AES-256-GCM for BT)
- [ ] Encryption at rest (Keychain/Keystore + encrypted SQLite)
- [ ] Device certificates expire and auto-renew at shop
- [ ] Sync indicator in app header shows current status
- [ ] BT encounter log tracks all device-to-device syncs
- [ ] Works on both iOS and Android via Capacitor BLE plugin
- [ ] 3-month log retention on devices, 1-year on shop

---

## Execution Order

1. **Migration:** `030_sync_bluetooth.sql` — all sync/device tables
2. **Backend (Python):** Extend sync_service with device management + certificate signing
3. **Backend (Python):** Add device admin APIs (storage config, error logs, overrides)
4. **Backend (Python):** Enforce override flags in auth middleware
5. **Backend (Python):** Add shop cluster discovery + inter-shop sync
6. **Mobile (TS):** Build crypto-service (key generation, certificate handling, encryption)
7. **Mobile (TS):** Build sync-engine core (change tracking, delivery tracking)
8. **Mobile (TS):** Build bt-service (BLE scanning, handshake, data exchange)
9. **Mobile (TS):** Implement gossip protocol (undelivered change propagation)
10. **Mobile (TS):** Implement media sync + periodic health/error reporting
11. **Frontend:** Build SyncStatusPage + SyncIndicator component
12. **Frontend:** Build DeviceManagementPage (primary user, storage, overrides)
13. **Frontend:** Build DeviceErrorLogPage + KeyManagementPage
14. **Frontend:** Build BluetoothPage + encounter log
15. **Integration:** Wire BT background scanning (iOS Background Modes)
16. **Test:** Two devices sync via BT in field scenario
17. **Test:** Data reaches shop via relay (Device A → Device B via BT, Device B → Shop via LAN)
18. **Test:** Company isolation — two company devices refuse to sync
19. **Test:** Manual override flows execute safely (logout/wipe/disable)

---

## Future Extensions (Not This Phase)

- **Shop↔Shop internet sync** (Phase 13: Remote Sync)
- **Shared channels / cross-company controlled sync** (Phase 13)
- **Bootstrap app** — new device downloads full app from shop (see `docs/plans/Mobile device bootstrap.md`)
- **BT mesh optimization** — priority queuing, bandwidth management for large crews
- **Selective sync** — per-user job subscriptions (reduced from "all active jobs" to "my jobs + shared")
