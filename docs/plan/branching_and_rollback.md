# Branching and Rollback Plan

> Branch naming, commit conventions, staging order, and rollback procedures for the native SwiftUI migration.

---

## Branch Strategy

```
main ─────────────────────────────────────────────────────────→
  │                                                            │
  ├── dev ────────────────────────────────────────────────────→│
  │     │                                                      │
  │     ├── phase/1-swift-core ──────────────┐                 │
  │     │     ├── feat/1.1-package-setup     │                 │
  │     │     ├── feat/1.2-migrations        │                 │
  │     │     ├── feat/1.3-models            │                 │
  │     │     ├── feat/1.4-base-repo         │                 │
  │     │     ├── feat/1.5-auth              │                 │
  │     │     ├── feat/1.6-settings          │                 │
  │     │     └── feat/1.7-tests             │                 │
  │     │                         merge → dev                  │
  │     │                                                      │
  │     ├── phase/2-sync-engine ─────────────┐                 │
  │     │     ├── feat/2.1-conflict-resolver │                 │
  │     │     ├── feat/2.2-change-tracker    │                 │
  │     │     ├── feat/2.3-crypto            │                 │
  │     │     ├── feat/2.4-lan-sync-server   │                 │
  │     │     ├── feat/2.5-peer-discovery    │                 │
  │     │     ├── feat/2.6-multipeer         │                 │
  │     │     ├── feat/2.7-sync-engine       │                 │
  │     │     └── feat/2.9-integration-tests │                 │
  │     │                         merge → dev                  │
  │     │                                                      │
  │     ├── phase/3-mac-shell ───────────────┐                 │
  │     ├── phase/4-dashboard-settings ──────┤                 │
  │     ├── phase/5-parts ───────────────────┤                 │
  │     ├── phase/6-warehouse ───────────────┤                 │
  │     ├── phase/7-jobs ────────────────────┤                 │
  │     ├── phase/8-orders ──────────────────┤                 │
  │     ├── phase/9-people ──────────────────┤                 │
  │     ├── phase/10-scheduling ─────────────┤                 │
  │     ├── phase/11-remaining ──────────────┤                 │
  │     ├── phase/12-ai-apple ───────────────┤                 │
  │     ├── phase/13-ai-windows ─────────────┤                 │
  │     ├── phase/14-windows ────────────────┤                 │
  │     └── phase/15-cleanup ────────────────┘                 │
  │                                            merge → main    │
  └── release/v2.0 ──────────────────────────────────────────→│
```

---

## Branch Naming Convention

| Level | Pattern | Example |
|-------|---------|---------|
| Development | `dev` | `dev` |
| Phase | `phase/<N>-<short-desc>` | `phase/1-swift-core` |
| Feature | `feat/<phase>.<task>-<desc>` | `feat/1.2-migrations` |
| Bugfix | `fix/<phase>-<desc>` | `fix/2-sync-json-format` |
| Release | `release/v<major>.<minor>` | `release/v2.0` |

---

## Commit Message Template

```
<type>: <short summary>

files: <comma-separated paths>
tests: <test file paths>
phase: <phase number>

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Types

| Type | Usage |
|------|-------|
| `feat` | New functionality |
| `port` | Direct port of existing functionality from TS/Rust/ObjC to Swift |
| `test` | Adding or updating tests only |
| `fix` | Bug fix |
| `refactor` | Code restructure without behavior change |
| `docs` | Documentation only |
| `chore` | Build/config changes |
| `delete` | Removing legacy code (Phase 15) |

### Examples

```
port: Port 17 SQLite migrations to GRDB DatabaseMigrator

files: core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift
tests: core/Tests/WiredPartCoreTests/DatabaseTests.swift
phase: 1
```

```
feat: Add macOS sidebar navigation with 14 modules

files: mac/WiredPartMac/Navigation/SidebarView.swift, mac/WiredPartMac/Navigation/AppDestination.swift
tests: mac/WiredPartMacTests/NavigationTests.swift
phase: 3
```

```
delete: Remove Tauri Rust shell and React frontend

