# Agent Instructions

> This file is mirrored across CLAUDE.md, copilot-instructions.md, AGENTS.md, and GEMINI.md so the same instructions load in any AI environment.

--- MEMORY.md use this for project context and architectural patterns. Re-read at ~80% context usage to prevent drift.

## Working Style & Collaboration

**The dynamic:** The user is the designer. They design the code — the architecture, the vision, the general idea. You code it. They give high-level direction; you deliver high-detail, high-quality implementation.

**Behavioral rules:**

1. **Ask clarifying questions when planning.** Don't guess at ambiguous requirements — ask before building. Planning is the time for questions, not mid-implementation.
2. **Always look for things to do next.** Be proactive. When a task finishes, identify the logical next step — suggest it, don't idle.
3. **Suggest areas of improvement.** If you see a better approach, a missing edge case, or a structural weakness — raise it. You're a collaborator, not a stenographer.
4. **High detail, high quality.** The user gives general ideas. Your job is to expand those into thorough, production-grade implementations — well-structured, well-commented, properly error-handled.
5. **Respect the user's intent.** The user may not always articulate things perfectly. Interpret the spirit of the request and deliver what they actually need, not a literal reading of ambiguous words.

---

## Large File Auto-Split Rule

When a code file is too large to read or process in a single pass, automatically split it into smaller files that work together without breaking functionality.

**Process:**

1. **Read directly** — don't search the file, read it.
2. **Detect** when the file exceeds safe processing size.
3. **Identify natural modular boundaries:** classes, functions, components, modules, configuration blocks, domain-specific sections.
4. **Split into smaller files** while preserving: imports/exports, namespaces, type definitions, shared utilities, dependency order.
5. **For each new file:** give it a clear descriptive name, ensure it compiles/runs as part of the project, add/adjust imports and exports so the system remains functional.
6. **After splitting:** generate a dependency map showing how the new files relate, plus a summary of what changed and why.

**Rules:**
- Never refactor or redesign architecture unless explicitly instructed.
- Never remove logic or alter behavior.
- Apply automatically for all oversized code files unless explicitly disabled.

---

## The 3-Layer Architecture

You operate within a 3-layer architecture that separates concerns to maximize reliability. LLMs are probabilistic, whereas most business logic is deterministic and requires consistency. This system fixes that mismatch.

**Layer 1: Directive (What to do)**
- SOPs written in Markdown, live in `directives/`
- Define the goals, inputs, tools/scripts to use, outputs, and edge cases
- Natural language instructions, like you'd give a mid-level employee

**Layer 2: Orchestration (Decision making)**
- This is you. Your job: intelligent routing.
- Read directives, call execution tools in the right order, handle errors, ask for clarification, update directives with learnings
- You're the glue between intent and execution. E.g. you don't try scraping websites yourself — you read `directives/scrape_website.md` and come up with inputs/outputs and then run `execution/scrape_single_site.py`

**Layer 3: Execution (Doing the work)**
- Deterministic Python scripts in `execution/`
- Environment variables, API tokens, etc. are stored in `.env`
- Handle API calls, data processing, file operations, database interactions
- Reliable, testable, fast. Use scripts instead of manual work. Commented well.

**Why this works:** If you do everything yourself, errors compound. 90% accuracy per step = 59% success over 5 steps. The solution is push complexity into deterministic code. That way you just focus on decision-making.

---

## Operating Principles

**1. Check for tools first**
Before writing a script, check `execution/` per your directive. Only create new scripts if none exist.

**2. Self-anneal when things break**
- Read error message and stack trace
- Fix the script and test it again (unless it uses paid tokens/credits/etc — in which case check with the user first)
- Update the directive with what you learned (API limits, timing, edge cases)
- Example: you hit an API rate limit → look into API → find a batch endpoint → rewrite script to accommodate → test → update directive.

