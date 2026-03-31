# Move Token Signing Key to Keychain
**PE:** PE-021
**Priority:** Medium
**Estimated effort:** Quick (Keychain read/write, ~30 lines)
**Status:** ✅ done — fixed by hunt-fix agent 2026-03-30 in `AuthService.swift:signingKey`

## What's Wrong
`AuthService.signingKey` is derived from `ProcessInfo.processInfo.globallyUniqueString` — a UUID regenerated each process launch. This means all session tokens are invalidated every time the app restarts. Users must re-authenticate after every app launch.

The comment at `AuthService.swift:653` already acknowledges this:
> "In production this should be stored in the Keychain; for now it's derived from a stable device identifier so tokens survive app restarts within the same device."

The comment is aspirational — the actual implementation does NOT survive restarts yet.

## File to Change
- `core/Sources/WiredPartCore/Services/AuthService.swift:656` — `signingKey` static property

## Fix
Replace the ephemeral UUID seed with a Keychain-backed key:

```swift
private static let signingKey: SymmetricKey = {
    let keychainKey = "com.wiredpart.token-signing-key"
    // Try to load existing key
    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: keychainKey,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data, data.count == 32 {
        return SymmetricKey(data: data)
    }
    // Generate new key and store it
    var keyData = Data(count: 32)
    _ = keyData.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
    let addQuery: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: keychainKey,
        kSecValueData: keyData,
        kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    SecItemAdd(addQuery as CFDictionary, nil)
    return SymmetricKey(data: keyData)
}()
```

## Behavior After Fix
- First launch: generates a 256-bit key, stores in Keychain
- Subsequent launches: loads same key → existing tokens remain valid
- New device (or after device wipe): new key generated → previous tokens invalid (expected)

## How to Verify
1. Log in → note the token
2. Force-quit app → reopen
3. Verify the session is still active (no re-login required)
