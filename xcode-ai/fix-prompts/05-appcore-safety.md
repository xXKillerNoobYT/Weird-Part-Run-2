# Fix Prompt 05: AppCore Safety — Prevent Launch Crashes

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

If the database fails to open (corrupted file, permissions issue, disk full), the app crashes immediately instead of showing an error the user can act on. The crash comes from force-unwrapped properties (`db!`, `authService!`, `settingsService!`) and a `fatalError()` call.

---

## File To Fix

**`App/AppCore.swift`**

### Fix 1: Replace IUOs with Safe Optionals

Change lines 25-27 from:
```swift
private(set) var db: AppDatabase!
private(set) var authService: AuthService!
private(set) var settingsService: SettingsService!
```

To:
```swift
private(set) var db: AppDatabase?
private(set) var authService: AuthService?
private(set) var settingsService: SettingsService?
```

### Fix 2: Update All Code That Uses These Three Properties

Every place that accesses `db`, `authService`, or `settingsService` must now use safe optional access. The main places:

**`login()` method** (line 104): Add guard:
```swift
func login(userId: Int64, pin: String) -> String? {
    guard let authService else { return "App not ready. Please wait." }
    do {
        let result = try authService.authenticateByPin(userId: userId, pin: pin)
        // ...rest stays the same
    }
}
```

**`seedFirstAdmin()` method** (line 130): Same pattern:
```swift
func seedFirstAdmin(displayName: String, pin: String) -> String? {
    guard let authService else { return "App not ready. Please wait." }
    // ...
}
```

**`updateTheme()` method** (line 164): Already uses safe optional (`if let settings = settingsService`), so it's fine.

**`performDatabaseReset()` method** (line 180): Already checks `if let database = self.db`, so it's fine.

**`bootstrap()` method** (line 48): Uses `=` assignment, so it's fine.

### Fix 3: Replace fatalError with Thrown Error

Change `databasePath()` (line 225-228) from:
```swift
static func databasePath() -> String {
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        fatalError("Unable to locate Documents directory — sandboxing issue")
    }
```

To:
```swift
enum AppCoreError: LocalizedError {
    case noDocumentsDirectory
    var errorDescription: String? {
        "Unable to locate app storage directory. Please restart the app."
    }
}

static func databasePath() throws -> String {
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        throw AppCoreError.noDocumentsDirectory
    }
```

Then update `bootstrap()` line 50 — it already wraps in `do/catch`, so `let path = try Self.databasePath()` will work as-is.

And update `performDatabaseReset()` line 181: `let dbPath = try Self.databasePath()` — this method already `throws`, so it's fine.

### Fix 4: Replace DispatchQueue.main.asyncAfter in Auth Views

While you're touching AppCore-related code, fix the auth views that use GCD instead of proper async:

**`Auth/BootstrapView.swift`**, **`Auth/LoginView.swift`**, **`Auth/AdminAccountSetupView.swift`**, **`Auth/BusinessProfileSetupView.swift`**

Find this pattern in each:
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    // synchronous work
}
```

Replace with:
```swift
Task { @MainActor in
    try? await Task.sleep(for: .milliseconds(200)) // brief UX delay
    // same work
}
```

---

## Testing Checklist

1. App should launch normally with no changes to user experience
2. If database can't open → user should see an error message on screen, NOT a crash
3. Login should still work
4. "Create New Business" onboarding should still work
5. Database reset should still work

---

## When Done

Start **prompt 06 (Missing CRUD — Jobs & People)** next.
