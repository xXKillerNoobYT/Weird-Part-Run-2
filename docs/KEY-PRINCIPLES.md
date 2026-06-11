# Wired-Part — Key Principles to Remember

> This document captures the core design philosophy and non-negotiable principles of the Wired-Part application. Every contributor (human or AI) should internalize these before making changes.
>
> **Paperclip staging update (2026-05-26):** Use `docs/plans/staged-paperclip-goals.md` for current execution order and active/planned status. Architecture notes below preserve product principles and may include historical platform language.

---

## 1. One App, Every Device — Identical Experience

Wired-Part is a **single standalone application** that looks and works the same across every platform:

| Platform | Form Factor | How It Runs |
|----------|-------------|-------------|
| **iPhone** | Mobile phone | Tauri native app (WKWebView + local SQLite) |
| **iPad** | Tablet | Tauri native app (WKWebView + local SQLite) |
| **Mac** | Desktop | Tauri native app (WebView + local SQLite) |
| **Windows** | Desktop | Tauri native app (WebView2 + local SQLite) |
| **Browser** | Desktop (at the shop) | Same React UI served by the shop's FastAPI server |

**The UI is identical.** The same React components render on every device. Responsive Tailwind CSS adapts layout to the viewport — but the app's features, flow, and behavior are the same everywhere.

**The data layer is identical.** Every native device has its own local SQLite database with the full schema. All 16 migrations run on every device. A phone at a job site has the same data capabilities as the shop computer.

---

## 2. Fully Offline, Always Functional

Every device runs **100% standalone** with no internet or server dependency:

- **All data is local.** Parts, jobs, labor, orders, notebooks, fleet — everything lives in the device's own SQLite database.
- **No server required.** The app boots, authenticates, and operates without ever contacting a server.
- **Sync is opportunistic.** When devices are on the same network, they sync via Wi-Fi LAN or Bluetooth P2P. But sync is never required for the app to work.
- **Offline is the default state.** The app assumes it's offline and treats connectivity as a bonus.

---

## 3. Devices Work Together

While each device is standalone, they form a **collaborative mesh** when connected:

- **Wi-Fi LAN sync:** Devices on the same network discover each other via mDNS and sync automatically.
- **Bluetooth P2P sync:** Apple devices use Multipeer Connectivity for peer-to-peer data exchange — no router needed.
- **Shop computer as truth anchor:** The shop's desktop (running FastAPI + SQLite) serves as the primary data source. Mobile devices sync to/from it.
- **Conflict resolution:** Last-writer-wins with field-level merge. Conflicts are logged for audit.
- **Change tracking:** Every write is tracked in `_change_log` with device ID and vector clock timestamps.

---

## 4. The API Adapter Pattern

The same React frontend works in two modes, selected automatically at runtime:

```
┌─────────────────────────────────────┐
│         React UI (shared)           │
├─────────────────────────────────────┤
│         API Adapter Layer           │
│   ┌───────────┐  ┌───────────────┐  │
│   │  Browser   │  │   Tauri/Native │  │
│   │  HTTP →    │  │   Local TS →   │  │
│   │  FastAPI   │  │   SQLite       │  │
│   └───────────┘  └───────────────┘  │
└─────────────────────────────────────┘
```

- **Browser mode:** `isBrowser() === true` → API calls go to FastAPI over HTTP (LAN)
- **Native mode:** `isNativeApp() === true` → API calls route to local TypeScript services that read/write SQLite directly

The adapter is transparent. Components call `getJobs()` or `createPart()` without knowing which backend handles it.

---

## 5. Local-First Architecture

Every native device has the full data layer:

- **35 local TypeScript services** covering auth, parts, jobs, labor, orders, fleet, tools, warehouse, notebooks, scheduling, people, reports, and more
- **16 SQLite migrations** that create and maintain 83+ tables
- **BaseRepo pattern** for generic CRUD with soft deletes and change tracking
- **UUIDs for all records** — no auto-increment conflicts between devices
- **Soft deletes** (`deleted_at` column) — nothing is permanently destroyed, sync can propagate deletions

---

## 6. Security & Trust

- **PIN-based authentication** with SHA-256 hashing (no passwords, no internet auth)
- **Ed25519 certificates** for device identity and sync authentication
- **Role-based access** — technicians, foremen, and admins see different capabilities
- **Device registry** — admin can force-logout, force-wipe, or disable any device
- **SQLCipher-ready** database encryption

---

## 7. Responsive Design Requirements

Every page must work across all viewport sizes:

| Breakpoint | Target | Layout |
|------------|--------|--------|
| `< 640px` | iPhone | Single column, hamburger nav, icon-only buttons |
| `640-768px` | Small tablet | Compact layout, collapsible sidebar |
| `768-1024px` | iPad | Mid-size layout, sidebar visible |
| `> 1024px` | Desktop | Full layout, all columns visible |

**Non-negotiable rules:**
- Tap targets ≥ 44×44px on mobile
- No horizontal overflow (use `overflow-x-auto` for wide tables)
- No hover-only interactions (always provide tap alternative)
- Dark mode works at every breakpoint

---

## 8. The Service Pattern

All local services follow the same pattern:

```typescript
// No classes — exported async functions
export async function getJobs(): Promise<Job[]> {
  const db = await getDb();        // Fresh connection per call
  const result = await db.query('SELECT * FROM jobs WHERE deleted_at IS NULL');
  return result.values as Job[];
}
```

- **No classes.** Pure functions with `getDb()` per call.
- **Soft deletes.** Always filter `WHERE deleted_at IS NULL`.
- **Timestamps on writes.** `created_at` and `updated_at` on every record.
- **Change tracking.** `BaseRepo` automatically logs changes to `_change_log`.
- **UUIDs.** All new records use `crypto.randomUUID()`.

---

## 9. Build & Distribution

| Platform | Package | Distribution |
|----------|---------|-------------|
| Mac | `.dmg` | Direct or App Store |
| Windows | NSIS installer | Direct download |
| iOS | `.ipa` | TestFlight → App Store |
| Browser | Served by FastAPI | LAN access at shop |

Auto-updates for desktop via `@tauri-apps/plugin-updater`.

---

## 10. What This App Is NOT

- **Not a web app with a native wrapper.** It's a native app with a shared UI layer.
- **Not cloud-dependent.** There is no cloud server. All data stays on your devices and your network.
- **Not a thin client.** Every device has the full database and full business logic.
- **Not platform-specific.** The same codebase compiles for all targets. No separate iOS/Android/Desktop codebases.

---

## Summary

**Wired-Part is one program** that runs identically on phones, tablets, Macs, and Windows PCs. Every device is self-sufficient with its own database. Devices sync when they can, work alone when they can't. The UI adapts to the screen, but the experience is the same everywhere.

*This is the vision. Every code change should reinforce it.*
