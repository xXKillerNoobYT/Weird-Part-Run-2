# Cross-Platform Architecture Alignment + Public Directory Feature

## Context

The user provided a comprehensive cross-platform instruction set. After analysis, the **existing Tauri architecture already satisfies ~80% of the requirements** — `src/` is the shared core, `src-tauri/` is the platform layer, one change propagates to all platforms. What's genuinely missing:

1. **Public directory for desktop** — DB is hardcoded to per-user app data; needs option for shared directory so all computer users access the same data
2. **`isDesktop()` / `isMobile()` utilities** — `isDesktop()` exists locally in `updater-service.ts` but should be shared in `environment.ts`
3. **Pre-existing TS errors** — blocking `npm run build`
4. **Documentation** — MEMORY.md and CLAUDE.md don't record the restructure or cross-platform rules

### Instruction Set vs Reality

| Instruction | Status | Notes |
|-------------|--------|-------|
| Shared core logic | ✅ Already done | `src/` = 100% shared React code |
| Platform-specific layers | ✅ Already done | `src-tauri/` + Rust `#[cfg]` + `capabilities/desktop.json` |
| One change → all builds | ✅ Already done | Tauri builds from single `src/` + `src-tauri/` |
| iPadOS vs iOS split | ✅ Unified (correct) | One iOS target, responsive CSS handles screen size |
| Public directory (desktop) | ❌ Needs building | Currently hardcoded `'sqlite:wiredpart.db'` in per-user dir |
| BT mesh sync | ✅ Already done | Multipeer Connectivity (Phase 5) |
| Cross-platform testing | ⏳ Future phase | No automated multi-platform test pipeline yet |
| `/core` + `/platforms` restructure | ❌ Skip | Would break Tauri — current `src/` + `src-tauri/` is equivalent |

---

## Where Files Are Saved (Current vs After This Plan)

### Current DB Storage Paths

| Platform | Path | Shared? |
|----------|------|---------|
| **macOS** | `~/Library/Application Support/com.wiredpart.app/wiredpart.db` | ❌ Per-user |
| **Windows** | `C:\Users\{user}\AppData\Local\wiredpart\wiredpart.db` | ❌ Per-user |
| **iOS (iPhone/iPad)** | App sandbox (managed by OS) | N/A (single user) |

### After This Plan — Desktop Gets Public Option

| Platform | Private Mode (default) | Public Mode (optional) |
|----------|----------------------|----------------------|
| **macOS** | `~/Library/Application Support/com.wiredpart.app/wiredpart.db` | `/Users/Shared/WiredPart/wiredpart.db` |
| **Windows** | `C:\Users\{user}\AppData\Local\wiredpart\wiredpart.db` | `C:\Users\Public\WiredPart\wiredpart.db` |
| **iOS** | App sandbox (no change) | N/A (single-user device) |

### Config File Location (always per-user — it's the pointer)

| Platform | Config Path |
|----------|------------|
| **macOS** | `~/Library/Application Support/com.wiredpart.app/db-config.json` |
| **Windows** | `C:\Users\{user}\AppData\Local\wiredpart\db-config.json` |

---

## Project File Layout (where source code lives)

