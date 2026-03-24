# Implementation Roadmap — Xcode AI Prompt Execution Order

> **Purpose:** Master guide for implementing all pending prompts in the correct order. Dependencies flow downward — don't skip ahead.
>
> **How to use:** Feed prompts to Xcode AI one at a time, in order. Each prompt ends with "Wait for user confirmation before proceeding." After Xcode reports success, verify the build passes, then move to the next prompt.
>
> **Total prompts:** ~200 (133 DONE, ~67 pending)

---

## Phase 1: Critical Fixes (Run FIRST)

These fix bugs and safety issues. Must be done before any new features.

| Order | Prompt | What | Why First |
|-------|--------|------|-----------|
| 1 | **53A** | Safe Update System | Prevents data loss in production. Wraps eraseDatabaseOnSchemaChange in #if DEBUG. |
| 2 | **34A** | UI Quality Audit | Sheet dismiss issues, sticky buttons, form validation across all pages |
| 3 | **35A** | Daily Report Submit Stubs | 2 submit buttons that do NOTHING — users think they saved |
| 4 | **35B** | Job Detail Tab Fixes | 5 silent error catches, client-side filtering |
| 5 | **35C** | Scheduling Raw SQL | 2 files still using GRDB directly |
| 6 | **35D** | GeofenceAlertView Fix | Raw SQL in view, silent clock errors |
| 7 | **35E** | Fleet ErrorStateView | 6 pages with invisible errors |
| 8 | **35F** | Audit Session ID Fix | Hardcoded 0, PO delete navigation |
| 9 | **35G** | Settings GRDB Removal | 10 Settings files still importing GRDB |
| 10 | **35H** | Companion GRDB + Hats | 2 companion sheets + hat delete confirmation |
| 11 | **35I** | Reports + Tools GRDB | Last remaining GRDB imports |

---

## Phase 2: Warehouse Infrastructure (Foundation for many features)

Floor plan and audit systems are referenced by Tools, Fleet, Forecasting, and Movements.

| Order | Prompt | What |
|-------|--------|------|
| 12 | **36A** | Floor Plan Migration (7 tables + 15 service methods) |
| 13 | **36B** | Floor Plan Editor UI |
| 14 | **36C** | Floor Plan Navigation (warehouse GPS) |
| 15 | **36D** | Onboarding Wizard (6-step progressive setup) |
| 16 | **37A** | Audit Confidence Migration (8 tables) |
| 17 | **37B** | Audit Count Tab UI (hidden counts, speed mode, walking path) |
| 18 | **37C** | Organization Tab (consolidation voting, ratings) |
| 19 | **37D** | User Ratings + Leaderboard |

---

## Phase 3: Clock & Compliance (Affects daily operations)

| Order | Prompt | What |
|-------|--------|------|
| 20 | **38A** | Break/Lunch Compliance (4-tier policy, state presets) |
| 21 | **38B** | Break/Lunch UI (clock page buttons, settings, questionnaire) |
| 22 | **39A** | Hats Permission Audit (cross-cutting, all pages) |
| 23 | **40A** | Clock To-Do Integration (picker, mark done, work type) |
| 24 | **40B** | Clock Live Timer (elapsed, hours per job/to-do, switch job) |

---

## Phase 4: People & Teams

| Order | Prompt | What |
|-------|--------|------|
| 25 | **41A** | Teams Detail Page |
| 26 | **44A** | People Dashboard |
| 27 | **44B** | Employee Detail Rebuild |
| 28 | **44C** | Customer Detail Full |
| 29 | **44D** | Contractor Detail |
| 30 | **44E** | Contacts Redesign |
| 31 | **44F** | Payment Tracking |

---

## Phase 5: Chat & Communication

| Order | Prompt | What |
|-------|--------|------|
| 32 | **42A** | Chat Unified Inbox |
| 33 | **42B** | Chat Thread Info (iMessage-style) |
| 34 | **42C** | Chat Attachments |
| 35 | **42D** | Q&A Escalation (bidirectional) |

---

## Phase 6: Notebooks & Documentation

| Order | Prompt | What |
|-------|--------|------|
| 36 | **43A** | Notebook Structure (migration, hierarchy) |
| 37 | **43B** | Notebook Detail Rebuild (blocks, shortcuts) |
| 38 | **43C** | Notebook Templates |
| 39 | **43D** | Panel Schedule Builder |
| 40 | **43E** | Daily Report System (AI-generated) |

---

## Phase 7: Jobs & Scheduling

