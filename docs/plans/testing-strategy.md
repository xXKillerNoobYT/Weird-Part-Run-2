# Testing Strategy — WiredPart Core

> **Created:** 2026-03-27
> **Status:** ACTIVE — 545 tests across 40 suites, all passing
> **Framework:** Swift Testing (`@Suite`, `@Test`, `#expect()`)

---

## Overview

The WiredPart testing strategy provides comprehensive coverage of the entire core service layer using Swift Testing framework with in-memory GRDB databases for complete test isolation.

## Test Inventory

### By Category

| Category | Suites | Tests | Files |
|----------|--------|-------|-------|
| Auth & Bootstrap | 2 | ~27 | AuthServiceTests, E2EAuthBootstrapTests |
| Parts & Catalog | 1 | ~30 | E2EPartsCatalogTests |
| Warehouse (Core) | 1 | ~25 | E2EWarehouseTests |
| Warehouse (Audit) | 1 | ~25 | WarehouseAuditTests |
| Warehouse (Floor Plan) | 1 | ~15 | WarehouseFloorPlanTests |
| Jobs & Labor | 1 | ~20 | E2EJobsLaborTests |
| Orders & Procurement | 1 | ~25 | E2EOrdersTests |
| Fleet & People | 1 | ~20 | E2EFleetPeopleTests |
| Scheduling | 1 | ~30 | SchedulingServiceTests |
| Notebooks | 1 | ~15 | NotebooksServiceTests |
| Tools | 1 | ~35 | ToolsServiceTests |
| Settings & Reports | 1 | ~15 | E2ESettingsReportsTests |
| Cross-Service | 1 | ~10 | E2ECrossServiceTests |
| Dashboard | 1 | 22 | DashboardServiceTests |
| Breaks | 1 | 11 | BreakServiceTests |
| Wishlist | 1 | 11 | WishlistServiceTests |
| Background Tasks | 1 | 8 | BackgroundTaskServiceTests |
| Job Estimation | 1 | 17 | JobEstimationServiceTests |
| Daily Report Gen | 1 | 3 | DailyReportGeneratorTests |
| Base Repository | 1 | 17 | BaseRepositoryTests |
| Database & Models | 2 | ~15 | DatabaseTests, ModelTests |
| Sync Infrastructure | 8 | ~80 | ConflictResolver, SyncEngine, SyncServer, ChangeTracker, PeerManager, PeerDiscovery, Multipeer, SyncIntegration, BinarySync, SyncPriorityQueue, SyncCrypto |
| AI/Vision | 4 | ~30 | QRCodec, OCR, ImageMatcher, TextPredictor |
| Device Reset | 1 | ~5 | DeviceResetServiceTests |
| Settings | 1 | ~15 | SettingsServiceTests |
| **TOTAL** | **40** | **545** | **41 files** |

### Production Bugs Found During Testing

| Service | Bug | Fix |
|---------|-----|-----|
| WishlistService | `createdAt: nil` → NOT NULL violation | Set ISO8601 timestamp |
| DailyReportGenerator | `first_name`/`last_name` columns don't exist | Use `display_name` |
| DailyReportGenerator | `break_minutes` column doesn't exist on `labor_entries` | Query `break_records` table |
| DailyReportGenerator | `j.name` doesn't exist on `jobs` | Use `j.job_number` |
| JobEstimationService | `hours_worked` column doesn't exist | Use `regular_hours + overtime_hours` |
| WarehouseService | `p.part_number` doesn't exist on `parts` | Use `p.code` |
| WarehouseService | `from_location`/`to_location` don't exist | Use `from_location_type`/`to_location_type` |
| WarehouseService | `qty` doesn't exist on `po_line_items` | Use `qty_ordered` |
| DashboardService | `jpo.created_by` doesn't exist | Use `jpo.requested_by` |
| ToolsService | FK failure — empty `tool_maintenance_types` | Auto-create default type |

## Test Patterns

### Fresh Environment Pattern
```swift
private func freshEnv() throws -> E2ETestHelpers.TestEnvironment {
    try E2ETestHelpers.setUp()
}
```
Every test creates a fresh in-memory database with all 61 migrations applied and all services initialized.

### Assertion Pattern
```swift
#expect(result.count == 1)           // Value equality
#expect(result != nil)               // Non-nil check
#expect(result.name == "Expected")   // Property check
#expect(result.isEmpty)              // Boolean check
```

### Error Testing Pattern
```swift
#expect(throws: SomeError.self) {
    try service.invalidOperation()
}
```

## Running Tests

```bash
cd /Users/IA/GitHub/Weird-Part-Run-2/core
swift test                          # Run all 545 tests
swift test --filter "AuthService"   # Run specific suite
swift test list                     # List all tests
```

## Future Test Additions

When adding new services or features:
1. Create `NewServiceTests.swift` in `core/Tests/WiredPartCoreTests/`
2. Use `@Suite("NewService Tests")` and `@Test("description")` macros
3. Use `E2ETestHelpers.setUp()` for tests needing full environment
4. Use `AppDatabase.openInMemoryDatabase()` for isolated service tests
5. Cover: CRUD, validation, business rules, edge cases, error paths
