# 35G — Settings Pages: Remove GRDB + Raw SQL (10 Files)

> **Chain position:** **35G** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. All database access goes through service methods
3. If a service method doesn't exist for the query, CREATE it in the appropriate service

## Context

10 Settings pages import GRDB and run raw SQL directly. These need to be migrated to use SettingsService, AuthService, or other appropriate services.

## Files to Fix

All in `Weird Parts IOS/Weird Parts IOS/Features/Settings/`:

1. **IOSBackupsPage.swift** — remove GRDB, use service methods, replace 2x DispatchQueue with async/await
2. **IOSDataExportPage.swift** — remove GRDB, use service methods, replace 4x DispatchQueue with async/await
3. **SecurityAdminPage.swift** — remove GRDB, use AuthService methods, add .refreshable
4. **AuditLogPage.swift** — remove GRDB, use SettingsService or AuthService methods, add .refreshable
5. **IOSUpdateProtocolPage.swift** — remove GRDB, replace DispatchQueue with async/await
6. **IOSIntegrationsPage.swift** — remove GRDB, use SettingsService
7. **IOSKeyManagementPage.swift** — remove GRDB, use AuthService/SettingsService
8. **IOSSupplierBridgePage.swift** — remove GRDB, use ChatService
9. **IOSBootstrapAdminPage.swift** — remove GRDB, use AuthService
10. **IOSClockOutQuestionsPage.swift** — remove GRDB, use SettingsService/JobsService

## Task

For EACH file:
1. Remove `import GRDB`
2. Identify every `db.writer.read` / `db.writer.write` / `Row.fetchAll` call
3. Move the SQL to the appropriate service (create new service methods if needed)
4. Replace raw SQL calls with service method calls
5. Replace any `DispatchQueue.main.asyncAfter` with `Task { try? await Task.sleep(...) }`
6. Remove any `#if os(iOS)` platform guards
7. Ensure `loadError` is set on failures (not just `print()`)

## Success Criteria

- [ ] Zero `import GRDB` in any Settings file
- [ ] Zero raw SQL in any Settings file
- [ ] Zero `DispatchQueue.main.asyncAfter` in any Settings file
- [ ] All errors visible to user
- [ ] Project builds with no errors
