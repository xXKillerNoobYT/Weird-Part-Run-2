# 53A — Safe Update System (Production Migration Safety)

> **Chain position:** Standalone (critical infrastructure)
> **Prerequisite:** None
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** This is a CRITICAL safety prompt. The current codebase uses `eraseDatabaseOnSchemaChange = true` which wipes the entire database on every schema change. This MUST be wrapped in a DEBUG flag before any production deployment. Additionally, implement pre-update backup and rollback capabilities.

## Context

The app uses GRDB with a `DatabaseMigrator` that registers 40+ migrations. In development, `eraseDatabaseOnSchemaChange = true` is convenient — it wipes and rebuilds the DB when migrations change. In production, this would destroy all user data. We need a safe update path.

**Files to modify:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`
- `core/Sources/WiredPartCore/Database/AppDatabase.swift`
- `Weird Parts IOS/Weird Parts IOS/App/AppCore.swift`

## Task

### Step 1: Wrap eraseDatabaseOnSchemaChange in DEBUG flag

In `AppDatabase+Migrations.swift`, change:

```swift
// BEFORE:
migrator.eraseDatabaseOnSchemaChange = true

// AFTER:
#if DEBUG
migrator.eraseDatabaseOnSchemaChange = true
#endif
```

This keeps the convenient wipe-and-rebuild for development but prevents data loss in production builds.

### Step 2: Add pre-migration backup

In `AppDatabase.swift`, add a backup method:

```swift
/// Create a backup of the database before running migrations.
/// Returns the backup file path, or nil if backup failed.
public static func backupDatabase(atPath path: String) -> String? {
    let fileManager = FileManager.default
    let backupDir = (path as NSString).deletingLastPathComponent + "/Backups"
    try? fileManager.createDirectory(atPath: backupDir, withIntermediateDirectories: true)

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
    let timestamp = dateFormatter.string(from: Date())
    let backupPath = backupDir + "/wiredpart-backup-\(timestamp).sqlite"

    do {
        try fileManager.copyItem(atPath: path, toPath: backupPath)

        // Keep only last 5 backups
        let backups = try fileManager.contentsOfDirectory(atPath: backupDir)
            .filter { $0.hasSuffix(".sqlite") }
            .sorted()
        if backups.count > 5 {
            for old in backups.prefix(backups.count - 5) {
                try? fileManager.removeItem(atPath: backupDir + "/" + old)
            }
        }

        return backupPath
    } catch {
        return nil
    }
}

/// Restore database from a backup file.
public static func restoreDatabase(from backupPath: String, to dbPath: String) throws {
    let fileManager = FileManager.default
    // Remove current DB
    try? fileManager.removeItem(atPath: dbPath)
    try? fileManager.removeItem(atPath: dbPath + "-wal")
    try? fileManager.removeItem(atPath: dbPath + "-shm")
    // Copy backup
    try fileManager.copyItem(atPath: backupPath, toPath: dbPath)
}
```

### Step 3: Add migration safety to AppCore

In `AppCore.swift`, update the database initialization to backup before migrating:

```swift
func setupDatabase() throws {
    let path = try Self.databasePath()

    // Backup before migration (production safety)
    #if !DEBUG
    let backupPath = AppDatabase.backupDatabase(atPath: path)
    #endif

    do {
        let database = try AppDatabase.openDatabase(atPath: path)
        self.db = database
        // ... setup services ...
    } catch {
        #if !DEBUG
        // Migration failed — try to restore from backup
        if let backup = backupPath {
            try? AppDatabase.restoreDatabase(from: backup, to: path)
            // Try again with restored DB (old schema, but data preserved)
            let database = try AppDatabase.openDatabase(atPath: path)
            self.db = database
            // Log the failure for debugging
            print("[AppCore] Migration failed, restored from backup. Error: \(error)")
        }
        #endif
        throw error
    }
}
```

### Step 4: Add migration safety checks to all migrations

Review ALL migrations (000-040) and ensure they use safe patterns:

```swift
// For CREATE TABLE — use ifNotExists:
try db.create(table: "my_table", ifNotExists: true) { t in ... }

// For ALTER TABLE — use try? to handle "column already exists":
try? db.alter(table: "parts") { t in
    t.add(column: "new_column", .text)
}

// For CREATE INDEX — use ifNotExists:
try db.create(index: "idx_name", on: "table", columns: [...], ifNotExists: true)

// For DROP TABLE — always use IF EXISTS:
try? db.drop(table: "old_table")
```

### Step 5: Add version tracking

Store the current schema version in settings after successful migration:

```swift
// After successful migration in AppDatabase.init:
try writer.write { db in
    try db.execute(sql: """
        INSERT OR REPLACE INTO app_settings (key, value)
        VALUES ('db_schema_version', '40'),
               ('last_migration_date', datetime('now'))
    """)
}
```

## Important Notes

- The `#if DEBUG` flag means development builds keep the convenient wipe-and-rebuild behavior
- Production builds NEVER wipe the database — migrations run incrementally
- Pre-migration backup ensures data can be recovered if a migration fails
- The restore flow tries the backup first before throwing the error
- Keep last 5 backups to prevent filling up storage
- All existing migrations (000-040) should be reviewed for `ifNotExists` / `try?` safety
- This prompt is CRITICAL for production deployment — do NOT skip it

## Success Criteria

- [ ] `eraseDatabaseOnSchemaChange` wrapped in `#if DEBUG`
- [ ] `backupDatabase()` method creates timestamped backup
- [ ] `restoreDatabase()` method can restore from backup
- [ ] AppCore backs up before migration in production builds
- [ ] AppCore restores from backup if migration fails
- [ ] Version tracking stored in app_settings
- [ ] At least migrations 035-040 use `ifNotExists` / `try?` safety patterns
- [ ] Project builds with no errors in both DEBUG and RELEASE

## Log Entry

```
## Prompt 53A Results (YYYY-MM-DD)
- Wrapped eraseDatabaseOnSchemaChange in #if DEBUG
- Added backupDatabase() + restoreDatabase() to AppDatabase
- Added pre-migration backup + rollback to AppCore
- Updated migrations with ifNotExists safety
- Added version tracking to app_settings
- Build: [PASS/FAIL]
```