**3. Update directives as you learn**
Directives are living documents. When you discover API constraints, better approaches, common errors, or timing expectations — update the directive. But don't create or overwrite directives without asking unless explicitly told to. Directives are your instruction set and must be preserved (and improved upon over time, not extemporaneously used and then discarded).

---

## Self-Annealing Loop

Errors are learning opportunities. When something breaks:

1. Fix it
2. Update the tool
3. Test tool, make sure it works
4. Update directive to include new flow
5. System is now stronger

---

## File Organization

**Deliverables vs Intermediates:**
- **Deliverables**: Google Sheets, Google Slides, or other cloud-based outputs that the user can access
- **Intermediates**: Temporary files needed during processing

**Directory structure:**
- `.tmp/` - All intermediate files (dossiers, scraped data, temp exports). Never commit, always regenerated.
- `execution/` - Python scripts (the deterministic tools)
- `directives/` - SOPs in Markdown (the instruction set)
- `.env` - Environment variables and API keys
- `credentials.json`, `token.json` - Google OAuth credentials (required files, in `.gitignore`)

**Key principle:** Local files are only for processing. Deliverables live in cloud services (Google Sheets, Slides, etc.) where the user can access them. Everything in `.tmp/` can be deleted and regenerated.

---

## Summary

You sit between human intent (directives) and deterministic execution (Python scripts). Read instructions, make decisions, call tools, handle errors, continuously improve the system.

Be pragmatic. Be reliable. Self-anneal.

---

## Context Management

When working in long sessions, **re-read `CLAUDE.md` and `MEMORY.md` at approximately 80% context usage.** This prevents instruction drift and keeps decisions aligned with project conventions. Better to refresh early than to lose track of patterns and repeat avoidable mistakes.

---

## Target Platforms & Compatibility

This application must be production-ready across **all** of the following:

| Platform | Viewport | Notes |
|----------|----------|-------|
| Windows desktop | 1280×800+ | Primary dev/test environment |
| Mac desktop | 1280×800+ | Safari + Chrome compatibility |
| iOS tablet (iPad) | 768×1024 | Touch-friendly, landscape & portrait |
| iOS phone (iPhone) | 375×812 | Full mobile-first responsive layout |

**Development requirements:**

1. **Responsive by default.** Every page must work at all four breakpoints. Use Tailwind's responsive prefixes (`sm:`, `md:`, `lg:`) consistently.
2. **Touch-friendly.** Buttons must be at least 44×44px tap targets on mobile. No hover-only interactions — always provide a tap/click alternative.
3. **No horizontal overflow.** The AppShell uses `overflow-hidden` on ancestor containers. Always use `flex-wrap gap-3` on header rows with action buttons. Use `overflow-x-auto` for wide tables and tab bars.
4. **Responsive text.** Long button labels should use `hidden sm:inline` or `hidden md:inline` patterns to show icon-only on smaller screens.
5. **Test at all breakpoints.** Before marking any UI work as complete, verify at desktop (1280×800), tablet (768×1024), and mobile (375×812).
6. **Cross-browser.** Avoid CSS features without broad support. Tailwind v4 handles most of this, but be mindful of Safari quirks (e.g. `gap` in flexbox, `dvh` units).

---

## Plan Filing & History

Plans are living documents that build our project's institutional memory. Treat them with care.

**Where plans live:**

- **Master plan:** `docs/implementation-plan.md` — the high-level roadmap
- **Phase/feature plans:** `docs/plans/<name>.md` (e.g. `docs/plans/phase-4-jobs-labor.md`)
- **The Full Plan:** `docs/The Full Plan.md` — the original comprehensive vision document

**Rules for plan management:**

