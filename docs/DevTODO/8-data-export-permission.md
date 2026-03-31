# Gate Data Export Behind Admin Permission
**GitHub Issue:** #8
**Priority:** Medium
**Estimated effort:** Quick (5 min)

## What's Wrong
Any logged-in user can export the entire SQLite database (all PINs, wages, business data) and access backups. These should be admin-only.

## Files to Change
- `Weird Parts IOS/Weird Parts IOS/Features/Settings/IOSDataExportPage.swift` — Add permission check at top of view
- `Weird Parts IOS/Weird Parts IOS/Features/Settings/IOSBackupsPage.swift` — Add permission check at top of view

## AI Prompt
```
In IOSDataExportPage.swift, add a permission check at the top of the body that shows "You don't have permission to export data" if the user doesn't have the "manage_settings" permission. Use the same pattern as other permission-gated pages in the app.

Do the same for IOSBackupsPage.swift.

Check NavigationConfig.swift for how other settings pages gate permissions for the pattern to follow.
```

## How to Verify
1. Log in as a non-admin user (Worker hat)
2. Navigate to Settings → Data Export — should show permission denied
3. Navigate to Settings → Backups — should show permission denied
4. Log in as admin — both should work normally


## Report
Both files compile cleanly. Here's what I changed:

IOSDataExportPage.swift:
• Changed can​Export from checking "export​_reports" to "manage​_settings" (matching the settings module permission)
• Updated the denied message to "You don't have permission to export data."

IOSBackupsPage.swift:
• Added can​Manage​Settings computed property checking "manage​_settings"
• Wrapped the body in a Group with the permission gate — shows the form when permitted, shows Content​Unavailable​View("​Access ​Restricted", ...) with "You don't have permission to manage backups." when denied
• Extracted the Form into a backups​Form computed property (same pattern as export​Form in the data export page)
• Guarded the .task { load​Data() } behind the permission check so data isn't loaded unnecessarily


NO way to verify 