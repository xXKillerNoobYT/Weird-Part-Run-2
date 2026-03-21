# Fix Prompt 09: Security Hardening

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

These are invisible to users but critical for data safety. PINs are hashed with a fixed salt (same PIN = same hash for every user), invalid tokens are treated as real tokens, and sync data from peers can inject table names into SQL queries.

---

## Files To Fix

### 1. AuthService.swift — Fix PIN Hashing

**File:** `core/Sources/WiredPartCore/Services/AuthService.swift`

Find the `hashPin` function (around line 410). It currently does:
```swift
SHA256(pin + ":wiredpart")
```

This uses a fixed salt — if two users have PIN "1234", they get identical hashes. Fix:

```swift
import CryptoKit

/// Hash a PIN with a per-user salt using PBKDF2-like approach.
/// The salt should be the user's UUID or a random value stored with their record.
func hashPin(_ pin: String, salt: String) -> String {
    let input = Data((pin + ":" + salt).utf8)
    // Multiple rounds of SHA256 for basic key stretching
    var hash = SHA256.hash(data: input)
    for _ in 0..<10_000 {
        hash = SHA256.hash(data: Data(hash))
    }
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
```

Update `authenticateByPin()` and `seedFirstAdmin()` to pass the user's ID or a stored salt.

**Note:** This is a breaking change for existing PINs. You'll need a migration path — either re-hash all PINs on next login, or add a `pin_version` column.

### 2. AuthService.swift — Fix Invalid Token

Find `generateLocalToken()` (around line 425). It currently returns `"invalid_token"` on failure. Any code that checks `if token != nil` will treat this as valid.

Fix:
```swift
func generateLocalToken(for userId: Int64) -> String? {
    // Generate a real random token
    let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
    return Data(bytes).base64EncodedString()
}
```

If token generation can't happen for some reason, return `nil` — not a magic string.

### 3. ConflictResolver.swift — Validate Peer Table Names

**File:** `core/Sources/WiredPartCore/Sync/ConflictResolver.swift`

Peer-supplied `change.tableName` is used directly in SQL. A malicious peer could send a crafted table name. Add a whitelist:

```swift
private static let allowedTables: Set<String> = [
    "users", "hats", "permissions", "settings", "notifications",
    "part_categories", "part_styles", "part_types", "part_colors",
    "brands", "suppliers", "parts", "stock_levels",
    "jobs", "labor_entries", "daily_reports",
    "notebooks", "notebook_sections", "notebook_entries",
    "jpos", "jpo_line_items", "purchase_orders", "po_line_items",
    "vehicles", "trailers", "tools", "tool_kits",
    "channels", "messages", "qa_threads",
    "dispatch_assignments", "time_off_requests",
    // ... add all valid table names
]

func validateTableName(_ name: String) -> Bool {
    allowedTables.contains(name.lowercased())
}
```

Call this before any SQL that uses `change.tableName`. Reject changes with invalid table names.

### 4. SyncEngine.swift — Same Table Name Validation

**File:** `core/Sources/WiredPartCore/Sync/SyncEngine.swift`

Apply the same whitelist check before building SQL with server-supplied table names.

### 5. ChangeTracker.swift — Remove Force Unwraps

**File:** `core/Sources/WiredPartCore/Sync/ChangeTracker.swift`

Line 85: `try Int.fetchOne(...)!` → `try Int.fetchOne(...) ?? 0`
Line 183: `try Int64.fetchOne(...)!` → `try Int64.fetchOne(...) ?? 0`

### 6. ChangeTracker.swift — Fix Device Identity

Line 260-263: `DeviceIdentity.current` generates a new UUID every launch. Fix by storing in Keychain:

```swift
struct DeviceIdentity {
    static var current: String {
        if let stored = KeychainHelper.read(key: "device_id") {
            return stored
        }
        let newId = UUID().uuidString
        KeychainHelper.write(key: "device_id", value: newId)
        return newId
    }
}
```

If a full Keychain helper is too much right now, at minimum store in UserDefaults:
```swift
static var current: String {
    let key = "com.wiredpart.deviceId"
    if let stored = UserDefaults.standard.string(forKey: key) {
        return stored
    }
    let newId = UUID().uuidString
    UserDefaults.standard.set(newId, forKey: key)
    return newId
}
```

---

## Testing Checklist

1. Create a user with PIN "1234", create another with PIN "1234" → their hashed PINs should be DIFFERENT
2. Login with correct PIN → works
3. Login with wrong PIN → fails with clear message
4. App generates real random tokens, never the string "invalid_token"
5. Sync with an invalid table name in a change → change is rejected, not applied

---

## When Done

Start **prompt 10 (Service Layer Bugs)** next.
