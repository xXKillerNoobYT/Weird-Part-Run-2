# PE-023: Strengthen DashboardService and BreakService Test Assertions

**Status:** Open
**Source:** dev-improvement-scanner run 2 (2026-03-31)
**Priority:** Medium
**Pipeline Step:** 7 — Fine-tune (test coverage)

---

## Problem

The new `DashboardServiceTests.swift` and `BreakServiceTests.swift` (31 tests, not yet committed) use mostly weak `>= 0` and `!= nil` assertions. These tests verify the service *doesn't crash* but do not verify *correctness*. They will pass even if every function returns empty/zero values due to a bug.

**Files affected:**
- `core/Tests/WiredPartCoreTests/DashboardServiceTests.swift`
- `core/Tests/WiredPartCoreTests/BreakServiceTests.swift`

---

## Specific Weak Assertions to Strengthen

### DashboardServiceTests.swift

| Test | Current (Weak) | Needed (Strong) |
|------|---------------|-----------------|
| `testCertAlerts` | `alerts.count >= 0` | seed a cert expiring in 7 days, assert count == 1 |
| `testVehicleAlerts` | `alerts.count >= 0` | seed a vehicle with expiring insurance, assert count == 1 |
| `testDailyReport` | `report.pendingJPOs >= 0` | seed a submitted JPO, assert `pendingJPOs == 1` |
| `testExpectedDeliveries` | `deliveries.count >= 0` | seed a PO with `expected_delivery` = tomorrow, assert count >= 1 |
| `testBudgetAlerts` | `alerts.count >= 0` | seed a job at >80% budget, assert count >= 1 |
| `testTeamClockedIn` | `team.count >= 0` | clock in a user, assert `team.count == 1` and `displayName` matches |
| `testStockByLocationType` | `groups.count >= 0` | seed stock in "warehouse", assert group found |
| `testLowStockParts` | `low.count >= 0` | seed part with min_stock=10 and qty=2, assert in results |
| `testLaborChartData` | `data.count >= 0` | seed labor entry today, assert `data.count == 1` with correct date |

### BreakServiceTests.swift

| Test | Current (Weak) | Needed (Strong) |
|------|---------------|-----------------|
| `testGetAllPolicies` | `policies.count >= 2` | assert `policies.count == 2` exactly |
| `testBreakCompliance` | `compliance.takenLunchMinutes >= 0` | after a lunch break, assert `takenLunchMinutes == 30` |
| `testAutoFillEnabled` | `records.count >= 2` | assert exact count matches default break types seeded |
| `testRoundedTime` | `rounded == "10:00" || rounded == "10:15"` | should be deterministic — assert exact expected value |

---

## Seed Helpers Needed

Some of these tests need seed helpers that don't yet exist in `E2ETestHelpers`. Specifically:

- `seedCertification(env, userId:, expiryDate:)` — inserts a certification expiring on a given date
- `seedVehicle(env, insuranceExpiry:)` — inserts a vehicle with expiring insurance
- `seedLaborEntry(env, userId:, clockIn:, clockOut:, jobId:)` — inserts a completed labor entry

---

## Instructions

1. Open `core/Tests/WiredPartCoreTests/DashboardServiceTests.swift`
2. For each weak test listed above, add a seeding step and replace the `>= 0` assertion with a specific value
3. If seed helpers are missing, add them to `E2ETestHelpers.swift` (in the same test target)
4. Run `swift test --package-path core` — all 790 tests must still pass
5. Mark this file as `done` when all assertions are strengthened

---

## Related

- PE-007: Coverage gaps in PeopleService/ChatService/SettingsService (separate issue)
- PE-023 was filed during the dev-improvement-scanner run on 2026-03-31
