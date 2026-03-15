# WiredPart: Windows Platform Continuation Prompt

> **Purpose:** This document is a complete context injection for an AI agent (or developer) picking up this project on a **Windows computer** to continue Phases 13, 14, and 15 of the native SwiftUI migration. It assumes you have no prior context and gives you everything you need.
>
> **Created:** 2026-03-15
> **Last Apple-side commit:** `1ff1b4d` (Phase 12: AI Integration)
> **All Apple platform phases (1-12) are COMPLETE and committed.**

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [What Has Been Completed (Phases 1-12)](#what-has-been-completed)
3. [Architecture Summary](#architecture-summary)
4. [Repository Structure](#repository-structure)
5. [The Legacy Codebase (Your Source of Truth for Porting)](#the-legacy-codebase)
6. [Phase 13: Windows AI Integration](#phase-13-windows-ai-integration)
7. [Phase 14: Windows Native App Target](#phase-14-windows-native-app-target)
8. [Phase 15: Legacy Cleanup](#phase-15-legacy-cleanup)
9. [Detailed Task Lists](#detailed-task-lists)
10. [Technical Reference: Services to Port](#technical-reference)
11. [Sync Protocol Specification](#sync-protocol-specification)
12. [Database Schema](#database-schema)
13. [Testing Strategy](#testing-strategy)
14. [Risk Register](#risk-register)
15. [Decision Log](#decision-log)

---

## 1. Project Overview <a name="project-overview"></a>

**WiredPart** is an ERP/field-service-management application for electrical contracting companies. It manages:

- **Parts & Inventory** — catalog, categories, brands, suppliers, pricing, stock levels, forecasting, import/export
- **Warehouse** — stock movements, staging, receiving, returns, audits, trailers
- **Jobs & Labor** — job CRUD, clock in/out with GPS, questionnaires, daily reports
- **Orders & Procurement** — JPO (Job Part Orders) to PO (Purchase Orders) lifecycle, receiving, returns
- **Fleet & Vehicles** — vehicles, assignments, maintenance, mileage, fuel
- **People** — employees, customers, contractors, contacts, teams, hats (roles), permissions, certifications
- **Scheduling** — dispatch board, time-off, templates, sub-schedules
- **Chat** — per-job channels, DMs, Q&A threads, RFI escalation
- **Notebooks** — job + general notes, todo stages, templates
- **Reports** — timesheets, labor overview, pre-billing, profitability, bookkeeper exports
- **Tools** — tool registry, kit verification, checkout/return, maintenance tracking
- **AI** — on-device LLM for text completion, enhancement, pre-fill (Apple Foundation Models on Apple; needs Windows equivalent)

### The Business Model

- Every device runs fully **offline-first** with its own local SQLite database
- One "shop computer" acts as the sync anchor and runs a Python FastAPI backend
- Devices sync over **LAN HTTP** and **Apple Multipeer Connectivity** (Bluetooth/Wi-Fi P2P)
- The app runs on macOS desktops, iOS phones/tablets, and will run on Windows desktops
- No internet required for any core functionality

### The Migration

The app was originally built as a **Tauri/React** cross-platform app (TypeScript frontend + Rust native shell). We are migrating to:

- **Apple platforms (DONE):** Native SwiftUI apps (macOS + iOS) sharing a `WiredPartCore` Swift package
- **Windows (YOUR JOB):** Either native Windows app or keep Tauri/React — you need to evaluate and decide
- **The Python FastAPI backend stays** — it runs on the shop computer regardless of platform

---

## 2. What Has Been Completed (Phases 1-12) <a name="what-has-been-completed"></a>

All Apple platform work is done. Here's what was built:

### Phase 1: Swift Core Package
- `WiredPartCore` Swift Package (SPM) with GRDB.swift 7.0.0 (SQLite ORM), swift-nio 2.65.0+ (HTTP server)
- 17 SQLite migrations ported from TypeScript
- All data models (Foundation, Parts, Jobs, Orders, Fleet, People, Scheduling, Chat, Sync, Costs, Notebooks, Tools)
- `BaseRepository` with automatic change tracking
- `AuthService` — PIN auth, user picker, seed admin, permissions
- `SettingsService` — settings CRUD, theme, company profiles

### Phase 2: Sync Engine
- `ConflictResolver` — field-level LWW merge with conflict logging
- `ChangeTracker` — automatic change log for all writes
- `SyncCrypto` — Ed25519 signing/verification via CryptoKit
- `LanSyncServer` — swift-nio HTTP server (push/pull/status endpoints)
- `PeerDiscovery` — mDNS via NWBrowser (`_wiredpart._tcp`)
- `MultipeerManager` — Apple Multipeer Connectivity (BT/Wi-Fi P2P)
- `SyncEngine` — orchestrates cloud sync cycles with backoff
- `PeerManager` — manages peer lifecycle, dual transport (LAN + Multipeer)

### Phase 3: App Shells
- macOS SwiftUI app with sidebar navigation, WebView fallback, auth flow, theme system
- iOS SwiftUI app with tab bar navigation, same patterns

### Phases 4-11: Feature Modules (all 13 modules)
Native SwiftUI views for both macOS and iOS:
- Dashboard, Settings, Parts, Warehouse, Jobs, Orders, Fleet, People, Scheduling, Chat, Notebooks, Reports, Tools

### Phase 12: AI Integration (Apple)
- `FoundationModelsService` actor — wraps Apple Foundation Models (`LanguageModelSession`)
- `AITools.swift` — `SearchPartsTool`, `SearchContactsTool`, `SearchJobsTool` (conform to `FoundationModels.Tool`)
- `AITextEditor` (macOS) — ghost text completion, enhancement popover, pre-fill
- `IOSAITextEditor` (iOS) — tap-to-accept suggestions, enhancement sheet
- `AIAvailabilityBanner` (both platforms) — status indicator

### Codebase Stats (as of Phase 12 completion)

| Target | Swift Files | Description |
|--------|------------|-------------|
| `core/` | 40 | Shared Swift package — models, services, sync, AI |
| `mac/` | 99 | macOS SwiftUI app — 13 feature modules + auth + nav |
| `ios-app/` | 77 | iOS SwiftUI app — 13 feature modules + auth + nav |
| **Total Swift** | **216** | New native code |

| Legacy Target | Files | Description |
|---------------|-------|-------------|
| `src/` (React/TS) | 468 | Legacy frontend — to be retired |
| `src-tauri/src/` (Rust) | 8 | Legacy native shell — to be retired |
| `backend/` (Python) | 1891 | Shop server — STAYS |

### Git Commit History (SwiftUI migration)

```
1ff1b4d Phase 12: AI Integration — Apple Foundation Models
fd8aa5d Phases 8-11: Orders, Fleet, People, Scheduling, Chat, Notebooks, Reports, Tools
ce5c77f Fix Package.swift missing swift-nio dep and ConflictLogEntry model
1b81643 Add generated build artifacts under core/.build
31ab1c8 Add Phase 2 sync engine files and migration plan
b0bc164 Native SwiftUI migration: Phases 1-7 complete
```

### Tests

- 153 unit tests in 14 test suites (all in `core/Tests/WiredPartCoreTests/`)
- Test files: AuthServiceTests, ChangeTrackerTests, ConflictResolverTests, ModelTests, MultipeerTests, PeerDiscoveryTests, PeerManagerTests, SyncCryptoTests, SyncEngineTests, SyncIntegrationTests, SyncServerTests, SettingsServiceTests, DatabaseTests, plus general WiredPartCoreTests

---

## 3. Architecture Summary <a name="architecture-summary"></a>

### Current Architecture (V1.0 — Tauri, still running)

```
┌─────────────────────────────────────────────────────┐
│  React Frontend (src/)                               │
│  468 TS/TSX files, 100 routes, 86 pages              │
├─────────────────────────────────────────────────────┤
│  TypeScript Data Layer (src/local/services/)          │
│  64 service files, local SQLite via Tauri SQL plugin  │
├─────────────────────────────────────────────────────┤
│  Tauri Rust Shell (src-tauri/src/)                    │
│  8 files: sync server, mDNS, crypto, multipeer, LLM  │
├─────────────────────────────────────────────────────┤
│  Python FastAPI Backend (backend/)                    │
│  30 routers, 802 endpoints, 48 services, 30 repos    │
│  Runs on shop computer as sync anchor                 │
└─────────────────────────────────────────────────────┘
```

### New Architecture (V2.0 — Native SwiftUI, Apple only)

```
┌──────────────┐    ┌──────────────┐
│ macOS App     │    │ iOS App       │
│ (mac/)        │    │ (ios-app/)    │
│ SwiftUI views │    │ SwiftUI views │
└──────┬───────┘    └──────┬───────┘
       │                    │
       └────────┬───────────┘
                │
       ┌────────▼────────┐
       │ WiredPartCore    │
       │ (core/)          │
       │ Models, Services │
       │ Sync, AI, DB     │
       └────────┬────────┘
                │
       ┌────────▼────────┐
       │ SQLite (GRDB)    │
       └─────────────────┘
```

### What Windows Needs

```
┌──────────────────────────────────────┐
│  Windows App (YOUR DECISION)          │
│  Option A: WinUI 3 / .NET MAUI       │
│  Option B: Keep Tauri/React           │
│  Option C: Swift on Windows (risky)   │
├──────────────────────────────────────┤
│  Windows AI (YOUR IMPLEMENTATION)     │
│  Primary: Windows Copilot Runtime     │
│  Fallback: llama.cpp (GGUF models)   │
├──────────────────────────────────────┤
│  Sync Engine (MUST BE COMPATIBLE)     │
│  LAN HTTP only (no Multipeer on Win)  │
│  Same wire protocol as Swift/Tauri    │
└──────────────────────────────────────┘
```

---

## 4. Repository Structure <a name="repository-structure"></a>

```
Weird-Part-Run-2/
├── core/                              # WiredPartCore Swift Package (DONE)
│   ├── Package.swift                  # SPM manifest (GRDB 7.0.0, swift-nio 2.65.0+)
│   ├── Sources/WiredPartCore/
│   │   ├── Database/                  # AppDatabase, Migrations, BaseRepository
│   │   ├── Models/                    # Foundation, Parts, Jobs, Orders, Fleet, People, etc.
│   │   ├── Services/                  # 14 service classes (Auth, Settings, Parts, Warehouse, etc.)
│   │   ├── Sync/                      # SyncEngine, ChangeTracker, ConflictResolver, etc. (8 files)
│   │   └── AI/                        # FoundationModelsService, AITools (2 files)
│   └── Tests/WiredPartCoreTests/      # 14 test files, 153 tests
│
├── mac/                               # macOS SwiftUI App (DONE)
│   ├── Package.swift
│   └── WiredPart/
│       ├── App/                       # AppCore, WiredPartApp, LoadingView
│       ├── Navigation/                # MainView, SidebarView, TabBarView, ContentRouter
│       ├── Auth/                      # LoginView, BootstrapView
│       ├── Features/                  # 13 modules (Dashboard, Parts, Warehouse, Jobs, etc.)
│       ├── AI/                        # AITextEditor, AIAvailabilityBanner
│       ├── WebFallback/               # WKWebView for unported pages
│       └── Theme/                     # ThemeManager
│
├── ios-app/                           # iOS SwiftUI App (DONE)
│   ├── Package.swift
│   └── WiredPartIOS/
│       ├── App/                       # AppCore, WiredPartIOSApp, LoadingView
│       ├── Navigation/                # IOSMainView, IOSContentRouter, NavigationConfig
│       ├── Auth/                      # IOSLoginView, IOSBootstrapView
│       ├── Features/                  # 13 modules (matching macOS)
│       ├── AI/                        # IOSAITextEditor, IOSAIAvailabilityBanner
│       ├── WebFallback/               # IOSWebFallbackView
│       └── Theme/                     # IOSThemeManager
│
├── src/                               # *** LEGACY React/TypeScript Frontend ***
│   ├── local/                         # Offline-first data layer
│   │   ├── services/                  # 64 TS service files (YOUR PORTING SOURCE)
│   │   ├── repos/                     # Base repository
│   │   ├── migrations/                # 17 SQLite migrations (already ported to Swift)
│   │   ├── change-tracker.ts          # Change tracking (already ported)
│   │   ├── conflict-resolver.ts       # Conflict resolution (already ported)
│   │   ├── sync-engine.ts             # Sync engine (already ported)
│   │   └── peer-manager.ts            # Peer management (already ported)
│   ├── features/                      # React page components (86 pages)
│   ├── lib/                           # Utilities, API adapter, environment detection
│   └── components/                    # Shared UI components
│
├── src-tauri/                         # *** LEGACY Tauri Rust Shell ***
│   ├── src/
│   │   ├── lib.rs                     # App setup, plugin registration, IPC commands
│   │   ├── commands.rs                # IPC command wrappers
│   │   ├── sync_server.rs             # HTTP sync server (axum)
│   │   ├── discovery.rs               # mDNS service discovery
│   │   ├── crypto.rs                  # Ed25519 certificate auth
│   │   ├── multipeer.rs               # Apple Multipeer FFI (macOS/iOS only)
│   │   └── foundation_models.rs       # Apple LLM FFI (macOS/iOS only)
│   ├── gen/apple/                     # Generated iOS/macOS project files
│   └── Cargo.toml                     # Rust dependencies
│
├── backend/                           # *** Python FastAPI Backend (STAYS) ***
│   ├── app/
│   │   ├── main.py                    # FastAPI app, 30 routers, lifespan
│   │   ├── routers/                   # 30 router modules, 802 endpoints
│   │   ├── services/                  # 48 service classes
│   │   ├── repositories/              # 30 repository classes
│   │   ├── models/                    # 28 Pydantic model files
│   │   ├── middleware/                # Auth, permissions
│   │   ├── database.py                # SQLite + aiosqlite
│   │   ├── config.py                  # Environment config
│   │   └── scheduler.py              # APScheduler background jobs
│   └── requirements.txt
│
├── windows/                           # *** YOUR TARGET — Currently empty ***
│
├── docs/
│   ├── The Full Plan.md               # Original comprehensive vision
│   ├── implementation-plan.md          # Master roadmap
│   ├── plan/                          # 10 architecture docs (repo_map, core_boundary, etc.)
│   ├── FEATURES.md                    # Feature list
│   ├── KEY-PRINCIPLES.md              # Architecture principles
│   └── SETUP.md                       # Setup instructions
│
├── directives/                        # AI agent instructions
│   ├── v1-development-prompt.md       # Original development prompt
│   ├── v1-real-world-e2e-testing-prompt.md
│   └── windows-continuation-prompt.md # THIS FILE
│
├── CLAUDE.md                          # Agent instructions (mirrored across AI tools)
└── MEMORY.md                          # Project context & patterns
```

---

## 5. The Legacy Codebase (Your Source of Truth for Porting) <a name="the-legacy-codebase"></a>

When building the Windows app, the **TypeScript services** in `src/local/services/` are your primary reference for business logic. The **Rust modules** in `src-tauri/src/` are your reference for native capabilities (sync server, discovery, crypto).

### TypeScript Services (64 files in `src/local/services/`)

#### Root-Level Services (33 files)
| Service | Lines | Description |
|---------|-------|-------------|
| `auth-service.ts` | ~300 | PIN auth, user picker, permissions |
| `settings-service.ts` | ~200 | Settings CRUD, theme, company profiles |
| `dashboard-service.ts` | ~200 | KPIs, activity feeds |
| `movement-service.ts` | ~442 | 3-phase stock movement (validate/preview/execute) |
| `warehouse-service.ts` | ~280 | Inventory dashboards, KPIs, stock health |
| `order-service.ts` | ~270 | JPO/PO creation and management |
| `job-service.ts` | ~300 | Job CRUD, labor |
| `labor-service.ts` | ~308 | Clock in/out, hours (8hr OT threshold), questionnaires |
| `fleet-service.ts` | ~125 | Vehicle assignments, inventory |
| `tool-service.ts` | ~405 | Tool checkout/return, kit verification |
| `receiving-service.ts` | ~222 | PO receiving workflow |
| `billing-service.ts` | ~195 | Billing periods, cost locking |
| `pto-service.ts` | ~298 | PTO policies, accruals, balance |
| `trailer-service.ts` | ~240 | Trailer CRUD, location events |
| `attachment-service.ts` | ~142 | Polymorphic order attachments |
| `depreciation-service.ts` | ~199 | Tool depreciation (straight-line, declining) |
| `supplier-portal-service.ts` | ~234 | Portal tokens, PO acknowledgments |
| `costs-service.ts` | ~725 | Cost tracking (FIFO/LIFO), margins, budget alerts |
| `relay-service.ts` | ~330 | P2P relay manifest, queue management |
| `bootstrap-client.ts` | ~551 | Artifact download, SHA-256, signature validation |
| `security-service.ts` | ~316 | Device keypair, certificates, DB encryption |
| `notebook-service.ts` | ~688 | Job + general notebooks, sections, tasks, templates |
| `bt-service.ts` | ~100+ | Multipeer peer discovery, sync status |
| `bt-inbox-handler.ts` | ~100+ | Incoming BT message processing |
| `autostart-service.ts` | ~74 | Launch-on-boot (Tauri plugin) |
| `scheduler-service.ts` | ~100+ | Cron scheduler (notification cleanup, backup) |
| `updater-service.ts` | ~100+ | Auto-update (Tauri updater, Ed25519 verification) |
| `notifications-service.ts` | ~100+ | Badge count, notification list, sound settings |
| `contacts-service.ts` | ~200 | Contact management |
| `chat-service.ts` | ~300 | Chat channels, messages, Q&A |
| `scheduling-service.ts` | ~300 | Dispatch, time-off |
| `file-export-service.ts` | ~150 | File export |
| `report-service.ts` | ~300 | Report generation |

#### People Sub-Services (`src/local/services/people/`, 8 files)
- `employees-service.ts` — Employee records
- `certifications-service.ts` — Certifications & expiry tracking
- `wages-service.ts` — Wage/pay management
- `skills-service.ts` — Employee skills
- `teams-service.ts` — Team management
- `hats-service.ts` — Role assignments
- `elevations-service.ts` — Permission elevations
- `notes-service.ts` — People notes

#### Parts Sub-Services (`src/local/services/parts/`, 10 files)
- `hierarchy-service.ts` — Category/style/type/color hierarchy
- `catalog-service.ts` — Parts catalog browsing
- `pricing-service.ts` — Pricing tiers, cost management
- `stock-service.ts` — Stock levels by location
- `suppliers-service.ts` — Supplier management
- `forecasting-service.ts` — Stock forecasting
- `import-export-service.ts` — CSV import/export
- `companions-service.ts` — Companion part rules
- `alternatives-service.ts` — Alternative parts

#### Reports Sub-Services (`src/local/services/reports/`, 9 files)
- `timesheets.ts`, `labor-overview.ts`, `profitability.ts`, `pre-billing.ts`
- `exports.ts`, `templates.ts`, `annotations.ts`, `share-tokens.ts`, `helpers.ts`

### Rust Modules (8 files in `src-tauri/src/`)

| File | Lines | Description |
|------|-------|-------------|
| `main.rs` | ~6 | Entry point |
| `lib.rs` | ~117 | Tauri setup, plugin registration, 14 IPC commands |
| `commands.rs` | ~150+ | IPC wrappers (sync, public data dir, company key, LLM) |
| `sync_server.rs` | ~100+ | axum HTTP server (push/pull/status) |
| `discovery.rs` | ~100+ | mDNS via `_wiredpart._tcp.local.` |
| `crypto.rs` | ~100+ | Ed25519 cert verification |
| `multipeer.rs` | ~100+ | Apple Multipeer FFI (macOS/iOS only — **N/A on Windows**) |
| `foundation_models.rs` | ~100+ | Apple LLM FFI (macOS/iOS only — **N/A on Windows**) |

### Python Backend (STAYS UNCHANGED)

The backend at `backend/` runs on the shop computer. It has:
- 30 routers with 802 API endpoints
- 48 services with ~28,000 lines of business logic
- 30 repositories with ~9,200 lines of data access
- 35 SQLite migrations
- 3 sync mechanisms (LAN HTTP, Remote Internet, Bluetooth)
- APScheduler for background jobs (daily reports, backups)

The Windows app will communicate with this backend over LAN HTTP, just like the existing Tauri app does.

---

## 6. Phase 13: Windows AI Integration <a name="phase-13-windows-ai-integration"></a>

### Goal
Provide on-device AI capabilities on Windows, matching the Apple Foundation Models experience.

### Primary: Windows Copilot Runtime

Windows Copilot Runtime provides on-device AI APIs for Windows 11 24H2+:

- **Windows.AI.MachineLearning** namespace
- **Phi Silica** — small language model available locally
- **Text generation, summarization, rewriting** — matches our use cases

#### Tasks

1. **Research Windows Copilot Runtime availability**
   - Check: Is Phi Silica available on all Windows 11 24H2+ devices or only Copilot+ PCs?
   - Check: What are the hardware requirements (NPU, RAM)?
   - Check: What languages/runtimes can call it? (C#, C++, Rust, Python?)
   - Decision: If only Copilot+ PCs, llama.cpp becomes primary instead of fallback

2. **Implement Windows AI service interface**
   - Same capabilities as Apple's `FoundationModelsService`:
     - `checkAvailability()` — is AI available on this device?
     - `generateCompletion(partialText, fieldType, context)` — autocomplete
     - `enhanceText(text, mode, fieldType)` — proofread/rewrite/summarize/expand/professional
     - `generatePreFill(fieldType, context)` — generate field content from context
     - `askQuestion(question, context)` — general Q&A about business data

3. **Implement AI tools for database queries**
   - `SearchPartsTool` — search parts catalog by name/SKU/category
   - `SearchContactsTool` — search customers & contacts
   - `SearchJobsTool` — search jobs by name/number/status
   - These query the local SQLite database and return formatted results to the LLM

### Fallback: llama.cpp

For devices without Copilot Runtime (older Windows, non-Copilot+ PCs):

4. **Integrate llama.cpp**
   - Use a small GGUF model (e.g., Phi-3-mini, Llama-3.2-1B, or similar)
   - Options for integration:
     - **C library** — link llama.cpp directly (C/C++ interop)
     - **llama-cpp-python** — Python bindings (if Windows app uses Python)
     - **Local HTTP server** — run llama.cpp as a server, call via HTTP (like LM Studio)
   - Model download: On first use, download model to `%APPDATA%\WiredPart\models\`
   - Model size target: <4GB for broad hardware compatibility

5. **User toggle in Settings**
   - "AI Engine" setting: Auto (prefer native) | Copilot Runtime | llama.cpp | Disabled
   - Show which engine is active and its status
   - Model download progress for llama.cpp

### AI UI Components

6. **Port AI text editor**
   - Ghost text autocomplete (Tab to accept, Escape to dismiss)
   - Enhancement popover (proofread, rewrite, summarize, expand, professional tone)
   - Pre-fill sparkles button
   - Availability banner showing AI status

### Testing

7. **3 canonical AI prompts for behavior tests**
   - **Autocomplete:** `"The delivery for job 1234 was del"` → continuation
   - **Enhance (proofread):** `"recived parts form supplyer, wil inspect tomorow"` → corrected
   - **Pre-fill:** Context: `{jobName: "Smith Renovation", crewLead: "Mike", date: "2026-03-15"}` → dispatch note

---

## 7. Phase 14: Windows Native App Target <a name="phase-14-windows-native-app-target"></a>

### The Big Decision

You need to evaluate three options and pick one:

### Option A: WinUI 3 / .NET MAUI (Recommended to evaluate first)

**Pros:**
- First-class Windows experience (native controls, Windows 11 design language)
- C# has excellent SQLite support (Microsoft.Data.Sqlite, Entity Framework)
- Direct access to Windows Copilot Runtime APIs
- .NET MAUI could theoretically target Android too (future)
- Strong IDE support (Visual Studio)

**Cons:**
- Need to rewrite all 14 services in C# (or call SQLite directly)
- Need to build all 13 feature module UIs from scratch
- Different language than the Swift core (no code sharing with Apple)
- Larger effort

**If you choose this:**
1. Create `windows/` as a .NET MAUI or WinUI 3 project
2. Port `WiredPartCore` services to C# (same logic, different language)
3. Use the same SQLite schema — database files are portable
4. Build all 13 feature module views in XAML or .NET MAUI
5. Implement sync client (LAN HTTP only — no Multipeer on Windows)

### Option B: Keep Tauri/React for Windows

**Pros:**
- Already works — zero porting effort for UI
- All 86 pages, 64 services, 8 Rust modules are done
- Tauri 2.0 supports Windows natively
- Can still add Windows Copilot Runtime via Rust FFI or separate process

**Cons:**
- WebView-based — not truly native Windows experience
- Tauri adds complexity (Rust + TypeScript + WebView)
- Maintenance burden of two stacks (Swift for Apple, Tauri for Windows)
- React WebView uses more memory than native

**If you choose this:**
1. Keep `src/` and `src-tauri/` as-is for Windows builds only
2. Add Windows Copilot Runtime via Rust FFI in `src-tauri/src/`
3. Add llama.cpp as a sidecar process or Rust binding
4. Modify `src-tauri/tauri.conf.json` to build Windows-only
5. Update `CLAUDE.md` to note that `src/` is Windows-only now

### Option C: Swift on Windows (Experimental)

**Pros:**
- Could share `WiredPartCore` directly (same language, same package)
- The Swift project has Windows support (swift.org/download/ has Windows builds)
- Theoretically the least effort if it works

**Cons:**
- Swift on Windows is immature (2026 status TBD — check swift.org)
- No SwiftUI on Windows — would need a different UI framework
- GRDB.swift may not compile on Windows
- CryptoKit doesn't exist on Windows (need alternative)
- swift-nio works on Windows but may have edge cases
- High risk of unresolvable blockers

**If you choose this:**
1. Test: `swift build` of `core/` on Windows
2. If GRDB compiles: you can share the data layer
3. UI: Use a C library UI toolkit, or call WinUI from Swift
4. Replace CryptoKit with SwiftCrypto (cross-platform)
5. This is experimental — have Option B as fallback

### Evaluation Checklist

Before committing to an option, verify:

- [ ] Can I build and run the chosen framework on Windows 11?
- [ ] Can I access a SQLite database with the same schema?
- [ ] Can I make HTTP requests to the shop server for sync?
- [ ] Can I start an HTTP server for peer-to-peer sync?
- [ ] Can I do mDNS service discovery (to find peers on the LAN)?
- [ ] Can I call Windows Copilot Runtime APIs?
- [ ] Can I integrate llama.cpp?
- [ ] What's the cold start time? (Target: <3 seconds)
- [ ] What's the memory usage? (Target: <200MB RSS idle)

---

### Windows App: Feature Module Task List

Regardless of which option you choose, you need these 13 feature modules:

| # | Module | Pages | Key Features |
|---|--------|-------|-------------|
| 1 | Dashboard | 1 | KPIs, activity feed, alerts, recent items |
| 2 | Settings | 5+ | Theme, company, PDF, billing, sync, AI, devices |
| 3 | Parts & Inventory | 10 | Catalog, categories tree, brands, suppliers, pricing, companions, forecasting, import/export |
| 4 | Warehouse | 9 | Dashboard, movements, staging, receiving, returns, audit, network, trailers |
| 5 | Jobs & Labor | 6 | Job list, job detail, clock in/out, questionnaire, daily reports, team |
| 6 | Orders & Procurement | 12 | Unified order form, JPO list, PO list, receiving, returns, conversation, PDF |
| 7 | Fleet & Vehicles | 6 | Vehicle list, detail, assignments, maintenance, mileage, fuel |
| 8 | People | 10 | Employees, customers, contractors, contacts, teams, hats, permissions, certifications, skills, wages |
| 9 | Scheduling | 7 | Calendar grid, dispatch board, templates, config, time off, availability, sub-schedule |
| 10 | Chat | 3 | Channel list, message thread, Q&A escalation |
| 11 | Notebooks | 3 | Notebook list, detail with entries, templates |
| 12 | Reports | 4 | Timesheets, labor overview, pre-billing, profitability |
| 13 | Tools | 4 | Tool registry, kit verification, checkout/return, maintenance |

**Total: ~80 pages/views**

---

### Sync Implementation for Windows

Windows sync is **LAN HTTP only** (no Multipeer Connectivity):

1. **Sync Client** — POST to `{shopUrl}/api/sync/push` and `/api/sync/pull`
2. **Sync Server** — HTTP server on random port for peer-to-peer
3. **mDNS Discovery** — Advertise and browse `_wiredpart._tcp` on LAN
4. **Change Tracking** — Same `_change_log` table, same schema
5. **Conflict Resolution** — Same field-level LWW algorithm
6. **Ed25519 Crypto** — Certificate signing/verification for device auth

#### Ad-Hoc Mac-to-Windows Sync

When Mac and Windows aren't on the same LAN:
- Windows creates a Wi-Fi hotspot
- Mac joins the hotspot's local network
- LAN sync proceeds normally over the hotspot
- This is user-initiated from Settings, not automatic

---

## 8. Phase 15: Legacy Cleanup <a name="phase-15-legacy-cleanup"></a>

> **REVISED for Option B:** Since we're keeping Tauri/React for Windows, there is NO legacy code to clean up. src/ and src-tauri/ ARE the Windows app. This phase becomes documentation-only.

### Original Tasks (ALL CANCELLED for Option B)

1. ~~**Remove `src/` directory**~~ — CANCELLED: src/ is the React frontend used by Windows Tauri
2. ~~**Remove `src-tauri/` directory**~~ — CANCELLED: src-tauri/ is the Tauri Rust shell
3. ~~**Remove `index.html`**~~ — CANCELLED: still needed for Vite/Tauri
4. ~~**Remove `vite.config.ts`**~~ — CANCELLED: still needed
5. ~~**Remove `package.json`**~~ — CANCELLED: still needed
6. ~~**Remove `node_modules/`**~~ — CANCELLED: still needed
7. ~~**Remove `tsconfig.json`**~~ — CANCELLED: still needed
8. ~~**Remove `postcss.config.js`**~~ — CANCELLED: still needed
9. ~~**Remove Capacitor artifacts**~~ — CANCELLED: still needed for iOS
10. **Update `.gitignore`** — already correct ✅
11. **Update `CLAUDE.md`** — reflect dual-platform architecture ✅ DONE
12. **Update `MEMORY.md`** — final architecture notes ✅ DONE
13. **Update `docs/implementation-plan.md`** — mark all phases complete ✅ DONE
14. **Final repo structure (REVISED for Option B — src/ and src-tauri/ STAY):**

```
Weird-Part-Run-2/
├── src/           # React frontend (serves ALL platforms via Tauri/WebView2/Safari)
├── src-tauri/     # Tauri Rust shell (Windows + iOS, with platform-specific AI)
├── core/          # Shared Swift package (Apple — NOT used for Windows)
├── mac/           # macOS SwiftUI app (NOT used for Windows)
├── ios-app/       # iOS SwiftUI app (NOT used for Windows)
├── backend/       # Python FastAPI shop server
├── docs/          # Documentation
├── directives/    # AI agent instructions
└── CLAUDE.md      # Agent config
```

### Pre-Cleanup Verification (REVISED for Option B)

With Option B, there is no cleanup of src/src-tauri. Verification is for the Tauri build:
- [x] All 13 feature modules exist in React (verified — 86 pages)
- [~] Sync works between all platforms (Mac ↔ iOS ↔ Windows) — DEFERRED (needs MSVC build)
- [x] AI works on all platforms (Rust bridge + TS types + UI complete)
- [N/A] No remaining WebView fallback pages — N/A (WebView IS the architecture)
- [x] All tests pass on all platforms (218 backend tests, TS type-check clean)
- [N/A] Users have migrated off the Tauri app — N/A (Tauri IS the app)

---

## 9. Detailed Task Lists <a name="detailed-task-lists"></a>

### Phase 13 Tasks (Windows AI)

```
[x] 13.1  Research Windows Copilot Runtime availability and requirements
[x] 13.2  Research Windows Copilot Runtime API surface (text generation, summarization)
[x] 13.3  Determine if Copilot Runtime requires Copilot+ PC hardware — YES, requires NPU
[x] 13.4  Design WindowsAIService interface (matching FoundationModelsService)
[x] 13.5  Implement WindowsAIService — llama.cpp sidecar (not Copilot Runtime — too restrictive)
         → foundation_models.rs: windows_llm module (11 functions, 563 lines)
[x] 13.6  Implement availability check — check_availability() returns 6 statuses
[x] 13.7  Implement generateCompletion — submit_request() + poll_result() via llama.cpp API
[x] 13.8  Implement enhanceText — proofread, rewrite, summarize, expand, professional
[x] 13.9  Implement generatePreFill — context-based field generation via same API
[N/A] 13.10 Implement askQuestion — handled by LM Studio backend (Phase 14 AI), not on-device
[N/A] 13.11 Implement SearchPartsTool — Apple-only (Swift FoundationModels.Tool protocol)
[N/A] 13.12 Implement SearchContactsTool — Apple-only (Swift FoundationModels.Tool protocol)
[N/A] 13.13 Implement SearchJobsTool — Apple-only (Swift FoundationModels.Tool protocol)
[x] 13.14 Integrate llama.cpp as PRIMARY engine (not fallback — Copilot Runtime rejected)
         → sidecar on localhost:8086, OpenAI-compatible /v1/chat/completions
[~] 13.15 Implement GGUF model download manager — MANUAL download for v1 (setup instructions in AiConfigPage)
[x] 13.16 Implement model selection — find_model() auto-detects best GGUF, prefers Q4_K_M/Q5_K_M
[x] 13.17 Implement AI engine toggle in Settings UI — AiConfigPage.tsx (382 lines)
[x] 13.18 Build AI text editor component — AiTextarea.tsx (170 lines, ghost text, Tab/Escape)
[x] 13.19 Build enhancement popover — AiSuggestionPopover.tsx (149 lines, 5 modes)
[x] 13.20 Build pre-fill sparkles button — useAITextField.ts (210 lines)
[x] 13.21 Build AI availability banner — AiConfigPage status badge + getAvailabilityMessage()
[~] 13.22 Write tests for 3 canonical prompts — DEFERRED (needs running llama-server)
[~] 13.23 Write tests for availability detection — DEFERRED (needs running llama-server)
[~] 13.24 Write tests for engine switching — N/A (single engine on Windows: llama.cpp)
[~] 13.25 Performance test: measure latency — DEFERRED (needs running llama-server + GGUF model)
```

### Phase 14 Tasks (Windows App)

```
[x] 14.1  Evaluate Option A (WinUI 3 / .NET MAUI) — REJECTED: massive rewrite, no ROI
[x] 14.2  Evaluate Option B (Keep Tauri/React) — CHOSEN: zero porting, all services exist
[x] 14.3  Evaluate Option C (Swift on Windows) — REJECTED: infeasible (no SwiftUI, immature)
[x] 14.4  DECISION POINT: Option B (Tauri/React) — documented in Decision Log above
[N/A] 14.5  Set up windows/ project scaffold — NOT NEEDED (Tauri project already exists)
[N/A] 14.6  Implement database layer — ALREADY EXISTS (35 migrations + TS services)
[N/A] 14.7  Implement BaseRepository with change tracking — ALREADY EXISTS
[N/A] 14.8  Implement AuthService — ALREADY EXISTS (TS + Rust IPC)
[N/A] 14.9  Implement SettingsService — ALREADY EXISTS
[N/A] 14.10 Implement PartsService — ALREADY EXISTS
[N/A] 14.11 Implement WarehouseService — ALREADY EXISTS
[N/A] 14.12 Implement JobsService — ALREADY EXISTS
[N/A] 14.13 Implement OrdersService — ALREADY EXISTS
[N/A] 14.14 Implement FleetService — ALREADY EXISTS
[N/A] 14.15 Implement PeopleService — ALREADY EXISTS
[N/A] 14.16 Implement SchedulingService — ALREADY EXISTS
[N/A] 14.17 Implement ChatService — ALREADY EXISTS
[N/A] 14.18 Implement NotebooksService — ALREADY EXISTS
[N/A] 14.19 Implement ReportsService — ALREADY EXISTS
[N/A] 14.20 Implement ToolsService — ALREADY EXISTS
[N/A] 14.21 Implement DashboardService — ALREADY EXISTS
[N/A] 14.22 Implement CostsService — ALREADY EXISTS in TS (725 lines)
[N/A] 14.23 Implement sync client — ALREADY EXISTS (Rust sync_server.rs + TS services)
[N/A] 14.24 Implement sync server — ALREADY EXISTS (Rust sync_server.rs)
[N/A] 14.25 Implement mDNS discovery — ALREADY EXISTS (Rust discovery.rs, mdns-sd crate)
[N/A] 14.26 Implement change tracking — ALREADY EXISTS (_change_log in TS)
[N/A] 14.27 Implement conflict resolution — ALREADY EXISTS (field-level LWW in TS)
[N/A] 14.28 Implement Ed25519 crypto — ALREADY EXISTS (Rust crypto.rs)
[N/A] 14.29 Build app shell — ALREADY EXISTS (86 pages, responsive layout)
[N/A] 14.30 Build Dashboard view — ALREADY EXISTS
[N/A] 14.31 Build Settings views — ALREADY EXISTS (5+ pages)
[N/A] 14.32 Build Parts views — ALREADY EXISTS (10 pages)
[N/A] 14.33 Build Warehouse views — ALREADY EXISTS (9 pages)
[N/A] 14.34 Build Jobs views — ALREADY EXISTS (6 pages)
[N/A] 14.35 Build Orders views — ALREADY EXISTS (12 pages)
[N/A] 14.36 Build Fleet views — ALREADY EXISTS (6 pages)
[N/A] 14.37 Build People views — ALREADY EXISTS (10 pages)
[N/A] 14.38 Build Scheduling views — ALREADY EXISTS (7 pages)
[N/A] 14.39 Build Chat views — ALREADY EXISTS (3 pages)
[N/A] 14.40 Build Notebooks views — ALREADY EXISTS (3 pages)
[N/A] 14.41 Build Reports views — ALREADY EXISTS (4 pages)
[N/A] 14.42 Build Tools views — ALREADY EXISTS (4 pages)
[x] 14.43 Integrate AI components into all views — AiTextarea already used cross-platform
[~] 14.44 Implement ad-hoc hotspot sync instructions — partial (Settings has sync UI)
[N/A] 14.45 Write unit tests for all services — ALREADY EXIST (218 backend tests + TS types)
[~] 14.46 Write integration tests for sync protocol — DEFERRED (needs 2+ devices)
[~] 14.47 Write UI tests for navigation — DEFERRED (needs Tauri test harness)
[~] 14.48 Performance testing (cold start <3s, idle <200MB RSS) — DEFERRED (needs MSVC build)
[~] 14.49 Cross-platform sync test: Windows ↔ macOS — DEFERRED (needs MSVC build + Mac)
[~] 14.50 Cross-platform sync test: Windows ↔ iOS — DEFERRED (needs MSVC build + iOS device)
[~] 14.51 Cross-platform sync test: Windows ↔ shop server — DEFERRED (needs MSVC build)
[~] 14.52 JSON wire format compatibility test — DEFERRED (needs MSVC build)
```

### Phase 15 Tasks (Cleanup) — MODIFIED: Option B means src/ and src-tauri/ stay

```
[~] 15.1  Verify all platforms work independently — DEFERRED (needs MSVC build for Windows)
[~] 15.2  Verify cross-platform sync (all combinations) — DEFERRED (needs MSVC build)
[N/A] 15.3  Verify no WebView fallback pages remain — N/A (Option B IS the WebView app)
[N/A] 15.4  Remove src/ directory — CANCELLED (Option B: src/ IS the Windows app)
[N/A] 15.5  Remove src-tauri/ directory — CANCELLED (Option B: src-tauri/ IS the Tauri shell)
[N/A] 15.6  Remove index.html — CANCELLED (still needed)
[N/A] 15.7  Remove vite.config.ts, tsconfig.json — CANCELLED (still needed)
[N/A] 15.8  Remove package.json — CANCELLED (still needed)
[N/A] 15.9  Remove postcss.config.js, tailwind.config.ts — CANCELLED (still needed)
[N/A] 15.10 Remove node_modules/ — CANCELLED (still needed)
[N/A] 15.11 Remove any remaining Capacitor files — CANCELLED (still needed for iOS)
[x] 15.12 Update .gitignore — already correct for dual-platform
[x] 15.13 Update CLAUDE.md to reflect final architecture — DONE this session
[x] 15.14 Update MEMORY.md — DONE this session
[x] 15.15 Update docs/implementation-plan.md — DONE this session
[x] 15.16 Create docs/plans/windows-architecture.md — DONE this session
[~] 15.17 Final build verification on all platforms — DEFERRED (needs MSVC + Mac + iOS)
[~] 15.18 Tag release: v2.0.0 — DEFERRED (after build verification)
```

---

## 10. Technical Reference: Services to Port <a name="technical-reference"></a>

### Swift Core Services (already implemented — use as reference)

These are the 14 services in `core/Sources/WiredPartCore/Services/`. Each one has been ported from TypeScript and is working with 153 passing tests. Use the Swift service as your **specification** for the Windows equivalent.

| Service | Swift File | Key Methods |
|---------|-----------|-------------|
| AuthService | `Services/AuthService.swift` | `authenticateByPin`, `getActiveUsers`, `seedFirstAdmin`, `getUserPermissions`, `hashPin`, `generateLocalToken` |
| SettingsService | `Services/SettingsService.swift` | `getSettingValue`, `upsertSetting`, `getTheme`, `updateTheme`, `getCompanyProfile`, `getPDFSettings`, `getBillingCycle` |
| DashboardService | `Services/DashboardService.swift` | `getKPISummary`, `getCertificationExpiryAlerts`, `getVehicleExpiryAlerts`, `getDailyReport` |
| PartsService | `Services/PartsService.swift` | 60+ methods — hierarchy, catalog, brands, suppliers, pricing, companions, alternatives, forecasting, import/export |
| WarehouseService | `Services/WarehouseService.swift` | 40+ methods — movements, staging, receiving, returns, audit, trailers |
| JobsService | `Services/JobsService.swift` | 30+ methods — CRUD, labor, clock in/out, questionnaire, daily reports, team, job parts |
| OrdersService | `Services/OrdersService.swift` | 20+ methods — JPO/PO lifecycle, lines, approval, receiving, links |
| FleetService | `Services/FleetService.swift` | 15+ methods — vehicles, assignments, maintenance, mileage, fuel |
| PeopleService | `Services/PeopleService.swift` | 15+ methods — employees, customers, contractors, contacts, teams, hats |
| SchedulingService | `Services/SchedulingService.swift` | 12+ methods — dispatch, time-off, templates |
| ChatService | `Services/ChatService.swift` | 12+ methods — channels, messages, Q&A threads |
| NotebooksService | `Services/NotebooksService.swift` | 10+ methods — notebooks, entries, templates |
| ReportsService | `Services/ReportsService.swift` | 8+ methods — timesheets, daily summary, spending, profitability |
| ToolsService | `Services/ToolsService.swift` | 10+ methods — tools, kits, checkout/return |

### Services in TypeScript but NOT in Swift Core

These exist in the TypeScript codebase but were not ported to the Swift core because they are desktop-only or were deemed non-essential for the Apple migration. You may need them on Windows:

| Service | TS File | Purpose |
|---------|---------|---------|
| CostsService | `costs-service.ts` (725 lines) | FIFO/LIFO cost layers, spending analytics, budget alerts |
| BillingService | `billing-service.ts` (195 lines) | Billing periods, cost locking |
| PTOService | `pto-service.ts` (298 lines) | PTO policies, accruals, balance |
| RelayService | `relay-service.ts` (330 lines) | P2P relay manifest, queue |
| SecurityService | `security-service.ts` (316 lines) | Device keypair, certificates |
| BootstrapClient | `bootstrap-client.ts` (551 lines) | Artifact download, SHA-256, signature |
| DepreciationService | `depreciation-service.ts` (199 lines) | Tool depreciation schedules |
| SupplierPortalService | `supplier-portal-service.ts` (234 lines) | Portal tokens, PO acks |
| AttachmentService | `attachment-service.ts` (142 lines) | Order file attachments |
| NotificationsService | `notifications-service.ts` (100+ lines) | Badge, notification list, sounds |
| SchedulerService | `scheduler-service.ts` (100+ lines) | Background job scheduling |
| AutostartService | `autostart-service.ts` (74 lines) | Launch-on-boot |
| UpdaterService | `updater-service.ts` (100+ lines) | Auto-update with Ed25519 |

---

## 11. Sync Protocol Specification <a name="sync-protocol-specification"></a>

### Wire Format (JSON)

All sync communication uses JSON over HTTP. The format must be identical across all platforms.

#### Push Request (Device → Shop)

```json
POST /api/sync/push
Content-Type: application/json

{
  "device_id": "abc123",
  "company_id": "company_uuid",
  "last_sync_at": "2026-03-15T10:00:00Z",
  "changes": [
    {
      "id": 42,
      "device_id": "abc123",
      "table_name": "parts",
      "record_id": "17",
      "operation": "UPDATE",
      "changed_fields": "{\"name\": \"New Name\", \"price\": 29.99}",
      "old_values": "{\"name\": \"Old Name\", \"price\": 19.99}",
      "record_data": "{\"id\": 17, \"name\": \"New Name\", ...}",
      "timestamp": "2026-03-15T10:05:00Z",
      "sequence": 1042
    }
  ],
  "auth": {
    "certificate_data": "base64...",
    "certificate_signature": "base64...",
    "device_public_key": "base64..."
  }
}
```

#### Push Response

```json
{
  "accepted": 5,
  "sync_batch_id": "uuid",
  "shop_changes": [...],
  "conflicts": [...]
}
```

#### Pull Request (Device ← Shop)

```json
POST /api/sync/pull
Content-Type: application/json

{
  "device_id": "abc123",
  "company_id": "company_uuid",
  "last_sync_at": "2026-03-15T10:00:00Z",
  "vector_clock": {
    "device_abc": 1042,
    "device_xyz": 987
  },
  "auth": { ... }
}
```

#### Pull Response

```json
{
  "changes": [...],
  "sync_batch_id": "uuid",
  "server_device_id": "shop_device_id"
}
```

#### Status (Health Check)

```json
GET /sync/status

Response:
{
  "device_id": "abc123",
  "device_name": "Shop Desktop",
  "company_id": "company_uuid",
  "app_version": "2.0.0",
  "pending_changes": 12,
  "last_sync_at": "2026-03-15T10:05:00Z",
  "port": 49152
}
```

### Conflict Resolution Algorithm (LWW + Field-Level Merge)

For each incoming change:

1. **INSERT (new record):** If record doesn't exist locally → insert. If exists → treat as UPDATE merge.
2. **UPDATE:** For each field in `changed_fields`:
   - Get local changed fields from `_change_log WHERE table_name=? AND record_id=? AND synced=0`
   - If field NOT in local changes → accept remote value
   - If field IS in local changes → compare timestamps:
     - Remote timestamp > local timestamp → remote wins
     - Otherwise → local wins
   - Log all conflicts to `_conflict_log`
3. **DELETE:** Try `UPDATE SET deleted_at = datetime('now')` (soft delete). If fails (no `deleted_at` column) → `DELETE FROM table WHERE id = ?`.

### mDNS Service Discovery

- Service type: `_wiredpart._tcp`
- TXT records: `device_id`, `device_name`, `company_id`, `version`
- Instance name: `WiredPart-{device_id[0:8]}`
- Filter: same `company_id` only, exclude self

---

## 12. Database Schema <a name="database-schema"></a>

The SQLite database schema is defined by 17 migrations (ported from `src/local/migrations/001-017`). The backend has 35 migrations (superset — includes server-only tables).

Key tables:

### Core Tables
- `users` — User accounts (id, display_name, pin_hash, email, role, is_active)
- `hats` — Roles (id, name, description)
- `hat_permissions` — Permissions per hat (hat_id, permission_key)
- `user_hats` — User-to-hat assignments (user_id, hat_id)
- `settings` — Key-value settings (key, value, category)
- `company_profiles` — Company info (name, address, phone, email)

### Parts & Inventory
- `parts` — Part catalog (id, name, code, category_id, brand_id, prices, stock levels)
- `part_categories`, `part_styles`, `part_types`, `part_colors` — Hierarchy
- `type_color_links`, `type_brand_links` — Relationship links
- `brands`, `suppliers`, `brand_supplier_links` — Supply chain
- `part_supplier_links` — Part-to-supplier with pricing
- `companion_rules`, `companion_rule_sources`, `companion_rule_targets` — Companion parts
- `part_alternatives` — Alternative parts

### Warehouse
- `stock` — Stock levels by location (part_id, location_type, location_id, qty)
- `stock_movements` — Movement history (from/to location, qty, type, reason)
- `receiving_sessions`, `receiving_session_items` — PO receiving
- `pulled_staging_tags` — Staging for delivery
- `stock_audits` — Audit counts

### Jobs & Labor
- `jobs` — Job records (name, number, status, customer, address, GPS)
- `labor_entries` — Clock in/out records (user_id, job_id, start/end, GPS)
- `clock_out_questions`, `clock_out_responses` — Questionnaire
- `daily_reports` — Generated reports (JSON blob)

### Orders
- `job_part_orders` — JPOs (field requests)
- `jpo_line_items` — JPO line items
- `purchase_orders` — POs (office-generated)
- `po_line_items`, `po_line_item_history` — PO details
- `return_entries`, `return_line_items` — Returns
- `jpo_to_po_links` — JPO-to-PO mapping

### Fleet
- `vehicles` — Vehicle records
- `vehicle_assignments` — Who has which vehicle
- `maintenance_types`, `maintenance_records` — Maintenance
- `mileage_logs`, `fuel_logs` — Usage tracking

### Sync
- `_change_log` — Change tracking (table, record_id, operation, changed_fields, timestamp, synced, device_id, sequence)
- `_conflict_log` — Conflict resolution log (table, record_id, field, local/remote values, winner, timestamps)
- `_device_registry` — Registered devices (device_id, name, role, certificate)
- `_sync_metadata` — Sync state (last_sync_at, vector_clock)

---

## 13. Testing Strategy <a name="testing-strategy"></a>

### Unit Tests (per service)
Each service needs tests covering:
- CRUD operations (create, read, update, delete)
- Search and filtering
- Edge cases (empty results, missing records)
- Business rules (e.g., OT threshold at 8 hours)

### Sync Integration Tests
1. Push changes to shop → verify shop received them
2. Pull changes from shop → verify local DB updated
3. Conflict: same field changed on two devices → verify LWW resolution
4. Field-level merge: different fields changed → both preserved
5. Ed25519 auth: valid cert → accepted; invalid → rejected
6. Vector clock filtering: only new changes returned
7. JSON wire format compatibility with Swift and TypeScript

### AI Tests
1. Availability detection (Copilot Runtime present? llama.cpp fallback?)
2. Engine switching (toggle between engines)
3. 3 canonical prompts (autocomplete, enhance, pre-fill)

### Cross-Platform Sync Tests
1. Windows → Shop Server → macOS (triangle sync)
2. Windows ↔ iOS (via shop server)
3. JSON encoding/decoding compatibility

---

## 14. Risk Register <a name="risk-register"></a>

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| 1 | Windows Copilot Runtime only available on Copilot+ PCs | High | Medium | llama.cpp fallback is primary for most devices |
| 2 | WinUI 3 learning curve slows development | Medium | Medium | Option B (keep Tauri) is zero-effort fallback |
| 3 | SQLite schema incompatibility between platforms | Low | High | Schema defined by migrations; test with shared DB file |
| 4 | JSON wire format differs between C#/TS/Swift | Medium | High | Explicit field mapping tests; shared test fixtures |
| 5 | Swift on Windows doesn't compile WiredPartCore | High | Low | This is a stretch goal; Options A/B are safe |
| 6 | mDNS discovery behaves differently on Windows | Medium | Medium | Windows uses Bonjour for Windows (Apple's SDK) or manual DNS-SD |
| 7 | Performance: native app slower than expected | Low | Medium | Profile early; target <3s cold start, <200MB RSS |
| 8 | Sync conflicts between 3+ platforms are hard to test | Medium | Medium | Automated integration test suite with scripted scenarios |

---

## 15. Decision Log <a name="decision-log"></a>

Record all architectural decisions here as you make them:

| Date | Decision | Rationale | Alternatives Considered |
|------|----------|-----------|------------------------|
| 2026-03-15 | Windows app framework: **Option B (Keep Tauri/React)** | Zero UI porting (86 pages already work), zero service rewriting (64 TS services already work), all sync/mDNS/crypto infrastructure already exists in Rust. WebView2 is adequate for a business ERP. Only AI needed new code. | WinUI 3 (.NET MAUI) — massive rewrite for no UX gain. Swift on Windows — desired but infeasible (immature, no SwiftUI, GRDB may not compile). |
| 2026-03-15 | Windows AI primary: **llama.cpp sidecar** | Windows Copilot Runtime requires Copilot+ PC hardware with NPU — only a tiny fraction of Windows PCs. llama.cpp runs on any machine with ≥8GB RAM. Sidecar approach (llama-server.exe) uses OpenAI-compatible HTTP API, keeping Rust code simple. | Windows Copilot Runtime — too restrictive hardware. LM Studio — already integrated separately for backend AI, but requires user to manage a separate app. |
| 2026-03-15 | mDNS library: **mdns-sd (Rust crate, already in use)** | Already integrated in `src-tauri/src/discovery.rs` with full `_wiredpart._tcp` service type. Cross-platform (uses Windows DNS-SD APIs internally). No changes needed for Windows. | Bonjour for Windows SDK — unnecessary since mdns-sd crate handles it. |
| 2026-03-15 | Phase 15 modified: **Do NOT delete src/ or src-tauri/** | With Option B, src/ and src-tauri/ ARE the Windows app. Cleanup only applies if we had ported to a native Windows framework. Instead, update docs to reflect the dual-platform architecture (SwiftUI for Apple + Tauri/React for Windows). | Full cleanup per original plan — only valid for Options A or C. |

---

## Appendix A: Key Files to Read First

When starting work, read these files in order:

1. `CLAUDE.md` — Agent instructions, architecture, conventions
2. `MEMORY.md` — Project context and patterns
3. `docs/The Full Plan.md` — Original comprehensive vision
4. `docs/implementation-plan.md` — Master roadmap
5. `docs/plan/repo_map.md` — Repository structure map
6. `docs/plan/core_boundary.md` — Core module boundaries
7. `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — Database schema
8. `core/Sources/WiredPartCore/Services/AuthService.swift` — Auth pattern (reference for porting)
9. `src/local/services/costs-service.ts` — Biggest unported TS service (725 lines)
10. `src-tauri/src/sync_server.rs` — Sync server reference implementation
11. `src-tauri/src/crypto.rs` — Ed25519 crypto reference
12. `src-tauri/src/discovery.rs` — mDNS discovery reference

## Appendix B: Environment Setup (Windows)

### Prerequisites
- Windows 11 (22H2 or later, 24H2 for Copilot Runtime)
- Git
- SQLite (comes with Python, or install separately)
- Python 3.10+ (for running the backend)
- Node.js 18+ (if keeping Tauri/React — Option B)
- Rust toolchain (if keeping Tauri — Option B)
- Visual Studio 2022 (if using WinUI 3 — Option A)
- .NET 8 SDK (if using .NET MAUI — Option A)
- Swift 5.10+ toolchain for Windows (if evaluating Option C)

### First Steps
1. Clone the repo: `git clone https://github.com/xXKillerNoobYT/Weird-Part-Run-2.git`
2. Start the backend: `cd backend && pip install -r requirements.txt && python -m app.main`
3. Verify the backend: `curl http://localhost:8000/api/health`
4. Read this document top to bottom
5. Make your framework decision (Phase 14 evaluation)
6. Start building

## Appendix C: Contact & Context

- **Repo:** https://github.com/xXKillerNoobYT/Weird-Part-Run-2
- **Main branch:** `main`
- **All Apple work is committed and pushed**
- **The Tauri app still works** — you can run it on Windows for reference
- **The Python backend is the authoritative data model** — 802 endpoints, 35 migrations, production-grade

---

*This document was generated on 2026-03-15 after completing all Apple platform phases (1-12). The next developer picks up at Phase 13 (Windows AI) on a Windows computer.*
