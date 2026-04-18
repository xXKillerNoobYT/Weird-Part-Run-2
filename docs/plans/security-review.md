# Security Review Scanner

> **Part of:** AUTO GO unified loop (see `auto-go-unified-loop.md`)
> **SKILL.md:** `~/.claude/scheduled-tasks/security-review/SKILL.md`

## What This Does (Plain English)

Scans files changed in the last 7 days against the OWASP Mobile Top-10 and common security anti-patterns. Files GitHub issues for findings. Focuses on the churn since the last run rather than re-scanning the whole repo every time.

## Why We Need This

`dev-improvement-scanner` has a security section, but it's only one of six phases in that task. Dedicated security-review ensures the security pass runs more often and more thoroughly than a shared scanner can afford.

## Current State

- No dedicated security SKILL.md today. Security checks are folded into `hunt-fix-verify` Scanner 10 and `dev-improvement-scanner` Phase B.
- Project stores credentials in Keychain (per architecture docs) but consistency isn't verified.
- No automated check for hardcoded secrets on every change.

## Proposed Changes

### SKILL.md content

Scanner phases (OWASP Mobile Top-10 alignment):

**Phase A — Identify changed files**
```
cd /Users/IA/GitHub/Weird-Part-Run-2 && git log --since="7 days ago" --name-only --pretty=format: | sort -u | grep -E "\.(swift|ts|tsx|rs|py)$"
```

**Phase B — M1 Improper Credential Usage**
- Grep changed Swift files for `UserDefaults.standard.set` with names suggesting credentials: `password`, `token`, `secret`, `apiKey`, `pin` (case-insensitive).
- Any match is a finding — should be Keychain (`KeychainService`) not UserDefaults.

**Phase C — M2 Inadequate Supply Chain Security**
- Check `package.json`, `Package.swift`, `src-tauri/Cargo.toml` — any new dependencies in the diff? If yes, note them for manual review (we can't audit them, just flag).

**Phase D — M3 Insecure Authentication/Authorization**
- Grep for hardcoded user IDs (`user_id: 1`, `created_by: 1`, `userId = 1`) — see memory `feedback_hardcoded_user_ids.md`.
- Grep for disabled auth checks (`// TODO: auth`, `// skip auth`, commented-out `guard user.isAuthenticated`).

**Phase E — M4 Insufficient Input/Output Validation**
- Grep for SQL string concatenation (`"SELECT * FROM \(table)"` where table is not a constant).
- Grep for user input going directly into queries without `?` parameterization.

**Phase F — M5 Insecure Communication**
- Grep for `http://` in source (should be `https://`).
- Grep for `NSAllowsArbitraryLoads` in Info.plist (should be false or not present).

**Phase G — M8 Security Misconfiguration**
- Grep for `.debug()` or verbose logging that could leak PII.
- Grep for `NSLog(` in Swift release code paths.
- Grep for `console.log(` in TypeScript production code (flag; user may have intentional dev logs).

**Phase H — M9 Insecure Data Storage**
- Any `FileManager.default.createFile` writing to non-sandboxed paths — flag.
- Any `.write(to: .documentsDirectory)` with sensitive-named files — verify encryption.

**Phase I — M10 Insufficient Cryptography**
- Grep for `MD5`, `SHA1` (should be SHA256+).
- Grep for `DES`, `RC4` (should be AES).
- Grep for random number generation with `arc4random` (should be `SecRandomCopyBytes` for crypto).

**Phase J — File findings**
- Each finding → GitHub issue with label `security` (check duplicates).
- Critical findings (hardcoded secrets, SQL injection risk): also create a DevTODO for immediate user attention.
- Passing scan → logged to `docs/security-review-tracker.md`.
- Heartbeat logs "security-review: N findings, M critical".

## Files to Create

- `~/.claude/scheduled-tasks/security-review/SKILL.md`
- `docs/security-review-tracker.md` (seeded on first run)

## Test Plan

1. First run with a clean working tree: should find hardcoded user-ID patterns (known issue per memory).
2. Introduce a test file with `UserDefaults.standard.set(password, forKey: "pw")`: scanner should flag it.
3. Subsequent runs: only scans files changed in the last 7 days.

## User Roles Affected

- **Owner/Developer:** steady stream of security findings caught before shipping.

## Security Considerations

- Meta: this scanner itself should not log secret values, only file paths and line numbers.

## Apple HIG Notes

N/A.