1. **Always save to `docs/plans/`.** Never leave plans only in `.claude/plans/` — those are ephemeral and won't persist. Plans are the source of truth for design goals and decisions.
2. **Use descriptive filenames:** `phase-N-short-name.md` or `feature-short-name.md`.
3. **ALWAYS read plans before making edits.** Before writing ANY code in a phase, read BOTH the plan you built (in `.claude/plans/`) AND the saved copy (in `docs/plans/`). Understand the full design before implementing. This prevents drift, contradictions, and wasted rework. At the start of a new phase, also read the master plan to understand cross-phase dependencies.
4. **Update plans as work completes.** Mark completed items, note any deviations from the original plan, and add learnings. Plans should reflect reality, not just intent.
5. **Preserve plan history.** Don't delete old plans when creating new ones. The progression from Phase 1 → 2 → 3 → ... tells the story of the project's evolution. Future agents (and the user) benefit from this context.
6. **When creating a new plan,** reference the master plan and summarize what phases came before. This makes each plan self-contained enough to understand in isolation.
7. **Design-first workflow (MANDATORY).** Plans come before prompts. ALL design decisions from reviews and discussions MUST be saved to `docs/plans/` with full detail before Xcode AI prompts are written. Plans define the WHAT and WHY. Prompts define the HOW. Reviews compare the result against the plan.
8. **Save ALL design info immediately.** If a conversation produces design decisions (data models, business rules, UI flows, behavioral rules, table schemas), save them to `docs/plans/` right away. Don't lose design work by leaving it only in conversation context.
9. **Xcode AI prompts track separately.** Prompt files live in `xcode-ai/fix-prompts/`. Tracking is in `xcode-ai/fix-prompts/00-fix-order.md`. The Xcode instruction file is at `xcode-ai/xcode.md`. But these all implement what `docs/plans/` specifies.
10. **INVOKE the `xcode-planner-and-review` skill** (via the Skill tool) for ALL iOS/Swift/Xcode work — planning features, writing prompts, reviewing code, auditing results. Do NOT do this work manually. The skill enforces the design-first workflow, tracks decisions, generates prompts with proper structure, audits results against plans, and self-improves. If the task involves iOS pages, Swift code, Xcode AI prompts, or page reviews — call the skill FIRST.

**Key active plan documents:**

- `docs/plans/hunt-fix-verify-loop.md` — **Hunt-Fix-Verify Loop** — autonomous bug-hunting process with 7 scanners, priority-based fixing, and final verification gate. Tracker at `docs/hunt-fix-tracker.md`
- `docs/plans/ios-page-review-tracker.md` — master tracking of all iOS page reviews, decisions, and remaining work
- `docs/plans/inventory-intelligence-system.md` — forecasting, wishlist, procurement redesign, movements, MIN/TARGET/MAX rules
- `docs/plans/forecasting-page-redesign.md` — focused design spec for forecasting prompts 23A-23H

**Hunt-Fix-Verify Loop (Bug Hunting Protocol):**

When performing bug hunts or quality sweeps, follow `docs/plans/hunt-fix-verify-loop.md`. This defines:
- **7 scanners** (compile, tests, code patterns, SQL integrity, problems folder, master issues, plan alignment)
- **Priority order** for fixes (compile > tests > SQL > user-reported > T1 > silent errors > T2 > patterns > T3 > plans)
- **Fix protocol** (read → understand root cause → fix → test → build → verify → mark fixed)
- **Final verification gate** (ALL scanners must pass simultaneously)
- **Tracker** at `docs/hunt-fix-tracker.md` — updated each iteration

**Current plan history:**

