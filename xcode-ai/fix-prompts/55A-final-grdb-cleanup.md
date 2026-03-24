# 55A — Final GRDB Cleanup (5 Remaining Files)

> **Chain position:** Standalone (run early, before feature work)
> **Prerequisite:** None
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

5 UI files still import GRDB and use raw SQL directly. Replace all raw SQL with service layer calls. Add service methods where needed.

## Files to Fix

### 1. IOSDashboardQRScannerPage.swift
- Has `import GRDB` and uses `Row.fetchAll` for stock/location queries
- Move queries to appropriate service (PartsService or WarehouseService)
- Call service methods instead of raw SQL

### 2. IOSEmployeeDetailPage.swift
- Has `import GRDB` and uses `db.writer.write` for employee updates
- Move write operations to PeopleService
- Call service methods instead of raw SQL

### 3. PartsCatalogPage.swift
- Has `import GRDB` and uses `Row.fetchAll`, `db.writer.read/write`
- Move queries to PartsService
- Call service methods instead of raw SQL

### 4. PartsForecastingPage.swift
- Has `import GRDB` and uses `Row.fetchAll` for forecast data
- Should use `PartsService.listForecastDataWithStock()` (already exists)
- Remove raw SQL, use existing service method

### 5. IOSClockPage.swift
- Has `import GRDB` and uses `db.writer.write` for clock operations
- Move write operations to JobsService
- Call service methods instead of raw SQL

## Task

For EACH file:
1. Read the file and identify ALL raw SQL usage
2. Check if a service method already exists for that query
3. If YES → replace raw SQL with service call
4. If NO → add the service method first, then replace
5. Remove `import GRDB`
6. Verify the file compiles without GRDB

## Success Criteria
- [ ] All 5 files have `import GRDB` removed
- [ ] All raw SQL replaced with service layer calls
- [ ] New service methods added where needed
- [ ] Zero `import GRDB` in any file under `Features/`
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 55A Results (YYYY-MM-DD)
- Removed import GRDB from 5 remaining UI files
- Added X new service methods
- Build: [PASS/FAIL]
```
