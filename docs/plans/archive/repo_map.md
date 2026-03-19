# Repository Map — Current to Target

> Maps every significant current file/directory to its target location in the native SwiftUI architecture.

## Current Repo Layout

```
/Users/IA/GitHub/Weird-Part-Run-2/
├── CLAUDE.md, MEMORY.md, README.md       # Project docs (kept)
├── package.json, vite.config.ts           # Frontend build (Phase 15: removed)
├── index.html                             # Vite entry (Phase 15: removed)
├── install.sh, install.bat, launch.sh     # Setup scripts (updated Phase 15)
│
├── src/                                   # React frontend — 180+ files
│   ├── main.tsx, App.tsx, index.css
│   ├── api/                               # HTTP API clients (~20 files)
│   ├── components/                        # Shared UI components
│   │   ├── layout/ (AppShell, Sidebar)
│   │   └── ui/ (Button, Card, Modal, AiTextarea, etc.)
│   ├── features/                          # 14 feature modules
│   │   ├── chat/, dashboard/, jobs/, notebooks/, office/
│   │   ├── orders/, parts/, people/, reports/
│   │   ├── scheduling/, settings/, tools/, trucks/, warehouse/
│   ├── hooks/                             # React hooks (useAITextField)
│   ├── lib/                               # Utilities, constants, types
│   │   ├── environment.ts                 # Platform detection
│   │   ├── foundation-models.ts           # AI service
│   │   └── types/                         # TypeScript interfaces
│   ├── local/                             # Tauri local data layer
│   │   ├── db.ts, db-config.ts            # SQLite connection
│   │   ├── migrations/ (001–017)          # Schema migrations
│   │   ├── repos/base-repo.ts             # Base CRUD
│   │   ├── services/ (36+ files)          # Domain services
│   │   ├── change-tracker.ts              # Change log tracking
│   │   ├── conflict-resolver.ts           # LWW merge
│   │   ├── sync-engine.ts                 # Sync orchestrator
│   │   └── peer-manager.ts               # Peer connections
│   └── stores/                            # Zustand stores
│
├── src-tauri/                             # Tauri Rust shell
│   ├── Cargo.toml, build.rs
│   ├── tauri.conf.json
│   ├── src/
│   │   ├── main.rs, lib.rs               # Entry + plugin registration
│   │   ├── commands.rs                    # LAN sync IPC commands
│   │   ├── discovery.rs                   # mDNS Bonjour
│   │   ├── sync_server.rs                 # Axum HTTP sync server
│   │   ├── multipeer.rs                   # Multipeer FFI bindings
│   │   ├── foundation_models.rs           # Foundation Models FFI
│   │   └── crypto.rs                      # Ed25519 verification
│   ├── swift/
│   │   └── FoundationModelsBridge.swift   # Swift @_cdecl bridge
│   ├── objc/
│   │   ├── MultipeerBridge.h              # Multipeer C FFI header
│   │   └── MultipeerBridge.m              # Multipeer ObjC implementation
│   ├── capabilities/                      # Tauri permission grants
│   └── gen/apple/                         # Generated Xcode project
│
├── backend/                               # Python FastAPI (unchanged)
├── docs/                                  # Documentation
│   ├── plans/                             # Phase plans (existing)
│   └── plan/                              # THIS migration plan
├── tests/                                 # Playwright tests (legacy)
└── Wierd Parts.xcworkspace/               # Xcode workspace
```

## Target Repo Layout

