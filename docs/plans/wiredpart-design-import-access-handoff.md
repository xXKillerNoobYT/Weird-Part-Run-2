# WiredPart Design Import Access & Handoff Brief

**Paperclip:** WEI-5840 (child of WEI-5729)
**Status:** BLOCKED — source artifacts cannot be inspected through an approved, authenticated path
**Owner:** UXDesigner
**Review lane:** CEO product/priority decision → CTO implementation routing
**Date:** 2026-07-21

## Objective

Turn these supplied source artifacts into an implementation-ready WPR2 design handoff without inventing requirements:

1. `WiredPart.dc.html` — `https://claude.ai/design/p/d4ace6a6-ba25-40f5-9a9a-483452c9718c?file=WiredPart.dc.html`
2. `Panel Schedule Builder.dc.html` — `https://claude.ai/design/p/d4ace6a6-ba25-40f5-9a9a-483452c9718c?file=Panel+Schedule+Builder.dc.html`

## Access outcome (verified 2026-07-21)

- Both URLs open in the approved browser tooling only to Cloudflare's “Performing security verification” page. No artifact content, frame, token, route, or export was exposed.
- The parent issue specifies the `claude_design` Anthropic MCP route. That route is not approved for this WPR2 work and was not used.
- A repository search found no checked-in `.dc.html` export or local copy of either supplied artifact.

### External unblock owner and exact action

**Isaac / local Paperclip board:** attach or link read-only, authenticated exports of both exact `.dc.html` files to WEI-5840, or provide an approved browser-accessible read-only artifact URL that bypasses the Cloudflare challenge for the authorized WPR2 account. The material must preserve screens, component/state variants, and annotations. Do not substitute a prose summary.

Until that action occurs, no visual parity requirement, colors, geometry, copy, or interaction detail may be inferred from the inaccessible imports.

## Confirmed WPR2 implementation surfaces

This is an iOS-first SwiftUI application. “Desktop” below means the supported Mac Catalyst / wide-window presentation, not a separate web implementation.

| Scope | Existing source of truth / likely implementation surface | What is known now |
|---|---|---|
| Shared design tokens | `Weird Parts IOS/Weird Parts IOS/DesignSystem/Tokens/{Spacing,Typography,SemanticColors,CornerRadius,Elevation}.swift` | Reuse existing DS tokens; do not introduce raw visual values from an unavailable artifact. |
| Shared loading state | `Weird Parts IOS/Weird Parts IOS/DesignSystem/Components/LoadingState.swift` | `DSLoadingState` provides centered progress plus an accessible loading label. |
| Shared empty state | `Weird Parts IOS/Weird Parts IOS/Shared/EmptyStateView.swift` | Existing state supports primary/secondary/help actions and 44pt action labels. Category-specific guidance is governed by `docs/plans/empty-state-help-link-taxonomy.md`. |
| Shared error state | `Weird Parts IOS/Weird Parts IOS/Shared/ErrorStateView.swift` | Existing state provides a user-facing error message and optional retry. |
| Panel Schedule Builder | `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/PanelScheduleBuilder.swift` | Existing in-app reference for the owner-approved quality bar: validation before save, visible recovery, 44pt targets, accessibility, gesture alternatives, multi-modal actions, adaptive colors, and iPad-safe export/print behavior. |
| Panel entry point | `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/IOSNotebookDetailPage.swift` | Existing route that opens the builder and persists its schedule. |

## Scope boundary: shared state system vs. imported designs

### In scope once artifacts are available

- Compare each imported artifact’s named frames, component variants, and interaction states against the surfaces above.
- Record an explicit route-to-artifact mapping and identify whether each change is a shared primitive, Panel Schedule Builder behavior, or a page-level adoption task.
- Write an implementation-ready, source-backed spec and route it through CEO review before CTO creates an engineering task.

### Explicitly not yet specified

- Any product-screen redesign outside the state primitives and Panel Schedule Builder reference surface.
- New tokens, type scale, colors, icons, layout geometry, or copy sourced only from the names of inaccessible files.
- Product code, design-system code, or an engineering implementation issue.

## Design requirements that are already established (not imported-artifact claims)

These are project standards and remain the floor for any eventual implementation:

1. **State separation:** loading must not flash an empty state; an empty state is rendered only after a successful zero-result load; an error is visibly distinct and exposes Retry when retry is safe.
2. **Empty-state taxonomy:** primary lists use page-level Help; wizard states use action-oriented inline guidance; picker/modal states name the source page; errors/not-found use recovery rather than generic help. See `docs/plans/empty-state-help-link-taxonomy.md`.
3. **Accessibility:** interactive controls require sentence-quality label, value where state varies, hint where action is not self-evident, and a stable accessibility identifier. Color cannot be the sole carrier of meaning. Drag interactions require a named non-drag alternative.
4. **Interaction recovery:** validation happens before persistence; rejected or failed actions remain visibly failed rather than appearing to succeed. Destructive actions use a cancel path and an accurate consequence/count.
5. **Design-system discipline:** adopt existing `DS` spacing, semantic colors, typography, corner radius, elevation, and craft-kit primitives before adding a new pattern.

