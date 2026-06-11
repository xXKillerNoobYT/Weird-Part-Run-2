# WiredPart

Native iOS field-service operations app for an electrical contracting shop. WiredPart manages parts inventory, warehouse operations, fleet tracking, job labor, procurement, scheduling, reporting, notebooks, chat/RFIs, and local device sync from a SwiftUI app backed by a shared Swift package.

Tracking:

- GitHub: [xXKillerNoobYT/Weird-Part-Run-2#942](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/942)
- Paperclip parent: `WEI-3096`
- Paperclip active implementation: `WEI-3099`
- Paperclip QA review: `WEI-3100`

## Start Here

| Need | Read |
| --- | --- |
| Build or test locally | [docs/SETUP.md](docs/SETUP.md) |
| Pick the right code area | [docs/WORKING-AREAS.md](docs/WORKING-AREAS.md) |
| Verify a change | [docs/QA-PROCESS.md](docs/QA-PROCESS.md) |
| Current staged roadmap | [docs/plans/staged-paperclip-goals.md](docs/plans/staged-paperclip-goals.md) |
| Dependency and runner notes | [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) |
| Historical implementation context | [docs/DEVELOPMENT-HANDOFF.md](docs/DEVELOPMENT-HANDOFF.md) |

## Repository Map

```text
Weird-Part-Run-2/
├── Weird Parts IOS/
│   ├── Weird Parts.xcodeproj/        iOS Xcode project
│   ├── Weird Parts IOS/              SwiftUI app target
│   ├── Weird Parts IOSTests/         app-level unit/regression tests
│   └── Weird Parts IOSUITests/       XCUITest suites and launch tests
├── core/
│   ├── Package.swift                 WiredPartCore Swift package
│   ├── Sources/WiredPartCore/        models, services, database, sync, AI, QR/OCR
│   └── Tests/WiredPartCoreTests/     Swift Testing package tests
├── docs/                             setup, QA, plans, trackers, runbooks
├── scripts/                          repo hygiene, GitHub/Paperclip sync, guards
├── tests/                            static/repo-level checks
├── tools/                            local developer utilities
└── xcode-ai/                         AI-agent prompts, skills, and observations
```

## Architecture

| Area | Technology |
| --- | --- |
| App UI | SwiftUI, iOS app target in `Weird Parts IOS/` |
| Shared domain core | Swift Package Manager library `WiredPartCore` |
| Database | GRDB.swift with SQLCipher-backed pinned dependency |
| Sync | Local-first service layer, LAN/peer sync surfaces, device trust primitives |
| AI/OCR/QR | Apple Foundation Models surfaces where available, Vision, AVFoundation |
| Tests | Swift Testing for core package, Xcode test plans/XCUITest for app flows |
| Automation | GitHub Actions plus local self-hosted Mac runner for Xcode/iOS work |

The app is intentionally local-first. Core business rules belong in `core/Sources/WiredPartCore` where they can be tested without booting the UI. SwiftUI feature screens should remain thin composition layers over shared services, view models, and app navigation state.

## Feature Areas

| Area | Purpose | Primary App Path |
| --- | --- | --- |
| Dashboard | KPIs, alerts, quick actions | `Features/Dashboard` |
| Parts | catalog, categories, brands, suppliers, pricing, forecasting, import/export | `Features/Parts` |
| Warehouse | locations, movements, receiving, staging, returns, audits, trailers | `Features/Warehouse` |
| Jobs | job lifecycle, labor, clock, questionnaire, daily reports | `Features/Jobs` |
| Orders | JPOs, purchase orders, returns, procurement, approvals | `Features/Orders` |
| Fleet | vehicles, trailers, inspections, maintenance, mileage, fuel | `Features/Fleet` |
| People | employees, customers, contacts, hats, teams, permissions | `Features/People` |
| Scheduling | calendar, dispatch, time off, templates, availability | `Features/Scheduling` |
| Tools | tool registry, kits, checkout, maintenance | `Features/Tools` |
| Notebooks | all notebooks, templates, job notebooks | `Features/Notebooks` |
| Reports | timesheets, spending, daily summaries, pre-billing exports | `Features/Reports` |
| Chat | messages, Q&A, RFIs | `Features/Chat` |
| Office | office management dashboards and admin workflows | `Features/Office` |
| Settings | company config, security, sync, theme, devices, AI settings | `Features/Settings` |

## Common Commands

```bash
# Core package tests
cd core
swift test

# Static artifact guard from repo root
python3 scripts/guard-tracked-artifacts.py

# Xcode app build/test from repo root; choose an installed simulator
xcodebuild \
  -project "Weird Parts IOS/Weird Parts.xcodeproj" \
  -scheme "Weird Parts" \
  -destination 'generic/platform=iOS Simulator' \
  build
```

For PR validation that needs iOS/macOS/Xcode, prefer the repository's local self-hosted Mac runner labels documented in [docs/QA-PROCESS.md](docs/QA-PROCESS.md). Do not call a WPR2 PR blocked only because GitHub-hosted macOS capacity or billing is unavailable until the local runner state has been checked.

## Work Rules

- Keep generated/runtime files out of commits. Run `python3 scripts/guard-tracked-artifacts.py` before handing off.
- Put domain rules in `WiredPartCore` first when practical, then adapt them in the app.
- Add or update the smallest relevant test for behavior changes.
- Capture UI evidence for user-facing changes: route/screen, device or simulator, viewport/orientation, command, and result.
- Link the GitHub issue and Paperclip ID in docs, PRs, and handoff comments when a change is part of tracked work.

## License

Private repository. All rights reserved.