```
/Users/IA/GitHub/Weird-Part-Run-2/
├── CLAUDE.md, MEMORY.md, README.md        # Updated for new architecture
│
├── core/                                   # WiredPartCore Swift Package
│   ├── Package.swift
│   ├── Sources/WiredPartCore/
│   │   ├── Database/
│   │   │   ├── AppDatabase.swift           ← src/local/db.ts + db-config.ts
│   │   │   ├── AppDatabase+Migrations.swift ← src/local/migrations/*
│   │   │   └── BaseRepository.swift        ← src/local/repos/base-repo.ts
│   │   ├── Models/
│   │   │   ├── Foundation/                 ← TS interfaces (User, Hat, Device, etc.)
│   │   │   ├── Parts/                      ← TS interfaces (Part, Category, etc.)
│   │   │   ├── Jobs/                       ← TS interfaces (Job, LaborEntry, etc.)
│   │   │   ├── Orders/                     ← TS interfaces (PO, JPO, etc.)
│   │   │   ├── Fleet/                      ← TS interfaces (Vehicle, Tool, etc.)
│   │   │   ├── People/                     ← TS interfaces (Employee, etc.)
│   │   │   ├── Scheduling/                 ← TS interfaces (Dispatch, etc.)
│   │   │   ├── Chat/                       ← TS interfaces (Message, etc.)
│   │   │   └── Sync/                       ← TS interfaces (ChangeLogEntry, etc.)
│   │   ├── Services/
│   │   │   ├── AuthService.swift           ← src/local/services/auth-service.ts
│   │   │   ├── SettingsService.swift       ← src/local/services/settings-service.ts
│   │   │   ├── DashboardService.swift      ← src/local/services/dashboard-service.ts
│   │   │   ├── JobService.swift            ← src/local/services/job-service.ts
│   │   │   ├── LaborService.swift          ← src/local/services/labor-service.ts
│   │   │   ├── OrderService.swift          ← src/local/services/order-service.ts
│   │   │   ├── WarehouseService.swift      ← src/local/services/warehouse-service.ts
│   │   │   ├── MovementService.swift       ← src/local/services/movement-service.ts
│   │   │   ├── FleetService.swift          ← src/local/services/fleet-service.ts
│   │   │   ├── ToolService.swift           ← src/local/services/tool-service.ts
│   │   │   ├── ChatService.swift           ← src/local/services/chat-service.ts
│   │   │   ├── NotebookService.swift       ← src/local/services/notebook-service.ts
│   │   │   ├── SchedulingService.swift     ← src/local/services/scheduling-service.ts
│   │   │   ├── ContactsService.swift       ← src/local/services/contacts-service.ts
│   │   │   ├── ReportService.swift         ← src/local/services/report-service.ts
│   │   │   ├── CostsService.swift          ← src/local/services/costs-service.ts
│   │   │   ├── SecurityService.swift       ← src/local/services/security-service.ts
│   │   │   ├── Parts/                      ← src/local/services/parts/*.ts
│   │   │   └── People/                     ← src/local/services/people/*.ts
│   │   ├── Sync/
│   │   │   ├── ChangeTracker.swift         ← src/local/change-tracker.ts
│   │   │   ├── ConflictResolver.swift      ← src/local/conflict-resolver.ts
│   │   │   ├── SyncEngine.swift            ← src/local/sync-engine.ts
│   │   │   ├── PeerManager.swift           ← src/local/peer-manager.ts
│   │   │   ├── LanSyncServer.swift         ← src-tauri/src/sync_server.rs
│   │   │   ├── PeerDiscovery.swift         ← src-tauri/src/discovery.rs
│   │   │   └── MultipeerManager.swift      ← src-tauri/objc/MultipeerBridge.m + multipeer.rs
│   │   ├── Crypto/
│   │   │   └── SyncCrypto.swift            ← src-tauri/src/crypto.rs
│   │   └── AI/
│   │       ├── FoundationModelsService.swift ← FoundationModelsBridge.swift + foundation_models.rs
│   │       └── LlamaCppService.swift       ← NEW (llama.cpp fallback)
│   └── Tests/WiredPartCoreTests/
│
├── mac/                                    # SwiftUI macOS App
│   ├── WiredPartMac.xcodeproj
│   └── WiredPartMac/
│       ├── App/
│       │   ├── WiredPartMacApp.swift       ← src/main.tsx
│       │   └── AppCore.swift               ← src/stores/ + init logic
│       ├── Navigation/
│       │   ├── SidebarView.swift           ← src/components/layout/Sidebar.tsx
│       │   ├── NavigationRouter.swift      ← src/App.tsx routes
│       │   └── AppDestination.swift        ← src/lib/navigation.ts
│       ├── Features/
│       │   ├── Dashboard/                  ← src/features/dashboard/
│       │   ├── Settings/                   ← src/features/settings/
│       │   ├── Parts/                      ← src/features/parts/
│       │   ├── Warehouse/                  ← src/features/warehouse/
│       │   ├── Jobs/                       ← src/features/jobs/
│       │   ├── Orders/                     ← src/features/orders/
│       │   ├── People/                     ← src/features/people/
│       │   ├── Scheduling/                 ← src/features/scheduling/
│       │   ├── Fleet/                      ← src/features/trucks/
│       │   ├── Tools/                      ← src/features/tools/
│       │   ├── Chat/                       ← src/features/chat/
│       │   ├── Notebooks/                  ← src/features/notebooks/
│       │   ├── Reports/                    ← src/features/reports/
│       │   └── Office/                     ← src/features/office/
│       ├── WebFallback/
│       │   └── WebFallbackView.swift       ← loads React dist for unported pages
│       ├── Theme/
│       │   └── ThemeManager.swift          ← src/stores/theme-store.ts
│       └── Auth/
│           ├── LoginView.swift             ← src/components/auth/
│           └── AuthManager.swift           ← src/stores/auth-store.ts
│
├── ios/                                    # SwiftUI iOS App
│   ├── WiredPartIOS.xcodeproj
│   └── WiredPartIOS/
│       ├── App/
│       ├── Navigation/ (tab bar)
│       └── Features/ (iOS-adapted views)
│
├── windows/                                # Windows app (Phase 14)
│
├── backend/                                # Python FastAPI (unchanged)
├── docs/
│   ├── plans/                              # Existing phase plans
│   └── plan/                               # This migration plan
└── tests/                                  # Updated for Swift tests
```

## Files to Remove (Phase 15)

| File/Directory | Reason |
|----------------|--------|
| `src/` | Entire React frontend — replaced by SwiftUI |
| `src-tauri/` | Entire Tauri Rust shell — replaced by native Swift |
| `index.html` | Vite entry point — no longer needed |
| `package.json`, `package-lock.json` | npm deps — no longer needed |
| `vite.config.ts` | Vite build config — no longer needed |
| `tsconfig*.json` | TypeScript config — no longer needed |
| `eslint.config.js` | ESLint config — no longer needed |
| `capacitor.config.ts` | Legacy Capacitor — already superseded |
| `node_modules/` | npm packages — no longer needed |
| `dist/` | Built frontend — no longer needed |
| `ios/` (Capacitor) | Legacy Capacitor iOS — replaced by `ios/` SwiftUI |
| `Wierd Parts.xcworkspace/` | Old workspace — replaced by new project files |
| `patches/` | patch-package patches — no longer needed |

## Files to Keep (Unchanged)

| File/Directory | Reason |
|----------------|--------|
| `backend/` | Python FastAPI shop server — still serves LAN browsers |
| `docs/` | All documentation preserved |
| `CLAUDE.md` | Agent instructions (updated for new architecture) |
| `MEMORY.md` | Project context (updated) |
| `.env` | Environment variables |
| `.git/` | Git history preserved |
