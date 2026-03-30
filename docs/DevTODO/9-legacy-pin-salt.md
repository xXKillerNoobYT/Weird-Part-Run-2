# Force Re-Hash Legacy PINs with Weak Salt
**GitHub Issue:** #9
**Priority:** Medium
**Estimated effort:** Quick (core fix, no UI needed)

## What's Wrong
Users who haven't logged in since migration 023 still have PINs hashed with a shared salt (`:wiredpart`). These are vulnerable to rainbow tables.

## What's Already Done
- New logins auto-migrate to per-user salts (AuthService.swift:92-103) ✅
- hashPin uses 10K iterations of SHA-256 with per-user salt ✅

## Remaining Fix
On next app startup, scan for users where `pin_salt IS NULL` and `pin_hash IS NOT NULL` and `pin_hash != '__PLACEHOLDER_HASH__'`. For these users, force a PIN reset on next login by setting a flag.

## Files to Change
- `core/Sources/WiredPartCore/Services/AuthService.swift` — In `authenticateByPin`, when `user.pinSalt == nil` and login succeeds, the re-hash already happens. The question is: should we force users to change their PIN, or is the auto-migration on next login sufficient?

## Decision Needed
This might already be good enough — the auto-migration re-hashes on successful login. The only risk is users who NEVER log in again. Ask yourself: is that a real risk for your use case?

**If auto-migration is sufficient:** Close this issue, it's already handled.
**If you want forced reset:** I'll add a `pin_needs_reset` flag that shows a "Please update your PIN" screen after login.

## How to Verify
1. Check database: `SELECT id, display_name, pin_salt FROM users WHERE pin_salt IS NULL`
2. If no results → all users migrated → close issue
3. If results exist → those users need to log in once to migrate
