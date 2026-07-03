# WiredPart — Key Principles to Remember

> This document captures the core design philosophy and non-negotiable principles of the WiredPart application. Every contributor (human or AI) should internalize these before making changes.
>
> **Updated 2026-07-01 (GitHub #1334):** Rewritten for the current native iOS architecture. The product principles are unchanged from the original vision; the platform sections previously described the retired Tauri/React/FastAPI stack (preserved in git history). Use `docs/plans/staged-paperclip-goals.md` for current execution order and active/planned status.

---

## 1. One App, Native Where It Runs

WiredPart is a **single native SwiftUI application** backed by one shared Swift core:

| Layer | Where | What |
|-------|-------|------|
| **App UI** | `Weird Parts IOS/` | SwiftUI feature screens for iPhone and iPad (deployment target iOS 26.2) |
| **Shared core** | `core/Sources/WiredPartCore/` | 22 services owning all business rules, GRDB/SQLite persistence, sync, AI, QR/OCR |
| **Mac compatibility** | `WiredPart-iOS` scheme on a Mac Catalyst-capable destination when needed | Same iOS app target and shared core; no standalone macOS project is active |

**The core is the app.** Business rules, validation, and data access live in `WiredPartCore`, where they are testable without booting the UI (2,200+ core tests). SwiftUI screens are thin composition layers over shared services, view models, and navigation state.

**The data layer is identical on every device.** Every device runs the full schema — all 109 migrations — in its own local SQLite database. A phone at a job site has the same data capabilities as the iPad at the shop.

---

## 2. Fully Offline, Always Functional

Every device runs **100% standalone** with no internet or server dependency:

- **All data is local.** Parts, jobs, labor, orders, notebooks, fleet — everything lives in the device's own encrypted SQLite database (GRDB + SQLCipher).
- **No server required.** The app boots, authenticates, and operates without ever contacting a server. There is no backend.
- **Sync is opportunistic.** When company devices are near each other, they sync peer-to-peer. Sync is never required for the app to work.
- **Offline is the default state.** The app assumes it's offline and treats connectivity as a bonus.

---

## 3. Devices Work Together

While each device is standalone, they form a **collaborative mesh** when connected:

- **Peer-to-peer sync:** Apple Multipeer Connectivity (Bluetooth / Wi-Fi P2P) plus LAN sync surfaces — no router or server required for nearby devices.
- **Device pairing:** New devices join by pairing with a device that already holds the company data, then receive a full initial sync.
- **Conflict resolution:** Last-writer-wins with field-level merge. Conflicts are classified, logged, and surfaced for review (including an AI-assisted review view).
- **Change tracking:** Every write is tracked in `_change_log` with device attribution so merges are reliable.

---

## 4. Core Owns the Business Rules

The dividing line between app and core is strict:

- **`WiredPartCore` first.** Domain rules, persistence, sync, and calculations go in the package, where `swift test` exercises them in-memory in seconds.
- **SwiftUI stays thin.** Feature screens compose services and render state; they do not embed business logic.
- **One service per domain.** 22 services (Parts, Orders, Jobs, Warehouse, People, Scheduling, Notebooks, Reports, Dashboard, Fleet, Tools, Chat, Auth, Settings, and more) — each `public final class`, `Sendable`, injected with `AppDatabase`.

---

## 5. Local-First Architecture

Every device has the full data layer:

- **22 Swift core services** covering auth, parts, jobs, labor, orders, fleet, tools, warehouse, notebooks, scheduling, people, reports, and more
- **109 SQLite migrations** (`000_change_log` → `105_job_records_local_first`) that create and maintain the full schema
- **Soft deletes** (`deleted_at` column) on every business table — nothing is permanently destroyed, and sync can propagate deletions
- **`is_active` + `deleted_at` defense in depth** — both flags filtered on every soft-deletable query
- **Change tracking** on every write so peer sync can merge reliably

---

## 6. Security & Trust

- **PIN-based authentication** with bcrypt hashing (no passwords, no internet auth), plus biometric unlock
- **Ed25519 keys** for device identity and sync trust
- **Role-based access ("hats")** — permission checks enforced at the service layer, not just UI hiding
- **Device registry** — admin can force-logout, force-wipe, or disable any device
- **Encrypted at rest** — SQLCipher via the pinned GRDB fork; iOS Data Protection on top

---

## 7. Adaptive, Accessible UI

Every screen must work on iPhone and iPad, portrait and landscape:

- Tap targets ≥ 44×44pt
- Dynamic Type scales without breaking layout (accessibility sizes included)
- Dark mode works everywhere
- No hover-only interactions; VoiceOver labels on interactive elements

---

## 8. The Service Pattern

All core services follow the same pattern:

```swift
public final class JobsService: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) { self.database = database }

    public func listJobs() throws -> [Job] {
        try database.reader.read { db in
            try Job.filter(Column("deleted_at") == nil).fetchAll(db)
        }
    }
}
```

- **Dependency injection** via `AppDatabase` — no singletons, fully testable with in-memory databases.
- **Soft deletes.** Always filter `deleted_at IS NULL` (and `is_active` where present).
- **Timestamps on writes.** `created_at` and `updated_at` on every record.
- **Real user IDs.** Never hardcode user IDs for `created_by`/`updated_by` — flow them from the session.

---

## 9. Build & Distribution

| Target | How | Distribution |
|--------|-----|-------------|
| iOS (iPhone/iPad) | `Weird Parts.xcworkspace` scheme `WiredPart-iOS`, or `Weird Parts IOS/Weird Parts.xcodeproj` scheme `Weird Parts` | TestFlight → App Store |
| Mac compatibility | workspace scheme `WiredPart-iOS` on a Mac Catalyst-capable destination when needed | not distributed |
| Core package | `cd core && swift build` | consumed by the app |

CI for iOS/Xcode work runs on the repo's local self-hosted Mac runner — see [runbooks/local-mac-actions-runner.md](runbooks/local-mac-actions-runner.md).

---

## 10. What This App Is NOT

- **Not a web app.** There is no web view, no JavaScript, no HTML UI — it is native SwiftUI end to end.
- **Not cloud-dependent.** There is no cloud server. All data stays on your devices and syncs device-to-device.
- **Not a thin client.** Every device has the full database and full business logic.
- **Not multi-stack.** One Swift codebase: one app target plus one shared package.

---

## Summary

**WiredPart is one native program** that runs on iPhones and iPads. Every device is self-sufficient with its own encrypted database and the full rule set in `WiredPartCore`. Devices sync when they can, work alone when they can't. Core owns the rules; SwiftUI stays thin.

*This is the vision. Every code change should reinforce it.*