- Phase 1: Foundation — DB, auth, nav shell, theme system (complete)
- Phase 2: Parts & Inventory Core — hierarchy CRUD, catalog, brands, suppliers, pricing, stock, forecasting, import/export (complete)
- Phase 2.5: Parts Hierarchy UX — categories tree editor, type-color links, grouped card view (complete)
- Phase 3: Warehouse & Movements — Guided Movement Wizard, dashboard, pulled staging, audit (complete)
- Phase 3.5: Companions & Enhancements — companion rules, alternatives, QR scanner, bin locations (complete)
- Phase 4: Jobs & Labor — job CRUD, clock in/out with GPS, questionnaire, daily reports, APScheduler (complete)
- Phase 4.5: Unified Notebook System — job + general notebooks, todo stages, templates (complete)
- Phase 5: Orders & Procurement — JPO→PO lifecycle, procurement planner, returns, price history (complete)
- Phase 6: Fleet & Vehicle Management — vehicles, assignments, deliveries, maintenance, mileage, reimbursements (complete)
- Phase 7A: Core Ordering Experience — unified order form, job preferences, special items (complete)
- Phase 7B: Office Workflow — PO management, approvals, PDF bundles, Review & Send (complete)
- Phase 7C: Warehouse Workflow — receiving sessions, return sorting (complete)
- Phase 7D: Analytics & Visibility — cost tracking (FIFO/LIFO), spending dashboard, job cost rollup, budget alerts (complete)
- Phase 7E: Quality of Life — notification sounds, QR enhancements, bulk actions (complete)
- Phase 8: People Full — employees, certifications, wages, skills, hats, permissions (complete)
- Phase 9: Tools & Kits — tool registry, kit verification, checkout/return, maintenance tracking (complete)
- Phase 10: People, Contacts & Scheduling — customers, GCs, contacts, scheduling, dispatch, time-off, subcontractors (complete)

**Recently Completed (2026-03-07):**

- Phase 7 Delta: People additions — PO naming convention, report filename naming (✅ complete — see `docs/plans/phase-7-people-delta.md`)
- Phase 8: Reports & Pre-Billing — all 6 pages, period locking, bookkeeper exports (✅ complete — see `docs/plans/phase-11-reports-prebilling.md`)
- Legacy Cleanup — superseded pages removed/redirected (✅ complete — see `docs/plans/legacy-cleanup-plan.md`)
- Testing Strategy — 119 tests across 10 files (✅ complete — see `docs/plans/testing-strategy.md`)
- Feature Audits — all 13 areas audited (✅ complete — see `docs/plans/Audit/`)
- Gap Closure — M1-M4, 44/44 items (✅ complete — see `docs/plans/full-program-gap-closure-plan.md`)
- Scheduling Enhancements — lunch breaks, supervisor role, multi-job dispatch UX (✅ complete — see `docs/plans/scheduling-enhancements.md`)
- V1.0 Deployment — 19 of 23 tasks complete. Remaining 5 tasks need Mac + physical devices (see `docs/plans/deployment-master-plan.md`)
- Phase 17: Orders Audit Closure — all 5 gaps: category supplier prefs, supplier portal notes, PDF templates, cross-job summary, explicit preferred suppliers (✅ complete — see `docs/plans/phase-17-orders-audit-closure.md`)
- Tauri 2.0 Migration — all 8 phases complete: scaffold, DB layer, services, API adapter, LAN sync, BT sync, native capabilities, iOS build, distribution (✅ complete — see `docs/plans/tauri-migration-plan.md`)
- Cross-Platform Architecture Alignment — shared `isDesktop()`/`isMobile()`, public data directory feature, DB path config, Rust IPC commands, Settings UI (✅ complete — see `docs/plans/frontend-to-root-restructure.md`)

**Recently Completed (2026-03-15):**

- Phase 13: Windows AI Integration — llama.cpp sidecar (not Copilot Runtime), Rust IPC bridge, TS types, Settings UI, AI components (✅ complete — see `docs/plans/windows-architecture.md`)
- Phase 14: Windows App — **Option B: Keep Tauri/React** — zero porting needed, all 86 pages + 64 services work as-is (✅ complete — see `docs/plans/windows-architecture.md`)
- Phase 15: Cleanup — modified for Option B: no file deletions, documentation updates only (✅ complete — see `docs/plans/windows-architecture.md`)
- Production Hardening — Sessions 1-6: 50+ backend crash fixes, 138 frontend routes audited, ErrorBoundary, global error handler, 23 pages patched, dark mode/loading/edge-case audits (✅ complete)

