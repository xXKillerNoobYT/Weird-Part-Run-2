# People PIN confirmation — issue #1881

## Status

Implementation slice approved 2026-08-31. This plan is limited to GitHub issue
#1881 and does not choose or change administrator reset, lockout recovery, hat,
or multi-admin policy.

## User experience

### Add employee

- Keep the existing display name, PIN, email, and phone form.
- Add a second secure field labelled **Confirm PIN**.
- Before creating the employee, require a 4–8 digit PIN and an exact matching
  confirmation.
- Show validation inline next to the PIN fields. The message describes the
  correction without displaying either PIN.

### Current user's account

- Make the existing profile row at the top of the user menu open an **Account**
  page. This is a focused entry point only; the rest of the settings layout is
  unchanged in this slice.
- The Account page shows the signed-in user's existing profile summary and a
  Change PIN form with **Current PIN**, **New PIN**, and **Confirm New PIN**.
- Validate confirmation locally, then call the existing
  `AppCore.changePin(userId:oldPin:newPin:)` path. `AuthService.changePin`
  remains responsible for verifying the current PIN and writing the new hash.
- On success, clear all PIN fields and show a non-secret confirmation message.
- On failure, show the existing user-friendly authentication error without
  adding PIN values to logs, analytics, screenshots, or error text.

## Shared validation contract

Both forms use one pure `PINConfirmationValidator`:

1. A new PIN is required.
2. It contains 4–8 digits.
3. A confirmation is required.
4. The confirmation exactly matches the new PIN.
5. Self-service change additionally requires the current PIN.

Validation errors contain only fixed copy. They never interpolate submitted
values.

## Boundaries

- No administrator PIN reset or account-recovery flow.
- No changes to PIN hashing, database encryption, lockout rules, or sessions.
- No employee hat, permission, status, or creation-authorization changes.
- No movement of device/company settings and no user-switching implementation.

## Verification

- iOS unit tests: matching PINs, mismatch, missing confirmation, and missing
  current PIN.
- Core service tests: wrong current PIN preserves the old credential; successful
  change rejects the old PIN and accepts the new PIN.
- Focused iOS test target and focused core test filter.
- Tracked iOS scheme build.