| Order | Prompt | What |
|-------|--------|------|
| 41 | **45A** | Jobs List Redesign (smart cards, AI summary) |
| 42 | **45B** | Job Detail Dashboard |
| 43 | **45C** | Job Types & Status (warranty, continuous, payment hold) |
| 44 | **45D** | Warranty To-Do |
| 45 | **46A** | Scheduling Calendar (month view, half-day) |
| 46 | **46B** | Dispatch Board (Gantt, drag-drop) |
| 47 | **46C** | Short-Term Pipeline |
| 48 | **46D** | Long-Term Pipeline |
| 49 | **46E** | AI Dispatch |
| 50 | **46F** | Job Estimation Questionnaire |

---

## Phase 8: Tools & Fleet

| Order | Prompt | What |
|-------|--------|------|
| 51 | **47A** | Tools Dashboard Redesign |
| 52 | **47B** | Tool Detail Rebuild |
| 53 | **47C** | Kit Management |
| 54 | **47D** | Tool Trade |
| 55 | **47E** | Tool Maintenance Types |
| 56 | **47F** | Tool Management Page |
| 57 | **48A** | My Vehicle Primary View |
| 58 | **48B** | Vehicle Detail 7-Tab |
| 59 | **48C** | Trailer Mini Warehouse |
| 60 | **48D** | Pre-Trip Inspection |
| 61 | **48E** | Fleet Dashboard KPIs |

---

## Phase 9: Reports & Office

| Order | Prompt | What |
|-------|--------|------|
| 62 | **49A** | Reports Categories |
| 63 | **49B** | Reports Export (PDF + CSV) |
| 64 | **49C** | Fleet/Warehouse/Scheduling Reports |
| 65 | **49D** | Report Builder |
| 66 | **50A** | Office Dashboard (daily briefing) |
| 67 | **50B** | Unified Approvals |
| 68 | **50C** | Office Chat Channel |
| 69 | **50D** | Office Router Cleanup |

---

## Phase 10: Cross-Cutting & Settings

| Order | Prompt | What |
|-------|--------|------|
| 70 | **51A** | Standard Filter Bar (ALL pages) |
| 71 | **52A** | Settings Grouped Navigation |
| 72 | **52B** | Settings Operations Pages (4 new) |
| 73 | **52C** | Settings Warehouse Pages (3 new) |
| 74 | **52D** | Settings Template Pages (3 new) |
| 75 | **52E** | Settings Functional Features (5 simulated → real) |
| 76 | **52F** | Settings Sync Classification |

---

## Program-Wide Standards (enforced in ALL prompts)

These standards apply to every prompt above. Xcode AI should follow them automatically because each prompt references them.

1. **Smart Cards** — stat card filters on all list pages (tap to filter, tap again for all)
2. **Help Button** — every page gets a help/info button with page purpose + how-to
3. **Standard Filter Bar** — This Week/Last Week/This Period/Last Period/This Month/Custom on all date pages
4. **Priority Colors** — green (ok), yellow (4 days), orange (24 hours), red (overdue), gray (done)
5. **One AI Button** — bottom right floating orange circle, same spot every page
6. **Hat Permissions** — never hardcoded roles, always `hasPermission("key")`
7. **Auto-Fill Job Context** — when clocked in, all job-related actions auto-fill the current job
8. **Single .sheet(item:)** — ActiveSheet enum pattern, never multiple .sheet() modifiers
9. **Error Visibility** — @State loadError + ErrorStateView on every page
10. **Service Layer Only** — never import GRDB in UI files
11. **44px Touch Targets** — all tappable elements
12. **Block-Based Sync** — notebooks use per-block conflict resolution
13. **Full Audit Trail** — part_change_log tracks who changed what
14. **Edit-Without-Permission** — Tools only: any user edits, pending verification if no hat
15. **No Platform Guards** — app is iOS-only, no #if os(iOS) needed

---

## Future Work (Not Yet Prompted)

These features were discussed and designed but need more detail before prompts can be written:

| Feature | Plan File | Status |
|---------|-----------|--------|
| AI Smart Question System | ios-scheduling-pages.md | Design complete, needs prompts |
| Wishlist Page | inventory-intelligence-system.md | Design complete, needs prompts |
| Background Task Dashboard Card | ios-office-pages.md | Design complete, needs prompts |
| Supplier Bridge Full Implementation | supplier-communication-bridge-plan.md | Prompts 22A-C DONE, bridge UI needs review |
| Job-specific AI suggestions | ios-scheduling-pages.md | Design complete, future phase |
| PWA & Desktop enhancements | phase-12-pwa-desktop.md | Plan exists, not yet designed for iOS |
| Remote Sync | phase-15-remote-sync.md | ON HOLD |

---

*Last updated: 2026-03-23*
