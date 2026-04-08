---
source: dev-improvement-scanner (2026-04-06)
severity: Low
category: Security — Legacy Token Acceptance
status: open
github_issue: PENDING — needs manual filing (gh unavailable in scheduled run 2026-04-06)
---

# DIS-014: Legacy Unsigned Token Acceptance Path Has No Removal Deadline

## Problem

`AuthService.parseLocalToken()` accepts tokens with no HMAC signature:

```swift
// AuthService.swift:735-748
static func parseLocalToken(_ token: String) -> TokenPayload? {
    let parts = token.split(separator: ".", maxSplits: 1)

    let payloadB64: String
    if parts.count == 2 {
        // ← Signed token (current format) — HMAC verified
        payloadB64 = String(parts[0])
        let sigB64 = String(parts[1])
        guard let sigData = Data(base64Encoded: sigB64) else { return nil }
        let expected = HMAC<SHA256>.authenticationCode(for: Data(payloadB64.utf8), using: signingKey)
        guard Data(sigData) == Data(expected) else { return nil }
    } else {
        // ← Legacy unsigned token — accept but it will be replaced on next login
        payloadB64 = token
    }
    // ...
}
```

HMAC token signing was added in PE-008a (commit b3eef3b, ~2026-03-31). The legacy path was kept as a backward-compat shim for tokens persisted before the signing migration. The comment says tokens are "replaced on next login" — but there's no removal deadline for the shim itself.

## Risk

An unsigned token is just a base64-encoded JSON payload. Anyone who can write an arbitrary base64 string to `AppCore.currentToken` (e.g., via a memory injection on a jailbroken device) could forge session tokens. This bypasses HMAC verification entirely.

This is **Low** severity because:
- It requires physical access + jailbreak to exploit
- The token is stored in-memory (`@Published var currentToken`) — not in UserDefaults or Keychain where it could be extracted without code execution
- All newly generated tokens use HMAC and won't match the unsigned path

## Suggested Fix

**Remove the legacy shim.** After the signing migration (PE-008a, 2026-03-31), any unsigned token in active use would have been replaced by now (within one app session). Add a build-time check or date-based guard:

```swift
} else {
    // Legacy unsigned token path removed — reject immediately.
    // All tokens generated since 2026-03-31 are signed.
    return nil
}
```

Or if backward compatibility is still needed for a bit longer, add a warning assertion:
```swift
} else {
    #if DEBUG
    assertionFailure("Legacy unsigned token found — should have been migrated by now")
    #endif
    payloadB64 = token
}
```

## Why Auto-Fix Was Deferred

- The change is a 1-line fix but touches authentication — needs manual on-device verification
  that no production tokens are still in the unsigned format before the shim is removed.
- Low urgency: the attack surface is narrow (requires jailbreak + memory injection).
- Best handled alongside DIS-012/DIS-013 as part of a single auth security hardening pass.

## Verification

1. Remove the `else` branch (or replace with `return nil`)
2. Fresh install: log in → get a signed token → verify parseLocalToken succeeds
3. Verify no "session expired" errors appear after removing the shim
4. Run AuthService tests: `swift test --filter AuthServiceTests`
