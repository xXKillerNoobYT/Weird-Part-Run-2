# Master Issue List — Complete Audit Results

> **Source:** 10 parallel audit agents covering routes, buttons, services, standards, plans, user flows, AI intelligence, discoverability, and 196-item pre-release checklist.
>
> **Each issue gets its own Xcode fix prompt.**

---

## TIER 1: Show-Stoppers (20 issues)

### Missing Features (designed but never built)

| # | Issue | Impact |
|---|-------|--------|
| T1-01 | Job Detail page is a skeleton — plan calls for full dashboard with smart cards, AI summary, today's activity, warranty info, financials. Code is a flat list of fields. | Users can't see job status at a glance |
| T1-02 | ~~Wishlist table missing~~ — ✅ **CLOSED** — `wishlist_items` table created in migration 057. WishlistService implemented. | Fixed |
| T1-03 | Procurement Planner not redesigned — still old JPO inbox, not the 4-source demand aggregator | No demand consolidation |
| T1-04 | Office Dashboard missing — no IOSOfficeDashboardPage with AI briefing, attention items, schedule | Managers have no daily overview |
| T1-05 | Unified Approvals missing — approvals split across separate pages | Approvals fall through cracks |
| T1-06 | Dispatch drag-and-drop not implemented — visual board with zero interaction | Can't drag workers onto jobs |
| T1-07 | Flex Pool missing — no self-assign jobs feature | Workers can't pick up unassigned work |
| T1-08 | AI summary on job cards not implemented | Job list is data-heavy, not scannable |
| T1-09 | Stage progression bars not implemented | Can't see job stage at a glance |
| T1-10 | ~~Background task log table missing~~ — ✅ **CLOSED** — `background_task_log` table created in migration 058. BackgroundTaskService implemented. | Fixed |

### Critical UX Breaks

| # | Issue | Impact |
|---|-------|--------|
| T1-11 | JPO "+" creates empty order — full cart builder (IOSJPOCreationPage) unreachable from JPO list | Field workers can't order parts easily |
| T1-12 | PO created with no line items — separate page to add parts | Office workers frustrated |
| T1-13 | "Submit to Supplier" doesn't actually send anything — misleading button name | Users think PO was sent when it wasn't |
| T1-14 | Stock shows "Warehouse #1" not human-readable names | Can't find parts on shelves |
| T1-15 | Receiving Back button discards ALL work with no confirmation | One tap = re-enter 20 quantities |
| T1-16 | Standard date filter bar: ZERO implementation anywhere in the app | Can't filter anything by date range |
| T1-17 | 2 broken sidebar routes (/orders/parts, /orders/wishlist) | Pages unreachable in sidebar layout |

### AI Assistant Failures

| # | Issue | Impact |
|---|-------|--------|
| T1-18 | AI has ZERO conversation memory — new LanguageModelSession per message | "Order those" doesn't know what "those" means |
| T1-19 | Only 5 of 87 pages send context to AI — AI blind on 82 pages | "What's the status of this job?" → useless response |
| T1-20 | AI and help system completely disconnected — AI can't read help content | User asks AI "how do I use this?" gets worse answer than help button |

---

## TIER 2: High Priority (25 issues)

### Standards Not Applied

| # | Issue | Count |
|---|-------|-------|
| T2-01 | Help buttons missing from 58+ pages | 58 pages |
| T2-02 | Help button buried in overflow menu (not visible) | All pages |
| T2-03 | Priority colors use labels not time-based | Every priority display |
| T2-04 | 6+ list pages use old chip bars instead of smart cards | 6 pages |
| T2-05 | Auto-fill job context missing from Q&A, notebooks, chat, report problem | 4+ forms |
| T2-06 | 44px touch targets not systematically enforced | Many pages |

### Dead/Broken Interactions

