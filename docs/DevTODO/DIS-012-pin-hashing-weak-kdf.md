---
source: dev-improvement-scanner (2026-04-06)
severity: Medium
category: Security — PIN Hashing Strength
status: open
github_issue: "#130 — filed 2026-04-07 (plan-enforcer run 8)"
---

# DIS-012: PIN Hashing Uses Iterated SHA-256, Not a Memory-Hard KDF

## Problem

`AuthService.hashPin(_:salt:)` hashes PINs with 10,000 iterations of SHA-256:

```swift
// AuthService.swift:661-668
static func hashPin(_ pin: String, salt: String) -> String {
    let input = Data((pin + ":" + salt).utf8)
    var hash = SHA256.hash(data: input)
    for _ in 0..<10_000 {
        hash = SHA256.hash(data: Data(hash))
    }
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
```

This is better than a single SHA-256, but SHA-256 is a fast hash designed for throughput — even at 10,000 iterations, a modern GPU can test millions of PIN candidates per second. PINs are only 4-6 digits (10^4–10^6 space), meaning a complete offline brute-force takes seconds on commodity hardware.

**What the industry uses instead:**
- **PBKDF2-SHA256** (available in CryptoKit, designed for key stretching)
- **bcrypt** (constant-time, memory-bound, tunable cost)
- **Argon2id** (memory-hard, most resistant to GPU parallelism)

## Context

- Per-user salt was added in migration 023 — that was a significant improvement.
- The `legacyHashPin()` single-salt path (DIS-013) makes this worse for un-migrated users.
- Tokens are HMAC-signed (PE-008a fixed), so PIN compromise doesn't extend to token forgery.
- The app stores the hash locally on-device — offline brute-force requires physical device access (jailbreak or backup extraction).
- Overall risk: **Medium** — bounded by requiring device access, but low-entropy PIN space is a real concern.

## Suggested Fix (Xcode AI prompt not needed — core Swift)

Migrate `hashPin` to use CryptoKit's PBKDF2 (already imported):

```swift
import CryptoKit

static func hashPin(_ pin: String, salt: String) -> String {
    guard let saltData = Data(base64Encoded: salt) else {
        // Fallback to iterated SHA-256 if salt isn't valid base64
        return legacyIteratedHash(pin, salt: salt)
    }
    let pinData = Data(pin.utf8)
    let derivedKey = try? HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: pinData),
        salt: saltData,
        info: Data("wiredpart-pin".utf8),
        outputByteCount: 32
    )
    // Or use PBKDF2 via CommonCrypto for true key stretching
    return derivedKey?.withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() } ?? ""
}
```

**Better option — use CommonCrypto PBKDF2 (no new dependencies):**

```swift
import CommonCrypto

static func hashPin(_ pin: String, salt: String) -> String {
    let pinBytes = Array(pin.utf8)
    let saltBytes = Array(Data(base64Encoded: salt) ?? Data(salt.utf8))
    var derivedKey = [UInt8](repeating: 0, count: 32)
    CCKeyDerivationPBKDF(
        CCPBKDFAlgorithm(kCCPBKDF2),
        pin, pinBytes.count,
        saltBytes, saltBytes.count,
        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
        100_000,  // 10× more iterations than current
        &derivedKey, derivedKey.count
    )
    return derivedKey.map { String(format: "%02x", $0) }.joined()
}
```

**Migration path:** Same as the salt migration — re-hash on next successful login. Add a `pin_hash_version` column (0 = legacy, 1 = iterated SHA-256, 2 = PBKDF2) to detect and upgrade.

## Why Auto-Fix Was Deferred

- Requires a design decision: which KDF? PBKDF2 (no new dependencies) vs Argon2id (needs a package)?
- Requires a DB migration (new `pin_hash_version` column).
- Existing users need a seamless upgrade path.
- The fix touches auth — must be tested on device before shipping.

## Verification

1. Create a user with a PIN → verify login works
2. Check `pin_hash_version` is 2 in DB after login
3. Upgrade: old version-1 user logs in → hash upgrades to version-2 transparently
4. Run all AuthService tests: `swift test --filter AuthServiceTests`
