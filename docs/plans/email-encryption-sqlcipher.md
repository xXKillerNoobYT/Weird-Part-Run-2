# Email-at-Rest Encryption — SQLCipher Whole-DB Migration

> **Status:** Design approved 2026-04-25 via Q&A ratification. Implementation pending.
> **Closes:** CodeQL Code Scanning issues #292, #294, #296, #298, #303.
> **Source decision:** [`docs/dev-qa.md`](../dev-qa.md) — Email-at-Rest Encryption cluster, 2026-04-25.
> **Scope:** Whole-database encryption via SQLCipher. NOT per-field encryption.

---

## Context

CodeQL flagged 5 issues (`swift/cleartext-storage-database`) where `email` columns are stored as plaintext in local SQLite tables (`entity_contacts`, `general_contractors`, `users.email`, `company_setup_draft.email`). Schema scan confirmed **11 email columns across 10+ tables** plus an even wider PII surface (employee names, wages, certifications, customer/contractor contact info).

iOS Data Protection encrypts the SQLite file on-disk while the device is locked, but plaintext is readable to any process running as the app while the device is unlocked.

**Owner decision (2026-04-25):** Option A — SQLCipher whole-DB encryption. Pre-beta is the right time for the migration; one stroke protects ALL PII, not just email. Acceptable trade: ~1MB binary size + 5–15% read/write overhead.

**Why not Option B (per-field AES on email):** half-measure. Same threat model as A, but every email-touching service/UI needs migration AND only protects email. Other PII (names, wages, certs) remains plaintext.

**Why not Option C (accept iOS Data Protection):** unlocked-stolen-device threat is unprotected. CodeQL flag would need permanent suppression. Future security audits would reopen the question.

---

## Design

### High-level shape

- Add the **SQLCipher** Swift package as a Package.swift dependency.
- Wrap GRDB's `DatabasePool` initialization in a helper that issues `PRAGMA cipher_*` BEFORE any other I/O.
- Derive the cipher key from `SHA-256(user PIN || device salt)`. Salt is 32 random bytes, generated on first launch, stored in the iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- One-time migration on the first launch with the new build: detect plaintext DB, run `sqlcipher_export()` to a temp encrypted DB, atomic-rename to replace the original. All wrapped in a transaction with rollback on failure.
- Multipeer Connectivity sync continues to work with **per-device DB keys** (no shared key across devices). Sync messages are application-layer plaintext that travels over Multipeer's existing TLS-equivalent encryption; the receiving device decrypts the message in memory and writes through its own `AppDatabase` (which encrypts on write).

### Key derivation detail

```
salt = Keychain.read(key: "wp.dbcipher.salt")
       ?? randomBytes(32) → store under "wp.dbcipher.salt" with
                            kSecAttrAccessibleWhenUnlockedThisDeviceOnly

cipherKey = SHA-256(pin.utf8 || salt)
hexKey    = cipherKey.hexEncoded   // SQLCipher accepts hex-encoded keys
```

Why PIN + salt (not just PIN, not just random):
- **Salt** prevents the same PIN producing the same key across devices (defeats rainbow tables).
- **PIN** means the user can change their PIN and we re-key (see "PIN change" below) — restoring control if PIN was exposed.
- Storing the *raw key* in Keychain is also viable but loses the PIN-change re-key path.

Counter to the "store raw key in Keychain" alternative: with PIN+salt, the running app must briefly hold the PIN in memory to re-derive the key. That's a small attack surface but no worse than what the app already does for PIN-based auth.

### `AppDatabase` init refactor

New helper in `core/Sources/WiredPartCore/Database/AppDatabase+Cipher.swift`:

```swift
extension AppDatabase {
    public static func makeEncryptedPool(path: String, keyHex: String) throws -> DatabasePool {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.usePassphrase(keyHex)        // GRDB-SQLCipher API
            try db.execute(sql: "PRAGMA cipher_page_size = 4096")
            try db.execute(sql: "PRAGMA kdf_iter = 64000")
        }
        return try DatabasePool(path: path, configuration: config)
    }
}
```

The existing `AppDatabase.init()` becomes:

```swift
public init() throws {
    let path = AppDatabase.defaultPath
    let keyHex = try CipherKeyManager.shared.deriveKeyHex()  // throws if no PIN
    self.pool = try AppDatabase.makeEncryptedPool(path: path, keyHex: keyHex)
    try registerMigrations(self.pool)
}
```

`CipherKeyManager` lives at `core/Sources/WiredPartCore/Security/CipherKeyManager.swift`:

