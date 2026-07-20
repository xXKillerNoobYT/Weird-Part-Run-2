# AI Page Context Coverage

Issue: GitHub #86 / WEI-4424 / WEI-5278
Updated: 2026-07-19

## Verified inventory baseline

The old “87 pages” estimate is retired. The machine-checkable source of truth is
`docs/testing/ai-page-context-inventory.json`, checked against both the live
`AppTab` declarations in `NavigationConfig.swift` and the explicit deep/alias
registry in `IOSContentRouter.swift`. A bounded canonical non-router registry
also source-checks concrete detail/page presentations reached through
`NavigationLink`, `navigationDestination`, `sheet`, and `fullScreenCover`.

Current verified inventory:

- 89 navigable `AppTab` destinations;
- 157 total inventory rows after router-owned deep/alias screens, dedicated deep screens, 15 explicit inherited details/drill-downs,
  one retired compatibility screen, and the non-feature placeholder are included;
- 26 canonical non-router source presentations, including documented transient/shell exemptions;
- 68 dedicated page-context rows;
- 72 router-owned rows;
- 15 inherited rows;
- 1 retired row;
- 1 not-user-facing row;
- 0 unresolved `gap` rows.

Every inherited, retired, not-user-facing, and Help exemption row includes an
existing source path and rationale. Aliases resolve to the same canonical screen
row instead of inflating the count.

## Coverage contract

Dedicated screens own a page-specific, read-only summary. The verifier requires
their active/inactive notification pair to be declared, posted by the cited
source, observed by the assistant, cleared on inactivity, and mapped to a real
`HelpContentRegistry` entry.

Router-owned screens use `routePageActive` / `routePageInactive` from
`IOSContentRouter`. This payload contains only module label, page label, route,
and page ID. It deliberately excludes credentials, private notes, raw records,
database dumps, and mutation/action identifiers. The router reposts on route/tab
changes and responds to `requestCurrentPageContext` when the assistant opens
after the screen's original appearance event.

The assistant tracks the active route path so a late inactive event from an old
router cannot clear a newer screen. Route identity is retained as fallback while
dedicated deep/sheet identity takes precedence; a Help-triggered route refresh
therefore cannot replace the visible deep screen, and its inactive event reveals
the parent route again. Route and dedicated context are cleared on page
disappearance and by the existing logout lifecycle reset. Existing
page-specific search/filter/tab/data reposts remain guarded by
`SearchablePageContextRegressionTests` and the focused freshness expectations in
`tests/static/test_ai_help_context_coverage.py`.

The dedicated Suppliers page uses an app-layer aggregate allowlist rather than
`PartsService.buildSupplierAIContext()`. Its context contains only total/active/
inactive/visible counts plus search-active, filter, and sort state. Supplier
names, record IDs, account identifiers, contact fields, delivery details,
scores/counts tied to one record, and free-form notes are excluded. A synthetic
sentinel boundary test and the coverage verifier prevent the full service dump
from being reconnected to the assistant.

Help remains local and read-only. Where canonical Help exists, the inventory row
names its exact `helpPageId`; where it does not, the row records that exemption
instead of inventing copy or silently mapping to unrelated help. Non-router
details with local PageHelpSheet copy intentionally inherit their containing
page identity today; Help → Ask AI still passes their visible detail copy.

## Permanent checks

Run from the repository root:

```bash
python3 scripts/verify-ai-help-context-coverage.py
python3 tests/static/test_ai_help_context_coverage.py
```

The verifier fails for:

- any current `AppTab` missing from the inventory;
- any explicit router path missing from the deep/alias registry, any stale registry
  path, or any registry page ID missing from the inventory (including a negative
  omission regression fixture);
- any canonical non-router destination whose presenting source/occurrence count
  drifts, whose disposition rationale is missing, or whose screen row is omitted
  (including a negative Vehicle Detail omission regression fixture);
- path drift or an unresolved `gap`;
- missing source/rationale/Help-exemption evidence;
- declaration, post, observer, inactive-clear, or Help-mapping drift on dedicated pages;
- missing router-owned active/inactive observation, current-route refresh, or logout clearing;
- Suppliers page aggregate-context or search/filter/sort freshness regressions.

## Scope boundary

This closure covers conversation resume regression safety, current-screen route
context, dedicated visible-state context, and Help integration. Preference
learning, proactive suggestions, generalized query logging/rate limits,
Windows/LM Studio/llama.cpp, mutation tools, and unrelated AI summaries remain
outside GitHub #86's focused closure PR.