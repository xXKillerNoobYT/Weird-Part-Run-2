# Prompt 52E — Settings: Make Simulated Features Functional

> **Area:** Settings → Data, AI, Sync pages
> **Dependencies:** None (works on existing pages)
> **What the user sees:** Backups, Export, Update Check, AI Config, and Sync Now all fake their results.
> **What this fixes:** Wire 5 simulated features to real functionality.

---

## Task

Update 5 existing settings pages to replace simulated/placeholder behavior with real functionality.

---

## 1. Backups (`IOSBackupsPage.swift`)

### Current State
Simulated — shows fake "backup complete" after a delay.

### Make Functional

**Create Backup:**
- Get database path from `AppCore.shared.databasePath`
- Create backup directory: `Documents/WiredPart/Backups/` using FileManager
- Copy SQLite file to backup dir with timestamp name: `wiredpart-backup-2026-03-23-143022.sqlite`
- Also copy `-wal` and `-shm` files if they exist (SQLite WAL mode)
- Show actual file size after copy
- Show success with file path, or error if copy fails

**List Existing Backups:**
- Scan `Documents/WiredPart/Backups/` directory
- Show each backup: filename, date (parsed from name), file size (formatted: KB/MB)
- Sort by date descending (newest first)
- Empty state: "No backups yet"

**Delete Old Backups:**
- Swipe to delete individual backups (confirmation alert)
- "Delete All" button in toolbar (confirmation: "Delete all X backups?")
- Actually remove files from disk

**Restore Backup:**
- Tap backup → confirmation: "Restore this backup? Current data will be replaced."
- Copy backup file over current database
- Show "Restart app to complete restore" message

### Error Handling
- FileManager errors → show in `actionError` banner
- Disk space check before backup (warn if < 100MB free)
- Permission errors → clear message

---

## 2. Data Export (`IOSDataExportPage.swift`)

### Current State
Simulated — shows fake export progress.

### Make Functional

**Export Options:**
- Format picker: CSV, JSON
- Data picker (multi-select checkboxes):
  - Parts & Inventory
  - Jobs & Labor
  - Orders & POs
  - People & Contacts
  - Tools & Equipment
  - Fleet & Vehicles

**Generate Export:**
- For each selected data type, query via service layer (NOT raw SQL)
- CSV: standard comma-separated with header row
- JSON: array of objects with property names as keys
- Write to temp file in `tmp/` directory
- File naming: `wiredpart-export-{type}-{date}.{csv|json}`

**Share:**
- After generation, present `UIActivityViewController` (share sheet)
- User can AirDrop, save to Files, email, etc.
- For multiple data types: create individual files, share all at once

**Progress:**
- Show actual progress: "Exporting Parts (1/4)..." with ProgressView
- Cancel button during export

---

## 3. Update Check (`IOSUpdateProtocolPage.swift`)

### Current State
Simulated — always shows "up to date" after delay.

### Make Functional

**Version Check:**
- Read current app version from `Bundle.main.infoDictionary["CFBundleShortVersionString"]`
- Read current build from `Bundle.main.infoDictionary["CFBundleVersion"]`
- Check against stored `latest_known_version` setting (via SettingsService)
- Compare versions: if stored > current → "Update Available", else → "Up to Date"

**Display:**
- Current version: "v{version} (build {build})"
- Status: green checkmark "Up to Date" or orange arrow "Update Available (v{latest})"
- Last checked date (stored in settings)
- "Check Now" button → updates `last_update_check` timestamp

**Note:** This is NOT an actual OTA update system. It just compares version strings. The actual update comes through the App Store or bootstrap server. This page shows the user whether they're current.

---

## 4. AI Config (`IOSAIConfigPage.swift`)

### Current State
Simulated — shows fake "checking availability" with hardcoded result.

### Make Functional

**Availability Check:**
- Call `FoundationModelsService.checkAvailability()` (the real method, not simulated)
- If the method doesn't exist yet, check for `FoundationModels` framework availability:
  ```swift
  if #available(iOS 26, *) {
      // Foundation Models available
  } else {
      // Not available on this iOS version
  }
  ```
- Show actual result: Available, Not Available (iOS version), Not Available (device)

**Display:**
- Device: actual device model (`UIDevice.current.model`)
- iOS version: `UIDevice.current.systemVersion`
- AI Status: green "Available" or red "Not Available" with reason
- If available: show model info, estimated capabilities
- If not available: explain why (iOS version, device limitations)

**Settings (functional):**
- "Enable AI suggestions": toggle (stored in settings)
- "AI response language": picker (English, Spanish — stored in settings)
- These settings are read by the AI system elsewhere in the app

---

## 5. Sync Now (`SyncPage.swift`)

### Current State
Simulated — shows fake sync animation.

### Make Functional

**Sync Attempt:**
- Check if sync is configured: `IOSSyncManager.shared.isSyncConfigured` (or equivalent)
- If configured: call `IOSSyncManager.shared.syncNow()` and show actual result
- If NOT configured: show clear message "Sync not configured. Set up a shop server connection first." with a link/button to Sync settings

**Display:**
- Last sync time (from settings or sync manager)
- Sync status: "Connected", "Not Configured", "Last sync failed"
- If sync in progress: actual ProgressView with cancel
- Error display: actual error message from sync attempt, not generic

**Note:** Don't change the sync infrastructure. Just wire the existing "Sync Now" button to actually call the sync manager instead of faking it.

---

## Build target

iOS only. Must compile. Start prompt 52F next.
