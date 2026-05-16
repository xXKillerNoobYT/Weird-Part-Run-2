# WEI-1361 Multi-User Verification UI Fixture

Deterministic multi-user verification fixture states are gated behind UI-test launch args.

## Base fixture args

Use these on iOS UI-test launches:

- `-UITesting`
- `-UITestingMultiUserVerificationFixture`

What this seeds:

- Warehouse discrepancy row for `UITest Verification Part` (system 12 vs counted 9) so manager flow can open **Send for Verification**.
- Multi-user audit session with seeded assignments.
- `UITest Owner` has at least one pending **My Verifications** assignment (populated state).

## Deterministic forced-error args

Add one of these when you need an exact inline error copy state:

- `-UITestingMultiUserVerificationForceDuplicateSubmit`
  - Submit Verification sheet shows: `You've already submitted a count for this part. Each counter can submit once.`
- `-UITestingMultiUserVerificationForceNoEligibleUsers`
  - Send for Verification sheets show: `No eligible active users are available to assign verification counts.`
- `-UITestingMultiUserVerificationForceAlreadyFlagged`
  - Send for Verification sheets show: `This part is already flagged for verification in the current audit session.`

## Empty-state coverage

- Launch with `-UITesting` only (omit `-UITestingMultiUserVerificationFixture`) for empty **My Verifications**.

## Smoke command

Example command that reaches a populated GH#486 state:

```bash
xcodebuild test \
  -project "Weird Parts IOS/Weird Parts.xcodeproj" \
  -scheme "Weird Parts IOS" \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:"Weird PartsUITests/Weird_Parts_IOSUITestsLaunchTests/testLaunchShowsDashboardWhenUITestingFlagPresent"
```

Then relaunch the same target with:

- `-UITesting`
- `-UITestingMultiUserVerificationFixture`

and navigate to Warehouse Audit -> My Verifications to validate populated fixture state.
