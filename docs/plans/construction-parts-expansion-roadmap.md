# Construction Parts Expansion and Integration Roadmap

> **For Hermes/Paperclip:** Use this as the product/UX routing plan for GitHub #645 / Paperclip WEI-1984. Do not treat future-trade or integration ideas as beta blockers unless a linked implementation issue explicitly narrows them into beta-safe work.

**Goal:** Split the Omi construction-parts intake into beta-safe lanes: electrical-first phase 1 now, trade expansion later, integrations last.

**Architecture:** Keep the current trade-neutral parts, jobs, warehouse, stock, receiving, audit, and ordering model as the foundation. Phase 1 should express "electrical" through seed data, templates, examples, labels, help copy, and workflow validation rather than creating electrical-only schema or navigation. Future trades and integrations should plug into stable domain seams after the core warehouse/job workflows are reliable.

**Tech Stack:** Swift/SwiftUI iOS app, shared Swift core package, GRDB/SQLite, local-first/offline-first data model, Paperclip/GitHub issue routing.

---

## Source links

- GitHub product tracker: https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/645
- Obsidian product note: `/Users/IA/Documents/Obsidian Vault/01_projects/Weird-Part-Run-2/Plans/Omi Intake - Construction Parts App and Company Context.md`
- Obsidian frontend handoff note: `/Users/IA/Documents/Obsidian Vault/01_projects/Weird-Part-Run-2/Plans/Omi Intake - Frontend Humane Review Handoff.md`
- Obsidian intake note: `/Users/IA/Documents/Obsidian Vault/Paperclip/Omi to GitHub and Paperclip intake.md`
- Related canonical implementation trackers:
  - GitHub #638 / Paperclip WEI-1981 — stock movement type centralization across UI flows.
  - GitHub #599 / Paperclip WEI-1937 — warehouse clock-in/out, only reopen/file fresh work with new regression evidence.
  - Paperclip WEI-1956, WEI-1848, WEI-1876 — launch/humane-review/frontend blockers.

## Omi intake update (2026-05-22)

- Keep this roadmap and GitHub #645 as planning/intake routing, not as a single execution epic.
- The clearest product theme from Omi intake remains split into this dedicated roadmap and associated frontend handoff note.
- Confirmed duplicates remain tracked in existing issues: #638 (stock movement centralization) and #599 (warehouse clock-in/out).
- No personal Obsidian TODOs were created for project-agent execution work from this intake pass.

## Non-goals for current beta

- Do not add plumbing/general-contractor-specific tables before electrical workflows are proven.
- Do not start maps/search/external-app integrations before launch stability and core construction workflows are usable.
- Do not duplicate #638 stock movement work or #599 clock-in/out work.
- Do not turn this roadmap into a broad implementation epic with unowned work; split only beta-safe, concrete deltas.

## Lane 0 — Beta guardrails and dedupe

**Purpose:** Keep GH #645 as a product roadmap and prevent planning work from stealing focus from launch readiness.

**Current decision:** No new beta blocker was found during this UX planning pass. Existing launch/implementation owners remain the right path.

**Routing rules:**

1. If the issue is about stock movement labels, picker choices, validation, or movement history presentation, route to GitHub #638 / WEI-1981.
2. If the issue is about clock-in/out state, warehouse clocking, or job attendance flow, route to GitHub #599 / WEI-1937 unless there is fresh regression evidence.
3. If the issue is about whether a construction worker can understand a screen during humane review, route to WEI-1956 or the relevant frontend launch blocker.
4. If the issue is about schema/data model neutrality, route to CTO/backend only after a concrete screen/workflow proves the current trade-neutral model cannot represent the needed data.
5. If the issue is about external integrations, hold it in this roadmap until core app stability and user workflow evidence exist.

## Lane 1 — Electrical-first phase 1

**Purpose:** Make the app feel like it is for electrical construction without narrowing the database into an electrical-only product.

**Beta-safe scope:**

- Electrical examples in onboarding/help copy.
- Electrical seed/template candidates such as common part categories, storage examples, receiving examples, job box examples, and quick-log examples.
- Construction-worker-facing labels that clarify: current job, current location/clock state, movement type, source location, destination location, and end-of-day/job questions.
- UX review of warehouse, receiving/sorting, movements, staging, audit, inventory grid, orders/procurement, and job usage flows using electrical scenarios.

**Implementation posture:** Prefer data/copy/templates over schema changes. A backend audit already found the current Swift/GRDB model mostly trade-neutral: parts hierarchy, jobs, stock movements, warehouse/truck/trailer storage, suppliers, pricing, receiving, and purchase-order seams do not require electrical-only tables.

**Done when:**

- A reviewer can walk through an electrical construction scenario and understand where parts are, what movement is being performed, which job is affected, and what should happen next.
- Any discovered UI deltas are filed under specific existing trackers instead of broad roadmap work.
- No electrical-only schema is introduced without evidence that templates/copy cannot solve the workflow.

