# 35E — Fleet Pages: Remove GRDB + Wire Missing ErrorStateView

> **Chain position:** **35E** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

**2 Fleet pages import GRDB with raw SQL:**
- IOSInspectionsPage — `import GRDB`, `db.writer.read`, `Row.fetchAll`
- IOSTelematicsPage — `import GRDB`, `db.writer.read`, raw SQL

**6 Fleet pages have `loadError` state but NEVER display it:**
- IOSFuelPage, IOSMaintenancePage, IOSMileagePage, IOSTrailerLocationsPage, IOSTrailersPage, IOSTruckToolsPage
- They all set `loadError` in catch blocks but the view body never shows `ErrorStateView`

## Files to Modify

All in `Weird Parts IOS/Weird Parts IOS/Features/Fleet/`:
1. IOSInspectionsPage.swift — remove GRDB, use FleetService
2. IOSTelematicsPage.swift — remove GRDB, use FleetService
3. IOSFuelPage.swift — add ErrorStateView to body
4. IOSMaintenancePage.swift — add ErrorStateView to body
5. IOSMileagePage.swift — add ErrorStateView to body
6. IOSTrailerLocationsPage.swift — add ErrorStateView to body
7. IOSTrailersPage.swift — add ErrorStateView to body
8. IOSTruckToolsPage.swift — add ErrorStateView to body

## Task

### For GRDB files (Inspections + Telematics):
1. Remove `import GRDB`
2. Replace `guard let db = appCore.db` with `guard let service = appCore.fleetService`
3. Move raw SQL to FleetService methods (add `listInspections()` and `listTelematicsData()` if missing)
4. Add `@State private var loadError: String?` if missing
5. Add ErrorStateView to body

### For ErrorStateView-missing files (6 pages):
Add this pattern to the body where the list/content is displayed:
```swift
} else if let error = loadError {
    ErrorStateView(message: error) { loadData() }
}
```

Also replace all `print("[PageName] Load error:")` with just setting `loadError`.

### Remove all `#if os(iOS)` guards in ALL 8 files.

## Success Criteria

- [ ] Zero `import GRDB` in any Fleet file
- [ ] All 8 Fleet pages show errors via ErrorStateView
- [ ] Zero print() error logging
- [ ] Zero #if os(iOS) guards
- [ ] Project builds with no errors