## Required state behavior for the future handoff

The imported-artifact review must classify every affected screen/variant into these states, not merely an ideal populated frame:

| State | Required behavior |
|---|---|
| Loading | Show `DSLoadingState` or an approved source-backed equivalent; announce loading accessibly; prevent a stale empty state from appearing before the fetch settles. |
| Empty — first use | Explain what is absent and the concrete next action. A primary action must be available when the user has permission; otherwise state the prerequisite/source page. |
| Empty — filtered/search | Distinguish “no matching results” from “no records yet”; retain reset/clear-filter affordance where filters caused the result. |
| Error | Explain the failed operation in user terms, retain usable context where safe, offer Retry when retry is meaningful, and do not disguise failure as no results. |
| Success/populated | Preserve source-backed hierarchy and affordances; confirm persistence/success through visible feedback where the action is not immediately self-evident. |
| Permission/unavailable | State capability and remediation without implying the user can complete a restricted action; do not present a dead primary action. |

## Viewport, platform, and accessibility evidence plan

A future implementation is not approvable without rendered evidence for all applicable variants:

| Variant | Minimum verification |
|---|---|
| Desktop / Mac Catalyst wide window (>=1280×800) | Full hierarchy, non-truncated labels, no accidental mobile-only layout, keyboard/focus path, and no horizontal overflow. |
| iPad (768×1024 portrait and the artifact-required landscape state) | Adaptive layout, sheet/popover anchors, touch target sizes, and no clipped toolbars/grids. |
| iPhone (375×812) | Core task without horizontal overflow; labels/action controls remain discoverable above keyboard and safe areas; no drag-only core action. |
| Accessibility | VoiceOver labels/value/hints/identifiers; reading/focus order; 44pt targets verified as real controls; Dynamic Type at an accessibility size; non-color status signaling; Reduce Motion behavior where motion is introduced. |

Required visual/source evidence after access is unblocked:

1. Annotated comparison of each imported source frame to the WPR2 route/component it governs.
2. Before/after screenshots or UI-test capture for desktop, iPad, and iPhone at the same named state.
3. User-like verification: tap/type/open/close/retry/save/cancel as applicable, then inspect accessibility semantics after the interaction.
4. A source-reference table with exact artifact frame name/URL or export page plus the corresponding WPR2 path.

## Acceptance criteria for the implementation-ready handoff

The handoff may be sent to CTO only when all items are true:

- [ ] Both exact design exports are accessible and cited.
- [ ] Every proposed affected route/screen is named with its primary user goal.
- [ ] Empty, loading, error, success, filtered-empty, and permission/unavailable behavior is named for each affected surface.
- [ ] Each behavior has an accessibility requirement and desktop, iPad, and iPhone expectation.
- [ ] Existing design-system primitive reuse is identified; any new primitive has a source-backed rationale.
- [ ] The design source/reference table and expected evidence are attached to the GitHub issue.
- [ ] CEO has approved product intent and priority.
- [ ] A GitHub issue exists before a separate CTO engineering issue is created, and both issues cross-link to WEI-5840.

## GitHub traceability

- **Existing related umbrella:** GitHub [#1421](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/1421), “Panel-quality uplift Waves 2-3,” is the current project-level quality-bar reference. It is not sufficient to claim parity with either inaccessible artifact.
- **No implementation issue created:** creating an engineering issue now would invent visual scope and violate the access constraint.
- **Precise future GitHub proposal, after source access:**
  - Title: `[Design][UX] Reconcile approved WiredPart design imports with shared state components and Panel Schedule Builder`
  - Body must include: `Tracked in WEI-5840`; both source export references; route/frame mapping; state matrix; accessibility/viewport acceptance criteria; screenshot/evidence checklist; CEO-approved product intent; and a `Refs #1421` link.
  - Labels: `ui`, `enhancement`, and CEO-selected priority.
  - Only after this GitHub issue exists and CEO approves the design brief may CTO receive a separate implementation task.

## Next action

Remain blocked pending Isaac/local-board’s exact export/access action. On receipt, UXDesigner will inspect the sources, replace this blocker brief’s “not yet specified” sections with source-backed requirements, request CEO product/priority confirmation, and then prepare GitHub-first CTO routing.
