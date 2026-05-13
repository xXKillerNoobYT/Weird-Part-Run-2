## Sync Conflict Banner Compact iPhone Fix — GitHub #410 / WEI-1054

Source: GitHub #410, captured during WEI-1016 QA on 2026-05-13.
Owner: UXDesigner.
Touches: `Weird Parts IOS/Weird Parts IOS/Sync/SyncConflictBanner.swift`, hosted by `Weird Parts IOS/Weird Parts IOS/Navigation/IOSMainView.swift`.
Coordinates with: GitHub #398 / WEI-1008 / WEI-1011 notebook layout work, but the banner lives in the app shell above all modules, so the fix is independent.

## Problem

On iPhone 13 mini (375×812, compact width) with the seeded sync conflicts and the Dynamic Type sizes exercised in the WEI-1016 capture, the "X sync conflicts auto-resolved" banner takes the top **~368 pt** of the screen. Source: `docs/testing/artifacts/wei-1016/iphone-rerun3-attachments/BC762C09-77CA-4B7D-92B7-F5C68DC4E27D.txt`:

- icon at `{{22.0, 185.7}, {28.7, 47.3}}` — image grows to 47 pt tall
- label at `{{64.7, 56.0}, {131.0, 306.3}}` — text wraps into a 131-pt-wide × 306-pt-tall column
- "Review" button at `{{235.0, 153.0}, {124.0, 112.3}}` — 124×112 pt tile
- Notebooks content begins at `y=368`, leaving ~444 pt before the tab bar / safe area, of which the navigation bar, search field, top tabs, and category chips already consume the bulk — only a single row of notebook content is visible.

Root cause: `SyncConflictBanner` is a single `HStack` containing an SF Symbol image, an unbounded `Text`, a `Spacer`, and a bordered `Button`. None of the three sized children have caps. At large or AX Dynamic Type sizes, the icon and the button both grow vertically, and the label wraps to a narrow column because it loses the horizontal contest with the two scaled neighbors.

## Goals

- Preserve conflict visibility — the banner must remain unmissable when unreviewed conflicts exist.
- Restore notebook task completion on compact widths at all Dynamic Type sizes, including AX1–AX5.
- Make "go review" the primary action, with one obvious target instead of three competing children.
- Stay within DS tokens and existing accent (orange) treatment.

## Non-Goals

- Auto-dismiss or hide the banner — must remain visible until conflicts are reviewed.
- Move to a toast/snackbar — sync conflicts are persistent state, not an event.
- Redesign the conflict review sheet itself (`SyncConflictReviewPage`).

## Design

### Layout (one tappable surface)

- Drop the inner `Button("Review")`. Wrap the whole banner in a `Button { onReview() }` with `.buttonStyle(.plain)` so the entire ~44 pt strip is the action target.
- Add a trailing `chevron.right` (caption, `.opacity(0.6)`) as the affordance.
- Cap the icon: `Image(systemName: "arrow.triangle.merge").imageScale(.small).font(.subheadline)` — keeps it ~16 pt across sizes.
- Cap the label: `.font(.subheadline)`, `.lineLimit(2)`, `.minimumScaleFactor(0.85)`, `.truncationMode(.tail)`.
- Use `@ScaledMetric` for vertical padding (base `6`, max `10`) so the banner stays 44–80 pt tall instead of running to 360 pt.
- HStack `spacing: 8`, `alignment: .firstTextBaseline`.
- Container padding: `.padding(.horizontal, 16)`, `.padding(.vertical, scaledPad)`.

### Copy

- Short form (default):
  - 1 conflict: "1 conflict auto-resolved — Review"
  - n > 1:    "{n} conflicts auto-resolved — Review"
- VoiceOver label (override): "{n} sync conflicts auto-resolved. Double-tap to review."
- The trailing word "Review" inside the label is acceptable because the whole row is the button; no nested button needed.

### Color / Surface

- Background: `Color.orange.opacity(0.12)` strip (current value is `.opacity(0.1)`; bump 2% for AA contrast against the system grouped background).
- Border-top hairline `Color.orange.opacity(0.35)` (1 pt) so the banner reads as a strip even when scrolled content butts against it.
- Icon tint: `.orange`. Label `.primary`. Chevron `.secondary`.
- No state where color alone communicates conflict — the count + word "conflict" carry meaning.

### Dynamic Type behaviour

- xSmall–xxxLarge: single line of label.
- AX1–AX2: label wraps to 2 lines with `minimumScaleFactor(0.85)`.
- AX3–AX5: the visual row caps at `xxxLarge` Dynamic Type while the button keeps the full accessibility label. The label remains 2 lines max, padding scales via `@ScaledMetric` up to 10 pt, and the chevron hides above `.xxLarge`. The whole row remains tappable.
- Predicted maximum banner height across all DT sizes: **~80 pt**, down from **368 pt**.

### Accessibility

- Single accessibility element: the outer SwiftUI `Button` owns the accessibility node, decorative children are hidden, and the button overrides label/hint so VoiceOver announces the conflict summary as one action.
- 44 pt minimum tap height via `.contentShape(Rectangle())` and `@ScaledMetric` min height.
- `accessibilityIdentifier("syncConflictBanner")` for UI tests.

### States

- **Hidden** (default): `unreviewedConflictCount == 0` — banner does not render. Identical to today.
- **Single conflict**: copy "1 conflict auto-resolved — Review".
- **Multi conflict**: copy "{n} conflicts auto-resolved — Review".
- **Loading**: no separate loading state needed. `unreviewedConflictCount` is read from the manager and updates reactively.

### Below the banner

No changes required to `IOSMainView`'s VStack composition. The banner remains the top child of the shell `VStack(spacing: 0)`, and module navigation flows below it.

## Acceptance Criteria

1. With one or more unreviewed conflicts, the banner is rendered at the top of every module and never exceeds **80 pt** total height on iPhone at any Dynamic Type size, including AX5.
2. Tapping anywhere on the banner opens the conflict review sheet (`activeRootSheet = .conflictReview`).
3. Notebook list rows are visible without scrolling at Default and Large Dynamic Type on iPhone 13 mini (375×812) with the banner present.
4. VoiceOver announces "{n} sync conflicts auto-resolved. Double-tap to review." as a single button element.
5. UI test selector `syncConflictBanner` exists and resolves to the tappable container.
6. At zero conflicts the banner does not render and contributes 0 pt height (regression guard).

## Verification

- Re-run the WEI-1016 banner capture path with seeded conflicts and capture the accessibility tree at:
  - Default DT, iPhone 13 mini
  - xxxLarge, iPhone 13 mini
  - AX3, iPhone 13 mini
  - Default DT, iPhone 17 Pro Max
- Compare measured banner height to the 80 pt budget.
- Place exported attachments under `docs/testing/artifacts/wei-1054/`.

## Handoff

This spec is paired with a same-heartbeat implementation against `SyncConflictBanner.swift`. If implementation lands cleanly, no engineering child issue is required. If the cap, scaled-metric padding, or AX layout reveals further regressions during QA, file an engineering follow-up under WEI-1054.

## References

- GitHub #410 (source bug).
- WEI-1016 capture artifacts: `docs/testing/artifacts/wei-1016/iphone-rerun3-attachments/`.
- Sibling work: GitHub #398 / WEI-1008 / WEI-1011 notebook layout. The banner sits above the notebook module and is independent of that work.
