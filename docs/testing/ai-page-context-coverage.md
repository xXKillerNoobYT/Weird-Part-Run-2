# AI Page Context Coverage

Issue: GitHub #86 / WEI-4424 / WEI-5278
Updated: 2026-07-19

## Verified inventory baseline

The old “87 pages” estimate is retired. The machine-checkable source of truth is
`docs/testing/ai-page-context-inventory.json`, checked against the live `AppTab`
declarations in `NavigationConfig.swift`.

Current verified inventory:

- 89 navigable `AppTab` destinations;
- 111 total inventory rows after dedicated deep screens, one inherited detail,
  one retired compatibility screen, and the non-feature placeholder are included;
- 68 dedicated page-context rows;
- 40 router-owned rows;
- 1 inherited row;
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
router cannot clear a newer screen. Route and dedicated context are cleared on
page disappearance and by the existing logout lifecycle reset. Existing
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
instead of inventing copy or silently mapping to unrelated help.

## Permanent checks

Run from the repository root:

```bash
python3 scripts/verify-ai-help-context-coverage.py
python3 tests/static/test_ai_help_context_coverage.py
```

The verifier fails for:

- any current `AppTab` missing from the inventory;
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