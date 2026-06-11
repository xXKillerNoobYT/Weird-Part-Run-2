# Working Area Guide

Tracking:

- GitHub: [xXKillerNoobYT/Weird-Part-Run-2#942](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/942)
- Paperclip parent: `WEI-3096`
- Paperclip active implementation: `WEI-3099`
- Paperclip QA review: `WEI-3100`

Use this guide to route work to the right part of the repo before editing. Keep changes small and area-owned; avoid cross-area refactors unless the issue explicitly calls for them.

## App Shell

| Path | Owns | Notes |
| --- | --- | --- |
| `Weird Parts IOS/Weird Parts IOS/App` | app entry, app-level composition | Keep launch/setup logic thin. |
| `Weird Parts IOS/Weird Parts IOS/Navigation` | routing, tabs, page selection | Update route maps when adding feature screens. |
| `Weird Parts IOS/Weird Parts IOS/DesignSystem` | shared tokens, primitives, app styling | Prefer existing components before adding new visual styles. |
| `Weird Parts IOS/Weird Parts IOS/Shared` | reusable SwiftUI components and charts | Only place broadly reusable UI here. |
| `Weird Parts IOS/Weird Parts IOS/WebFallback` | fallback surfaces | Do not route primary native work here unless issue scope says so. |

## Feature Modules

Each feature folder under `Weird Parts IOS/Weird Parts IOS/Features` should own its screens, view-local state, and feature-specific UI composition. Shared business logic belongs in `core/Sources/WiredPartCore`.

| Feature | Folder | Typical evidence |
| --- | --- | --- |
| Chat/RFI | `Features/Chat` | message thread, Q&A, RFI create/review screenshots or UI test |
| Dashboard | `Features/Dashboard` | KPI/alert screen at phone and tablet sizes |
| Fleet | `Features/Fleet` | vehicle/trailer detail and inspection workflow evidence |
| Jobs | `Features/Jobs` | job list/detail, clock, questionnaire, daily report flow |
| Notebooks | `Features/Notebooks` | notebook list/detail/template state |
| Office | `Features/Office` | office dashboards and management flows |
| Orders | `Features/Orders` | JPO/PO lifecycle, approvals, receiving links |
| Parts | `Features/Parts` | catalog/category/brand/supplier/pricing/import flows |
| People | `Features/People` | employee/customer/contact/hat flows |
| Reports | `Features/Reports` | report generation/export screens |
| Scheduling | `Features/Scheduling` | calendar, dispatch, time-off, templates |
| Settings | `Features/Settings` | company, security, sync, devices, AI settings |
| Tools | `Features/Tools` | tool registry, kits, checkout, maintenance |
| Warehouse | `Features/Warehouse` | floor plan, movement, receiving, staging, audit flows |

## Core Package

| Path | Owns | Guidance |
| --- | --- | --- |
| `core/Sources/WiredPartCore/Models` | domain entities and value types | Keep model changes backward-compatible with migrations and test fixtures. |
| `core/Sources/WiredPartCore/Services` | business operations | Put testable workflow rules here instead of embedding them in SwiftUI views. |
| `core/Sources/WiredPartCore/Database` | GRDB setup, migrations, repositories | Migration changes need tests and rollback/seed impact notes. |
| `core/Sources/WiredPartCore/Sync` | change tracking, peer/device sync, conflict handling | Include multi-device or conflict evidence for sync changes. |
| `core/Sources/WiredPartCore/AI` | AI service adapters and tools | Guard availability and keep privacy/local-first assumptions explicit. |
| `core/Sources/WiredPartCore/OCR` | OCR processing | Include image/input fixture notes where possible. |
| `core/Sources/WiredPartCore/QR` | QR encoding/scanning core | Include round-trip tests for format changes. |

## Tests

| Test area | Path | Use for |
| --- | --- | --- |
| Core package tests | `core/Tests/WiredPartCoreTests` | service, repository, migration, model, sync, QR/OCR logic |
| App tests | `Weird Parts IOS/Weird Parts IOSTests` | app-level regressions that need app target integration |
| UI tests | `Weird Parts IOS/Weird Parts IOSUITests` | XCUITest coverage, screenshots, launch and navigation flows |
| Repo/static checks | `tests`, `scripts` | tracked artifact guards, helper script validation |

## Automation And GitHub

| Path | Purpose |
| --- | --- |
| `.github/workflows` | GitHub Actions workflows |
| `scripts/guard-tracked-artifacts.py` | blocks committed runtime/generated artifacts |
| `scripts/github-issue-sync.sh` | GitHub issue synchronization helper |
| `scripts/paperclip-github-tracker-sync.sh` | Paperclip tracker sync workflow helper |
| `scripts/pr-merge-maintenance.sh` | one-PR-at-a-time maintenance automation |

For WPR2 PR testing, iOS/macOS/Xcode work should use the local self-hosted Mac runner path when CI capacity is the only blocker. See [docs/QA-PROCESS.md](QA-PROCESS.md).

## Documentation

| Path | Use |
| --- | --- |
| `README.md` | repo front door and contributor map |
| `docs/SETUP.md` | local setup and command reference |
| `docs/QA-PROCESS.md` | verification evidence and reviewer handoff |
| `docs/TESTING-REQUIREMENTS.md` | detailed testing standards |
| `docs/DEPENDENCIES.md` | dependency decisions and runner context |
| `docs/plans` | active and historical plans |
| `docs/DevTODO` | implementation findings that need follow-up |
| `xcode-ai` | AI-agent prompts, observations, and local fix order |

## Handoff Checklist

- Name the feature/core area touched.
- Name the GitHub issue and Paperclip ID.
- List commands run and whether they passed.
- For UI changes, attach or describe simulator/device evidence and viewport/orientation.
- State residual risk and next owner.
