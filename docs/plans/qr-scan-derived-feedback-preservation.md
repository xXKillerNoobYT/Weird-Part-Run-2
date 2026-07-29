# QR Scan Derived Feedback Preservation

## Scope and source direction

- GitHub tracker: #1442
- Paperclip implementation: WEI-4883
- Parent preservation classification: WEI-4869 under WEI-4864
- Integration base: PR #1441 (`hermes/hermes-205c3f48`)
- User-visible flow: the shared `QRScanSheet` used by Purchase Orders, Clock In/Out, and Warehouse Movement scanner entry points, including the manual fallback when camera scanning is unavailable.
- Existing UX direction: preserve PR #1441's loading, error, warning, success, not-found, cancellation, and accessibility presentation. This change introduces no new visual pattern.
- Backend contract: `QRAutoFillService.processQRScan(_:)` returns `QRAutoFillResult`, whose `isFound`, `entityType`, `fields`, and `code` values determine feedback and whether a matching result may complete.

## Design decision

Mismatch status is derived from the current result snapshot rather than stored independently. A `QRScanFeedback` value receives the current result's found flag, actual entity type, expected entity type, display title, and code. It produces both:

1. `typeMismatch`, used only to select warning versus ordinary result styling.
2. `message`, used unchanged by both visible status text and the accessibility status label.

This removes the mutable `@State typeMismatch` flag, which could drift from `resultIsFound`, `resultEntityType`, or `expectedType` during loading and retries. The rendered and announced copy therefore share one source of truth.

## Contract-stable feedback

The feedback message contract remains:

- Found wrong type: `Expected <expected raw value>, got <actual raw value>`.
- Found matching type: `Found: <title>`.
- Not found: `Not found: <code>`.

The executable preservation case is a found `.job` result when `.po` is expected. It must classify as a mismatch and emit exactly `Expected po, got job`.

## State behavior preserved

- Loading continues to clear stale result fields, show and announce `Looking up…`, and disable Look Up.
- Scan errors continue to take precedence over result feedback.
- Not-found results remain retryable and retain their code in the message.
- Matching found results continue through the existing duplicate-delivery gate, dismiss once, and invoke the callback once.
- Wrong-type results remain visible as orange warnings and do not dismiss. Repeated camera delivery of the same found mismatch is suppressed until a different payload is accepted, preventing lookup and announcement churn while the code remains in frame.
- Return-key submission and both Look Up buttons share the same manual-entry gate: blank input and submissions made while a lookup is active are ignored without clearing the typed code.
- Cancel continues to dismiss without invoking the callback.
- Camera support and scanner lifecycle behavior are unchanged.

## Current-head review disposition

- Completion ordering and duplicate suppression move to focused runtime helpers/tests. One normalized source-shape assertion remains for the actor-isolation compiler regression that requires the view call site to enter `MainActor.run`.
- The not-found/title fallback finding is rejected as already covered by the service contract: `QRAutoFillResult.code` is non-optional, and the title derivation ends in `?? result.code`. A code-only not-found response therefore always stores both a title and result code and renders `Not found: <code>`.
- Found results, including wrong-type results, record the last accepted found payload. Only the immediately repeated found payload is suppressed; accepting another payload clears that suppression. Not-found and failed lookups remain retryable.
- A found external catalog result has no `entityType`. When a caller requires a specific type, the feedback treats that nil type as a mismatch (`Expected <type>, got external`) so warning presentation and auto-completion use the same rule.
- The delivery gate owns a terminal cancellation state. Cancel and sheet disappearance enter that state before dismissal cleanup; an in-flight lookup can release no completion after cancellation, and later scanner events cannot claim the gate. The gate, manual-submission helper, feedback helper, and nested settings hydration entry are explicitly nonisolated/Sendable where appropriate so detached executor checks cannot recreate the MainActor crash class.

## Portable source-contract fixture

The remaining source-shape assertions must execute on a physical iPhone/iPad without trying to open the build machine's checkout path embedded by `#filePath`. The iOS test target therefore has a deterministic build phase that copies the current production `QRScanSheet.swift` from `$(SRCROOT)` into the test bundle as `QRScanSheetSource.txt`. `QRScanSheetRegressionTests` reads only that bundle resource. This keeps the fixture synchronized with the exact compiled checkout while avoiding any developer- or worktree-specific absolute path at test runtime.

## Acceptance and verification

- `QRScanSheet` contains no mutable `@State typeMismatch`.
- Visible and accessibility result copy both consume the same `QRScanFeedback.message`.
- `QRScanSheetRegressionTests` executes the `.job`/`.po` mismatch and exact-message assertion.
- Runtime regressions prove completion callback ordering, in-flight manual-submit rejection without input loss, matching completion deduplication, consecutive found-mismatch suppression, and not-found/failure retryability.
- Runtime regressions prove a cancel/disappear transition suppresses an already-claimed result callback and detached execution can use the pure QR helpers plus settings hydration error descriptions safely.
- The focused iOS test bundle contains `QRScanSheetSource.txt`, and the 14-test QR/MainActor suite passes on physical iPad without checkout-path failures.
- Focused regression tests pass on the local Mac.
- `git diff --check` passes, and the committed worktree is clean.
- Patch remains limited to the scanner, focused regression/isolation tests, settings nested error isolation, the test-target fixture build phase, and this plan.
