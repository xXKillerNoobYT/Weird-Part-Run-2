# PE-008c: Legacy PIN Hash Upgrade Banner

## What This Fixes
GitHub Issue #9 — Hardcoded legacy salt in PIN hashing.

Users who created their PIN before migration 023 (commit b3eef3b) still have
`pin_salt = NULL` in the database. Their PIN is hashed with a fixed salt
(`pin + ":wiredpart"`) instead of a per-user random salt, making them
vulnerable to rainbow table attacks on a stolen database.

The migration path already exists: when a legacy-hashed user logs in,
`authenticateByPin()` re-hashes their PIN with a fresh random salt automatically.
The risk is users who haven't logged in since the migration.

`AuthService.getLegacyHashedUserCount()` is now available to query this count.

## What To Build

In `People/PermissionsPage.swift` (the iOS Permissions page under the People tab):

### Step 1 — Load the count on appear

Add a `@State private var legacyPinCount: Int = 0` state variable.

In `.onAppear` (or `.task`), call:
```swift
legacyPinCount = (try? authService.getLegacyHashedUserCount()) ?? 0
```

### Step 2 — Show a banner if count > 0

At the top of the page body (before the hat picker), insert:

```swift
if legacyPinCount > 0 {
    HStack(spacing: 10) {
        Image(systemName: "lock.trianglebadge.exclamationmark.fill")
            .foregroundStyle(.orange)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
            Text("\(legacyPinCount) user\(legacyPinCount == 1 ? "" : "s") need a PIN upgrade")
                .font(.subheadline.bold())
            Text("They will be upgraded automatically on their next login.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
    }
    .padding(12)
    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    .padding(.horizontal)
    .padding(.top, 8)
}
```

### Step 3 — Accessibility

The banner `HStack` should have:
```swift
.accessibilityElement(children: .combine)
.accessibilityLabel("\(legacyPinCount) user\(legacyPinCount == 1 ? "" : "s") need a PIN security upgrade. They will be upgraded automatically on their next login.")
```

### Step 4 — Refresh on foreground

Add `.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in ... }` to re-query the count when the app returns to foreground.

## Files To Touch
- `Weird Parts IOS/Weird Parts IOS/Features/People/PermissionsPage.swift`

## Do NOT Change
- Any auth logic — the migration path in `AuthService.authenticateByPin()` is correct and complete.
- The hat picker or permission toggle behavior.
- Any other People pages.

## Expected Result
- If 0 users have legacy PINs: no banner shown.
- If N > 0: orange informational banner at top of Permissions page.
- Banner disappears once all users have logged in and been upgraded.