## Lane 2 — Core construction workflows before expansion

**Purpose:** Stabilize the workflows that make the app useful for construction companies regardless of trade.

**Core workflow order:**

1. App launch and humane review path.
2. Warehouse clock-in/out and job context clarity.
3. Stock movement type centralization (#638 / WEI-1981).
4. Receiving/sorting: supplier delivery, job return, damaged/wrong/used condition checks, and routing to shelf/staging/returns.
5. Staging/job boxes: physical boxes, job labels, verification, and no destructive clear-without-movement behavior.
6. Audit/inventory grid: physical count, shelf/bin clarity, and confidence/certainty feedback.
7. Procurement/wishlist/forecasting: demand grouping, supplier decisions, internal movement before external order.

**UX acceptance for each workflow:**

- The user can answer "where am I?" and "what job/location am I affecting?"
- The movement or data change has a visible source and destination.
- Dangerous actions have confirmation or reversible status.
- Empty/error states explain what to do next in construction language.
- The workflow can be tested offline/local-first.

## Lane 3 — Future trade expansion

**Purpose:** Prepare for plumbing and other trades without implementing them prematurely.

**Hold until:**

- Electrical phase 1 has enough humane-review feedback to prove the core flow.
- At least one non-electrical reviewer or domain source provides concrete differences, not just a generic desire to support more trades.
- The difference cannot be represented as seed data, categories, templates, labels, or optional metadata.

**Likely future seams:**

- Trade taxonomy: electrical, plumbing, HVAC, general contractor, etc.
- Trade-specific default categories/templates.
- Trade-specific condition/routing questions, if evidence shows they differ.
- Optional vertical metadata attached to parts/categories/jobs, not a rewrite of stock/jobs/warehouse.

**Not beta blocking:** Plumbing/company integration ideas, multi-trade marketing, and non-electrical defaults.

## Lane 4 — Integrations and external surfacing

**Purpose:** Connect the parts app with other tools only after the core local workflow is trustworthy.

**Potential integration families:**

- Import/export add-ons for other construction/business tools.
- Search/map-style surfacing of useful job/parts context.
- Supplier catalogs, supplier portals, and purchase-order acknowledgments.
- Reporting/dashboard outputs for office workflows.

**Hold until:**

- Core app can launch reliably and pass humane review.
- Movement, receiving, staging, audit, and procurement semantics are stable.
- The integration has a named target app/API/workflow and a clear offline-first fallback.

**Integration acceptance gate:** Every integration candidate must answer: what data crosses the boundary, who owns conflicts, what happens offline, and which current workflow becomes easier.

## Recommended owner routing

| Lane | Owner | Paperclip/GitHub routing |
| --- | --- | --- |
| Beta guardrails/dedupe | CTO + UXDesigner | GH #645 / WEI-1984 comments |
| Electrical phase-1 UX/copy/templates | UXDesigner + FrontendCoder | File child only for concrete screen/copy/template delta |
| Stock movement consistency | FrontendCoder | GH #638 / WEI-1981 |
| Warehouse clock/job state | BackendCoder/FrontendCoder as applicable | GH #599 / WEI-1937, only with fresh evidence |
| Launch/humane review | FrontendCoder/UX | WEI-1956 / WEI-1848 / WEI-1876 |
| Trade expansion | CTO + Product/UX | Future child after evidence |
| Integrations | CTO/backend first, UX second | Future child after target integration is named |

## Concrete follow-up decision

No new immediate implementation issue is required from this planning pass.

Reasoning:

- Stock movement centralization already has GH #638 / WEI-1981.
- Clock-in/out already has GH #599 / WEI-1937.
- Launch/humane-review work already has WEI-1956 / WEI-1848 / WEI-1876.
- Backend/data audit already found no safe immediate schema change for GH #645.
- Electrical phase 1 can begin as UX validation, copy, and seed/template recommendations during existing humane-review work.

Create a new implementation child only if one of these concrete deltas appears:

1. A specific screen needs electrical construction copy/help/examples and is not covered by an existing frontend issue.
2. A specific seed/template pack is ready to implement with exact categories/examples.
3. A specific non-electrical trade requirement proves the current generic model cannot represent the workflow.
4. A named integration target is selected with API/workflow details and offline behavior.

## Review checklist for future agents

- [ ] Did you link back to GitHub #645 and this roadmap?
- [ ] Did you check #638 and #599 before filing a duplicate?
- [ ] Is the work beta-safe, or is it clearly parked for post-beta?
- [ ] Is electrical expressed through templates/copy/data before schema?
- [ ] Does the issue have a named owner lane?
- [ ] Does the issue include source evidence from Omi/Obsidian/GitHub/Paperclip?