```swift
public final class CipherKeyManager {
    public static let shared = CipherKeyManager()
    private static let keychainAccount = "wp.dbcipher.salt"

    public func deriveKeyHex() throws -> String {
        let pin = try AuthService.shared.requireCurrentPin()        // throws if locked
        let salt = try ensureSaltExists()
        let key = SHA256.hash(data: Data(pin.utf8) + salt)
        return key.map { String(format: "%02x", $0) }.joined()
    }

    private func ensureSaltExists() throws -> Data {
        if let existing = Keychain.read(account: Self.keychainAccount) { return existing }
        let salt = randomBytes(32)
        try Keychain.write(account: Self.keychainAccount, data: salt,
                           accessibility: .whenUnlockedThisDeviceOnly)
        return salt
    }
}
```

### One-time plaintext-to-encrypted migration

Runs on the FIRST launch of a build with SQLCipher. Detection: try a probe query (`SELECT 1 FROM sqlite_master`) with cipher PRAGMA and decrypt; if fails with `SQLITE_NOTADB`, the file is plaintext and needs migration.

```swift
public func migratePlaintextDBIfNeeded() throws {
    let path = AppDatabase.defaultPath
    let keyHex = try CipherKeyManager.shared.deriveKeyHex()

    // Probe: try to open as encrypted
    if (try? AppDatabase.makeEncryptedPool(path: path, keyHex: keyHex)) != nil {
        return  // already encrypted
    }

    // Confirm it's a plaintext SQLite file (not corrupted)
    let plaintextPool = try DatabasePool(path: path)  // no cipher
    try plaintextPool.read { db in
        _ = try Row.fetchOne(db, sql: "SELECT 1 FROM sqlite_master")
    }

    // Migrate via sqlcipher_export
    let tempPath = path + ".encrypted.tmp"
    try plaintextPool.write { db in
        try db.execute(sql: "ATTACH DATABASE ? AS encrypted KEY ?",
                       arguments: [tempPath, keyHex])
        try db.execute(sql: "SELECT sqlcipher_export('encrypted')")
        try db.execute(sql: "DETACH DATABASE encrypted")
    }

    // Atomic rename
    try FileManager.default.removeItem(atPath: path)
    try FileManager.default.moveItem(atPath: tempPath, toPath: path)
}
```

Wrap the whole call in a top-level try/catch in `AppDatabase.bootstrap()`. If migration fails, delete the temp file and rethrow — original plaintext DB is preserved untouched, app refuses to launch with a clear error message ("DB encryption migration failed; please contact support" + the underlying error).

### PIN change re-key

When the user changes their PIN, the cipher key changes too. Use `PRAGMA rekey`:

```swift
public func rekey(newPin: String) throws {
    let newKeyHex = try deriveKeyHexForPin(newPin)
    try pool.write { db in
        try db.execute(sql: "PRAGMA rekey = ?", arguments: [newKeyHex])
    }
}
```

Hook this into `AuthService.changePin()`. Old PIN must be confirmed (already required by the auth flow) before rekey runs.

### Multipeer Connectivity sync follow-up

Per-device DB keys means each device's encrypted DB is opaque to other devices. Sync messages must NOT contain raw encrypted bytes — they must be application-layer rows.

Today the sync layer (`core/Sources/WiredPartCore/Sync/`) already exchanges JSON-encoded change records via `MultipeerManager`. SQLCipher doesn't change that pattern: device A's DB encrypts on write → reads back plaintext → emits JSON change record → travels over Multipeer's encrypted transport → device B receives → decodes JSON → writes through its own `AppDatabase` (which encrypts on write into device B's DB).

**Net effect: zero change to the sync protocol.** Document this and add a sync-roundtrip integration test (see test plan below).

### Performance expectations

SQLCipher overhead, measured on similar projects:
- Reads: 5–15% slower depending on result size.
- Writes: 5–15% slower.
- App launch: +50–150ms for the initial cipher setup.
- Memory: negligible at our DB size.