**Architecture (V1.0 — Tauri, Dual-Platform):**

Every device runs the same React frontend (`src/`) with its own local SQLite database. The Tauri native shell (`src-tauri/`) wraps this as a desktop/mobile app on **both macOS/iOS AND Windows**. One change in `src/` propagates to all platforms.

- **Shop computer (Tauri desktop — macOS or Windows):** React frontend + full 35-service TS data layer + local SQLite. Also runs Python FastAPI as a sync anchor + serves desktop browsers over LAN.
- **Windows devices (Tauri desktop):** Same React frontend via WebView2. On-device AI via **llama.cpp sidecar** (localhost:8086, GGUF models). Same sync infrastructure as other devices.
- **Mobile devices (Tauri iOS):** Same React frontend + same TS data layer — works fully offline. Single-user sandbox storage. On-device AI via Apple Foundation Models (macOS 26+).
- **Desktop browsers:** Hit shop server directly over LAN HTTP (always at the shop).
- **Sync:** Device ↔ Shop over LAN HTTP + Apple Multipeer Connectivity (BT/Wi-Fi P2P). Change tracking via `_change_log` table. LWW + field-level merge conflict resolution.
- **API adapter pattern:** Frontend detects environment — `isTauri()` → local TS services, `isBrowser()` → HTTP API. Same React UI everywhere.
- **AI adapter pattern:** Foundation Models bridge detects OS — Apple → native FM API, Windows → llama.cpp HTTP, Browser → no on-device AI. Same `useAITextField` hook everywhere.
- **Cross-platform rule:** All UI code in `src/` runs identically everywhere. Platform differences are only: (1) screen size → responsive CSS, (2) desktop-only features → gated by `isDesktop()` in TS / `#[cfg(desktop)]` in Rust, (3) AI engine → gated by `#[cfg(target_os)]` in Rust.
- **Public directory (desktop):** Optional shared DB location (`/Users/Shared/WiredPart/` on macOS, `C:\Users\Public\WiredPart\` on Windows) for multi-user shop computers. Configured in Settings → Data Storage.

**Future phases (planned — all have plan files):**

- Phase 9: Chat & Q&A — per-job group chat, DMs, Q&A escalation chain, RFI bridge (see `docs/plans/phase-9-chat.md`)
- Phase 10: PWA & Desktop — service worker, keyboard shortcuts, command palette, push notifications (see `docs/plans/phase-12-pwa-desktop.md`)
- Phase 11: Sync & Bluetooth — BT mesh, gossip protocol, PGP encryption, device pairing, shop cluster (see `docs/plans/phase-13-sync-bluetooth.md`)
- Phase 12: AI Integration — LM Studio local LLM, NL queries, anomaly detection, predictive ordering (see `docs/plans/phase-14-ai-integration.md`)
- Phase 13: Remote Sync — ON HOLD — internet sync, shop↔shop, shared channels (see `docs/plans/phase-15-remote-sync.md`)
- Phase 16: UX Polish & Admin Hub — nav restructure, warehouse enhancements, report filters, teams, device mgmt (see `docs/plans/phase-16-ux-polish-and-admin-hub.md`)
- Bootstrap App — App Store shell that downloads real program from shop (see `docs/plans/Mobile device bootstrap.md`)

**Codebase stats (as of 2026-03-07):**

| Metric | Count |
|--------|-------|
| Backend routers | 18 (all mounted) |
| API endpoints | ~480 |
| Backend services | 28 |
| Repositories | 19 + base |
| Migrations | 35 |
| Frontend feature files | ~180 |
| Frontend routes | 100 |
| Functional pages | 87 |
| Stub pages | 1 (DeviceManagementPage — v2.0+) |
| API client functions | ~300 |