| # | Issue | Count |
|---|-------|-------|
| T2-07 | 8 tappable buttons do absolutely nothing (empty closures) | 8 buttons |
| T2-08 | 9 orphaned/unreachable pages | 9 pages |
| T2-09 | 2 NavigationLinks go to bare Text() placeholders | 2 links |
| T2-10 | People Dashboard unreachable (no tab in NavigationConfig) | 1 page |
| T2-11 | Clock out blocked during break with no explanation | UX confusion |
| T2-12 | Questionnaire Skip bypasses required questions | Data integrity |
| T2-13 | No per-part barcode scan during receiving | Slow receiving |
| T2-14 | Received quantities default to 0 (should be expected qty) | Extra work |
| T2-15 | No "Order This" action from part detail | Dead end |

### Code Quality

| # | Issue | Count |
|---|-------|-------|
| T2-16 | ~130 silent guard-let-service returns | 130 instances |
| T2-17 | 11 empty catch blocks | 11 blocks |
| T2-18 | 17 files with multiple .sheet() modifiers | 17 files |
| T2-19 | 7 undisplayed loadError variables | 7 files |

### UX / Discoverability

| # | Issue | Impact |
|---|-------|--------|
| T2-20 | No first-launch guided checklist (empty dashboard, no direction) | New users lost |
| T2-21 | Quick Actions buried at bottom of Dashboard (below charts) | Most useful buttons least visible |
| T2-22 | Error messages use raw localizedDescription (technical) | "no such table: parts" shown to users |
| T2-23 | AI conversation not persisted — close panel, lose everything | Frustrating for returning to AI |
| T2-24 | AI has no user preference learning | AI never gets smarter |
| T2-25 | AI makes no proactive suggestions | AI is passive, not helpful |

---

## TIER 3: Medium Priority (20 issues)

| # | Issue | Count |
|---|-------|-------|
| T3-01 | 6 pages use ContentUnavailableView instead of EmptyStateView | 6 pages |
| T3-02 | 39 pages missing .refreshable | 39 pages |
| T3-03 | 28 pages missing .searchable | 28 pages |
| T3-04 | AIDispatchService not wired to AppCore | 1 service |
| T3-05 | 9 orphan model structs in CostsModels | 9 structs |
| T3-06 | 4 services missing isTableNotFoundError | 4 services |
| T3-07 | Price shows 5 decimal places in receiving | Display bug |
| T3-08 | PO number generation has duplicate risk | Data integrity |
| T3-09 | Completing receiving with unrouted items — no warning | Silent problem |
| T3-10 | Draft PO line item edit uses cramped alert instead of sheet | Hard to use |
| T3-11 | Notebook AI merge not implemented | Sync conflicts unresolved |
| T3-12 | Weekly/end-of-job reviews only partially exist | Missing feedback loop |
| T3-13 | Multi-user audit verification not implemented | Accuracy feature missing |
| T3-14 | JPO Hold chat threads not dual-homed | Chat fragmented |
| T3-15 | PO detail missing job grouping on line items | Hard to read |
| T3-16 | PO detail missing delivery timeline bars | No ETA visibility |
| T3-17 | PO detail missing receipt history timeline | No delivery tracking |
| T3-18 | Bulk JPO hold only prompts for first item | 4/5 items get generic reason |
| T3-19 | Location permission requested on every page load | Annoying system dialogs |
| T3-20 | AI filter activation only works on catalog page (1 of 87) | Limited AI capability |

---

## SUMMARY

| Tier | Count | Prompt Range |
|------|-------|-------------|
| Tier 1: Show-Stoppers | 20 | 60A — 60T |
| Tier 2: High Priority | 25 | 61A — 61Y |
| Tier 3: Medium Priority | 20 | 62A — 62T |
| **TOTAL** | **65** | **65 prompts** |

---

## PROMPT WRITING ORDER

Write prompts in this order for maximum impact:
1. T1-16 (date filter bar — cross-cutting, touches 40+ pages)
2. T1-11 (JPO cart builder wiring — most common user flow)
3. T1-18 (AI conversation memory — makes AI actually useful)
4. T1-04 (Office Dashboard — managers need this daily)
5. T1-01 (Job Detail dashboard — most viewed page)
6. T1-15 (Receiving back button — prevents data loss)
7. T2-01+02 (Help buttons visible + on all pages)
8. T2-20 (First-launch checklist — onboarding)
9. T2-16 (Silent guard returns — bulk fix)
10. Everything else by tier
