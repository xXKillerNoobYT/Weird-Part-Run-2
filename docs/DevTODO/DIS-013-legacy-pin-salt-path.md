---
source: dev-improvement-scanner (2026-04-06)
severity: Medium
category: Security — Legacy PIN Verification Path
status: open
github_issue: PENDING — needs manual filing (gh unavailable in scheduled run 2026-04-06)
---

# DIS-013: Legacy Single-Salt PIN Hash Path Permanently Reachable

## Problem

`AuthService.verifyPinLocally()` falls through to `legacyHashPin()` for any user with
`pin_salt IS NULL` (i.e., any account that hasn't logged in since migration 023):

```swift
// AuthService.swift:643-658
static func verifyPinLocally(pin: String, storedHash: String, salt: String?) -> Bool {
    if storedHash.hasPrefix("$2b$") || storedHash.hasPrefix("$2a$") {
        return false
    }

    if let salt {
        let computed = hashPin(pin, salt: salt)       // ← good: per-user salted
        return computed == storedHash
    } else {
        let computed = legacyHashPin(pin)             // ← problem: hardcoded "wiredpart" salt
        return computed == storedHash
    }
}

// AuthService.swift:672-676
private static func legacyHashPin(_ pin: String) -> String {
    let data = Data((pin + ":wiredpart").utf8)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
```

`legacyHashPin` uses a single hardcoded app-wide salt (`"wiredpart"`). This means:
- All legacy-format hashes have the **same salt** — rainbow tables can be computed once and applied to ALL legacy accounts.
- Brute-forcing any one account's PIN also cracks all accounts with the same PIN.
- Users who never log in again stay permanently on this weaker path.

## Context

- Migration 023 added per-user salts. Existing accounts keep the old hash until next login.
- The intent was: verify old hash → re-hash with new salt on success → migration complete.
- The problem: "next login" may never happen for inactive accounts. There's no deadline.
- The plan mentions this as a "known migration path" — it is, but there's no enforcement.

## Suggested Fix

**Option A — Force-reset PIN on next login for stale accounts (recommended):**

When `pin_salt IS NULL`, instead of verifying with the legacy hash:
1. Verify with the legacy hash (for this one time)
2. If valid, immediately re-hash and save with new salt
3. If the user never logs in, flag the account as "requires PIN reset" after N days

```swift
// In the login flow (after verifyPinLocally succeeds on legacy path):
if user.pinSalt == nil {
    let newSalt = generateSalt()
    let newHash = hashPin(pin, salt: newSalt)
    try db.execute(
        "UPDATE users SET pin_hash = ?, pin_salt = ?, updated_at = ? WHERE id = ?",
        arguments: [newHash, newSalt, now, user.id]
    )
}
```

**Option B — Set a migration deadline:**

After a fixed date (e.g., 90 days after migration 023 shipped), reject logins for `pin_salt IS NULL` accounts and show: "Your PIN needs to be reset. Please contact your administrator."

## Why Auto-Fix Was Deferred

- The login flow re-hash step (Option A) requires verifying it works end-to-end on device.
- Option B could lock out real users if migration 023 was recent.
- Needs coordination with the overall PIN hardening plan (DIS-012).

## Verification

1. Create a legacy user (manually set `pin_salt = NULL` in DB) with a known PIN
2. Log in → verify login succeeds AND `pin_salt` is populated afterward (auto-upgrade)
3. Confirm `legacyHashPin` is never called for any user with a valid salt