```
Weird-Part-Run-2/                         ← PROJECT ROOT
├── backend/                              ← Python FastAPI (shop computer only)
│   └── app/main.py                       ← Serves dist/ to desktop browsers
├── src/                                  ← SHARED REACT UI (ALL PLATFORMS)
│   ├── features/                         ← Feature pages (responsive, no platform branches)
│   ├── components/                       ← Reusable UI (44px touch targets, responsive)
│   ├── api/                              ← API adapter (browser → HTTP, Tauri → local services)
│   ├── lib/
│   │   └── environment.ts                ← isTauri(), isDesktop(), isMobile(), getPlatform()
│   └── local/
│       ├── db.ts                         ← SQLite connection (configurable path after this plan)
│       ├── db-config.ts                  ← NEW: reads/writes DB path config
│       ├── services/                     ← 35 TS services (on-device in Tauri mode)
│       ├── repos/                        ← Data access (BaseRepo pattern)
│       └── migrations/                   ← 16 schema migrations (same on every device)
├── src-tauri/                            ← TAURI NATIVE SHELL (Rust)
│   ├── src/
│   │   ├── lib.rs                        ← Entry + plugin registration
│   │   ├── commands.rs                   ← IPC commands (+ new create_public_data_dir)
│   │   ├── sync_server.rs                ← LAN sync (all platforms)
│   │   ├── multipeer.rs                  ← BT sync (Apple only: #[cfg])
│   │   ├── discovery.rs                  ← mDNS peer discovery
│   │   └── crypto.rs                     ← Ed25519 device trust
│   ├── capabilities/
│   │   ├── default.json                  ← Cross-platform permissions
│   │   └── desktop.json                  ← Desktop-only (autostart, updater)
│   ├── objc/MultipeerBridge.m            ← ObjC Bluetooth bridge (Apple)
│   ├── Cargo.toml                        ← Rust dependencies
│   └── gen/apple/project.yml             ← iOS build spec (iPhone + iPad unified)
├── public/                               ← Static assets (favicon, etc.)
├── ios/                                  ← Capacitor iOS (legacy, Tauri handles iOS now)
├── tests/                                ← Frontend tests
├── docs/                                 ← Documentation + plans
│   └── plans/                            ← Archived plan files
├── directives/                           ← Development SOPs
├── execution/                            ← Deterministic Python scripts
├── patches/                              ← patch-package patches
├── package.json                          ← Frontend dependencies
├── vite.config.ts                        ← Vite build config
├── tsconfig.json / tsconfig.app.json     ← TypeScript config
├── index.html                            ← SPA entry point
├── capacitor.config.ts                   ← Capacitor config (legacy)
├── install.sh / launch.sh                ← Setup/launch scripts
└── CLAUDE.md                             ← Agent instructions
```

---

## Execution Plan

### Task 1: Add `isDesktop()` and `isMobile()` to environment.ts

**File:** `src/lib/environment.ts`

Add after `isBrowser()`:

```typescript
/** True when running on a desktop OS (macOS or Windows) */
export function isDesktop(): boolean {
  if (!isTauri()) return false;
  const platform = getPlatform();
  return platform === 'macos' || platform === 'windows';
}

/** True when running on a mobile OS (iOS or Android) */
export function isMobile(): boolean {
  if (!isTauri()) return false;
  const platform = getPlatform();
  return platform === 'ios' || platform === 'android';
}
```

Update `src/local/services/updater-service.ts` to import `isDesktop` from `environment.ts` instead of defining its own copy.

### Task 2: Public Directory Feature

#### 2a: Create `src/local/db-config.ts`

Config reader/writer that stores DB path preference in a small JSON file in the default app data dir. Uses `@tauri-apps/plugin-fs` to read/write.

```typescript
interface DbConfig {
  mode: 'private' | 'public';
  customPath?: string; // absolute path to DB file when mode === 'public'
}

// Default: { mode: 'private' }
// Public macOS: { mode: 'public', customPath: '/Users/Shared/WiredPart/wiredpart.db' }
// Public Windows: { mode: 'public', customPath: 'C:\\Users\\Public\\WiredPart\\wiredpart.db' }
```

#### 2b: Modify `src/local/db.ts` (line 75)

```typescript
// FROM:
const db = await Database.load('sqlite:wiredpart.db');

// TO:
const config = await getDbConfig();
let dbPath = 'sqlite:wiredpart.db'; // default: Tauri app data dir
if (isDesktop() && config.mode === 'public' && config.customPath) {
  dbPath = `sqlite:${config.customPath}`;
}
const db = await Database.load(dbPath);
```

#### 2c: Add Rust IPC command `create_public_data_dir`

**File:** `src-tauri/src/commands.rs`

```rust
#[tauri::command]
pub fn create_public_data_dir() -> Result<String, String> {
    #[cfg(target_os = "macos")]
    {
        let dir = std::path::PathBuf::from("/Users/Shared/WiredPart");
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        // Set permissions: rwxrwxrwx (world-readable/writable)
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o777))
            .map_err(|e| e.to_string())?;
        Ok(dir.to_string_lossy().to_string())
    }
    #[cfg(target_os = "windows")]
    {
        let dir = std::path::PathBuf::from(r"C:\Users\Public\WiredPart");
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        Ok(dir.to_string_lossy().to_string())
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        Err("Public directory is only supported on desktop".to_string())
    }
}
```

