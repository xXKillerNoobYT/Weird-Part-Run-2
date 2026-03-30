# 35I — Reports Pages: Remove GRDB + Raw SQL

> **Chain position:** **35I** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

2 Reports pages import GRDB and run raw SQL:
- IOSPreBillingPage.swift
- IOSBookkeeperExportPage.swift

Also: IOSToolKitsPage.swift (Tools) imports GRDB.

## Files to Fix

1. `Weird Parts IOS/Weird Parts IOS/Features/Reports/IOSPreBillingPage.swift`
2. `Weird Parts IOS/Weird Parts IOS/Features/Reports/IOSBookkeeperExportPage.swift`
3. `Weird Parts IOS/Weird Parts IOS/Features/Tools/IOSToolKitsPage.swift`

## Task

For EACH file:
1. Remove `import GRDB`
2. Move raw SQL to appropriate service (ReportsService for reports, ToolsService for tools)
3. Create service methods if they don't exist
4. Use `ErrorStateView` instead of `ContentUnavailableView` for error display (consistency)
5. Remove `#if os(iOS)` platform guards

## Success Criteria

- [ ] Zero `import GRDB` in Reports or Tools UI files
- [ ] Error display uses ErrorStateView consistently
- [ ] Project builds with no errors
