# Panel-Quality Uplift — Bring Every Page to the Panel Schedule Builder Bar

> **Owner directive (2026-07-06):** "This is the level of design I want all the way across the app… see all the little things that make this better — this is what I want for everything in the app." Reference: the Panel Schedule Builder (`Features/Notebooks/PanelScheduleBuilder.swift`). Deliverables: (1) audit of what meets/doesn't meet the bar, (2) this plan, (3) implementation, (4) cleaned up and landed on main.
>
> **Audit provenance:** 19-agent workflow (2026-07-06): 1 rubric-extraction agent → 16 per-area auditors (Dashboard, Jobs, Chat, Scheduling, Warehouse, Orders, Fleet, Tools, Notebooks, Parts, People, Office, Settings, Reports, Auth+Onboarding, Sync+Scanning+Shared) → completeness critic with grep-verification of suspicious claims. Full structured output: session task `w3y11frho` (278 KB). Key content digested here.

---

## 1. The Quality Bar (rubric distilled from the Panel Schedule Builder)

Sixteen checkable criteria — what "Panel-Builder quality" concretely means:

| # | Criterion | The reference behavior |
|---|-----------|------------------------|
| 1 | **44pt tap targets** | Every interactive cell: `.frame(minHeight: 44)` + `.contentShape(Rectangle())`; regression test forbids the old 36pt |
| 2 | **Four-part accessibility** | `.accessibilityLabel` + `Value` + `Hint` + stable kebab `Identifier` on every interactive element, built by helper funcs producing sentence-quality output ("20 amp, GFCI breaker, Lighting, fed from MDP"), empty states distinguished ("Spare circuit, no breaker assigned") |
| 3 | **Gesture alternatives** | Drag/drop has a named `.accessibilityAction`; decorative shapes `.accessibilityHidden(true)` |
| 4 | **Multi-modal interaction** | ≥2 input paths to core actions (tap, context menu, drag, toolbar); empty cells open pre-seeded editors |
| 5 | **Mode banner + escape** | Any modal state shows an inline instruction banner, visual target affordances, and a visible Cancel |
| 6 | **Validate before persist** | Throwing validation on a candidate copy BEFORE committing state; errors alert, never `try?`-swallowed |
| 7 | **Failed actions roll back UI** | Rejected drops/edits visibly cancel (propagated Bool), never appear to succeed |
| 8 | **Destructive confirmation with counts** | `.destructive`/`.cancel` roles, message interpolates exact count with pluralization, plus early inline ⚠️ warning before the user even reaches Save |
| 9 | **Normalize on save** | `normalizedForPersistence()` at BOTH ends of the editor callback |
| 10 | **Single source of truth for options** | Picker options from model constants, never duplicated UI literals |
| 11–16 | Domain-constrained inputs, export polish (iPad popover anchoring), contextual help, monospaced numerals, adaptive dark-mode colors, doc-comments citing issues | (see rubric in task output) |

## 2. Audit Results — What Doesn't Meet the Bar

### 2a. Verified functional bugs found by the audit (fix FIRST — these are broken, not unpolished)
| Sev | Finding | File | Status |
|-----|---------|------|--------|
| 🔴 | **Sync conflict resolution is cosmetic** — all 4 "pick local/remote" callbacks funnel to `markReviewed()` which only deletes the row; NO value-application path exists. Data-loss surface masquerading as a feature | `Sync/SyncConflictReviewPage.swift` | **fixed this wave** |
| 🔴 | Notebooks checklist **encode/decode contract mismatch** — `encodeChecklistItems()` persists `"true"/"false"` strings that the decoder doesn't accept | `Notebooks/AddNotebookEntrySheet.swift:584` + `IOSNotebookDetailPage` | **fixed this wave** |
| 🟠 | Settings Break: editing an existing bonus **amount silently dropped** (only the toggle persists) | `Settings/IOSBreakSettingsPage.swift:604` | tracked |
| 🟠 | Jobs: clock-in **note collected but never persisted** (`clockIn(userId:jobId:)` has no notes param) | `Jobs/LaborPage.swift:289` | tracked |
| 🟠 | Reports Spending: `StandardFilterBar` rendered but **selected range never reaches the query** (`getSpendingSummary(days:)` uses the pill picker only) | `Reports/IOSSpendingPage.swift:222` | tracked |
| 🟠 | Tools: `ToolApproveEditSheet` fully built but **unreachable** (nothing sets `.pendingVerification`) | `Tools/IOSToolDetailPage.swift:639` | tracked |
| 🟡 | Dashboard: checklist dismiss has **two** `.accessibilityIdentifier`s (second silently wins) | `Dashboard/DashboardView.swift:289` | **fixed this wave** |
| 🟡 | Jobs: dead `effectiveStart`/`effectiveEnd` in LaborPage + JobReportsPage | both files | tracked |

### 2b. Systemic craft gaps (the critic's ranked "fix once" list — grep-verified)
1. **Four-part accessibility missing in all 15 areas** — Settings: 0 `accessibilityValue` hits; Fleet: 0 `accessibilityIdentifier`; Orders: 5 identifiers across 20 files → **`.rowAccessibility(label:value:hint:id:)` shared ViewModifier** *(built this wave)*
2. **Sub-44pt custom controls everywhere** — Fleet pre-trip OK/Issue/N/A ≈24pt; Office approval buttons ≈36pt; Scheduling dispatch chips ≈20pt with bare `.onTapGesture` → **`.dsMinTapTarget()` shared modifier** *(built this wave; adopted in Fleet pre-trip + Office approvals)*
3. **Orders: zero `.contextMenu` in the whole area** (multi-modal criterion) → adoption pass
4. **Destructive confirmations without counts/pluralization** (Notebooks, Parts, Warehouse, People, Sync) → count-interpolating confirm helper
5. **`LoadState`/error surfacing inconsistency** + filter-bar contract (Reports Spending proves the drift) → shared LoadState + "filter bar must feed the query" contract tests

### 2c. Dimensions the auditors missed (critic; queued as future audit passes)
Cross-area entity consistency (same job status = same color everywhere) · pagination/data-volume behavior · Dynamic Type XXL layout (fixed 22/26pt numeric columns) · localization discipline · first-run zero-data states · sync-merge-while-sheet-open interaction.

## 3. The Plan

**Wave 1 (this session):** the two functional data bugs (conflict apply, checklist contract), the shared craft kit foundation (`rowAccessibility` + `dsMinTapTarget`), proof-of-adoption on the worst offenders (Fleet pre-trip, Office approvals), Dashboard dup-identifier, panel edge fix (done, 7f280bf9). Build + tests green → main.
**Wave 2 (tracked in #1418):** remaining functional bugs (break-bonus edit, clock-in note, spending filter, unreachable approve sheet, dead code); area adoption passes for the kit (Orders/Settings/Fleet first — the grep-zero areas); destructive-confirm helper + adoption; Orders context menus.
**Wave 3 (tracked):** LoadState consolidation, filter-bar contract tests, legend/mode-banner shared components, then the critic's missed dimensions as their own audit rounds (Dynamic Type XXL, first-run states, cross-area consistency).

**Method for adoption passes:** per-area PRs using the shared kit, each with contract-pin tests (real invariants, not string-scans — see the stale source-scan repairs in 7f280bf9), Copilot-reviewed per repo policy.

## 4. Status

- [x] Audit (19-agent workflow, all areas)
- [x] Plan (this document)
- [x] Wave 1 implementation — see commits on `claude/fervent-rhodes-03a6e8`
- [x] Landed on main (build + affected tests green)
- [ ] Wave 2 (#1418) · Wave 3 (#1418)
