# GitHub #86 — AI Conversation Memory, Page Context, and Help Closure

> Status: Approved technical execution baseline for WEI-5275 / parent WEI-4424
> Updated: 2026-07-19
> GitHub: #86
> Architecture: native iOS + shared Swift core only

## Objective

Close GitHub #86 with one bounded completion PR that proves the three capabilities named by the issue title:

1. authenticated-user-scoped conversation memory survives app/session lifecycle changes;
2. every current user-facing iOS page has an explicit AI page-context disposition; and
3. Help can hand visible, read-only page guidance to the assistant.

The PR must not reopen already-merged conversation/help architecture or absorb the broader AI roadmap from parent GitHub #65.

## Current architecture truth

- The active product is the native SwiftUI app in `Weird Parts IOS/` plus `WiredPartCore` in `core/`.
- AI uses Apple Foundation Models and local SQLite only. The retired React/Tauri, Windows, LM Studio, and `llama.cpp` designs are historical context and are not implementation targets.
- Conversation persistence and Help → Ask AI shipped through PR #1460 at merge commit `7293b4ad8`. The implementation scopes rows by authenticated owner, hydrates the Foundation Models transcript on resume, serializes Help/Clear/Resume/model lifecycle transitions, and fails closed without a valid user.
- `PageHelpSheet` exposes an accessible 44-point Ask AI action. Help handoff is local/read-only, uses canonical registry content when available, falls back to visible help content, and does not require a model call merely to open Help in the assistant.
- `scripts/verify-ai-help-context-coverage.py` currently reports 72 help entries, 69 registry mappings, and 69 assistant-observed page-active notifications with no broken mapping among the observed set.
- The remaining uncertainty is inventory completeness: the historical “87 pages” count is stale and cannot be treated as proof that exactly 18 notification pairs are missing.

## Scope decision

### In scope

- Build a deterministic inventory of current user-facing SwiftUI routes/screens.
- Give every inventory row one of these dispositions:
  - `dedicated`: the screen posts its own active/inactive context;
  - `router-owned`: a containing router posts context that accurately follows the selected child;
  - `inherited`: a detail/sheet intentionally uses a parent context and documents why that context remains correct;
  - `not-user-facing`: component, wrapper, preview, or implementation-only type;
  - `retired`: unreachable compatibility surface;
  - `gap`: user-facing screen that needs new context coverage.
- Implement every `gap` required for GitHub #86 closure, including context refresh after visible search/filter/tab/data state changes.
- Extend the permanent verification script/test so future route additions fail when they lack an explicit disposition, notification observation, or Help mapping where Help exists.
- Update `docs/testing/ai-page-context-coverage.md` from the stale count narrative to the verified inventory.
- Re-run the existing conversation persistence and Help-resume regression suites to prove the closure PR does not regress already-merged contracts.

### Explicitly out of scope

The following broad roadmap items remain under GitHub #65 or their dedicated issues and do not block #86 after this plan is implemented:

- preference learning;
- proactive suggestions;
- AI summaries outside the already-shipped job-detail behavior;
- anomaly detection and predictive ordering;
- new mutation tools;
- generalized AI query logging and the historical “10 requests/minute” server limit.

Those items need separate product/privacy acceptance criteria. This PR must not add behavioral profiling, cloud sync, external endpoints, or a new logging store. Existing fallback-persistence defects remain tracked independently by GitHub #1467, same-second ordering by #1464, and saved-load error handling by #1121.

## Safety contracts

- Page context is a minimal read-only summary of visible state. Do not include PINs, tokens, credentials, private notes, raw database dumps, or mutation/action identifiers.
- User-owned conversation rows remain isolated by `owner_user_id`; nil/non-positive users fail closed.
- Help handoff remains local and read-only. Any future write-capable AI action requires a separate confirmation-before-write design and issue.
- Context lifecycle must clear on page disappearance, logout, user change, conversation change, and assistant teardown so one user/page cannot contaminate another.
- Context freshness must follow user-visible search, filter, tab, selection, and loaded-data changes.
- No new telemetry or query logging is introduced in this closure slice. If logging or rate limiting is later added, it requires a privacy/redaction/retention plan and deterministic tests.

## Smallest safe PR boundary

One implementation PR may contain only:

- the route/page inventory and coverage verifier;
- missing page-context notification declarations, posts, observations, and Help mappings discovered by that inventory;
- focused regression tests;
- this plan and the updated coverage document.

The PR must not refactor the assistant architecture, add preference/proactive behavior, or change unrelated pages. Its body must include:

- `Closes #86`
- `Tracked in WEI-4424`
- `CTO child: WEI-5275`

## Dependency map and owners

1. **FrontendCoder — inventory + implementation + PR**
   - First commit/update the plan and deterministic inventory before changing runtime Swift.
   - Implement gaps, permanent guards, focused tests, and documentation.
   - Open the focused PR and hand its exact head to verification/review.
2. **UIExpertVerifier — user-like iPhone/iPad verification**
   - Validate Help → Ask AI, resume, representative dedicated/router-owned/inherited context transitions, accessibility labels/focus/hit targets, and stale-context clearing.
   - Desktop is explicitly excluded because the supported architecture is iOS-only; evidence is required on iPhone and iPad.
3. **SecurityAgent — privacy/data-loss review**
   - Review context minimization, owner isolation, lifecycle clearing, local-only Help behavior, confirmation-before-write boundary, logging absence, and rate-limit non-expansion.
4. **Independent review lane**
   - LocalFirstReviewer → GPTReviewer → ClaudeReviewer, serialized on the same exact head.
5. **CTO merge issue**
   - Created after the PR URL exists; blocked on implementation, QA, security, and all three review issues, then placed in the priority/age merge chain.

## Acceptance criteria

- A machine-checkable inventory covers every current user-facing iOS route/screen and contains no unresolved `gap` rows.
- Every dedicated page-active notification is declared, posted, observed, cleared, and mapped to canonical Help where Help exists.
- Router-owned and inherited dispositions include a concrete source path and rationale; they are not blanket exemptions.
- Search/filter/tab/data changes refresh context where they change what the user sees.
- Conversation persistence/resume tests pass, including owner isolation and clear/write ordering.
- Help handoff/lifecycle tests pass and user-like iPhone/iPad verification confirms the visible and accessibility flow.
- Privacy/security review finds no secret leakage, cross-user/page context bleed, silent data-loss regression, or implicit write path.
- The PR is current with `main`; local/Xcode and required GitHub checks pass on the final head; Copilot and independent reviewers have commented on that final head; all non-outdated threads are resolved.
- The PR is squash-merged, its branch is deleted, GitHub #86 is verified closed, and WEI-4424 receives links to the merge, tests, QA, reviews, and cleanup state.

## Required evidence

- `python3 scripts/verify-ai-help-context-coverage.py`
- focused inventory/page-context regression tests
- `swift test --filter FoundationModelsServiceTests` from `core/`
- focused iOS Simulator tests for AI Help/resume and new context guards
- generic iOS Simulator build through the local Mac/Xcode path
- exact-head GitHub required checks and unresolved-thread readback
- iPhone + iPad user-like QA notes

## Failure handling

- If a page cannot be safely classified, create a first-class blocker assigned to FrontendCoder/UXDesigner with the exact route and missing product decision.
- If context would expose sensitive data, block that row on SecurityAgent; do not add the payload first and review later.
- If Apple tooling or CI fails, record the local runner/service/check URL and exact command/log evidence in a dedicated CI blocker.
- If the inventory proves the remaining scope is not one coherent PR, split by route area and serialize children with real `blockedByIssueIds`; do not create parallel branches against a moving `main`.