files: src-tauri/ (removed), src/ (removed), package.json (removed), vite.config.ts (removed)
tests: verified all swift tests still pass
phase: 15
```

---

## Staging Order

Changes are staged in dependency order:

```
1. core/Package.swift               ← must exist first
2. core/.../Database/               ← models depend on DB
3. core/.../Models/                 ← services depend on models
4. core/.../Sync/ChangeTracker.swift ← repos depend on tracker
5. core/.../Database/BaseRepository.swift ← services depend on repos
6. core/.../Services/               ← app depends on services
7. core/.../Sync/                   ← app shell depends on sync
8. core/.../Crypto/                 ← sync depends on crypto
9. core/Tests/                      ← tests validate core
10. mac/WiredPartMac/App/           ← app entry depends on core
11. mac/WiredPartMac/Navigation/    ← content depends on nav
12. mac/WiredPartMac/WebFallback/   ← fallback for unported
13. mac/WiredPartMac/Auth/          ← must login before features
14. mac/WiredPartMac/Theme/         ← theme applies to features
15. mac/WiredPartMac/Features/      ← feature views (one module at a time)
16. mac/WiredPartMacTests/          ← UI tests for features
17. core/.../AI/                    ← AI after features
18. Phase 15 deletions              ← cleanup last
```

---

## Pre-Merge Checks

Before merging any branch to `dev`:

```bash
# 1. Core package builds and tests pass
cd core && swift build && swift test

# 2. macOS app builds (if mac/ exists)
xcodebuild build -project mac/WiredPartMac.xcodeproj -scheme WiredPartMac -destination 'platform=macOS'

# 3. iOS app builds (if ios/ exists)
xcodebuild build -project ios/WiredPartIOS.xcodeproj -scheme WiredPartIOS -destination 'generic/platform=iOS Simulator'

# 4. Existing Tauri app still works (until Phase 15)
cd src-tauri && cargo check
npm run build

# 5. No external network references in Swift code
grep -r "https://" core/Sources/ mac/ ios/ --include="*.swift" | grep -v "github.com" | grep -v "Package.swift"
# Must return empty (only Package.swift has external URLs)
```

---

## Rollback Procedures

### Rollback a Feature Branch

If a feature branch breaks something:
```bash
git checkout dev
git branch -D feat/X.Y-broken-feature
# The feature was never merged, so dev is clean.
```

### Rollback a Phase

If an entire phase needs reverting after merge to `dev`:
```bash
git checkout dev
git revert --no-commit <first-commit-of-phase>..<last-commit-of-phase>
git commit -m "revert: Roll back phase N due to [reason]"
```

Since all phases are additive (new files in `core/`, `mac/`, `ios/`), reverting simply removes those files. The existing `src/` and `src-tauri/` are untouched.

### Rollback Phase 15 (Critical)

Phase 15 is the only destructive phase — it deletes `src/` and `src-tauri/`. If it needs reverting:

```bash
# Option A: Git revert (preferred)
git revert <phase-15-commit>
# This restores src/ and src-tauri/ from git history

# Option B: Checkout from pre-Phase-15
git checkout <last-commit-before-phase-15> -- src/ src-tauri/ package.json vite.config.ts index.html
git commit -m "revert: Restore Tauri/React for rollback"
```

### Emergency: Ship Tauri While Fixing Native

During the entire migration (Phases 1–14), `main` always has the working Tauri app. If the native app has issues:
1. Continue shipping the Tauri app from `main`
2. Fix native issues on `dev`
3. Only merge to `main` when stable

---

## Local-Only Guarantee Validation

After every merge, verify no external network calls were introduced:

```bash
# Static check: no external URLs in production Swift code
grep -rn "URL(string:" core/Sources/ mac/WiredPartMac/ ios/WiredPartIOS/ --include="*.swift" \
  | grep -v "localhost" | grep -v "127.0.0.1" | grep -v "0.0.0.0" | grep -v ".local"
# Must be empty or only contain Bonjour service names

# Runtime check: network monitor in debug builds
# AppCore.swift includes NWPathMonitor that logs all network transitions
# Debug builds assert no connections to external IPs
```

---

## Phase Dependencies

```
Phase 1 ──→ Phase 2 ──→ Phase 3 ──→ Phase 4 ──→ Phases 5–11 (sequential)
                                                         │
                                                         ├──→ Phase 12 (AI)
                                                         │
                                                         └──→ Phase 14 (Windows)
                                                                    │
Phase 13 (Windows AI) ←─────────────────────────────────────────────┘

Phases 5–14 all complete ──→ Phase 15 (Cleanup)
```

- Phases 1→2→3→4 are strictly sequential (each depends on the prior)
- Phases 5–11 are sequential (one module at a time to maintain focus)
- Phase 12 can start after Phase 4 (AI is independent of feature pages)
- Phase 13 depends on Phase 14 (Windows AI needs Windows target)
- Phase 15 requires ALL prior phases complete