We accept these costs. If catalog page load (`PartsCatalogPage` with cursor-paginated 1000-row default) shows a perceptible hitch in benchmarks, revisit by:
1. Caching the derived key in memory across the session (already implicit — we don't re-derive per query).
2. Increasing `cipher_page_size` (default 4096 — could try 8192 for read-heavy workloads).
3. As a last resort, downgrading `kdf_iter` from 64000 to 16000 (still secure for our threat model).

---

## Test Plan

Five end-to-end verification scenarios:

### 1. Fresh install + encrypt
- Wipe app, install build with SQLCipher.
- User sets a PIN.
- App writes some test rows (employee, customer).
- Quit app.
- External tool (`sqlite3 file.db`) opens the file and runs `SELECT * FROM users` — must fail with "file is not a database" (proof of encryption).
- Re-open app, log in with PIN, verify rows readable.

### 2. Dev-DB migration (existing plaintext DB)
- Start with a build pre-SQLCipher; populate DB with realistic data (10+ employees, 100+ parts).
- Quit app.
- Replace binary with the SQLCipher build.
- Launch + log in.
- App detects plaintext DB, runs `sqlcipher_export()`, atomic-rename completes.
- Verify all rows preserved (count + spot-check). Verify `sqlite3 file.db` now fails (encrypted).
- Verify the temp `.encrypted.tmp` file is gone.

### 3. PIN change re-key
- Logged-in app, encrypted DB.
- User changes PIN via Settings.
- `rekey()` runs.
- Quit app.
- Try to open with old PIN-derived key (manually) — must fail.
- Open with new PIN — must succeed.

### 4. Restore from backup
- Encrypted DB on Device A. iCloud backup includes the file.
- Restore Device A from backup onto a new device (same Apple ID).
- Keychain is also restored (Apple's normal behavior for `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`? — actually NOT migrated to new devices; need to test).
- If Keychain salt is not restored, app must detect missing salt and either prompt for backup-recovery passphrase or refuse to open the encrypted DB. Document this behavior.

### 5. Sync message round-trip with two devices, different PINs
- Device A and Device B are paired via Multipeer.
- Each device has its own PIN, each derives its own salt + key.
- Device A writes a part record.
- Sync triggers → Multipeer message goes to Device B.
- Device B receives, decodes, writes into its own DB.
- Verify: Device B reads back the part record correctly.
- Verify: snapping the Multipeer transport (intercepting bytes on the wire) shows TLS-encrypted bytes (Multipeer's own encryption), not the raw cipher bytes from Device A's DB.

---

## Migration & Rollout

### Phase 1 — Scaffolding (no behavior change)
1. Add SQLCipher Swift package to `Package.swift`.
2. Create `CipherKeyManager.swift` and `AppDatabase+Cipher.swift`.
3. Unit tests for `CipherKeyManager` (salt generation, key derivation determinism).
4. Build + test verifies SQLCipher links correctly.

### Phase 2 — Wire into AppDatabase init
5. Refactor `AppDatabase.init()` to call `makeEncryptedPool()`.
6. Update `bootstrap()` to call `migratePlaintextDBIfNeeded()` before init.
7. Run all existing tests — they must still pass against an encrypted in-memory DB.
8. Add the 5 scenarios from the test plan as XCTests.

### Phase 3 — User-facing
9. Add PIN-change re-key wiring in `AuthService.changePin()`.
10. Add an in-app indicator (Settings → "Database encrypted ✓") for transparency.
11. Document the backup recovery behavior (Scenario 4 above) in the user-facing help.

### Phase 4 — Verification
12. Run the 5 test-plan scenarios on real devices (TestFlight beta).
13. Benchmark catalog/orders read/write throughput; compare to pre-encryption baseline.
14. Close CodeQL issues #292, #294, #296, #298, #303 with rationale + commit links.

---

## Critical Files

### To create
- `/Users/IA/GitHub/Weird-Part-Run-2/core/Sources/WiredPartCore/Database/AppDatabase+Cipher.swift`
- `/Users/IA/GitHub/Weird-Part-Run-2/core/Sources/WiredPartCore/Security/CipherKeyManager.swift`
- `/Users/IA/GitHub/Weird-Part-Run-2/core/Tests/WiredPartCoreTests/CipherKeyManagerTests.swift`
- `/Users/IA/GitHub/Weird-Part-Run-2/core/Tests/WiredPartCoreTests/AppDatabaseEncryptionTests.swift`

### To modify
- `/Users/IA/GitHub/Weird-Part-Run-2/Package.swift` (add SQLCipher dependency)
- `/Users/IA/GitHub/Weird-Part-Run-2/core/Sources/WiredPartCore/Database/AppDatabase.swift` (init refactor + bootstrap migration call)
- `/Users/IA/GitHub/Weird-Part-Run-2/core/Sources/WiredPartCore/Services/AuthService.swift` (rekey on PIN change)

### Read-only references
- `/Users/IA/GitHub/Weird-Part-Run-2/core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — schema (11 email columns confirmed)
- `/Users/IA/GitHub/Weird-Part-Run-2/core/Sources/WiredPartCore/Sync/MultipeerManager.swift` — sync message shape (no change needed)

---

## Cross-References

- CodeQL issues: #292, #294, #296, #298, #303 (all `swift/cleartext-storage-database`)
- Source Q&A: [`docs/dev-qa.md`](../dev-qa.md) — Email-at-Rest Encryption cluster, answered 2026-04-25
- Memory: [`feedback_release_state.md`](../../.claude/projects/-Users-IA-GitHub-Weird-Part-Run-2/memory/feedback_release_state.md) — pre-beta posture justifies the migration timing.
- Companion plan: [`docs/plans/sync-field-timestamps-upgrade.md`](sync-field-timestamps-upgrade.md) — runs on top of SQLCipher (per-field timestamps stored as encrypted column values like everything else).