Register in `src-tauri/src/lib.rs` invoke_handler.

#### 2d: Settings UI for data location

Add to the Settings page — only visible when `isDesktop()` returns true:

```
┌─ Data Storage ───────────────────────────────────┐
│                                                  │
│  ○ Private (this user only)                      │
│    ~/Library/Application Support/.../wiredpart.db│
│                                                  │
│  ● Public (all users on this computer)           │
│    /Users/Shared/WiredPart/wiredpart.db          │
│                                                  │
│  ⚠ Changing requires app restart                 │
│  [Switch to Public] or [Switch to Private]       │
└──────────────────────────────────────────────────┘
```

Hidden entirely on iOS — the component checks `isDesktop()`.

When switching private→public:
1. Call `create_public_data_dir` IPC to create + set permissions
2. Copy existing DB to public dir
3. Update db-config.json
4. Prompt user to restart app

### Task 3: Fix Pre-Existing TypeScript Errors

| File | Line(s) | Issue | Fix |
|------|---------|-------|-----|
| `src/local/services/notifications-service.ts` | 79,109,116,123,153,159,177,214,235,279,300 | Missing `await` on `getDb()` | Add `await` |
| `src/local/services/job-service.ts` | 456 | Unused `db` variable | Remove |
| `src/local/services/settings-service.ts` | 28 | Unused `_settingsRepo` | Remove |
| `src/local/services/report-service.ts` | 1111 | Unused `_jobParams` | Remove |

### Task 4: Update MEMORY.md

**File:** `/Users/IA/.claude/projects/-Users-IA-GitHub-Weird-Part-Run-2/memory/MEMORY.md`

Add after Architecture Decisions section — restructure record, cross-platform rules, DB storage paths, key environment detection files, known TS errors.

### Task 5: Update CLAUDE.md

**File:** `/Users/IA/GitHub/Weird-Part-Run-2/CLAUDE.md`

- Add restructure + Tauri migration to "Recently Completed" (~line 175)
- Replace Architecture section (~line 177-184) with updated version reflecting Tauri, cross-platform rule, and computer users ≠ app users distinction

### Task 6: Archive plan to docs/

**File:** `docs/plans/frontend-to-root-restructure.md` — completed restructure record + cross-platform architecture principles.

---

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `src/lib/environment.ts` | **Modify** | Add `isDesktop()`, `isMobile()` |
| `src/local/db-config.ts` | **Create** | DB path config reader/writer |
| `src/local/db.ts` | **Modify** | Use configurable path from db-config |
| `src-tauri/src/commands.rs` | **Modify** | Add `create_public_data_dir` IPC command |
| `src-tauri/src/lib.rs` | **Modify** | Register new IPC command |
| `src/local/services/updater-service.ts` | **Modify** | Import shared `isDesktop` |
| Settings page (TBD exact file) | **Modify** | Add desktop-only data location UI |
| `src/local/services/notifications-service.ts` | **Fix** | Add missing `await` on 10 calls |
| `src/local/services/job-service.ts` | **Fix** | Remove unused `db` |
| `src/local/services/settings-service.ts` | **Fix** | Remove unused `_settingsRepo` |
| `src/local/services/report-service.ts` | **Fix** | Remove unused `_jobParams` |
| MEMORY.md | **Update** | Restructure + cross-platform rules + DB paths |
| CLAUDE.md | **Update** | Recently completed + architecture |
| `docs/plans/frontend-to-root-restructure.md` | **Create** | Archived plan |

---

## Verification

1. `npm run build` — passes after TS fixes (Task 3)
2. `npx vite build` — already working
3. `cargo check` (in src-tauri/) — compiles with new IPC command
4. Settings page on desktop shows data location section with current path
5. Switching to public mode creates shared directory and opens DB there
6. Mobile settings page does NOT show data location section
7. Future sessions read MEMORY.md/CLAUDE.md and see correct structure + rules + file paths
