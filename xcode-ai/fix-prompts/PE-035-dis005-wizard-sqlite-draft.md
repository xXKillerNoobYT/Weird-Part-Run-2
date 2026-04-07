# PE-035: Company Setup Wizard — Migrate PII from UserDefaults to SQLite Draft

**Priority:** Medium-High (Security — PII Storage)
**Source:** dev-improvement-scanner run 7 (DIS-005), Q&A answered 2026-04-04
**Plan:** `docs/DevTODO/DIS-005-userdefaults-pii-wizard.md`
**GitHub Issue:** File manually — CompanySetupWizard stores company PII in unencrypted UserDefaults

---

## Problem

`CompanySetupWizard.swift` stores company name, address, phone, and email in `UserDefaults` as wizard draft state. These keys (`companySetup_name`, `companySetup_address`, `companySetup_phone`, `companySetup_email`, plus 4 more) **are never deleted** — they persist in the unencrypted plist indefinitely, even after the wizard finishes.

`UserDefaults` is stored unencrypted on the device and may be exposed in unencrypted iCloud/iTunes backups.

**Decision (owner-confirmed):** Option B — migrate wizard draft state to a `company_setup_draft` SQLite table. SQLite in iOS benefits from iOS Data Protection (encrypted at rest). Delete the draft row when the wizard completes successfully.

---

## Files to Modify

### 1. `core/Sources/WiredPartCore/AppDatabase+Migrations.swift`

Add a new migration at the end of `registerMigrations()`.

The migration creates a `company_setup_draft` table:

```swift
migrator.registerMigration("migration_NNN_company_setup_draft") { db in
    try db.create(table: "company_setup_draft", ifNotExists: true) { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("name", .text)
        t.column("address", .text)
        t.column("city", .text)
        t.column("state", .text)
        t.column("zip", .text)
        t.column("phone", .text)
        t.column("email", .text)
        t.column("industry", .text)
        t.column("updated_at", .datetime).notNull().defaults(to: nil)
    }
}
```

**Migration number:** Use the next sequential number (check the last migration registered to find N, then use N+1).

---

### 2. `core/Sources/WiredPartCore/Services/SettingsService.swift` (or a new `SetupDraftService.swift`)

Add two methods to read/write the draft row. Place them in `SettingsService.swift` if that already handles company profile operations, or create a minimal helper if not:

```swift
// Load wizard draft (returns nil if no draft started)
public func loadSetupDraft() throws -> CompanySetupDraft? {
    try db.read { db in
        try Row.fetchOne(db, sql: "SELECT * FROM company_setup_draft LIMIT 1")
            .map { row in CompanySetupDraft(row: row) }
    }
}

// Save/update wizard draft (upsert — only one row ever exists)
public func saveSetupDraft(_ draft: CompanySetupDraft) throws {
    try db.write { db in
        try db.execute(sql: """
            INSERT INTO company_setup_draft (name, address, city, state, zip, phone, email, industry, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                address = excluded.address,
                city = excluded.city,
                state = excluded.state,
                zip = excluded.zip,
                phone = excluded.phone,
                email = excluded.email,
                industry = excluded.industry,
                updated_at = excluded.updated_at
        """, arguments: [draft.name, draft.address, draft.city, draft.state, draft.zip, draft.phone, draft.email, draft.industry])
    }
}

// Delete draft after wizard completion
public func deleteSetupDraft() throws {
    try db.write { db in
        try db.execute(sql: "DELETE FROM company_setup_draft")
    }
}
```

Add a `CompanySetupDraft` struct (in `SettingsModels.swift` or near the service):

```swift
public struct CompanySetupDraft {
    public var name: String
    public var address: String
    public var city: String
    public var state: String
    public var zip: String
    public var phone: String
    public var email: String
    public var industry: String

    init(row: Row) {
        name = row["name"] ?? ""
        address = row["address"] ?? ""
        city = row["city"] ?? ""
        state = row["state"] ?? ""
        zip = row["zip"] ?? ""
        phone = row["phone"] ?? ""
        email = row["email"] ?? ""
        industry = row["industry"] ?? ""
    }
}
```

---

### 3. `Auth/CompanySetupWizard.swift`

This is the main UI file that currently uses `UserDefaults`. Replace all `UserDefaults` reads/writes with calls to the new SQLite draft methods.

**Step A — Find all UserDefaults references in this file:**

Look for any lines containing:
- `UserDefaults.standard.set(` — write operations
- `UserDefaults.standard.string(forKey:` — read operations
- `@AppStorage("companySetup_` — property wrappers
- Keys like `"companySetup_name"`, `"companySetup_address"`, etc.

**Step B — Replace `@AppStorage` with `@State` properties:**

If the wizard uses `@AppStorage("companySetup_name") var companyName = ""` patterns, replace them with plain `@State private var companyName = ""` properties. The `@AppStorage` wrapper is what writes to UserDefaults.

**Step C — Load draft on appear:**

In the wizard's `.task { }` or `.onAppear { }`, load the draft from SQLite and populate the `@State` fields:

```swift
.task {
    if let draft = try? settingsService.loadSetupDraft() {
        companyName = draft.name
        companyAddress = draft.address
        companyCity = draft.city
        companyState = draft.state
        companyZip = draft.zip
        companyPhone = draft.phone
        companyEmail = draft.email
        // etc.
    }
}
```

**Step D — Save draft on step advance (progress save):**

The wizard currently calls `saveProgress()` when the user taps Exit or advances between steps. Find `saveProgress()` and update it to write to SQLite instead of UserDefaults:

```swift
private func saveProgress() {
    let draft = CompanySetupDraft(
        name: companyName,
        address: companyAddress,
        // ... fill all fields
    )
    try? settingsService.saveSetupDraft(draft)
}
```

**Step E — Delete draft on completion:**

When the wizard successfully saves the final company profile to the `company_profile` table (the existing completion path), add one line:

```swift
try? settingsService.deleteSetupDraft()
```

This ensures the draft row is cleaned up after the wizard finishes.

**Step F — Remove old UserDefaults cleanup (if any existed):**

If there were any `UserDefaults.standard.removeObject(forKey:)` calls for `companySetup_*` keys, remove them (they're no longer needed).

---

## Verification

After making these changes, verify:

1. Run the wizard through all steps — confirm no `companySetup_*` keys appear in `UserDefaults` (use `UserDefaults.standard.dictionaryRepresentation()` in a breakpoint to check)
2. Force-quit mid-wizard, relaunch — confirm wizard resumes with previous values (loading from SQLite draft)
3. Complete the wizard — confirm the `company_setup_draft` table row is deleted
4. Cancel/Exit the wizard — confirm draft row persists for later resume

---

## Notes

- The `company_setup_draft` table has at most **one row** at all times (upsert overwrites it)
- SQLite on iOS uses `NSFileProtectionComplete` when the device is locked — much stronger than UserDefaults
- This change has no effect on the `company_profile` table (the real data destination) — only the wizard's temporary draft state moves to SQLite
- Keep the migration number consistent with the rest of the migration sequence (check `AppDatabase+Migrations.swift` for the last used number)
