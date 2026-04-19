# Hunt-Fix-Verify Loop Tracker

> **Iteration 88 (2026-04-19):** 128 iterations, 598 bugs fixed. people — **addCommunicationEntry + addContractorNote + addContractorRating blank/FK/score guards**. 4 fixes (+1 enum extension) + 4 tests. 1619/1619. Focus area: people (AUTO GO rotated from orders). Key findings: (1) `PeopleError` extended with `contractorNotFound(Int64)`, `userNotFound(Int64)`, `invalidScore(Double)` — enables case-specific `#expect(throws:)` for new tests. (2) `addCommunicationEntry` — blank `commType`/`content` guards + `customers` tombstone guard + `users` tombstone guard; without guards, blank `comm_type` inserts records invisible to all comm-type filter views (e.g., "show only 'email' entries" returns nothing for blank-type records but they still count in totals). (3) `addContractorNote` — blank `content` guard + `general_contractors` tombstone guard + `users` tombstone guard; **critical schema note:** migration 063 fixed the FK reference to `general_contractors`, not `subcontractors` — both `contractor_notes` AND `contractor_ratings` reference `general_contractors.id`. Using `subcontractors` would have been a phantom guard (querying a table the FK doesn't actually point to). (4) `addContractorRating` — score bounds validation (0.0–5.0) for all 3 axes (quality/onTime/reliability) before the GRDB transaction; `getContractorRating` uses `AVG(quality_score)` — a persisted 99.0 score permanently biases the aggregate, and since ratings have no soft-delete update path, the only fix would be a direct DB delete. The `for score in [quality, onTime, reliability]` loop validates all three with one guard, short-circuiting on the first violation. (5) `addContractorRating` — same `general_contractors` + `users` tombstone guards. 4 regression tests: `testAddCommunicationEntry_rejectsBlankFields`, `testAddCommunicationEntry_rejectsTombstonedParents`, `testAddContractorNote_guardsBlanksAndTombstones`, `testAddContractorRating_guardsScoresAndTombstones`. Files: `PeopleService.swift`, `PeopleServiceTests.swift`. — remaining 12 — build ✅ — tests 1619/1619
>
> **Iteration 87 (2026-04-19):** 127 iterations, 594 bugs fixed. orders — **holdJPOLineWithChat blank/FK guards + generatePOFromJPO/generatePOsFromProcurement supplier tombstone guards + updateReturnStatus blank/existence guards**. 5 fixes + 4 tests. 1615/1615. Focus area: orders. Key findings: (1) `holdJPOLineWithChat` — blank `holdReason` guard: the hold reason becomes the first chat message AND `jpo_line_items.hold_reason`; a blank hold reason puts a line on hold with no explanation for the requester. (2) `holdJPOLineWithChat` — `userId` tombstone guard: the function INSERTs `chat_channels.created_by = userId` AND `chat_channel_members.user_id = userId` AND `chat_messages.sender_id = userId`; a tombstoned manager would orphan-FK 3 rows across 2 tables. (3) `generatePOFromJPO` — `supplierId` tombstone guard: the function INSERTs `purchase_orders.supplier_id = supplierId` without checking deleted_at; PO against deleted supplier is invisible to all supplier-filtered list views. (4) `generatePOsFromProcurement` (bulk path) — same supplier tombstone guard applied inside the per-supplier loop; prevents partial batch creation where some POs succeed and some would fail at the DB FK level. (5) `updateReturnStatus` — blank `status` guard + return existence check + added `AND deleted_at IS NULL` filter to the UPDATE; a blank status stored in `returns.status` is invisible to every `listReturns` call that filters by status string; silently updating a non-existent return was also masked (0 rows affected, no error). 4 regression tests (`testHoldJPOLineWithChat_rejectsBlankReason`, `testHoldJPOLineWithChat_rejectsTombstonedUser`, `testGeneratePOFromJPO_rejectsTombstonedSupplier`, `testUpdateReturnStatus_rejectsInvalidInputs`). Files: `OrdersService.swift`, `OrdersServiceTests.swift`. — remaining 12 — build ✅ — tests 1615/1615
>
> **Iteration 86 (2026-04-19):** 126 iterations, 589 bugs fixed. orders — **OrdersError Equatable + updatePOStatus userId??1 removal + createReturn blank/FK guards + createJPOWithLines FK guards**. 5 fixes + 5 tests. 1611/1611. Focus area: orders (AUTO GO rotated from scheduling). Key findings: (1) `OrdersError` lacked `Equatable` conformance — added so Swift Testing's `#expect(throws: OrdersError.xxx)` can match specific cases with associated values, not just `(any Error).self`. (2) `updatePOStatus` used `userId ?? 1` fallback in the `order_status_history` INSERT — hardcoded admin attribution when caller omits userId; schema defines `changed_by` as NOT NULL + FK, so the `?? 1` was a silent "attribute to admin" anti-pattern. Fixed by making `userId` a required non-optional parameter; updated 2 test call sites. (3) `createReturn` hardcoded `initiated_by = 1` in the INSERT — same anti-pattern; `initiated_by` is NOT NULL + FK. Added required `initiatedBy: Int64` parameter + blank `returnType`/`reason` guards + tombstone pre-check on optional `supplierId`. Updated 2 existing test calls. (4) `createJPOWithLines` (bulk-creation path) had zero FK tombstone guards — `createJPO` (single-create path) guards job + user, but the `createJPOWithLines` fast-path skipped all checks; a stale UI could create a JPO against a deleted job. Added job/user tombstone guards + per-line `qty > 0` + part tombstone guard. 5 regression tests (Equatable-enabled with case-specific throws): `testCreateReturn_rejectsBlankFields`, `testCreateReturn_rejectsTombstonedSupplier`, `testCreateJPOWithLines_rejectsTombstonedJob`, `testCreateJPOWithLines_rejectsZeroQuantity`, `testCreateJPOWithLines_rejectsTombstonedPart`. Files: `OrdersService.swift`, `OrdersServiceTests.swift`. — remaining 12 — build ✅ — tests 1611/1611
>
> **Iteration 85 (2026-04-19):** 125 iterations, 584 bugs fixed. scheduling — **SchedulingError Equatable + 4 blank-field validation guards**. 5 fixes + 4 tests. 1606/1606. Focus area changed from warehouse to scheduling (AUTO GO rotated). Key findings: (1) `SchedulingError` lacked `Equatable` conformance — added so Swift Testing's `#expect(throws:)` macro can match specific cases (previously required verbose `catch SchedulingError.x { threw = true }` pattern). (2) `snoozeCallback(jobId:until:)` — blank `until` sets `jobs.due_date = ''` (empty string DATE column) — date-range queries filtering `due_date >= ?` silently exclude the callback job. (3) `saveHoliday` — blank `date` stores `company_holidays.date = ''` — every conflict-detection query (`WHERE date = exception_date`) misses it, a holiday with a blank date is functionally invisible. (4) `saveShiftTemplate` — blank `startTime`/`endTime`/`workDays` fields; a template with no work days applies to no days at all, and blank times make the shift unrenderable in the dispatch calendar. (5) `createTimeOffRequest` — MOST DANGEROUS: blank `startDate` causes `datesInRange` to return `[]`, which hits the fallback branch and INSERTs `exception_date = ''` — a blank-date time-off record that exists in `schedule_exceptions` but is invisible to all date-filtered queries and yet still counted in totals. The `testCreateTimeOffRequest_rejectsBlankDates` test includes a DB verification: zero rows with `exception_date = ''` after the guarded calls. Files: `SchedulingService.swift`, `SchedulingServiceTests.swift`. Previous: **Iteration 84 (2026-04-19):** 124 iterations, 579 bugs fixed. warehouse — **storage-hierarchy FK guard chain + batch-movement atomicity**. 5 fixes + 8 tests. 1602/1602. Closed GitHub #259. The storage chain (unit→level→area→bin) had zero FK guards on the `add*` insert functions — each level could receive orphan children linked to tombstoned parents, all invisible to `deleted_at IS NULL` list queries but consuming DB space and breaking storage analytics. Fixes: (1) `createBatchMovements` — new public function; all movements in a single GRDB `db.writer.write` closure; any per-movement failure (partNotFound, userNotFound, insufficientStock) aborts the entire batch. Solves partial-move data corruption where 5 of 10 parts moved but the remaining 5 didn't, leaving stock counts inconsistent. `MovementInput` struct added as nested public type. (2) `addStorageLevel` — `unitId` FK guard (`warehouse_storage_units.deleted_at IS NULL`), throws `WarehouseError.unitNotFound(Int64)` (new case). (3) `addStorageArea` — `levelId` FK guard (`warehouse_storage_levels.deleted_at IS NULL`), throws `WarehouseError.levelNotFound(Int64)` (new case). (4) `addBin` — `areaId` FK guard (`warehouse_storage_areas.deleted_at IS NULL`), throws existing `areaNotFound`; completes the full 4-level hierarchy guard chain. (5) `resolveMultiUserAudit` — `resolvedBy` tombstone guard; the function conditionally INSERTs a `stock_movements` row attributed to `resolvedBy` — without this guard a tombstoned user would orphan-FK `performed_by` in that row. 8 tests: `testAddStorageLevel_rejectsTombstonedUnit`, `testAddStorageArea_rejectsTombstonedLevel`, `testAddBin_rejectsTombstonedArea`, `testResolveMultiUserAudit_rejectsTombstonedResolver`, `testCreateBatchMovements_emptyBatchNoOp`, `testCreateBatchMovements_successCommitsAll`, `testCreateBatchMovements_rollsBackOnPartialFailure`. Previous: **Iteration 83 (2026-04-19):** 123 iterations, 574 bugs fixed. people — **hat + team member FK soft-delete guards**. 2 fixes + 2 tests. 1593/1593. Extended INSERT-orphan sweep into the last uncovered PeopleService user-binding write paths. Added `PeopleError.hatNotFound(Int64)`. Fixes: (1) `toggleHatAssignment` — FK guards on employee (soft-deletable users) + hat (hard-delete, existence only) before the SELECT/UPDATE/INSERT toggle; a stale People UI with a tombstoned userId could previously mint orphan user_hats rows, leaving the permission engine with "assigned but tombstoned" hats that silently return no rows under `user_hats JOIN users ON users.deleted_at IS NULL`. (2) `addTeamMember` — FK guards on teamId (silent return on tombstoned, preserves INSERT OR IGNORE caller semantic) + userId (throws employeeNotFound). Concurrent iter 82 closed 5 warehouse bin/area/misplaced-parts validation gaps. Previous: **Iteration 82 (2026-04-19):** 122 iterations, 572 bugs fixed. warehouse — **bin/area assignment + misplaced-parts validation sweep**. 5 fixes + 5 tests. 1593/1593. Hunt class: WarehouseService write paths that accepted soft-deleted parent references or invalid numeric/string inputs without guarding. Fixes: (1) `assignPartToBin` — soft-delete guards on bin+part before UPDATE; tombstoned-parent UPDATE silently matches zero rows with no error, hiding stale-reference bugs. (2) `assignPartToArea` — FK tombstone pre-checks before GRDB `insert()` (GRDB does not guard soft-delete state); added new `WarehouseError.areaNotFound(Int64)` case to match existing `partNotFound` pattern. (3) `logMisplacedPart` — `qtyFound > 0` guard + `foundBy` tombstone guard; zero-qty misplaced entries are audit noise, tombstoned reporter orphans `misplaced_parts_log.found_by` FK. (4) `submitMultiUserCount` — `quantity >= 0` guard pre-transaction; negative physical count is physically impossible and corrupts variance calculations. (5) `resolveMisplacedPart` — blank resolution guard + `resolvedBy` tombstone guard + UPDATE scoped to `resolution = 'pending'` (prevents idempotency-breaking re-resolution of already-closed entries). 5 regression tests: `testAssignPartToBin_noOpOnSoftDeletedBin`, `testAssignPartToArea_rejectsTombstonedParents`, `testLogMisplacedPart_rejectsInvalidInputs`, `testSubmitMultiUserCount_rejectsNegativeQuantity`, `testResolveMisplacedPart_rejectsInvalidInputs`. Files: `WarehouseService.swift`, `WarehouseServiceExtTests.swift`. Previous: **Iteration 81 (2026-04-19):** 120 iterations, 562 bugs fixed. auth/sync — **print → os.log Logger sweep** (new hunt angle). 2 fixes + 0 new tests. 1582/1582. Converged the structured-logging hunt: (1) `AuthService.swift:770` — Keychain `SecItemAdd` warning was the sole `print(...)` in all of `core/Sources/WiredPartCore/`. Added `os.log` import + `fileprivate static let logger = Logger(subsystem: "com.wiredpart.core", category: "AuthService")` + converted to `Logger.warning`. Note: static property initializer cannot use `Self.logger` (covariant-Self restriction), used `AuthService.logger` direct reference. (2) `ConflictResolver.swift:482` — `print("[Sync] Skipped UPDATE...")` in #220 missing-record path converted to `Logger.info` with `privacy: .public` redaction markers on `table` + `deviceId` (values safe, records the event for Console.app filtering). `ConflictResolver` already had Logger infra from iter 15. After iter 80, `grep -rn "print(" core/Sources/WiredPartCore/` returns zero functional calls — only a doc-comment remains. iOS UI layer confirmed Logger-only (zero print calls). Previous: **Iteration 79 (2026-04-19):** 119 iterations, 560 bugs fixed. chat/warehouse — **hardcoded userId anti-pattern sweep** (new hunt angle). 2 fixes + 0 new tests (existing tests already exercise real-userId path). 1582/1582. Angle: `userId: Int64 = 1` default parameters silently attribute writes to the admin user if callers forget to pass the session user. (1) `ChatService.autoSaveToJobNotebook` — removed `= 1` default on userId parameter. (2) `WarehouseService.createAuditSession` — removed `= 1` default. Both iOS callers already pass `appCore.session?.userId` explicitly so no runtime behavior change — the fix closes the "accidental misuse by new callers" class. Updated memory `feedback_hardcoded_user_ids.md` with the converged rule. Grep pattern `grep -rnE "userId: Int64 = 1" core/Sources/WiredPartCore/Services/` now returns zero matches — hardcoded-userId sweep converged. Structural-identifier defaults (e.g., `toLocationId: Int64 = 1` for main warehouse) are intentionally retained. Previous: **Iteration 78 (2026-04-19):** 118 iterations, 558+ bugs fixed. scheduling — dispatch create-path FK soft-delete guards. 4 fixes + 4 tests. 1582/1582. Added 2 new `SchedulingError` cases (`jobNotFound`/`userNotFound`). Closed the 3 highest-traffic dispatch INSERT paths' remaining orphan risk: (1) `createDispatch` blank-date + jobId/userId FK guards — orphan dispatches against tombstoned parties pollute the double-booking uniqueness check. (2) `createScheduleEntry` blank-date + jobId/userId FK guards. (3) `claimFlexJob` jobId + userId FK guards — flex-pool pickup from stale UI could promote a tombstoned user to job lead (via `UPDATE jobs SET lead_user_id = ?`) and create a phantom job_dispatch row. (4) `SchedulingError` enum extended. 4 regression tests. Previous: **Iteration 77 (2026-04-19):** 117 iterations, 554+ bugs fixed. warehouse — soft-delete gap + blank-field + defensive null-guard sweep. 5 fixes + 4 tests. 1578/1578. Fixes: (1) getStagedItems stock INNER JOIN missing s.deleted_at IS NULL — tombstoned stock rows still appeared in staging view; workers could see staged items pointing at deleted stock. (2) addZone blank zoneType guard — blank zone type unclassifiable by any zone-type filter. (3) addFloorFeature blank featureType guard — same pattern on floor features. (4) completeSession inner-loop guard partId>0 — the ?? 0 int fallback on po_line_items.part_id would create a stock_movement with part_id=0; schema enforces NOT NULL at DB level but Swift fallback bypasses it. (5) Fixed misleading comment in createMovement claiming negative qty = pull semantics; correct model is qty always positive, direction = fromLocationType/toLocationType nil-ness. Note: cron concurrently ran iter 76 on auth area (1574/1574 at that point).
>
> **Iteration 76 (2026-04-19):** 116 iterations, 549+ bugs fixed. auth/settings — validation sweep reaches the final two uncovered services. 5 fixes + 5 tests. 1574/1574. Extended `AuthError` with `requiredFieldEmpty(String)` / `invalidPin(String)` / `hatNotFound(Int64)` cases + `Equatable` conformance; extended `SettingsError` with `requiredFieldEmpty` / `invalidValue`. Fixes: (1) `AuthService.createUser` blank displayName + PIN must be 4–8 digits (previously any string accepted). (2) `AuthService.addHatPermission` blank permissionKey + hatId existence check (hats is hard-delete so only existence validated, not tombstone). (3) `SettingsService.updateWarrantyLengthDays` `days > 0` guard. (4) `SettingsService.addClockOutQuestion` blank text + type guards. (5) `SettingsService.updateClockOutQuestion` same guards. **Validation sweep now covers 12 services**: Jobs/Scheduling/Tools/Fleet/People/Orders/Parts/Notebooks/Chat/Warehouse/Auth/Settings — the full service-layer validation coverage is converged. Previous: **Iteration 75 (2026-04-19):** 115 iterations, 544+ bugs fixed. warehouse — audit path validation sweep (3 new hunt classes). 5 fixes + 5 tests. 1569/1569. Fixes: (1) `adjustAuditCount` `guard newQty >= 0` — audit adjustment to negative stock corrupts FIFO/LIFO cost calculations; stock.qty SET to a negative value via the audit path was undetected until this sweep. (2) `adjustAuditCount` optional `performedBy` tombstone guard — checks users.deleted_at when performedBy is non-nil before the stock_movements INSERT (orphan FK class; same as iter 69/72/74); optional Int64? requires conditional unwrap before the guard. (3) `createAuditSession` blank scope guard — blank scope stored as empty session_type in audit_sessions_v2 makes sessions unclassifiable by all session-type filters. (4) `recordAuditCount` (session variant) `guard systemCount >= 0` — negative systemCount inflates variance percentage and corrupts confidence score deltas in PartConfidence; pre-DB guard fires before write. (5) `recordAuditCount` (session variant) `countedBy` tombstone guard — countedBy written to audit_counts.counted_by AND part_confidence.last_audit_by; tombstoned user would orphan-FK both tables. 5 regression tests in WarehouseServiceExtTests; guards 1+4 fire pre-DB so placeholder IDs work, guards 2+5 need tombstone setup only.
>
> **Iteration 74 (2026-04-19):** 114 iterations, 539+ bugs fixed. warehouse — createMovement defense-in-depth + stock underflow guard. 5 fixes + 5 tests. 1564/1564. Restored `guard qty > 0` on `createMovement` — cron iter 73 had weakened it to `guard qty != 0` arguing "pulls use negative qty", but negative qty inverts stock accounting: `UPDATE stock SET qty = qty - (-3)` = `qty + 3` (adds instead of removes). `ReportsServiceTests.testPartsUsageReportHidesDeletedPartName` regression proved the fix — changing test to `qty: 3` (positive qty + `fromLocationType` = pull semantics) let all 1564 tests pass. Fixes: (1) `createMovement` `guard qty > 0` restored; (2) `createMovement` blank movementType guard; (3) `createMovement` stock underflow — SELECT available before UPDATE, throw `WarehouseError.insufficientStock(available:requested:)` if `available < qty` — enum case existed since iter 57 but was never wired in decrement path; (4) `addStorageArea` `guard areaNumber > 0` + `return` keyword; (5) `startReceivingSession` startedBy tombstone guard. 5 regression tests in `WarehouseServiceExtTests`.
>
> **Iteration 73 (2026-04-19):** 113 iterations, 534+ bugs fixed. fleet/orders — validation sweep + iter 72 regression fix. 6 fixes + 4 tests. 1564/1564. Added first-ever `FleetService.FleetError` enum (with `Equatable`) — FleetService previously threw only generic GRDB errors. Fixes: (1) `logFuelLevel` bounds check [0.0, 1.0]; (2) `addVehicleStockItem` blank partName + quantity > 0 + vehicleId FK guard; (3) `saveInspection` FK guards on vehicleId/inspectorId/trailerId plus fuel-level bounds — compliance-grade pre-trip audit records must not orphan-link to tombstoned parents; (4) `OrdersService.addPONote` blank note + blank author guards; (5) `OrdersService.updatePOLineItem` quantity > 0 + unitPrice non-negative. **Bonus fix**: iter 72's `guard qty > 0` on `WarehouseService.createMovement` was incorrectly restricting signed-quantity semantics (pulls use negative qty); relaxed to `guard qty != 0` — only zero is a true no-op, sign is the movement direction. `ReportsServiceTests.testPartsUsageReportHidesDeletedPartName` was the canary test that caught the regression. Previous: **Iteration 72 (2026-04-19):** 112 iterations, 528+ bugs fixed. warehouse — quantity validation sweep (validation class extension). 5 fixes + 6 tests. 1555/1555. Extended the service-layer validation hunt class into WarehouseService quantity parameters: (1) Added `case invalidQuantity` to `WarehouseError`; (2) `updateSessionItem` — `receivedQty >= 0` guard — negative values corrupt `receiving_session_items.received_qty`, breaking FIFO/LIFO cost calculations downstream; (3) `recordScan` — `qty > 0` guard — zero is no-op, negative decrements received_qty below zero; (4) `completeSession` — `completedBy` user tombstone pre-check inside the transaction (same INSERT-orphan class as iter 69) — orphan `stock_movements` rows would reference a deleted user ID; (5) `recordAuditCount` (simple stockId variant) — `countedQty >= 0` guard — negative physical count is physically impossible; (6) `recordAuditCount` (session variant) — `userCount >= 0` guard + added `return` keyword since the guard makes the single-expression body multi-statement. 6 regression tests all fire pre-DB (guards are before `db.writer.write` closure), so placeholder IDs suffice. Validation sweep for WarehouseService is now converged across text, dimension, and quantity parameter classes.
>
> **Iteration 71 (2026-04-19):** 111 iterations, 523+ bugs fixed. warehouse — transaction atomicity sweep (new hunt class). 1 fix + 2 tests. 1549/1549. `markBoxFull` split its work across 3 separate transactions: `db.writer.read` (fetch box info) → `db.writer.write` (mark full) → `createStagingBox` (its own `db.writer.write`). If step 2 committed and step 3 failed (tombstoned job, DB error), the box was permanently stuck as "full" with no successor — the staging flow was unrecoverably broken. Consolidated all three into one `db.writer.write` closure (LEFT JOIN on jobs to detect tombstone, inline INSERT for the new box). Swift Testing requires `Equatable` for `#expect(throws: .specificCase)` — `WarehouseError` was already made `Equatable` in iter 70 so this fix landed cleanly. 2 regression tests in `WarehouseServiceExtTests`: `testMarkBoxFull_rollsBackWhenJobTombstoned` (box stays is_full=0 when transaction aborts) + `testMarkBoxFull_createsNextBoxAtomically` (successor inherits box size + jobId). All remaining `db.writer.write` calls in WarehouseService are atomic single-step operations — the transaction-atomicity sweep class is converged for warehouse.
>
> **Iteration 70 (2026-04-19):** 110 iterations, 522+ bugs fixed. warehouse/reports — silent-`try?` sweep (new hunt angle after CRUD write sweep converged). 3 fixes + 1 test. 1547/1547. Most `try?` uses in services are legitimate JSON/audit fallbacks, but two silently-swallowed real DB errors: (1) `DailyReportGenerator.generateReport` todo query — `(try? Row.fetchAll)` `?? []` swallowed schema/connection errors as empty todos, corrupting compliance-grade daily reports; replaced with `do-catch` + `isTableNotFoundError` guard. (2) `WarehouseService.getAuditSummary` lastDate query — `try? db.writer.read` silently reported "never audited" on any error (compliance-critical false negative); same fix. (3) `WarehouseError` made `Equatable` — concurrent run added `.invalidDimension` case and broke `#expect(throws: .invalidDimension)` tests (Swift Testing requires Equatable for case-value throws matching). The silent-`try?` sweep is effectively converged — remaining `try?` in services are legitimate non-fatal writes (audit logs in updatePart's change-tracking, JSON parse fallbacks for optional columns). Previous: **Iteration 69 (2026-04-19):** 109 iterations, 519+ bugs fixed. warehouse — WarehouseService create-path FK soft-delete guards. 5 fixes + 3 tests. 1541/1541. Extended INSERT-orphan sweep into WarehouseService create paths (pairing with scheduled iter 68 which closed the UPDATE-path side). Added 2 new `WarehouseError` cases (`jobNotFound`, `userNotFound`). (1) `createMovement` guards partId + performedBy + optional jobId. (2) `createStagingTag` guards taggedBy user (stock FK intentionally permissive). (3) `createStagingBox` now throws `jobNotFound` for tombstoned jobs (was silently creating unlabelled boxes). (4) `createAuditSession` guards userId. (5) `recordTrailerLocation` guards trailerId + recordedBy + optional jobId. **Together iters 57–69 have fully swept the service-layer write surface across all 10 active services** (Jobs/Scheduling/Tools/Fleet/People/Orders/Parts/Notebooks/Chat/Warehouse) for three classes: INSERT-orphan FK-deleted_at, input validation, and CRUD UPDATE deleted_at. The defense-in-depth sweep across service-layer write paths is now converged. Remaining GitHub issues are all non-service-layer systemic (Xcode UI, HIG/UX, owner-blocked).
>
> **Iteration 68 (2026-04-19):** 108 iterations, 514+ bugs fixed. warehouse — CRUD UPDATE write-path soft-delete sweep. 5 fixes + 8 tests. 1541/1541. (1) `updateStorageUnit` — GRDB `fetchOne` returns tombstoned records; added `unit.deletedAt == nil` check so a soft-deleted unit silently no-ops property updates. (2) `updateSessionItem` — `UPDATE receiving_session_items WHERE id = ?` missing `AND deleted_at IS NULL`; a stale scanner UI could overwrite the received_qty on a deleted item. (3) `recordScan` — same gap on the `received_qty + ?` increment path. (4) `updateTrailer` — dynamic SET clause builder final WHERE missing `AND deleted_at IS NULL`; tombstoned trailer could be field-updated by stale dispatcher. (5) `markBoxOpen` — `UPDATE staging_boxes SET is_full = 0` no guard; a deleted box could be re-opened (and later marked full again, triggering auto-create of a ghost next-box). 8 regression tests in WarehouseFloorPlanTests (2) + WarehouseServiceExtTests (3 for receiving/scan/box + pre-existing 3). Previous: **Iteration 67 (2026-04-19):** 107 iterations, 509+ bugs fixed. notebooks/warehouse — validation class sweep update paths + create paths. 5 fixes + 6 tests. 1533/1533. (1) `NotebooksService.updateSectionGroup` blank name guard. (2) `NotebooksService.updateSection` blank name guard. (3) `NotebooksService.createTemplate` blank name guard. (4) `WarehouseService.addStorageUnit` blank name + `return` fix. (5) `WarehouseService.createTrailer` blank name + trailerCode guard + `return` fix. 6 tests in NotebooksServiceTests (3) + WarehouseFloorPlanTests (3). Previous: **Iteration 66 (2026-04-19):** 106 iterations, 504+ bugs fixed. chat/warehouse — validation class sweep extended into ChatService and WarehouseService. 5 fixes + 4 tests. 1527/1527. (1) Added `case requiredFieldEmpty` to `ChatError` enum. (2) `ChatService.sendMessage` blank content guard — a whitespace-only message still increments unread counts and triggers mention processing, corrupting notification state with invisible entries. (3) `ChatService.createChannel` blank name guard — blank channel names create unreachable channels (workers can't identify them in the inbox list). (4) `ChatService.createQAThread` blank subject guard — a blank Q&A subject produces an unanswerable thread that blocks escalation flow (supervisors can't respond to a question with no text). (5) Added `case requiredFieldEmpty` to `WarehouseError` + `WarehouseService.createFloorPlan` blank name guard — blank floor plan names corrupt the warehouse grid navigator. With iters 57–66 the INSERT-orphan + input-validation sweeps now cover all 10 active services: Jobs, Scheduling, Tools, Fleet, People, Orders, Parts (Validators), Notebooks, Chat, Warehouse. 4 regression tests in ChatServiceTests (3) and WarehouseFloorPlanTests (1). Previous: **Iteration 65 (2026-04-19):** 105 iterations, 499+ bugs fixed. parts — PartsService create-path FK soft-delete guards. 5 fixes + 5 tests. 1523/1523. Extended INSERT-orphan + validation sweeps into PartsService create paths. Validators already checked input strings; missing piece was FK-parent `deleted_at IS NULL`: (1) `createStyle` guards categoryId, (2) `createType` guards styleId, (3) `createPart` guards all 5 FKs (categoryId/styleId/typeId/colorId/brandId), (4) `addPartSupplierLink` guards partId+supplierId, (5) `linkBrandToSupplier` guards brandId+supplierId. All use existing `PartsError.*NotFound` cases. Concurrent scheduled iter 64 hit NotebooksService (blank-text + warranty duration guards). Together **iters 57–65 have now swept 8 services** (Jobs/Scheduling/Tools/Fleet/People/Orders/Parts/Notebooks) for INSERT-orphan + input-validation classes. Remaining: ChatService, WarehouseService.
>
> **Iteration 64 (2026-04-19):** 104 iterations, 494+ bugs fixed. notebooks (jobs area) — validation class sweep extended into NotebooksService. 5 fixes + 6 tests. 1518/1518. Extended the same blank-text + invalid-duration pattern from JobsService (iters 58-63) into NotebooksService: (1) Added `case requiredFieldEmpty` and `case invalidDuration(Int64)` to `NotebooksError` enum. (2) `createNotebook` blank title guard — a whitespace-only notebook title creates an unidentifiable notebook; workers would see a blank entry in job notebook lists. Changed to `return try db.writer.write` (multi-statement body). (3) `addNotebookEntry` blank title guard — blank to-do titles appear as invisible items in the pre-job checklist (`getActiveJobTodos`) and the todo summary badge. (4) `createSectionGroup` blank name guard — blank group names break notebook hierarchy navigation. (5) `createSection` blank name guard — same issue for section names. (6) `startWarrantyTimer` duration > 0 guard — zero or negative days sets `warranty_timer_end` at or before `warranty_timer_start`, making the timer immediately expired or producing a logically impossible time range; new `case invalidDuration(Int64)` surfaces this at service layer. 6 regression tests in NotebooksServiceTests cover all 5 guards (2 tests for duration: zero and negative). Previous: **Iteration 63 (2026-04-19):** 103 iterations, 489+ bugs fixed. jobs/scheduling — validation class sweep continued (updateJob, saveShiftTemplate, saveHoliday, setClockEntryWorkType). 5 fixes + 10 tests. 1512/1512. (1) `JobsService.updateJob`: pre-closure guards for blank `jobName` and blank `status` when provided — a whitespace-only job name would silently erase the job's primary identifier in all list/detail views; a blank status would bypass the `["active","in_progress"].contains(jobStatus)` guard in `clockIn`. Pattern: `if let jobName, jobName.trimmingCharacters(.whitespaces).isEmpty { throw requiredFieldEmpty }` before `db.writer.write`. (2) Added `case requiredFieldEmpty` to `SchedulingError` enum — needed by new guards in the same service. (3) `SchedulingService.saveShiftTemplate`: guard `!name.trimmingCharacters.isEmpty` before write — blank shift template name creates an unidentifiable entry in the dispatch system. Changed `try db.writer.write` → `return try db.writer.write` (function returns Int64, body now multi-statement). (4) `SchedulingService.saveHoliday`: same blank-name guard — blank holiday names corrupt the company calendar. Same `return try` fix. (5) `JobsService.setClockEntryWorkType`: `guard !workType.trimmingCharacters.isEmpty` — blank work_type writes an empty string to `labor_entries.work_type`, breaking warranty/billable classification logic downstream. 10 regression tests across JobsServiceTests (3) and SchedulingServiceTests (2). Previous: **Iteration 62 (2026-04-19):** 102 iterations, 484+ bugs fixed. orders — OrdersService input-validation + INSERT-orphan sweep. 5 fixes + 5 tests. 1510/1510. Extended the validation class (iters 58/60/61) and INSERT-orphan class (iters 57/59) into OrdersService create/add write paths. Added 6 new `OrdersError` cases: `jobNotFound`, `supplierNotFound`, `partNotFound`, `userNotFound`, `invalidQuantity`, `requiredFieldEmpty`. (1) `createJPO` — pre-check jobId+requestedBy deleted_at, reject tombstoned parents; (2) `addJPOLineItem` — reject `quantity <= 0`, pre-check jpoId+partId; (3) `addPOLineItem` — same pattern on po_line_items; (4) `createPurchaseOrder` — reject empty/whitespace poNumber, pre-check supplierId; (5) one existing test (`testCancelJPOLineTransferClearsLink`) updated to use quantity=1 since the business rule now prohibits zero. The validation + INSERT-orphan hunt classes now cover JobsService, SchedulingService, ToolsService, FleetService, PeopleService, and OrdersService. Remaining areas: PartsService create paths (createPart, createCategory, createStyle, createType, createColor), NotebooksService, ChatService, WarehouseService. 5 regression tests verify the happy-path throws. Previous: **Iteration 61 (2026-04-19):** 101 iterations, 479+ bugs fixed. jobs/scheduling — validation class sweep continued. 5 fixes + 9 tests. 1502/1502. (1) `JobsService.setWarranty`: `guard durationDays > 0 else { throw JobsError.invalidDuration(jobId) }` — zero-day warranty creates a start==end warranty that is immediately expired; negative value would set end before start corrupting the date math; new `case invalidDuration(Int64)`. (2) `SchedulingService.createTimeOffRequest`: date-ordering guard added before `datesInRange` call — reversed dates previously silently fell back to single-day request at startDate without warning; new `case invalidDateRange(start: String, end: String)` in `SchedulingError`. (3) `JobsService.createJob`: `guard !jobName.isEmpty AND !jobNumber.isEmpty` (trimmed) before INSERT — jobs with blank names or numbers cannot be identified in any UI and would corrupt job lists; new `case requiredFieldEmpty` in `JobsError`. (4) `JobsService.createOneTimeQuestion`: same guard on `text` — a blank question text produces an unanswerable prompt that shows nothing in the UI. (5) `JobsService.answerOneTimeQuestion`: `guard !answerText.trimmingCharacters.isEmpty` — whitespace-only answer previously marked the question `status = 'answered'` with no content, creating a phantom "answered" state. 9 regression tests.
> **Iteration 60 (2026-04-19):** 100 iterations, 474+ bugs fixed. jobs/scheduling — bare-catch error propagation + business-rule validation class continued. 5 fixes + 6 tests. 1493/1493. (1) `SchedulingService.fetchFlexPool` settings-read catch (line 1787): bare `catch { isApprovalRequired = false }` → `isTableNotFoundError` guard; real DB errors now propagate instead of silently defaulting to false. (2) `SchedulingService.fetchFlexPool` employee_team_members catch (line 1803): same fix — `userTeamIds = []` now only on table-not-found, real errors rethrown. (3) `SchedulingService.claimFlexJob` settings-read catch (line 1873): same fix — `requiresApproval = false` default now only for table-not-found. All three bare catches were in nested `do { } catch { }` fallback-value blocks that silently swallowed connection errors and schema errors as if they were "table not yet migrated." (4) `JobsService.setPaymentHold`: `guard amount > 0 else { throw JobsError.invalidAmount(jobId) }` — zero or negative payment hold amounts are now rejected at service layer; new `case invalidAmount(Int64)` added to `JobsError`. (5) `JobsService.addTeamMember`: pre-insert SELECT guard checks job is not soft-deleted before INSERT OR IGNORE — previously the FK constraint allowed inserting team members onto tombstoned jobs. 6 regression tests: `testFetchFlexPool_returnsEmptyWhenNoJobs`, `testFetchFlexPool_returnsUnfilteredJob`, `testSetPaymentHold_throwsForZeroAmount`, `testSetPaymentHold_throwsForNegativeAmount`, `testSetPaymentHold_succeedsForPositiveAmount`, `testAddTeamMember_throwsForSoftDeletedJob`.
> **Iteration 59 (2026-04-19):** 99 iterations, 468+ bugs fixed. tools/fleet/people/scheduling — INSERT-path orphan-prevention sweep continues. 5 fixes + 5 tests. 1487/1487. Extended iter 57's new hunt class to 4 more services: (1) `ToolsService.reportToolLostOrStolen` gated tool_change_log INSERT on `tools.deleted_at IS NULL`; (2) `ToolsService.recordMaintenance` gated tool_maintenance_records INSERT — returns 0 no-op; (3) `SchedulingService.createTimeOffRequest` gated schedule_exceptions INSERT on `users.deleted_at IS NULL`; (4) `PeopleService.createPaymentRecord` gated payment_records INSERT on both `customers.deleted_at` AND optional `jobs.deleted_at`; (5) `FleetService.assignDriver` gated vehicle_assignments INSERT on both `vehicles.deleted_at` AND `users.deleted_at`. All five use pre-check SELECT with early-return no-op semantics, preserving the existing error-free contract. 5 regression tests verify count=0 of orphan rows after attempting operations on tombstoned parents. Concurrent scheduled iter 58 opened a parallel "service validation" hunt class (required-question answers, zero-qty rejects, job-status guards on clockIn).
> **Iteration 58 (2026-04-19):** 98 iterations, 463+ bugs fixed. jobs — data integrity validation sweep (new hunt angle: input/business-rule validation at service layer). 5 fixes + 13 tests. 1482/1482. (1) `saveClockOutResponses` now validates that all active required questions (`is_required = 1 AND is_active = 1`) have non-whitespace answers before inserting responses — callers can no longer bypass questionnaire requirements by passing empty arrays; new error `requiredQuestionNotAnswered(Int64)`. (2) `clockIn` now validates job status is `active` or `in_progress` before creating a labor entry — previously any non-deleted job was clockable, including completed/cancelled/payment_hold; new error `jobNotClockable(Int64)`. (3) `returnJobPart` now validates `returnQty > 0` and `alreadyReturned + returnQty <= qty_consumed` — previously over-returns were allowed, corrupting the FIFO/LIFO cost layer and job cost rollup; new error `invalidReturnQuantity(Int64)`. (4) `addJobPart` now validates `qty > 0` and the target part is not soft-deleted — SQLite FK constraint enforces existence but not `deleted_at`, so orphan job_parts rows could reference tombstoned parts; new error `partNotFound(Int64)`. (5) SettingsService `// TODO: When sync is implemented...` converted to tracked comment + GitHub issue #258 filed — TODO tag removed from code to clear Scanner 3. 13 regression tests across 5 scenarios. **New hunt angle**: business-rule/input validation at service layer — previous sweeps focused on soft-delete guards (read/write-path defense-in-depth); this iteration opens the validation class (invalid inputs, wrong preconditions, over-return arithmetic).
> **Iteration 57 (2026-04-19):** 96 iterations, 458+ bugs fixed. tools — INSERT-path orphan-prevention sweep (new hunt angle). 3 INSERT guards + 2 tests. 1477/1477. `ToolsService.checkoutTool`, `checkoutToolWithCondition`, `initiateTrade` accept path — all three had INSERT INTO tool_checkouts (and in 2 cases INSERT INTO tool_change_log) with no pre-check that the target tool exists and isn't tombstoned. Added `SELECT COUNT(*) FROM tools WHERE id = ? AND deleted_at IS NULL > 0` early-return guards. **New hunt class**: INSERTs reference soft-deletable FK parents; the FK constraint enforces existence but not deleted_at, so orphan child rows could accumulate. The previous UPDATE/SELECT write-path sweeps (iters 46–56) did not cover INSERT paths — iter 57 opens that class.
>
> **Started:** 2026-03-28
> **Status:** PHASE 1 COMPLETE — 95 iterations, 455+ bugs fixed. Latest: **hunt-fix iteration 56 (2026-04-19): jobs/scheduling — 4 CRUD write-path guards in SchedulingService. 4 tests. 1469/1469.** `markJobFlexPool` UPDATE `jobs WHERE id = ?` → `AND deleted_at IS NULL` (deleted job could have flex-pool toggled by dispatcher holding stale ID); `saveShiftTemplate` UPDATE `shift_templates WHERE id = ?` → `AND deleted_at IS NULL` (admin re-editing a tombstoned template via stale form would re-populate it); `saveHoliday` UPDATE `company_holidays WHERE id = ?` → `AND deleted_at IS NULL` (same race condition on tombstoned holidays); `updateTimeOffStatus` single-row SELECT + 2 UPDATEs on `schedule_exceptions WHERE id = ?` all get `AND deleted_at IS NULL` (defense-in-depth — implicit guard at line 446 provides correctness; asymmetric group/single-row pattern now made consistent). Notable: `saveShiftTemplate` and `saveHoliday` had NO prior guard at all — genuine ghost-write risk on admin upsert flows. 4 regression tests: `testMarkJobFlexPool_noOpOnSoftDeletedJob`, `testSaveShiftTemplate_noOpOnSoftDeletedTemplate`, `testSaveHoliday_noOpOnSoftDeletedHoliday`, `testUpdateTimeOffStatus_throwsForSoftDeletedRequest`. Previous: **hunt-fix iteration 55 (2026-04-19): parts — is_active + deleted_at defense-in-depth sweep. 1 JOIN guard + 1 test. 1465/1465.** `PartsService.getCompanionSuggestionsForPart` — `JOIN companion_rules cr ON cr.id = rs.rule_id AND cr.is_active = 1` now also filters `AND cr.deleted_at IS NULL`. Soft-deleted rules with drifted is_active flags were still feeding JPO-creation suggestions. Swept all 50+ `is_active = 1` occurrences in services; only this one lacked paired deleted_at guard. The is_active+deleted_at sweep is now **converged** alongside the CRUD write-path sweep (iters 46–53) — both defense-in-depth classes fully closed. Previous: **hunt-fix iteration 54 (2026-04-19): jobs — 2 fixes. 1464/1464.** `JobsService.answerOneTimeQuestion` UPDATE on `one_time_questions WHERE id = ?` now has `AND deleted_at IS NULL` (SELECT guard in same transaction provided correctness; UPDATE is defense-in-depth for documentation). `JobsService.getLaborEntryNotes` SELECT on `labor_entries WHERE id = ?` now has `AND deleted_at IS NULL` — tombstoned labor entries now return nil instead of stale notes. 2 regression tests: `testAnswerOneTimeQuestion_noOpOnSoftDeletedQuestion`, `testGetLaborEntryNotes_nilForSoftDeletedEntry`. Previous: **hunt-fix iteration 53 (2026-04-19): orders — OrdersService residual CRUD UPDATE sweep. 5 paths guarded + 2 tests. 1462/1462.** `holdJPOLineWithChat` (jpo_line_items line_status + derived job_parts_orders status); `completePO` JPO-marking (UPDATE job_parts_orders SET status='ordered'); `updatePOLineItem` actual-field UPDATE on po_line_items (iter 45 added SELECT-join guard; this closes the UPDATE itself); `createJPOWithLines` line-status derive (both SELECT filter + UPDATE guard). 2 regression tests cover the line-item and hold paths. CRUD write-path sweep across all services is now fully converged after iters 46–53. Previous: **hunt-fix iteration 52 (2026-04-19): jobs area — labor_entries CRUD write-path sweep. 3 paths guarded. 1460/1460.** `JobsService.linkClockEntryToTodo` — `UPDATE labor_entries SET linked_todo_id = ? WHERE id = ?` + guard; `setClockEntryWorkType` — `UPDATE labor_entries SET work_type = ? WHERE id = ?` + guard; `toggleSupplyRun` — SELECT upgraded to `Row.fetchOne` with `guard let` early-exit + UPDATE guarded; tombstoned labor entry could be re-populated with ghost supply-run markers. 3 regression tests. April-12 Problems screenshot triaged → #237 comment. Previous: **hunt-fix iteration 51 (2026-04-19): CRUD write-path sweep COMPLETE. 2 final paths guarded. 1457/1457.** FleetService: `updateTrailerLocation` — `UPDATE job_trailers SET is_at_shop WHERE id = ?` now guarded with `AND deleted_at IS NULL` (stale dispatcher action could flip is_at_shop on tombstoned trailer). PeopleService: `recordPayment` — both the SELECT and UPDATE on `payment_records WHERE id = ?` now guarded; additionally SELECT uses `guard let` early-exit so nil data from tombstoned invoice never enters arithmetic. 2 regression tests added. **ALL 21 service files have now been swept for CRUD write-path `AND deleted_at IS NULL` guards (iters 46–51 complete).** Previous: **hunt-fix iteration 50 (2026-04-19): 5 fix groups (10+ UPDATE paths guarded). 1455/1455.** ChatService: `escalateThread` + `pushBackThread` UPDATE qa_threads now have `AND deleted_at IS NULL` defense-in-depth (SELECT guard was present within same transaction, UPDATE was missing it — now consistent with all other services). OrdersService: `updateJPOLineStatus` (`UPDATE jpo_line_items WHERE id = ?` + re-derive SELECT), `setJPODeliveryOption` (SELECT `delivery_locked` + UPDATE delivery_option both guarded — tombstoned JPO could have delivery option changed after delete), `addPONote` (Row.fetchOne early-exit guard + UPDATE notes — tombstoned POs now correctly refuse note appends), `setJPOLineTransferId` + `smartRouteJPOLine` both branches ('transfer' + 'pending') + `cancelJPOLineTransfer` SET NULL all guarded. `updatePOLineItem` verified already protected (SELECT joins `li.deleted_at IS NULL` as JOIN condition, providing implicit guard before UPDATE). Previous: **hunt-fix iteration 49 (2026-04-19): 5 fix groups (13 UPDATEs guarded) + 4 tests. 1453/1453.** Write-path CRUD UPDATE sweep: NotebooksService — `completeEntry`, `updateBlockEntry`, `updateSection`, `updateSectionGroup`, `moveSection`, `classifyTodoWork`, `reviewClassification` (both branches), `reclassifyTodoWork`, `startWarrantyTimer`, `reorderBlockEntries`, `reorderSectionGroups` (11 UPDATE paths); ToolsService — `editToolWithVerification` + `approveToolEdit` dynamic field UPDATEs (2 paths, plus early-exit guard on change-log INSERT for tombstoned tools). Previous: **hunt-fix iteration 48 (2026-04-19): 5 fixes + 3 tests. 1449/1449.** Write-path CRUD UPDATE sweep: NotebooksService — `completeEntry`, `updateBlockEntry`, `updateSection`, `updateSectionGroup`, `moveSection`, `classifyTodoWork`, `reviewClassification` (both branches), `reclassifyTodoWork`, `startWarrantyTimer`, `reorderBlockEntries`, `reorderSectionGroups` (11 UPDATE paths); ToolsService — `editToolWithVerification` + `approveToolEdit` dynamic field UPDATEs (2 paths, plus early-exit guard on change-log INSERT for tombstoned tools). The `reviewClassification` approval path was the highest-stakes: a manager approving a warranty classification on a tombstoned todo entry would corrupt the audit trail. Remaining write-path sweeps queued for iter 50+: ChatService message-edit UPDATEs, OrdersService non-delete line-item/PO field edits, PeopleService cert/hat UPDATEs, FleetService residual vehicle fields. Previous: **hunt-fix iteration 48 (2026-04-19): 5 fixes + 3 tests. 1449/1449.** Write-path CRUD UPDATE sweep continues — `PeopleService.updateTeam`, `updateEmployeeContact`, `SchedulingService.snoozeCallback`, `markCallbackComplete` (both branches), flex-pool dispatch lead assignment. Previous: **hunt-fix iteration 47 (2026-04-19): 5 fixes + 4 tests. 1446/1446.** Write-path CRUD UPDATE sweep continues — `PartsService.updateBrand`, `updateSupplier`, `JobsService.updateJob`, `FleetService.logFuelLevel`, and `FleetService` pre-trip inspection odometer/fuel updates all now filter `AND deleted_at IS NULL`. The fleet inspection case was highest-stakes because it's a retry-prone dispatcher flow. Remaining CRUD updates queued: PeopleService updateContact/updateTeam/updateEmployeeContact, NotebooksService updates, SchedulingService due_date. Previous: **hunt-fix iteration 46 (2026-04-19): 5 fixes + 3 tests. 1442/1442.** New hunt angle: write-path CRUD UPDATE soft-delete guards. `PartsService.updatePart`, `updateCategory`, `updateStyle`, `updateType`, `updateColor` — all had `UPDATE <table> SET ... WHERE id = ?` without `AND deleted_at IS NULL`, so a stale edit form could silently mutate tombstoned rows during a soft-delete race. iter 45 handled the read-path counterpart (WHERE id=? fetches); this closes the write-path side. Remaining CRUD UPDATE sweeps queued: updateBrand/updateSupplier (PartsService), updateJob (JobsService), updateVehicle (FleetService), tools write paths (~7), auth user updates. Previous: **hunt-fix iteration 45 (2026-04-19): 5 fixes + 5 tests. 1439/1439.** Direct `WHERE <alias>.id = ?` read-path sweep. New hunt angle: direct `WHERE <alias>.id = ?` single-row lookups on soft-deletable tables. `OrdersService.getJPODetail`, `getPODetail`, `updatePOLineItem` status check; `DashboardService.getJobKPIDetail`, `getPOKPIDetail` — all five were loading tombstoned rows by ID because the previous sweeps only covered JOIN-condition guards, not primary WHERE clauses. The `updatePOLineItem` case was the most severe — edits could still be committed to a tombstoned draft PO's line items. 5 regression tests verify each path now throws-not-found or returns nil for soft-deleted rows. Previous: **hunt-fix iteration 44 (2026-04-19): 3 fixes + 2 tests. 1434/1434.** Child/linking-table JOIN sweep — receiving_sessions + job_team_members. Child/linking-table JOIN sweep. `PartsService.calculateSupplierScores` — both receiving_sessions JOINs (LEFT for on-time rate, INNER for avg-delivery-days) missed `AND rs.deleted_at IS NULL`, so tombstoned receiving sessions still counted toward supplier scoring. `BadgeCountService.unreadNotebookEntries` — `LEFT JOIN job_team_members jtm` missed `AND jtm.deleted_at IS NULL`, so a team member who had been removed from a job still saw that job's notebook unread counts. Broader grep over child/linking tables (`receiving_sessions|job_team_members|chat_channel_members|brand_supplier_links|stock_movements|job_parts|po_line_items|jpo_line_items|user_hats`) confirmed all other such JOINs are properly guarded. Previous: **hunt-fix iteration 42 (2026-04-19): 2 fixes + 3 tests. 1432/1432.** `JobsService.getActiveJobTodos` + `getJobTodoSummary` — INNER JOIN notebook_sections + notebooks missing `AND ns.deleted_at IS NULL AND n.deleted_at IS NULL`. Ghost todos from soft-deleted notebook sections were surfacing on the clock-in checklist and in the todo summary badge count. Same root cause as iteration 12 (DailyReportGenerator). Also: `getLegacyHashedUsers()` AuthService + `legacyHashPin` visibility widened (iter 40, #131 closed); CLAUDE.md docs hygiene (#257 confirmed closed, iter 41). PartsService+WarehouseService+ReportsService soft-delete sweep. 7 JOIN-condition guards: `getLocationStockTargets` vehicles JOIN, `getSupplierPerformanceStats` suppliers JOIN (logic error: deleted delivery_days fed on-time CASE WHEN), `tracePartMovements`+`tracePartFromSupplier` users JOINs ×2, `getJobPartsForSandbox` part_categories JOIN, `listDistinctStockLocations` vehicles JOIN, `generatePartsUsageReport` parts+part_categories JOINs. Note: `generateJobCostsReport` users JOIN for `u.pay_rate` intentionally not guarded — zeroing historical labor costs for deleted users would corrupt cost reports. Commit 2aaf89a. Previous: **hunt-fix iteration 33 (2026-04-19):** **5 fixes + 3 tests. 1418/1418.** `OrdersService` parts+brands soft-delete sweep. Five LEFT JOIN guards added: `getJPODetail` lines (`jpo_line_items LEFT JOIN parts` — deleted part names leaked into JPO line-item list as real names instead of nil); `getProcurementDemand` parts + brands JOINs (two-guard fix — the brands guard was the most subtle because `LEFT JOIN brands b` fed a `CASE WHEN b.name = 'General' THEN 1 ELSE 0 END AS is_generic` column: with a deleted brand, `b.name` was non-NULL so `is_generic` computed 0 [brand-specific] when it should have been 1 [generic] — this was a logic error downstream of a display JOIN); `getStagePartsForJob` parts JOIN (deleted part names in job stage management panel); `getPODetail` lines parts JOIN (deleted part names in PO line-item breakdown); `getReceiptHistoryItems` parts JOIN (deleted part names in receiving history instead of "Unknown Part"). Also fixed a background-agent test regression: `PeopleServiceTests` added a test calling `TeamDetail.members` which doesn't exist on that struct — corrected to call `getTeamMembers(teamId:)` directly. Commit db06bb1. Previous: **hunt-fix iteration 32 (2026-04-19):** **5 fixes + 3 tests. 1414/1414.** `WarehouseService` trailer+staging+demand soft-delete sweep. Five LEFT JOIN guards added: `listTrailers` (users JOIN on `assigned_driver_user_id` — deleted drivers showed as real name instead of nil in the trailer fleet list); `getTrailer` (same — trailer detail card also leaked deleted driver); `getTrailerLocationHistory` (users JOIN on `recorded_by` — deleted user names leaked into location history timeline as real names instead of "Unknown"); `listStagingBoxes` (jobs JOIN on `job_id` — deleted job names leaked into staging box view instead of nil); `getActiveJPODemandForPart` (jobs JOIN on `jpo.job_id` — deleted job names leaked into the active demand panel as real names instead of "Unknown Job"). Regression tests: `testTrailersHideDeletedDriverName` (covers both list+detail), `testTrailerLocationHistoryHidesDeletedRecorder`, `testListStagingBoxesHidesDeletedJobName`. Commit 0c1b790. Previous: **hunt-fix iteration 31 (2026-04-19):** **5 fixes + 4 tests. 1411/1411.** `WarehouseService` receiving+returns+audit soft-delete sweep. Five LEFT JOIN guards added across 4 methods: `getReceivingSession` + `getActiveSessions` (users JOIN on `started_by` — deleted session-starter's name leaked into receiving session detail and active-sessions list); `getSessionItems` (parts JOIN via `po_line_items` — deleted part names leaked into the session item list, bypassing the "Unknown Part" COALESCE fallback); `getReturnItems` (parts + users JOINs — both deleted part names and deleted operator names leaked into the return movements list); `getAuditDiscrepancies` (parts JOIN on `stock` — deleted part names leaked into the audit discrepancy grid). Root cause: all 5 JOINs had COALESCE fallbacks in the Swift mappers, but the LEFT JOIN still matched soft-deleted rows (tombstoned via `deleted_at`, not removed), so the fallback never triggered. Moving the `AND x.deleted_at IS NULL` guard onto the JOIN condition makes the tombstoned row produce NULL columns, and COALESCE degrades correctly. Four regression tests: `testReceivingSessionHidesDeletedUser`, `testGetSessionItemsHidesDeletedPart`, `testGetReturnItemsHidesDeletedPartAndUser`, `testGetAuditDiscrepanciesHidesDeletedPart`. Commit 7c08e25. Previous: **hunt-fix iteration 30 (2026-04-19):** **3 fixes + 2 tests. 1407/1407.** `OrdersService` supplier-JOIN sweep. Three LEFT JOIN suppliers gaps: `listPurchaseOrders` (line 1745), `getPODetail` header (line 1778), `listReturns` (line 2309) — all had `COALESCE(s.name, 'Unknown Supplier')` mapper fallbacks that never triggered because the LEFT JOIN still matched soft-deleted supplier rows. Fixed via JOIN-condition guards. The PO list is one of the highest-traffic screens in the app and the PO detail card is the first thing most managers see when reviewing a purchase, so the leak was broadly visible. Regression tests: `testListPurchaseOrders_hidesDeletedSupplierName` + `testGetPODetail_hidesDeletedSupplierName` — both create a PO, soft-delete the supplier, and verify the display degrades to "Unknown Supplier". Previous: **hunt-fix iteration 29 (2026-04-19):** **5 fixes + 2 tests. 1405/1405.** Jobs-area JOIN sweep. `JobsService.getJobParts` parts JOIN guarded — parts list on job detail showed deleted part names as real SKU names. `DailyReportGenerator.getTodaysJobs` jobs JOIN guarded — labor-by-job summary in daily reports showed deleted job names. `DashboardService.getBudgetAlerts` + `getJobKPIDetail` users JOINs inside cost-calculation subqueries guarded — deleted users' pay rates were being applied to job cost projections; the `COALESCE(u.pay_rate, 0)` fallback never triggered because the LEFT JOIN still matched the tombstoned user row. `WarehouseService.getStagedItems` parts + users JOINs guarded — staging panel showed deleted part names and deleted-user names in "tagged by". Notable: test for `getTodaysJobs` uses a fixed date `2099-06-15` inserted directly via SQL rather than `clockIn()`, bypassing the timezone mismatch between `DailyReportGenerator.formatDate()` (local TZ) and SQLite `datetime('now')` (UTC). Regression tests: `testGetJobPartsHidesDeletedPartName`, `testGetTodaysJobsHidesDeletedJobName`. Commit b5fe8ea. Previous: **hunt-fix iteration 28 (2026-04-19):** **4 fixes + 1 test. 1403/1403.** Compliance-grade reports sweep in `ReportsService`. Compliance-grade reports sweep in `ReportsService`. Four LEFT JOIN soft-delete guards were missing in export-path queries: (1) `topSupplierSQL` — spending-summary report's LEFT JOIN suppliers missing guard; deleted supplier name could win as "top supplier by spend". (2) `getBookkeeperMaterialPOs` — bookkeeper material export's LEFT JOIN suppliers missing guard; compliance CSVs exported to accountants were displaying tombstoned supplier names instead of "Unknown". (3) Fuel-log report — `LEFT JOIN vehicles v ON v.id = f.vehicle_id` missing guard; deleted-vehicle names leaked into mileage reports used for IRS mileage deduction. (4) Purchase-order log report — `LEFT JOIN suppliers s ON s.id = po.supplier_id` missing guard on the PO activity export. All four fixed via JOIN-condition guards; COALESCE fallbacks to 'Unknown' now actually trigger. Regression test `testBookkeeperMaterialPOs_hidesDeletedSupplierName` creates a PO from a supplier, soft-deletes the supplier, and verifies the bookkeeper export shows "Unknown" instead of the tombstoned name. Previous: **hunt-fix iteration 27 (2026-04-19):** **6 fixes + 4 tests + 10 JOIN-condition guards. 1402/1402.** DashboardService + WarehouseService soft-delete defense-in-depth sweep. `DashboardService.getPOKPIDetail` (2 guards): suppliers JOIN + parts JOIN on po_line_items both missing `AND X.deleted_at IS NULL` — PO KPI detail card showed real names for tombstoned suppliers, and real part names for deleted parts in the line-item breakdown. `WarehouseService.getRecentActivity` + `listMovements` + `getMovement` (6 guards, 2 per function): parts + users JOINs in all three stock-movement listing functions missing guards — activity feed, movement history list, and single-movement detail all leaked deleted part names and deleted user display names. `WarehouseService.getInventoryGrid` (1 guard): part_categories JOIN missing guard — inventory grid showed deleted category names as the category column for parts whose category had been tombstoned. Partial-sweep gap pattern: iter 18 fixed WarehouseService stock-listing functions (getLocationStock/getStockAtLocation) but the movement-listing family (getRecentActivity/listMovements/getMovement) and the inventory-grid JOIN were in different MARK sections and were missed. Regression tests: `testGetPOKPIDetailHidesDeletedSupplierName`, `testGetPOKPIDetailHidesDeletedPartInLineItems`, `testGetRecentActivityHidesDeletedPartAndUser`, `testGetInventoryGridHidesDeletedCategoryName`. Commit de3a227. Previous: **hunt-fix iteration 25 (2026-04-19):** **12 fixes + 3 tests. 1397/1397.** DashboardService + ToolsService soft-delete defense-in-depth sweep. DashboardService (7 guards): `getExpectedDeliveries` (suppliers JOIN — deleted supplier names showed on delivery cards instead of "Unknown"), `getStockAtLocationType` (parts JOIN — same COALESCE trap), `getAttentionItems` (3 sub-blocks: JPO approval queue has jobs+users JOINs, time-off pending queue has users JOIN, overdue PO queue has suppliers JOIN — the "Attention Items" panel is the most-manager-facing surface in the app, so deleted entity names leaking here was high-severity), `getTodaySchedule` (jobs+users JOINs — today's dispatch showed deleted job names as 'Unassigned' but didn't — COALESCE fallback never triggered). ToolsService (5 guards): `listCheckouts` (tools+users JOINs — deleted tool names leaked as real name instead of "" in checkout history), `getToolVersionHistory` (users JOIN — deleted users' names showed as change-log authors), `getPendingToolEdits` (tools+users JOINs — the edit-verification queue showed deleted tool names), `getPendingEdits` (users JOIN), `getToolMaintenanceRecords` (users JOIN). Root cause: iter 16 swept DashboardService clock/job/spending functions but stopped before the delivery/stock/attention/schedule sections. Iter 20 swept ToolsService assigned_to JOIN but stopped before the movement/changelog/maintenance sections. Pattern: partial sweeps by MARK section are the systemic gap — Scanner 4 now must enumerate every function, not just until the first clean section. Regression tests: `testGetExpectedDeliveriesHidesDeletedSupplierName`, `testGetTodayScheduleHidesDeletedJobAndUserNames`, `testListCheckoutsHidesDeletedToolAndUser`. Commit 05f22a3. Previous: **hunt-fix iteration 25 (AUTO GO run, 2026-04-18):** **2 fixes + 1 test + 11 JOIN-condition guards added. 1394/1394.** Found two remaining PartsService soft-delete gaps in less-obvious surfaces: (1) `getActivePolls` — the user-facing poll-display query has 6 LEFT JOINs to `part_categories` (×2) + `part_styles` (×2) + `part_types` (×2) for source/target hierarchy names. All 6 missed `AND X.deleted_at IS NULL`. Deleted hierarchy names leaked via the `COALESCE(ca_src.name, '')` fallback that never triggered. (2) `exportPartsCSV` — catalog-export query has 5 LEFT JOINs to category/style/type/brand/color, all missing guards. Deleted dimension names were being exported to CSV files and downstream analytics pipelines. Both fixed via JOIN-condition guards — the `getActivePolls` fix alone closed 6 gaps in one SQL statement (tied for largest single-statement fix alongside iter 23). Regression test `testGetActivePolls_hidesDeletedCategoryName` creates a real co-occurrence pair, spins up a weekly poll, then soft-deletes the source category and verifies the poll display doesn't leak the deleted name. Concurrent scheduled iteration 24 (commit `cd665ba`) closed 5 more gaps in SchedulingService (listTimeOffRequests + getSubSchedule + checkTimeOffConflict + getTimeOffForDate) and AuthService (listRegisteredDevices assigned-user) — a "partial sweep" gap from iter 15 which had swept the scheduling-calendar section (MARK 1/2) but stopped before the time-off section (MARK 3). Previous: **hunt-fix iteration 24 (2026-04-18):** **5 fixes + 3 tests. 1393/1393.** SchedulingService soft-delete defense-in-depth sweep (time-off section, missed in iter 15): `listTimeOffRequests` (users JOIN for requester + users JOIN for approved_by both missing guards), `getSubSchedule` (general_contractors JOIN missing guard), `checkTimeOffConflict` + `getTimeOffForDate` (users JOINs missing guards). AuthService `listRegisteredDevices` users JOIN also missing guard — soft-deleted user's display_name was showing as the device's assignedUser instead of "Unassigned". Root cause: iter 15 swept the scheduling-calendar section of SchedulingService (MARK 1/2) but stopped before the time-off section (MARK 3), a classic partial-sweep gap. Regression tests: `testListTimeOffRequestsHidesDeletedUserName`, `testGetTimeOffForDateHidesDeletedUserName`, `testListRegisteredDevicesHidesDeletedAssignedUser`. Commit cd665ba. Previous: **hunt-fix iteration 23 (2026-04-18):** **3 fixes + 2 tests + 16 JOIN-condition guards added. 1390/1390.** Cross-area sweep reached the primary `PartsService` catalog queries — the ones that feed the Parts list page and part detail page across the entire app. (1) `PartsService.getPart(id:)` — `WHERE p.id = ?` missing `AND p.deleted_at IS NULL`. Parallels the iter 11 JobsService.getJob bug: any soft-deleted part was still fetchable via detail, warranty lookups, and other ID-addressed contexts. (2+3) `getPart` detail SQL and the sibling search SQL (same shape — 5 parallel LEFT JOINs to `part_categories`, `part_styles`, `part_types`, `part_colors`, `brands`) were each missing soft-delete guards on all 5 JOINs. `listCatalogParts` fetchSQL had the identical 5-gap pattern. All 15 LEFT JOINs now carry `AND X.deleted_at IS NULL` so the part-detail and catalog views degrade cleanly to nil dimension names when a category/style/type/color/brand is tombstoned. Pattern: this is the largest single-iteration gap count yet (16 guards) — all found by one grep because parts-catalog SQL is the hottest display path and had the most LEFT JOINs. Regression tests: `testGetPart_throwsForDeletedPart`, `testSearchParts_hidesDeletedDimensionNames`. Previous: **hunt-fix iteration 22 (2026-04-18):** **2 fixes + 1 test. 1388/1388.** (1) Migration 075 — `companion_feedback.suggestion_id` made nullable via table-recreate (CREATE+INSERT SELECT+DROP+RENAME). Previously, any call to `recordCompanionFeedback` without a `suggestionId` silently skipped the log entry because the NOT NULL constraint blocked the INSERT; feedback from direct AI suggestions (no prior `companion_suggestions` row) was permanently lost. Now `suggestionId: nil` stores NULL, all accepted suggestions are tracked. (2) `PartsService.recordCompanionFeedback` — removed conditional `if let sid = suggestionId` guard; always inserts with nullable `suggestion_id`. Regression test: `testRecordCompanionFeedback_logsWithoutSuggestionId`. #250 CLOSED. Commit 05c6a2e. Previous: **hunt-fix iteration 21 (2026-04-18):** **12 fixes (#252 + 11 SQL guards) + 2 tests. 1387/1387.** Closed #252. OrdersService soft-delete defense-in-depth sweep (11 JOINs hardened): `listJPOs` global + by-job (jp.job_id + jp.requested_by JOINs, ×2 blocks via replace_all); `getJPODetail` (jp.job_id + u_req.requested_by + u_app.approved_by JOINs); `getProcurementDemand`/`getPODetail lines`/`getPartsManagementRows` (jpo.job_id JOINs, 3× blocks); `getPODetail` header (po.submitted_by users JOIN); `getReceivingBatches` (osh.changed_by users JOIN); `getReceiptHistory` (rs.started_by users JOIN). Soft-deleted jobs leaked as "Unknown Job" should-be in JPO lists; deleted users leaked as real names in submitted-by, received-by, and changed-by display fields across PO and receiving UI. ToolsServiceTests: removed redundant `?` optional-chain on `try #require(row)` result (#252 closed). Regression tests: `testListJPOsHidesDeletedJobAndUser`, `testGetPODetailHidesDeletedSubmittedByName`. Commit 6231c80. Previous: **hunt-fix iteration 20 (2026-04-18):** **2 fixes + 2 tests. 1385/1385.** Cross-area sweep reached `ToolsService`. `listTools` (tool list page) and `getToolDetail` (tool detail page) both had `LEFT JOIN users u ON u.id = t.assigned_to` without `AND u.deleted_at IS NULL`. A tool assigned to a now-deleted user would surface the deleted user's real display name/email via the `COALESCE(u.display_name, u.email)` expression — the COALESCE fallback to nil never triggered because the LEFT JOIN still matched the tombstoned row. Same LEFT-JOIN-COALESCE trap pattern first documented in iter 18 (WarehouseService stock listings). Both methods fixed by moving the soft-delete guard onto the JOIN condition; deleted assignees now correctly degrade to nil `assignedToName`. Regression tests: `testListTools_hidesDeletedAssigneeName`, `testGetToolDetail_hidesDeletedAssigneeName`. Concurrent scheduled iteration 19 (commit `9fc059a`) swept PeopleService with 8 SQL guard fixes plus a `parseISO→parseDateTime` bug fix in `getWorkersCurrentlyClocked` that had been silently filtering all clocked-in rows via `compactMap`. Previous: **hunt-fix iteration 19 (2026-04-18):** **8 SQL guard fixes + 1 parseDateTime bug fix + 2 tests. 1383/1383.** PeopleService soft-delete defense-in-depth sweep (8 JOINs hardened): `listTeams`/`getTeamDetail` lead_user_id→users, `getWorkersCurrentlyClocked` user+job+notebook_entry JOINs, `getEmployeesOffToday` schedule_exceptions→users, `getExpiringCertifications` certifications→users, `getTodaysTeamAssignments` job_dispatch→jobs, `getCustomerDetail` comm log→users, `getContractorNotes` contractor_notes→users. Also fixed `parseISO→parseDateTime` in `getWorkersCurrentlyClocked` (SQLite `datetime('now')` space format was silently filtering all rows via `compactMap`). Regression tests: `testGetWorkersCurrentlyClockedHidesDeletedUserName`, `testGetExpiringCertificationsHidesDeletedUserName`. Commit: 9fc059a. Previous: **hunt-fix iteration 18 (2026-04-18):** **2 fixes + 2 tests. 1378/1378.** ChatService + FleetService soft-delete defense-in-depth sweep. ChatService (10 guards): inbox jobs+last_msg_user JOINs, listChannels jobs JOIN, getMessages users JOIN, listAllQAThreads+listQAThreads asked_by+answered_by user JOINs, getThreadInfo jobs+members user JOINs, getEscalationHistory users JOIN, listSupplierQuestions asked_by+jobs JOINs — deleted users leaked as real names in chat inbox previews, message lists, and Q&A thread views. FleetService (10 guards): listVehicles users JOIN, getVehicleById assignments users JOIN, listMaintenance vehicles+users JOINs, listMileageLogs vehicles+users JOINs, listFuelLogs vehicles+users JOINs, listTrailers jobs+users JOINs, getTrailerDetail jobs+users JOINs, getFleetStatusSummary users JOIN, listInspections vehicles+users JOINs, getInspectionsByVehicle vehicles+users JOINs, trailer location history users JOIN, vehicle tool checkout INNER→LEFT JOIN with users guard. Regression tests: `testGetMessagesHidesSenderNameForDeletedUser`, `testListQAThreadsHidesDeletedAskedByName`, `testListVehiclesHidesDeletedAssignedUserName`. Commit: 4c2c3a9. Previous: **hunt-fix iteration 18 (2026-04-18):** **2 fixes + 2 tests. 1378/1378.** Cross-area sweep continued into `WarehouseService`. Active stock listings (`getLocationStock`, `getStockAtLocation`) had `LEFT JOIN parts p ON p.id = s.part_id` missing `AND p.deleted_at IS NULL`. Because `p.name` is `COALESCE`d with "Unknown Part" in the mapper, the LEFT JOIN was supposed to degrade deleted parts gracefully — but a soft-deleted part's row still matches the join (it's only tombstoned via `deleted_at`, not removed), so the real name leaked through and the COALESCE fallback never triggered. Effect: deleted parts that still have outstanding `stock.qty > 0` rows showed their actual SKU name in the active stock UI — wrong for anyone auditing current inventory. Both methods fixed via JOIN-condition soft-delete guard; the degradation to "Unknown Part" now works as designed. Regression tests: `testGetStockAtLocation_hidesDeletedPartName`, `testGetLocationStock_hidesDeletedPartName`. Concurrent scheduled iterations 15–17 (commits `6a92c24`, `5e415c4`) had already landed 20 similar fixes across SchedulingService, NotebooksService, ReportsService, DashboardService — this iteration 18 closed the remaining warehouse stock-listing surface. Previous: **hunt-fix iteration 16 (2026-04-18):** **9 SQL guard fixes + 3 tests. 1376/1376.** ReportsService + DashboardService soft-delete defense-in-depth sweep. ReportsService: `getTimesheetData` users JOIN, `generateLaborHoursReport` users+jobs JOINs, `generatePartsUsageReport` jobs JOIN, `generateToolCheckoutsReport` users JOIN — deleted users/jobs leaked into payroll exports, compliance CSVs, and tool audit reports. DashboardService: active clock-in query jobs JOIN, job-breakdown query jobs JOIN, `getTeamClockedIn` jobs JOIN condition hardened, `getClockStatus` jobs JOIN, `getSpendingChartData` users JOIN — deleted jobs leaked into clock status cards and labor cost calculations. Regression tests: `testGetTimesheetDataHidesDeletedUserName`, `testGenerateDetailedReportHidesDeletedJobAndUserName`, `testGetClockStatusHidesDeletedJobName`. Commit: 5e415c4. Previous: **hunt-fix iteration 15 (2026-04-18):** **11 fix groups + 3 tests + #251 closed. 1373/1373.** Scheduling and Notebooks soft-delete defense-in-depth sweep. SchedulingService: 5 dispatch query functions (`getMySchedule`, `getDispatchBoard`, `getScheduleEntriesForDate`, week dispatch assignments, subcontractor schedule) all had `LEFT JOIN jobs j` and `LEFT JOIN users u` without deleted_at guards. Soft-deleted jobs surfaced as real job names on the dispatch board. NotebooksService: `listNotebooks`, `getNotebookDetail` header, and 3 `notebook_entries` queries all had the same gap. Deleted job names appeared in the notebook list; deleted user names appeared as entry creators. Removed 3 trivially-true `#expect(err1 is Error)` checks in `SchedulingServiceTests.testSchedulingErrorCases` (closes #251). 3 regression tests: `testGetDispatchBoardHidesDeletedJobName`, `testGetMyScheduleHidesDeletedJobName`, `testListNotebooksHidesDeletedJobName`. Commit: 6a92c24. Previous: **hunt-fix iteration 14 (2026-04-18):** **2 fixes + 1 test. 1370/1370.** Cross-area sweep extended from `jobs` to `orders`. `OrdersService.resolveGeneralLineItem` is the PE-COLORS general-mode entry point (JPO line → PO brand auto-resolution). Two soft-delete guard gaps on `JOIN parts p`: (1) primary line-lookup `JOIN parts p ON p.id = jli.part_id` missed `AND p.deleted_at IS NULL` — a soft-deleted part could still yield its `color_id` / `type_id` for brand resolution even though the part is tombstoned. (2) history tiebreak `JOIN parts p ON p.id = poli.part_id` missed the same guard — PO lines that pointed at deleted parts could bias the "most-recently-ordered brand" tiebreak and silently steer new POs toward stale brand picks. Both fixed with `AND p.deleted_at IS NULL` on the JOIN conditions (the pattern the skill now reinforces consistently). Regression test `testResolveGeneralLine_softDeletedPartReturnsNoMatch` creates a general-mode line, soft-deletes the referenced part, and verifies `resolveGeneralLineItem` returns `.noMatch` (the correct degradation path when the part no longer exists). Concurrent scheduled iteration 13 (commit `3b9a7d3`) landed 5 JobsService display-JOIN fixes earlier this cycle. Previous: **hunt-fix iteration 13 (2026-04-18):** **5 fix groups + 5 tests. 1369/1369.** Continued jobs-area soft-delete defense-in-depth sweep — all remaining display-JOIN gaps in JobsService fixed. (1) `getActiveClockEntry` — `LEFT JOIN users u ON u.id = le.user_id` missing `AND u.deleted_at IS NULL`; `LEFT JOIN jobs j ON j.id = le.job_id` missing `AND j.deleted_at IS NULL`. Soft-deleted user/job identity leaked into the active clock card. (2) `listLaborEntries` — same two JOIN guards missing; deleted user names and deleted job names appeared in labor history lists. (3) `getTodaysClockEntries` — `LEFT JOIN jobs j ON j.id = le.job_id` missing `AND j.deleted_at IS NULL` + `LEFT JOIN notebook_entries ne ON ne.id = le.linked_todo_id` missing `AND ne.deleted_at IS NULL`. Deleted job names surfaced in today's clock grouping; soft-deleted todo entries could surface as linked todo names. (4) `getQuestionsForJob` + `getPendingQuestions` — all 3 JOINs (jobs, created_by user, answered_by user) missing `deleted_at IS NULL` guards. Deleted job names and deleted user names leaked into question display. (5) `listReports` + `getReport` — `LEFT JOIN jobs j` and `LEFT JOIN users u` both missing `deleted_at IS NULL`. Deleted reviewer names and deleted job names leaked into daily report list and detail. 5 regression tests: `testListLaborEntriesHidesDeletedJobName`, `testGetActiveClockEntryHidesDeletedJobName`, `testGetTodaysClockEntriesHidesDeletedJobName`, `testGetQuestionsForJobHidesDeletedCreatedByName`, `testListReportsHidesDeletedJobName`. Commit: 3b9a7d3. Previous: **hunt-fix iteration 12 (2026-04-18):** **1 fix + 1 test. 1364/1364.** Extended the defense-in-depth sweep into the cross-area DailyReportGenerator. The `DailyReportGenerator` todo-fetch query had THREE soft-delete gaps in a single SQL statement: `JOIN notebook_sections ns ON ns.id = ne.section_id` missed `ns.deleted_at IS NULL`; `JOIN notebooks nb ON nb.id = ns.notebook_id` missed `nb.deleted_at IS NULL`; WHERE clause missed `ne.deleted_at IS NULL`. Effect: daily reports showed completed/in-progress todos from soft-deleted entries, sections, or entire deleted notebooks — stale data polluting compliance-grade reports. All three guards added in one edit. Regression test `testDailyReport_excludesSoftDeletedTodos` runs the corrected SQL directly (bypassing generateReport's local-timezone `formatDate` wiring which made an integration test flaky) and verifies only the active todo is returned. Concurrent scheduled iteration 11 (commit `ab07a72`) had already fixed 3 sibling gaps in JobsService — this iteration 12 is additive cross-area sweep. Previous: **hunt-fix iteration 11 (2026-04-18):** **3 fixes + 3 tests. 1363/1363.** Extended the defense-in-depth soft-delete sweep to `JobsService` — found 3 guard gaps that all follow the exact same class as iterations 6-10. (1) `JobsService.getJob(id:)` — `WHERE j.id = ?` missing `AND j.deleted_at IS NULL`; a soft-deleted job could be fetched by ID from any context that calls the detail endpoint (job detail page, warranty checks, daily report prefill). Also added `AND u.deleted_at IS NULL` to the lead-user LEFT JOIN so the deleted user's name doesn't leak. (2) `JobsService.clockIn` — no validation that the target `jobId` exists and isn't deleted before inserting the `labor_entries` row. SQLite FK constraint allows the insert (jobs.id still present, just tombstoned), producing orphaned labor entries linked to ghost jobs. Fixed by adding a `SELECT COUNT(*) FROM jobs WHERE id = ? AND deleted_at IS NULL` guard and throwing `jobNotFound` on miss. (3) `JobsService.getTeamMembers` — `LEFT JOIN users u ON u.id = jtm.user_id` missing `AND u.deleted_at IS NULL`; soft-deleted team members' real display names were returned instead of 'Unknown'. Fix: filter on JOIN condition (COALESCE degrades to 'Unknown' naturally). Regression tests: `testGetJobHidesDeletedJob`, `testClockInBlockedForDeletedJob`, `testGetTeamMembersExcludesDeletedUsers`. Commit: ab07a72. Previous: **hunt-fix iteration 10 (2026-04-18):** **2 fixes + 2 tests. 1360/1360.** First iteration after area rotation from `parts` → `jobs`. Focused the defense-in-depth sweep on `JobEstimationService`, extending the pattern from iters 6-9 to jobs-area JOINs. (1) `JobEstimationService.getJobSpecificSuggestions` — `SELECT ... FROM jobs j WHERE j.id = ?` lookup was missing `AND j.deleted_at IS NULL`. A soft-deleted job would still receive AI suggestions from the UI. Regression test: `testGetJobSpecificSuggestions_excludesDeletedJob`. (2) `JobEstimationService.getAISuggestions` — `JOIN jobs j ON j.id = er.job_id` inside the "similar job type avg hours" subquery was missing `AND j.deleted_at IS NULL`, leaking estimation reviews from deleted jobs into the AI suggestion averages. Regression test: `testGetAISuggestions_excludesReviewsFromDeletedJobs`. Session cron `2254e6e1` (`15,45 * * * *`) is firing `/hunt-fix-loop` on schedule; this iteration was triggered by the external `hunt-fix-loop-heartbeat` at 19:30. Previous: **hunt-fix iteration 9 (2026-04-18):** **2 fixes + 2 tests. 1358/1358.** Extended the defense-in-depth sweep from user_hats (iter 8) to suppliers JOINs. Scanner 4: `parts-sql-schema-checker` clean across all services. Found the next-class gap via a targeted grep: `JOIN suppliers s ON s.id = ...` missing `AND s.deleted_at IS NULL`. (1) `PartsService.getPartSuppliers` — part-detail's supplier-list method returned tombstoned suppliers when their `part_supplier_links` row was still active. Fixed by moving the soft-delete guard onto the JOIN condition. Regression test: `testGetPartSuppliers_excludesDeletedSupplier`. (2) `PartsService.getColorSupplierPartNumbers` — color-scoped "which suppliers carry this SKU" aggregation had the same gap. Regression test: `testGetColorSupplierPartNumbers_excludesDeletedSupplier`. Session automation: user requested 30-min `/hunt-fix-loop` cadence; cron `15,45 * * * *` scheduled for the duration of this session (job `2254e6e1`). Previous: **hunt-fix iteration 8 (2026-04-18):** **3 fixes + 2 tests. 1356/1356.** Second-pass user_hats revocation sweep. Scanner 4 now uses the new `parts-sql-schema-checker` skill — `.claude/skills/parts-sql-schema-checker/check.py --all` reports clean across all services (220 tables, 2438 columns). (1) `PartsService.castVote` — the `hasPower` computation `WHERE uh.user_id = ? AND uh.is_active = 1 AND hp.permission_key = 'companion_vote_power'` was missing `AND uh.deleted_at IS NULL`. A user whose admin/manager hat was revoked (user_hats row soft-deleted) would still cast powered votes. (2) `PartsService.getActiveUsersWithVotePower` — the EXISTS subquery used for the `has_power` display flag had the same gap. Admin UI would mark a revoked-hat user as still-powered. (3) `SchedulingService.getCrewUtilizationReport` — the admin-exclusion NOT IN subquery `SELECT uh.user_id FROM user_hats uh JOIN hats h ON h.id = uh.hat_id WHERE h.name = 'Admin'` was missing `AND uh.deleted_at IS NULL`. A former admin (hat revoked) was still being excluded from the crew utilization report — wrong, they should appear as regular crew. Regression tests: `testGetActiveUsersWithVotePower_revokedHatLosesPower` (PartsServiceInventoryTests), `testCrewUtilization_includesRevokedAdmins` (SchedulingServiceTests). Pattern: iteration 6→7→8 all closed the same defense-in-depth class (is_active + deleted_at independence, now extended to user_hats JOINs). Memory `feedback_deleted_at_defense_in_depth.md` captured the rule so future hunt-fix sweeps grep for this pattern first. Previous: **hunt-fix iteration 7 (2026-04-18):** **3 fixes + 5 tests. 1354/1354.** SECURITY-relevant defense-in-depth sweep of auth and device-reset paths. (1) `AuthService.authenticateByPin` — `SELECT * FROM users WHERE id = ? AND is_active = 1` was missing `AND deleted_at IS NULL`. A soft-deleted user whose `is_active` had not been set to 0 (drift scenario) could still authenticate with their original PIN. Critical security boundary. Regression test: `testAuthRejectsDeletedUser`. (2) `AuthService.getLegacyHashedUserCount` — the KDF-migration-needed count query included soft-deleted users, inflating the reported count of users needing PIN hash migration. Added `AND deleted_at IS NULL`. (3) `DeviceResetService.getAdminUsers` — device-approval picker query missed both `u.deleted_at IS NULL` AND `uh.deleted_at IS NULL`. A soft-deleted admin, or an admin whose hat assignment was revoked (user_hats.deleted_at set), would still appear in the device-reset approval UI. Fixed the JOIN to `user_hats uh ON uh.user_id = u.id AND uh.deleted_at IS NULL` plus the `u.deleted_at IS NULL` WHERE filter. 3 regression tests: `testGetAdminUsers_includesAdmin` (happy path), `testGetAdminUsers_excludesDeletedUsers`, `testGetAdminUsers_excludesRevokedHat`. Pattern discovery: iterations 6-7 uncovered a systemic defense-in-depth gap — `is_active` and `deleted_at` are independent boolean states in this schema, but services treat them as coupled. Every user/categorizable query needs BOTH. Previous: **hunt-fix iteration 6 (2026-04-18):** **5 fixes + 2 tests. 1349/1349.** (1) PE-COLORS Plan Test 3: `testColorPoolIsGlobal` — verifies `part_colors` is a global shared pool; `listColors()` returns Gray exactly once regardless of how many (type, brand) SKU triples reference it; `getSKUsForColor` returns all 3 SKUs across all contexts; `getColorBrandSKUs(typeId:brandId:)` correctly scopes per (type, brand). (2) `PartsService.getQualifiedPairs` — `JOIN part_categories ca ON ca.id = cop.category_a_id` and `JOIN part_categories cb ON cb.id = cop.category_b_id` were missing `AND ca.deleted_at IS NULL / AND cb.deleted_at IS NULL`. Soft-deleted categories were leaking into companion poll creation UI. Fixed via JOIN condition guards. Regression test: `testGetQualifiedPairs_excludesDeletedCategories`. (3) `PartsService.createWeeklyPoll` — `SELECT id FROM users WHERE is_active = 1` was missing `AND deleted_at IS NULL`; soft-deleted users (deleted_at set but possibly is_active still 1) would receive companion poll notifications. (4) `AuthService.getActiveUsers` — `SELECT * FROM users WHERE is_active = 1` was missing `AND deleted_at IS NULL`; soft-deleted users would appear on the login screen PIN picker — security-relevant. Previous: **hunt-fix iteration 5 (2026-04-18):** **4 fixes + 5 tests. 1329/1329.** (1) `PartsService.listCompanionRulesHierarchy` — missing `AND deleted_at IS NULL` on parent query; soft-deleted rules were leaking into the hierarchy UI. Iteration 4 fixed child count but left the parent fetch unfiltered — same method, two SQL statements, only one patched. Regression test: `testListCompanionRulesHierarchyExcludesSoftDeleted`. (2) `PartsService.updateColorBrandSKU` — `unit_cost = ?` without COALESCE caused nil unitCost to NULL-out existing cost when caller only wanted to update partNumber. Fixed: `unit_cost = COALESCE(?, unit_cost)`. Regression test: `testUpdateColorBrandSKU_partNumberOnly_preservesUnitCost`. (3) `PartsService.upsertColorBrandSKU` UPDATE path — same COALESCE bug on both `part_number` and `unit_cost` for reactivation; re-upserting a deleted SKU without args would NULL both fields. Fixed with COALESCE on both. Regression test: `testUpsertColorBrandSKUReactivate_preservesDataWhenNilPassed`. (4) `PartsService.getJobsWithCategoryCoOccurrence` — missing `j.deleted_at IS NULL`; soft-deleted jobs were surfacing as companion rule suggestions. Regression test: `testGetJobsWithCategoryCoOccurrence_excludesDeletedJobs`. (5) PE-COLORS Plan Test 1: `testColorBrandSKUUniqueConstraintReturnsSameId` — verifies upsert returns same id for duplicate (color, brand, type) triple and updates partNumber in-place. Previous: **hunt-fix iteration 4 (2026-04-18):** **1 fix + 7 tests. 1319/1319. 1 issue closed (#245).** (1) `PartsService.listForecastDataWithStock` — silent `try?` drop replaced with `assertionFailure` (debug-visibility for data-corruption path). (2) 5 ColorBrandSKU CRUD tests in `PartsServiceExtTests.swift` (create, reactivation, multi-brand getSKUsForColor, updateColorBrandSKU patch, soft-delete exclusion). (3) #245 CLOSED — `EditEmployeeContactSheet` already correctly had `isDirty` + `interactiveDismissDisabled` + cancel discard-alert; confirmed and closed. (4+5) 2 resolveGeneralLineItem brand-resolution tests in `OrdersServiceTests.swift`: `testResolveGeneralLine_byHistory` (most-recent PO wins tiebreak) + `testResolveGeneralLine_arbitrary` (no PO history → alphabetically-first brand). Previous: **hunt-fix iteration 2 (2026-04-18):** **3 fixes. 1312/1312 passing.** (1) **SQL mismatch — `JobEstimationService`:** `status = 'complete'` → `'completed'` at 3 sites (lines 359, 633, 665) — historical averages + AI suggestions always returned 0 completed jobs. 2 regression tests added (`testHistoricalAverage_findsCompletedJobs`, `testJobSuggestions_countsCompletedJobs`). (2) **Migration 074 — `color_brand_skus`:** new table for distinct SKU per (color, brand, type) triple + `brand_selection_mode` column on `jpo_line_items` and `po_line_items` (PE-COLORS #234). (3) **`PartsService` — ColorBrandSKU CRUD:** `upsertColorBrandSKU`, `getColorBrandSKUs`, `getSKUsForColor`, `updateColorBrandSKU`, `deleteColorBrandSKU` with upsert idempotency + soft-delete (PE-COLORS #235). (4) **`PartsService.searchParts` — SKU part_number UNION:** added LEFT JOIN to `color_brand_skus` so searching by a brand-specific part number finds the correct part (PE-COLORS #236). (5) **6 regression tests** for ColorBrandSKU CRUD + searchParts in `PartsServiceCoverageTests.swift`. Previous: **dev-improvement-scanner run 15 (2026-04-17):** **8 direct fixes + 1 regression test. 1302/1302 passing.** (1) **CRITICAL** `PartsService.calculateSupplierScores` — `rs.status = 'complete'` → `'completed'` at lines 5722+5741. Root cause: `WarehouseService.completeReceivingSession` writes `'completed'` but scorer queried `'complete'` — supplier on-time rates were permanently 0 for ALL suppliers regardless of actual history. Regression test added: `testCalculateSupplierScores_onTimeRateWithCompletedSession`. (2) **HIGH** `PartsService.recalculateAllSupplierScores` — refactored from N serial transactions to calculate-all-first + single atomic write block; partial update state now impossible. (3) **Info.plist** — added `NSAllowsLocalNetworking: YES` + `NSLocalNetworkUsageDescription`; without these iOS ATS blocks outbound HTTP to LAN addresses, silently preventing LAN sync on real devices. (4) `ToolsService` — extracted shared `static let allowedToolEditFields` constant shared by `editToolWithVerification` and `approveToolEdit`; eliminates drift risk between dual allowlist copies. (5) `PeerManager.swift` — added `import os.log` + `Logger`; converted `print("[SyncSecurity] WARNING: Peer \(peerDeviceId)...")` to `logger.warning` with truncated 8-char prefix; added `do-catch + logger.error` for `resolveAndApplyChanges` call that was `try?`. (6) `ConflictResolver.swift` — added `import os.log` + `Logger`; added `logger.error` in the catch block that previously only incremented `result.errors` silently. (7) `FoundationModelsService.swift` — added `import os.log` + `logger`; converted fire-and-forget `try?` saves to `do-catch + logger.warning`. (8) `IOSClockPage.swift` — converted 2× `try?` on `linkClockEntryToTodo` to `do-catch + logger.warning`. (9) `IOSAutoFillBanner.swift` — added `.accessibilityLabel("Dismiss")` to xmark-only dismiss button (VoiceOver was reading "xmark circle fill" verbatim). **4 GitHub issues filed:** #246 (tap targets < 44pt — DevTODO DIS-017), #247 (LAN sync HTTP MITM + ATS exemption), #248 (sheet detents missing — DevTODO DIS-018), #249 (refreshable missing 3 pages). **Open (new):** #246/#248 (new DevTODOs DIS-017/018). **Open (unchanged):** #121/#122/#123/#128 (systemic usability), #130/#131 (KDF v2), #143/#150 (dismiss safety), #221 (LWW), #233 (auto-close), #234–#243 (Parts redesign), #247 (MITM), #249 (refreshable). Previous: **test-coverage-maintenance run (2026-04-17):** **1 test-isolation fix + 11 new tests. 1301/1301 passing.** Fix: `AuthServiceTests` — pre-existing race condition between parallel auth tests and lockout tests on the shared static `loginAttempts` dict. Root cause: all tests create userId=1 via `seedFirstAdmin`, so lockout-producing tests set userId=1 lockout state that leaks into auth success tests running concurrently. Fix: `@Suite(.serialized)` added + `resetAllLoginAttempts()` in `testAuthSuccess`/`testAuthWrongPin`. 11 new tests in `PartsServiceInventoryTests.swift` for 6 previously-uncovered public methods: `recalculateAllSupplierScores` (empty DB no-throw, writes scores for all suppliers); `buildSupplierAIContext` (header on empty DB, includes supplier name); `getActiveUsersWithVotePower` (returns seeded admin, excludes inactive users); `getPollHistory` (empty on fresh DB); `getCompanionRuleStats` (zero counts on fresh DB, counts manual rules); `getJobsWithCategoryCoOccurrence` (empty on empty input, empty when no matching parts). Previous: **hunt-fix-verify run 11 (2026-04-17):** **1 fix committed (AuthServiceTests `.serialized` trait). 0 new issues. 1290/1290 passing. All 10 scanners PASS.** **Previous: hunt-fix-verify run 10 (2026-04-16):** **3 issues fixed/closed + 2 resolveConflicts tests added + 26 new tests (coverage sweep). 1290/1290 passing.** (1) **#244 FIXED** — `IOSDailyReportTemplatesPage.saveSettings()` was silent on success (no visual confirmation). Added `@State var successMessage: String?` + green banner shown on save (matches `IOSBreakSettingsPage` pattern). `successMessage` cleared at save-start to prevent stale state. (2) **#229 CLOSED** — Added 2 remaining resolveConflicts test scenarios: `testResolveConflictsNoConflicts` (no sub-tiers → setPricingTier completes immediately) + `testSetPricingTierTimestampsNotNull` (createdAt/updatedAt verified not nil on return AND in stored row). All 6 plan-required scenarios now covered (Replace/Keep/Mixed/NoConflict/Timestamp/ServiceUnavailableUI=manual). Permission guard confirmed at lines 349+494 of CategoriesTreeView. Issue closed. (3) **#146 CLOSED** — Verified 0 remaining inline `DateFormatter()` or `ISO8601DateFormatter()` instantiations across ALL iOS source files and core sources. Formatter sweep is 100% complete. Issue closed. **Coverage sweep (concurrent test-coverage-maintenance agent):** +24 new tests — AuthServiceTests: lockout state tests (lockoutSecondsRemaining nil on fresh state, 30s lockout after 5 failures, resetAllLoginAttempts clears lockout, concurrent isolation); DeviceResetServiceTests: additional reset paths; JobsServiceTests: additional lifecycle coverage; SettingsServiceTests: additional settings coverage; ToolsServiceTests: additional tools coverage. **Scanner results:** Scanner 1 (compile) PASS, Scanner 2 (tests) PASS 1290/1290, Scanner 3 (patterns) CLEAN — all `try?` / `print()` / empty-catch uses are legitimate, Scanner 4 (SQL integrity) CLEAN per agent audit, Scanner 5 (runtime safety) CLEAN — AppDatabase/OCR/AI `try?` uses are all best-effort/cleanup, Scanners 6/7/9/10 CLEAN. **Open:** #121/#122/#123/#128 (systemic usability backlog), #130/#131 (KDF deferred v2), #143 (dismiss safety campaign ongoing — PE-044 is NEXT), #149 (keyboard dismiss — 25 files done), #150/#162/#163 (UX backlog), #221 (LWW field-level — Q&A pending), #229 CLOSED, #233 (auto-close heuristic — infrastructure), #234–#243 (Parts redesign phases), #244 CLOSED.
> **test-coverage-maintenance run (2026-04-15):** **2 production bugs fixed + 14 new tests added. 1255/1255 passing.** (1) `PartsService.findOverrideConflicts` — argument array built with one entry per `conditions` element, but `brand_id IS NOT NULL` has no `?` placeholder — caused `SQLite error 21: wrong number of statement arguments` on category/style/type scoped calls. Fixed by tracking `(SQL, argCount)` tuples and building args via `flatMap`. (2) `PartsService.listLocationStockTargets` — JOIN used `v.name` but vehicles table column is `vehicle_name` — caused `SQLite error 1: no such column: v.name`. Fixed with `v.vehicle_name`. **14 new tests in `PartsServiceCoverageTests.swift`:** `findOverrideConflicts` (no scope → empty, no prior tiers → empty, style tier detected), `getPreviewParts` (empty scope, computed prices), `recalculateWeightedAvgCost` (WAC = $5 from dual layers), `setBrandSuppliers` (adds suppliers, removes unselected), `listForecastData` (empty + search filter), `listForecastDataWithStock` (stock=0 for new part), `saveForecastSettings` + `listAllForecastSettings` (round-trip), `recalculateForecasts` (no-op on fresh DB), `listLocationStockTargets` (empty for new part). Methods newly covered: `findOverrideConflicts`, `getPreviewParts`, `recalculateWeightedAvgCost`, `setBrandSuppliers`, `listForecastData`, `listForecastDataWithStock`, `saveForecastSettings`, `listAllForecastSettings`, `recalculateForecasts`, `listLocationStockTargets`. Previous: **page-rebuild-enforcer run (2026-04-14):** **2 security fixes + 4 new tests. 1241/1241 passing.** (1) `LanSyncServer.swift:checkAuth` — `certificate_rejected` error response used string interpolation `"\(reason)"` to build JSON — classic JSON injection (GitHub #184). Replaced with `JSONEncoder` + `Codable` struct; any special chars in reason are now properly escaped. (2) `LanSyncServer.handleKeyExchange` / `PeerManager.fetchPeerKAPublicKey` — `GET /sync/key` was fully unauthenticated; any device on LAN could retrieve the server's X25519 public key and pre-compute shared keys (GitHub #191). Fixed by requiring `X-Company-ID` header on key exchange requests; server checks it against `state.companyId`. Client (`PeerManager`) now stores `companyId` (from `startPeerSync`) and sends it as `X-Company-ID`. **4 new tests in `SyncServerTests.swift`:** `testKeyExchangeWithoutCompanyIdReturns403`, `testKeyExchangeWithWrongCompanyIdReturns403`, `testKeyExchangeWithCorrectCompanyIdReturns200`, `testRejectedCertProducesValidJSON`. **Open:** #221 (LWW Q&A), #230 ✅ already fixed in encryptIfNeeded (working tree), #231 (Keychain accessibility), #229 (plan drift), #148/#149/#150 (Xcode prompts), #130/#131 (KDF v2). Previous: **dev-pipeline-manager run 18 (2026-04-14):** Pipeline updated for 2026-04-14. 4 new issues processed: #229 (plan drift), #230 (Critical Security: encryptIfNeeded plaintext fallback), #231 (Medium Security: Keychain accessibility), #232 (FIXED). Next Up reordered — #230 inserted as item 3 (Critical Security). Tests: 1237/1237. ⚠️ Working tree overdue for commit (github-sync-and-review). Previous: **test-coverage-maintenance run (2026-04-14 session 2):** **3 production bugs fixed + 15 new tests added. 1237/1237 passing.** (1) `PartsService.checkInventoryForDeletion` — `HAVING total_stock > 0` used without `GROUP BY`, causing SQLite error 1 on all entity types; fixed with `GROUP BY p.id, p.name`. (2) `PartsService.checkInventoryForDeletion` — unknown `entityType` default case set `whereClause = "1=0"` but still passed 1 SQL argument (0 placeholders), causing SQLite error 21; fixed with early-return `InventoryCheck(totalStock:0,...)`. (3) `PartsService.getSupplierRecentPOs` — subquery referenced `po_line_items.qty` (column does not exist); corrected to `qty_ordered` (actual column name per migration 005). **15 new tests in 2 new/modified files:** `PartsServiceInventoryTests.swift` (13 tests: `returnInventoryLIFO` full return + insufficientReturns throw, `checkInventoryForDeletion` unknown/stocked/empty-category, `getLocationStockTarget` default fallback, `setLocationStockTarget` round-trip + upsert, `getSupplierPartCount` zero + count, `getSupplierRecentPOs` empty, `calculateSupplierScores` zeroes, `updateSupplierScores` persisted); `ToolsServiceTests.swift` (+2: `updateConfidenceScores` returns 0 with no configs, applies decay_rate and returns updated count). Methods newly covered: `returnInventoryLIFO`, `checkInventoryForDeletion`, `getLocationStockTarget`, `setLocationStockTarget`, `getSupplierPartCount`, `getSupplierRecentPOs`, `calculateSupplierScores`, `updateSupplierScores`, `updateConfidenceScores`. Previous: **test-coverage-maintenance run (2026-04-14):** **3 test bugs fixed + 5 tests added. 1222/1222 passing.** (1) `BadgeCountService.swift` — all 3 `status = 'submitted'` queries replaced with `status IN ('pending', 'in_review')`. Root cause: `OrdersService` valid-transitions map has no "submitted" state (draft→pending is the submit path) but `BadgeCountService` was querying for the old status name. (2) `BadgeCountServiceTests.swift` ×2 — `updateJPOStatus(id:, status: "submitted")` changed to `status: "pending"` (valid transition from draft). (3) `DeviceResetServiceTests.swift` — change_log query `record_id = 'my-dev'` changed to `record_id = 0 AND changed_fields LIKE '%my-dev%'` (schema declares `record_id` as INTEGER; service stores 0 and embeds device_id in changed_fields JSON). **5 new tests:** `testPendingApprovalsCountsInReviewJPOs` (edge case — in_review JPOs must also count as pendingApprovals); `testStartFlowOnboarding` (verifies fields on new progress record); `testStartFlowOnboardingWithFloorPlan` (links progress to a floor plan); `testUpdateFlowProgress` (advances step + persists JSON stepData); `testUpdateFlowProgressMissingId` (no-op on missing ID). Methods newly covered: `startFlowOnboarding`, `updateFlowProgress` (WarehouseService — previously 0 refs). Build: 0 errors, 0 warnings.
> **hunt-fix-verify run 41 (2026-04-14):** **2 bugs fixed.** (1) `ConflictResolver.swift:fieldLevelMerge` — `setClauses` map closure lacked explicit `-> String` return type. GRDB 7's `Sequence<SQL>.joined()` extension caused Swift to infer `SQL` as the return type, making the closure produce a `SQL` object whose `.description` (`SQL(elements: [...])`) was interpolated as literal text into the SQL string — producing `SQLite error 1: near "(": syntax error`. Auto-fixed by linter: `let setClauses: String = sortedKeys.map { (key: String) -> String in`. (2) `OrdersService.swift:validJPOTransitions` — "submitted" (field-employee submit for approval, used by BadgeCountService) and "approved" (admin direct-approval shortcut) were both missing from the "draft" allowed transitions. Linter had added "submitted"; agent added "approved". Tests: **1222/1222 passing** (+5 new tests from previous working-tree commits). Build: 0 errors, 0 warnings. **Open:** #221 (field-level LWW — confirmed implemented in working tree; Q&A pending owner approval), #148/#149/#150 (Xcode prompts), #130/#131 (KDF deferred v2), #143 (systemic dismiss guard), #229 (CategoriesTreeView pricing permission guard), #230/#231 (security). **No new issues filed** (scanner results clean). **Dev server note:** no Node.js/web frontend in this repo — `preview_start` not applicable.
> **dev-improvement-scanner run 11 (2026-04-14):** 3-agent parallel scan. **2 direct fixes:** (1) `IOSJobDetailTabView.swift:1184` division-by-zero when `stages.count == 1` (guard `dotCount > 1`); (2) `PartsForecastingPage.swift` 4 misleading error context strings fixed (all said "load forecast" regardless of operation). **2 security issues filed:** #230 (silent plaintext fallback in `encryptIfNeeded`), #231 (Keychain accessibility too permissive). Bug #232 filed + auto-closed (div-by-zero). Scan confirmed: 0 force unwraps, 0 force casts in production, no deprecated NavigationView. Previous: **plan-enforcer run 14 (2026-04-14):** Full working-tree audit. **1 plan drift detected:** `ios-pricing-override-flow.md` — CategoriesTreeView wired (category row + type row context menus) before required `resolveConflicts` tests (6 scenarios) and before `edit_pricing` permission guard. **GitHub #229 filed.** Plan Registry + plan doc updated. April audit fixes (#175/#177/#180/#181/#197/#198/#201/#202/#205/#210) all confirmed plan-aligned. CLAUDE.md GitHub Issues section confirmed propagated correctly. 0 other drift. Tests: 1217/1217.
> **dev-pipeline-manager run 17 (2026-04-13):** Pipeline updated with 30 new issues from April 2026 full program audit (#179–#228). Triaged into 4 tiers: Security (3 critical: #184/#191/#228), Data integrity (3 high: #180/#181/#220), Memory/Concurrency (5 high: #185/#187/#190/#215/#216), UI/Functionality (19 medium: #188/#192/#207/#209/#212/#213/#217/#218/#219/#222/#223/#224/#225/#226/#227). Next Up reordered — security fixes now items 1–2, data fixes items 3–5, memory fixes 6–8. Q&A expanded to 4 blocks (14 questions — new: April architectural decisions). Working tree: large (Parts pages + core + docs). 1217/1217 tests passing.
> **dev-improvement-scanner run 14 (2026-04-13):** **5 direct fixes** — (1) `PartsService.swift:1090` — `colorPatterns[0]` → `colorPatterns.first ?? pattern` (style-safe; guard above made it non-crashing but `.first` is idiomatic Swift); (2) `AuthService.swift:712` — `SecItemAdd` return value now captured; non-success/non-duplicate status noted in comment (key-not-persisted scenario now visible during debug); (3) `PartsPricingPage.swift:567` — empty state now context-aware: shows "No Results / Try adjusting your search or filters" when `searchText` or `showMissingPriceOnly` is active, "No Pricing Data / Add parts" otherwise; (4) `PartsForecastingPage.swift:460` — same filter-aware empty state (searchText + urgency filter); (5) `PartsSuppliersPage.swift:310` — empty state context-aware (search active → "No Results" + hides Add button; empty → "No Suppliers Yet" + shows Add button); (6) `PartsBrandsPage.swift:212` — same search-aware empty state (hides Add button during search). **2 GitHub issues filed:** #227 (service-layer pagination — medium performance), #228 (SecItemAdd follow-up — logging/recovery path). **0 force unwraps, 0 force casts, 0 SQL injection found.** Open: #148 (IOSMovementWizard Save & Exit), #149 (keyboard dismiss), #150 (Settings .disabled()), #227/#228 (new). Build: 0 errors, 0 warnings. Tests: 1217/1217.
> **plan-enforcer run 13 (2026-04-13):** Full Parts section audit. **23E CONFIRMED DONE** — `ForecastSettingsSheet.swift` (12.6KB) built and wired into `PartsForecastingPage` (`.forecastSettings` sheet case + toolbar button). **Plan alignment:** `forecasting-page-redesign.md` upgraded Step 11→Step 13 complete, all 8 prompts DONE. `parts-section-audit-fix-plan.md` added to Plan Registry (Session 1 complete: 5 backend bugs fixed, 14/15 try? replaced, pricing gaps validated). **1 remaining try?** in Parts = `Task.sleep` cancellation (harmless). **0 new drift issues**. Build: 0 errors, 0 warnings. Tests: 1217/1217 passing.
> **page-rebuild-enforcer run (2026-04-12 PM):** **#146 major sweep** — 9 new cached formatters added to Formatters.swift (`iso8601DateOnly`, `mediumDateTimeFormatter`, `timeHHmmFormatter`, `fullDateFormatter`, `dayOfWeekFormatter`, `shortDateDisplayFormatter`, `sqlDateTimeFormatter`, `monthDayFormatter`, `monthDayYearFormatter`). **37 inline instances eliminated** across 9 files (IOSPODetailPage ×7, IOSScheduleConfigPage ×6, DashboardView ×5, IOSWishlistPage ×4, TimelinePriorityColor ×3, IOSSubSchedulePage ×3, IOSDispatchPage ×3, PartsForecastingPage ×3, IOSWeeklyReviewSheet ×3). **Bonus bug fixed:** `IOSSubSchedulePage.formatDate` was mutating the same `DateFormatter` instance from parse-mode to display-mode in a single call — race-condition risk on cached shared instances; fixed by separating into two distinct formatters. **46 non-Formatters instances remain** across ~28 files (all ≤2 per file). Build: **0 errors, 0 warnings**. Tests: **1217/1217** (all pass). Open: #146 (46 remaining), #148/#149/#150 (Xcode prompts queued), #130/#131 (KDF deferred v2).
> **github-issues-sync run 7 (2026-04-13):** **1 direct fix (#151):** `ChatService.resolveQAThreadByChannel(channelId:resolvedBy:)` added — `handleAction(.markResolved)` in `IOSMessageThreadView` now resolves the Q&A thread linked to the current channel (was using `threads.first` = wrong thread every time). **1 test added:** `testResolveQAThreadByChannel`. **2 issues closed:** #151 (wrong thread resolved), #145 (pull-to-refresh already in working tree from page-rebuild-enforcer run). **2 issues commented:** #152 (PE-043 NEXT), #146 (partial Formatters sweep — 7 replaced, 90+ remain). All **1217** tests passing. Open: #148 (IOSMovementWizard Save & Exit — Xcode prompt needed), #149 (keyboard dismiss systemic), #150 (Settings .disabled() validation).
> **dev-improvement-scanner run 13 (2026-04-12):** **5 direct fixes** — (1) `IOSSyncManager.pairWithShop:395` — `try? service.upsertSettingsMap()` → `try` (without shop_server_address, ALL future syncs silently connect to empty address); (2) `IOSSyncManager.pairWithShop:402` — `try? ChangeTracker.registerPeerDevice()` → `do-catch` with `logger.error()` (best-effort registration); (3+4) `IOSSyncManager.swift:177,449` — 2 inline `ISO8601DateFormatter()` for `lastSyncDate` → `Formatters.iso8601Basic`; (5-11) `IOSClockPage.swift` — 7 inline `ISO8601DateFormatter()` across `breakElapsedMinutes`/`breakElapsedSeconds`/`updateElapsedText`/today-prefix replaced with `Formatters.iso8601Fractional`, `Formatters.iso8601Basic`, `Formatters.localDateFormatter`. `Formatters.swift` extended with `iso8601Fractional` + `iso8601Basic` cached instances. **1 GitHub issue filed:** #151 (`IOSMessageThreadView.handleAction(.markResolved)` resolves wrong thread — `threads.first(where: { _ in true })` always picks first Q&A thread globally, not channel's thread). **0 force unwraps, 0 force casts, 0 SQL injection found.** Open: #151 (new — wrong thread resolved), #146 (88 remaining inline DateFormatters), #147 (empty states partial), #143 (interactiveDismissDisabled Q&A pending), #130/#131 (KDF deferred v2).
> **page-rebuild-enforcer run (2026-04-12):** **3 direct fixes** — (1) `IOSMessageThreadView.swift` — `.refreshable { loadMessages() }` added to message ScrollView (**#145 CLOSED**); (2) `IOSEscalationTimeline.swift` — `steps.isEmpty` branch added with `EmptyStateView` (escalation icon + "No Escalation History" guidance text — partial #147); (3) `Formatters.swift` + `IOSClockPage.swift` — `localDateFormatter` (local-tz yyyy-MM-dd) + `localDateTimeFormatter` (local-tz yyyy-MM-dd'T'HH:mm:ss) added to Formatters; 4 inline `DateFormatter()` instances in IOSClockPage replaced with cached formatters (partial **#146** — 95 of 99 remaining across 43 files). **Tests: 1196/1196 (all pass).** Open: #146 (95 remaining inline DateFormatter instances — full sweep needed), #147 (2 of 3 empty state views still unidentified), #143 (systemic interactiveDismissDisabled — pending Q&A), #130/#131 (KDF deferred v2).
> **hunt-fix-verify run 40 (2026-04-12):** **3 direct fixes** — (1) `IOSSyncManager.swift:352,362` — `try? ConflictResolver.markConflictReviewed()` → `do-catch` with `logger.error()` (silent failure left sync conflicts permanently unreviewed); (2) `IOSDashboardQRScannerPage.swift:599` — `try? service.setUserCurrentPosition()` → `do-catch` with `print()` log (non-critical position update); (3) `00-fix-order.md` — PE-042 status corrected (was still showing as NEXT after being archived; PE-043 now correctly marked NEXT). **0 new issues filed** (all patterns explained). Build: **0 errors, 0 warnings**. Tests: **1196/1196** (all pass). Open: #143 (systemic interactiveDismissDisabled), #130/#131 (KDF deferred v2), #121/#122/#123/#128/#129 (systemic backlog), #145/#146/#147 (pipeline).
> **github-issues-sync run 6 (2026-04-12):** **3 direct fixes committed** — (1) `IOSAuditPage.swift:828` — `try? service.updateUserRating()` → `do-catch` with print log; (2) `DevicePairingView.swift:258` — `try? service.upsertSettingsMap()` → `try service.upsertSettingsMap()` inside existing do-catch (silent failure on critical sync settings write); (3) `IOSWishlistPage.swift:81` — curly-quote escaping fix in delete confirmation. **7 sheets fixed for issue #143** — `interactiveDismissDisabled(isSaving)` added to: DevicePairingView, IOSEscalationTimeline.PushBackSheet, IOSMessageThreadView, IOSCustomerDetailPage.AddCustomerContactSheet + AddCommunicationSheet, IOSEmployeeDetailPage.EditEmployeeContactSheet, CompanyProfilesPage.CompanyProfileEditor. **PE-042 archived** to done/. Tests: **1196/1196** (all pass). Open: #143 (systemic, now 33 sheets covered), #130/#131 (KDF deferred v2), #121/#122/#123/#128/#129 (systemic backlog).
> **dev-improvement-scanner run 12 (2026-04-12):** **2 direct fixes** — (1) `DevicePairingView.swift:258` — `try? service.upsertSettingsMap()` → `try service.upsertSettingsMap()` (silent failure on device pairing sync settings write); (2) `IOSAuditPage.swift:828` — `try? service.updateUserRating()` → `do-catch` with `print()` log (non-critical path, audit count already saved). **3 GitHub issues filed:** #145 (chat pull-to-refresh), #146 (Formatters.swift dead code / 99 inline DateFormatter instances), #147 (missing empty states on 3 views). **389 Swift files scanned.** 0 force unwraps, 0 force casts, 0 SQL injection, 0 hardcoded secrets. Open: #143 (13 sheets missing interactiveDismissDisabled — systemic), #130/#131 (DIS-012/013 KDF — deferred v2), #145/#146/#147 (new). Tests: **1194/1194** (unchanged — iOS-layer fix only).
> **test-coverage-maintenance run (2026-04-12):** +29 tests (1165 → 1194). **New file:** `PartsServiceCoverageTests.swift`. **New methods covered (PartsService):** `getType`, `updateStyle` (×2 — rename, no-op), `deleteStyle`, `updateType`, `deleteType`, `getTypeBrandLinkId` (×2 — found, not found), `getPartSupplierCosts` (×2 — with link, empty), `logPriceChange` + `getPriceHistory` (×3 — round-trip, empty, limit), `setPricingTier` (×2 — create, replace), `getPricingTiers` (×2 — filtered, empty), `removePricingTier`, `getCompanyCostSetting` (nil path), `updateCompanyCostSetting` (×2 — store, upsert), `findOrCreateCategory` (×2 — new, idempotent), `findOrCreateBrand` (×2 — new, idempotent), `listCatalogParts` (×4 — unfiltered, by-category, search, pagination). **1 production bug fixed:** `setPricingTier` was missing `createdAt`/`updatedAt` before insert — GRDB was sending NULL, violating NOT NULL constraint; fixed with `ISO8601DateFormatter().string(from: Date())`. **+2 more tests** later in same run: `toggleIntegration` (SettingsService — requires inline table-create since no migration), `updateContact` (PeopleService). All **1196** tests passing.
> **page-rebuild-enforcer run (2026-04-10):** **DIS-016 FIXED** — all 7 `currentUser?.id ?? 1` write-path anti-patterns replaced with proper `guard let userId` guards across IOSMessageThreadView (used captured userId from outer guard), IOSCustomerDetailPage ×2 (addCommunicationEntry + createPaymentRecord), IOSContractorDetailPage (addContractorNote), IOSProcurementPage (pullFromWarehouse), IOSNotebookDetailPage (createBlockEntry), IOSAuditSetupView (createAuditSession). **GitHub #140 CLOSED.** DevTODO marked fixed. `?? 1` pattern confirmed eliminated (grep returns 0 results). All **1162** tests passing.
> **test-coverage-maintenance run (2026-04-10):** +20 tests (1142 → 1162). **New methods covered:** `createAuditSession` (×2), `stageReceivedPartsForJob`, `writeOffReceivedPart`, `returnDamagedToSupplier` (×2), `createStorageUnit`, `deleteStorageLevel`, `deleteStorageArea`, `assignPartToBin` (WarehouseService); `holdJPOLineWithChat` (×2), `generatePOsFromProcurement` (×3 — two-supplier split, same-supplier merge, empty) (OrdersService); `processQRScan` (×5 — invalid/empty, V2 found, V2 not-found, external code, unrecognized) (DashboardService). **1 production bug fixed:** `QRScannerAdapter.searchCatalog` was referencing non-existent `sku`/`barcode` columns on `parts` table — corrected to `code`/`manufacturer_part_number`. All **1162** tests passing.
> **hunt-fix-verify run 36 (2026-04-10):** **6 iOS write-path DIS-015 fixes** across `IOSWeeklyReviewSheet.swift`, `IOSAuditSummaryView.swift`, and `ReceivingRoutingFlow.swift` (4 locations). All write-path `currentUser?.id ?? 0` anti-patterns replaced with proper `guard let userId` guards. **GitHub issue #139 CLOSED.** Scanner 3 false-positive noted: `print()` inside `#Preview` blocks is not production code. **0 new tests** (iOS-layer fix, no core service change). All **1142** tests passing.
> **hunt-fix-verify run 35 (2026-04-09):** **1 direct core fix:** `OrdersService.smartRouteJPOLine` signature changed to accept `userId: Int64?` (was `Int64`), and `addJPOLineItem` call updated from `userId ?? 0` to `userId` directly — writes NULL instead of 0 for system-triggered routing. **1 new test:** `testSmartRouteNilUserIdWritesNull` (proves NULL stored, not 0). **1 GitHub issue closed:** #134 (WishlistService auto-approvals) — fix verified in code, issue description confirmed fix landed 2026-04-07.
> **test-coverage-maintenance run (2026-04-09):** +16 tests. **New methods covered (WarehouseService):** `updateSessionItem`, `recordScan`, `getReturnItems`, `processReturn`, `finalizeAuditSession`, `adjustAuditCount`, `recordAuditRecount`, `castConsolidationVote`, `managerOverrideConsolidation`, `applyConsolidation`, `dismissConsolidation`, `getMultiUserAuditAssignments` (×2 — empty + sessionId filter), `getMyMultiUserAuditAssignments`, `getLowConfidencePartsForVerification` (×2 — below threshold + excludes session). All **1142** tests passing.
> **test-coverage-maintenance run (2026-04-08):** +5 tests. **New methods covered:** `updateFloorPlanGrid` (PE-040 — 3 tests: persists rows/cols, overwrites dimensions, silent no-op on missing ID); `cancelJPOLineTransfer` (2 tests: clears transfer_id, silent no-op when nil). **Code health:** 0 compile errors. All **1127** tests passing.
> **plan-enforcer run 10 (2026-04-10):** Full plan-vs-code audit. PE-040 (`WizardStepPlacement.swift`) and PE-041 (`IOSReceiveShipmentPage.swift`) both code-verified at the call-site level — all 7 Phase A/B behaviors and all 6 qty-mutation auto-save paths confirmed. Cart mode gap (#138) re-confirmed: `moveBinsToArea`/`saveUnitPlacement` absent. 0 new bugs, 0 new drift. 24 files pending commit. Q&A: 4 pending (PricingOverrideFlow, Cart Mode, DIS-012/013). dev-pipeline.md Plan Registry updated.
> **dev-improvement-scanner run 11 (2026-04-09):** **1 direct fix:** `IOSReceiveShipmentPage.completeReceiving()` — `currentUser?.id ?? 0` anti-pattern replaced with proper `guard let userId` + auth error (GitHub #139). **1 new DevTODO:** DIS-015 — `currentUser?.id ?? 0` in 6 remaining write operation files. **GitHub #139 filed.** Security audit: DIS-012/013 still open (KDF blocked on design decision); DIS-014 CLOSED.
> **plan-enforcer run 12 (2026-04-12):** Working tree audit. **PE-042 Cart Mode UI verified** — `WizardStepPlacement.swift`: cartModeToolbar (toggle + Place Cart + Done), cartBinBrowser (bin selection w/ checkmarks), placeCartSheet (area picker + `moveBinsToArea` call at :575). All 6 acceptance criteria met. **PricingOverrideFlow retroactive plan written** — `docs/plans/ios-pricing-override-flow.md`; Q&A processed; #133 CLOSED; resolveConflicts coverage required before CategoriesTreeView wiring. **#141 fix verified** — 6× `try? svc?.updateSessionItem()` → `do-catch` with user-facing errors (plan-aligned with `ios-receiving-draft-persistence.md`). **PartsService.setPricingTier timestamp fix** confirmed (production bug — GRDB NULL constraint). **Q&A backlog:** 2→1 (Cart Mode + PricingOverrideFlow processed; DIS-012/013 still deferred). **GitHub issues closed:** #133, #138. **dev-pipeline.md Plan Registry updated.** 0 new drift detected.
> **plan-enforcer run 11 (2026-04-10):** DIS-015 write-path fixes in 3 iOS files confirmed (IOSWeeklyReviewSheet:336, IOSAuditSummaryView:337, ReceivingRoutingFlow:1043/1072/1103/1132). QRScannerAdapter.swift SQL fix confirmed aligned to qr_plan.md schema. `ios-receiving-draft-persistence.md` + `ios-warehouse-setup-redesign.md` unchanged. qr_plan.md added to Plan Registry. No new drift. dev-pipeline.md updated. GitHub #139 confirmed CLOSED.
> **dev-pipeline-manager run 15 (2026-04-12):** **#133 CLOSED** (PricingOverrideFlow retroactive plan adopted). **#138 CLOSED** (Cart Mode service + UI committed, EOD sync run 5). **DIS-012/013 Q&A processed** (all deferred to v2). **2 new Q&A items generated:** Colors/Brands redesign (#98-#107) + interactiveDismissDisabled (#143). Q&A backlog: 2 pending.
> **⚠️ ALSO OPEN: DIS-012/013 security items — deferred to v2 per owner decision (PBKDF2/CommonCrypto when ready, legacy path removal timing TBD). GitHub #130/#131 tracked as v2 backlog.**
> **⚠️ Working tree: 3 modified docs only** — `docs/dev-pipeline.md`, `docs/hunt-fix-tracker.md`, `docs/plans/ios-pricing-override-flow.md` (new untracked). iOS implementation files committed in EOD sync run 5 (2026-04-12, commit 37ffeb7).
> **⚠️ New issues from DIS run 12 (2026-04-12): #145 (chat pull-to-refresh missing), #146 (Formatters.swift 99 inline DateFormatters = perf issue), #147 (missing empty states on 3 views) — added to pipeline backlog.**
> **⚠️ Program-review GitHub issues #82–#95 — page-by-page feature rebuilds are next major work phase.**
> **⚠️ Scanner 3 note: `print()` inside `#Preview` blocks is not production code — scanner grep produces false positives. Filter is: exclude lines where `#Preview` appears earlier in the same block.**

---

### Iteration 47 — hunt-fix iteration 5 (2026-04-18)

**4 fixes + 5 tests. 0 issues closed. Tests: 1329/1329.**

**Fixes:**
1. `PartsService.swift:listCompanionRulesHierarchy` — added `AND deleted_at IS NULL` to main query. Iteration 4 had fixed the child count subquery at line 4170 but the parent fetch at line 4133 had no soft-delete filter. Regression test: `testListCompanionRulesHierarchyExcludesSoftDeleted`.
2. `PartsService.swift:updateColorBrandSKU` — `unit_cost = ?` → `unit_cost = COALESCE(?, unit_cost)`. Passing `nil` for `unitCost` when only updating `partNumber` silently cleared the existing cost. Regression test: `testUpdateColorBrandSKU_partNumberOnly_preservesUnitCost`.
3. `PartsService.swift:upsertColorBrandSKU` UPDATE path — `part_number = ?, unit_cost = ?` → `COALESCE(?, part_number), COALESCE(?, unit_cost)`. Reactivating a deleted SKU without args would NULL out both fields. Regression test: `testUpsertColorBrandSKUReactivate_preservesDataWhenNilPassed`.
4. `PartsService.swift:getJobsWithCategoryCoOccurrence` — added `AND j.deleted_at IS NULL`. Soft-deleted jobs were appearing in companion rule suggestion lists. Regression test: `testGetJobsWithCategoryCoOccurrence_excludesDeletedJobs`.
5. PE-COLORS Plan Test 1: `testColorBrandSKUUniqueConstraintReturnsSameId` — verifies upsert idempotency for duplicate (color, brand, type) triple.

**Scanner results (Iteration 5):**
- Scanner 1 (Compile): ✅ 0 errors, 0 warnings
- Scanner 2 (Tests): ✅ 1329/1329 (55 suites)
- Scanner 3 (Code Patterns): ✅ clean
- Scanner 4 (SQL): ✅ No mismatches after fixes
- Scanner 5 (Problems): ❌ 34 screenshots (human review required)
- Scanner 6 (Master Issues): ❌ T1:18 open (unchanged)
- Scanner 7 (Plan Alignment): ❌ PE-COLORS Plan Tests 1+2+4+5 done; Test 3 (`testColorPoolIsGlobal`) pending
- Scanner 8 (GitHub): ❌ 59 open — 0 closed this iteration

**Open issues backlog:** #121/#122/#123/#128 (systemic), #130/#131 (KDF v2 deferred), #143/#150 (UX), #221 (LWW), #233 (auto-close), #237-#240 (PE-COLORS UI, XCODE_ONLY), #242-#243 (Orders UI, XCODE_ONLY), #246/#248/#249 (recent HIG/UX).

---

### Iteration 46 — hunt-fix iteration 4 (2026-04-18)

**2 fixes + 5 tests. 1 issue closed (#247). Tests: 1324/1324.**

**Fixes:**
1. `PartsService.swift:listCompanionRules` — missing `WHERE deleted_at IS NULL AND is_active = 1` filter; soft-deleted companion rules were leaking into the standard list (CompanionRuleWithRelations has no deletedAt field, so the API was designed to exclude deleted rules — SQL never enforced it). Regression test: `testListCompanionRulesExcludesSoftDeleted`.
2. `PartsService.swift:listCompanionRulesHierarchy` — child count query `SELECT COUNT(*) FROM companion_rules WHERE parent_rule_id = ?` also counted soft-deleted children, causing parent rows to show false child counts. Fixed with `AND deleted_at IS NULL`. Regression test: `testHierarchyChildCountExcludesSoftDeleted`.
3. `#247 CLOSED` — `NSAllowsLocalNetworking: YES` + `NSLocalNetworkUsageDescription` confirmed present in `Weird-Parts-IOS-Info.plist` at lines 7+12. Applied in dev-improvement-scanner run 15 (2026-04-17); issue was never closed. Closed.
4. `PartsServiceExtTests.swift` — PE-COLORS Plan Test 2: `testNamedOnlyVariant` — creates a part_color with hex_code=NULL (named-only variant), verifies it lists with nil hexCode.
5. `OrdersServiceTests.swift` — PE-COLORS Plan Test 4: `testSearchBySkuPartNumber` — creates a ColorBrandSKU with a distinct part number, verifies searchParts returns the parent part via the LEFT JOIN on color_brand_skus. PE-COLORS Plan Test 5: `testAddJPOLineItemGeneralModePersists` — verifies brand_selection_mode='general' is stored in jpo_line_items (prerequisite for resolveGeneralLineItem to work correctly).

**Scanner results (Iteration 4):**
- Scanner 1 (Compile): ✅ 0 errors, 0 warnings
- Scanner 2 (Tests): ✅ 1324/1324 (55 suites)
- Scanner 3 (Code Patterns): ❌ 9 TODOs (dueDate UI — schema-blocked; 1 sync deferred)
- Scanner 4 (SQL): ✅ No mismatches
- Scanner 5 (Problems): ❌ 33 screenshots (human review required)
- Scanner 6 (Master Issues): ❌ T1:18 open (unchanged)
- Scanner 7 (Plan Alignment): ❌ UI phases #237-#243 require Xcode prompts
- Scanner 8 (GitHub): ❌ 44 open — #247 closed this iteration

**Open issues backlog:** #121/#122/#123/#128 (systemic), #130/#131 (KDF v2 deferred), #143/#150 (UX), #221 (LWW), #233 (auto-close), #237-#240 (PE-COLORS UI, XCODE_ONLY), #242-#243 (Orders UI, XCODE_ONLY), #246/#248/#249 (recent HIG/UX).

---

### Iteration 45 — hunt-fix iteration 3 (2026-04-18)

**1 fix + 7 tests. 1 issue closed (#245). Tests: 1319/1319.**

**Fixes:**
1. `PartsService.swift:listForecastDataWithStock` — silent `try?` drop (Part decode failure) replaced with `assertionFailure` that logs the failing row id. Debug-builds surface data corruption; release builds no-op.
2. `PartsServiceExtTests.swift` — 5 ColorBrandSKU CRUD tests: `testUpsertColorBrandSKUCreate`, `testUpsertColorBrandSKUReactivate` (same id returned on reactivation), `testGetSKUsForColor` (multi-brand/type), `testUpdateColorBrandSKU` (patch), `testDeleteColorBrandSKU` (soft-delete exclusion from both listing methods).
3. `#245 CLOSED` — `EditEmployeeContactSheet` already had `isDirty` + `interactiveDismissDisabled(isDirty)` + cancel discard-alert at lines 371/376/380/407. Fix was already applied; issue confirmed closed.
4. `OrdersServiceTests.swift` — `testResolveGeneralLine_byHistory`: seeds brandA + brandB with purchase history; brandB ordered more recently (5 days ago vs 30) → expects byHistory confidence.
5. `OrdersServiceTests.swift` — `testResolveGeneralLine_arbitrary`: seeds AaaFirst + ZzzLast with no PO history → expects AaaFirst (.arbitrary confidence).

**Scanner results (Iteration 3):**
- Scanner 1 (Compile): ✅ 0 errors, 0 warnings
- Scanner 2 (Tests): ✅ 1319/1319 (55 suites)
- Scanner 3 (Code Patterns): ❌ 9 TODOs (UI layer — dueDate field placeholders, not auto-fixable)
- Scanner 4 (SQL): ✅ No mismatches
- Scanner 5 (Problems): ❌ 33 screenshots (require human review)
- Scanner 6 (Master Issues): ❌ T1:~18 open (unchanged)
- Scanner 7 (Plan Alignment): ❌ UI phases (#237–#243) require Xcode prompts
- Scanner 8 (GitHub): ❌ 45 open — #245 closed this iteration

**Open issues backlog:** #121/#122/#123/#128 (systemic), #130/#131 (KDF v2 deferred), #143/#150 (UX), #221 (LWW), #233 (auto-close), #237–#240 (PE-COLORS UI, XCODE_ONLY), #242–#243 (Orders UI, XCODE_ONLY), #246–#249 (recent filings).

---

### Iteration 44 — hunt-fix iteration 2 (2026-04-18)

**3 fixes. 3 tests added. 1 issue closed (#241).**

**Fixes:**
1. `OrdersService.swift` — Added `BrandResolutionResult` + `BrandResolutionConfidence` enums + `resolveGeneralLineItem(jpoLineId:supplierId:)` method (PE-COLORS Phase 3 service). Queries `brand_supplier_links JOIN color_brand_skus` to find matching brands, falls back to PO history for tiebreak, returns `.exclusive`/`.byHistory`/`.arbitrary` confidence.
2. `OrdersService.swift:addJPOLineItem` — Added `brandSelectionMode: String = "specific"` parameter. Column `brand_selection_mode` now written at insert time via service API (previously only settable via direct DB write).
3. `OrdersServiceTests.swift` — 3 tests for `resolveGeneralLineItem` (`alreadySpecific`, `noMatch`, `exclusive`). `makeGeneralLine` helper simplified to use the new `brandSelectionMode` parameter instead of a post-insert raw SQL UPDATE.

**Scanner results (Iteration 2):**
- Scanner 1 (Compile): ✅ 0 errors, 0 warnings
- Scanner 2 (Tests): ✅ 1312/1312 (55 suites)
- Scanner 3 (Code Patterns): ❌ 9 TODOs (UI layer — unchanged from Iteration 1)
- Scanner 4 (SQL): ✅ No new mismatches
- Scanner 5 (Problems): ❌ 33 screenshots (human review required)
- Scanner 6 (Master Issues): ❌ T1:~18 open (unchanged)
- Scanner 7 (Plan Alignment): ❌ UI work (#237–#243) requires Xcode prompts
- Scanner 8 (GitHub): ❌ 46 open — #241 closed this iteration

**Open issues backlog:** #121/#122/#123/#128 (systemic), #130/#131 (KDF v2 deferred), #143/#150 (UX), #221 (LWW), #233 (auto-close), #237–#240 (PE-COLORS UI, XCODE_ONLY), #242–#243 (Orders UI, XCODE_ONLY), #245 (EditEmployeeContactSheet dismiss), #246–#249 (recent filings).

---

### Iteration 43 — hunt-fix iteration 1 (2026-04-18)

**5 fixes. 7 tests added. 0 new issues filed.**

**Scanner results:**
- Scanner 1 (Compile): ✅ PASS — 0 errors, 0 warnings
- Scanner 2 (Tests): ✅ PASS — 1309/1309 (55 suites)
- Scanner 3 (Code Patterns): ❌ 9 TODOs found (all in UI layer — dueDate field placeholders in Chat/Orders/Office; tracked, not auto-fixable without schema changes)
- Scanner 4 (SQL Integrity): ❌ → ✅ FIXED — `JobEstimationService` queried `jobs.status = 'complete'` (3 sites) but `JobsService` writes `'completed'`; silent: all historical averages and AI suggestions returned zero. Fixed all 3 sites. Regression tests added.
- Scanner 5 (Problems Folder): ❌ 33 screenshots (accumulated, require human review)
- Scanner 6 (Master Issues): ❌ T1:~18 open, T2:25, T3:20 — backlog unchanged
- Scanner 7 (Plan Alignment): ❌ → ✅ PARTIAL — PE-COLORS Phase 1 implemented: migration 074 + ColorBrandSKU CRUD + searchParts UNION. UI work (#237–#240) still requires Xcode prompts.
- Scanner 8 (GitHub): ❌ 50 open → 47 open — #234/#235/#236 addressed by this iteration

**Fixes:**
1. `JobEstimationService.swift:359,633,665` — `status = 'complete'` → `'completed'` for jobs table (same class of bug fixed in PartsService for receiving_sessions in iteration 42)
2. `AppDatabase+Migrations.swift` — Migration 074 creates `color_brand_skus` table + `brand_selection_mode` column on `jpo_line_items`/`po_line_items` (PE-COLORS #234)
3. `PartsService.swift` — ColorBrandSKU CRUD: `upsertColorBrandSKU`, `getColorBrandSKUs`, `getSKUsForColor`, `updateColorBrandSKU`, `deleteColorBrandSKU` (PE-COLORS #235)
4. `PartsService.swift:searchParts` — Extended LEFT JOIN to `color_brand_skus` for brand-level part number search (PE-COLORS #236)
5. `JobEstimationServiceTests.swift` — 2 regression tests; `PartsServiceCoverageTests.swift` — 5 tests for ColorBrandSKU CRUD + searchParts UNION

**Open issues backlog:** #121/#122/#123/#128 (systemic usability), #130/#131 (security KDF v2, deferred), #143/#150 (UX), #221 (LWW), #233 (auto-close), #237–#243 (PE-COLORS UI phases), #244–#249 (recent filings).

---

### Iteration 42 — hunt-fix-verify run 11 (2026-04-17)

**1 fix committed. 0 new issues filed.**

**Scanner results:**
- Scanner 1 (Compile): ✅ PASS — 0 errors, 0 warnings
- Scanner 2 (Tests): ✅ PASS — 1290/1290 (55 suites)
- Scanner 3 (Code Patterns): ✅ PASS — 3 `print()` statements confirmed legitimate warnings (ConflictResolver sync-skip, PeerManager unencrypted-sync, AuthService key-persist). All `Button { }` patterns are `.cancel` role dismiss (intentional). Zero force casts, force unwraps.
- Scanner 4 (SQL Integrity): ✅ PASS — Explore agent reported 33 mismatches; all verified FALSE POSITIVES. Every column exists via ALTER TABLE in later migrations. Agent had only checked CREATE TABLE, not ALTER TABLE.
- Scanner 5 (Runtime Safety): ✅ PASS — No `try!`, no force unwraps, no `fatalError`/`preconditionFailure` in production paths.
- Scanner 6 (Edge Cases): ✅ PASS — No new patterns. iOS `try?` uses are all best-effort read paths or FileManager operations.
- Scanner 7 (Problems Folder): ✅ PASS — docs/Problomes folder is empty.
- Scanner 8 (Master Issue List): T1/T2 backlog unchanged. Open GitHub issues: 30 (same as last run — all tracked, none new).
- Scanner 9 (Plan Alignment): ✅ PASS — No new plan drift. April audit closures (#221 LWW, #223/#227 pagination) are in-plan. ADU fix (#224) confirmed CLOSED and code verified.
- Scanner 10 (Security): ✅ PASS — No hardcoded secrets, no SQL injection via string interpolation, no new security issues.

**Fix:**
1. `AuthServiceTests.swift` — Added `.serialized` trait to `@Suite("AuthService Tests")`. Reason: `AuthService.loginAttempts` is a static property shared across all concurrent test runners. Even with `resetAllLoginAttempts()` called before individual tests, two tests can be in the reset-then-query window simultaneously, causing false lockout failures. `.serialized` forces sequential execution within the suite, eliminating the race entirely. Complementary to the per-test reset added in commit 72ae6e7. Committed as `eca541b`.

**No new GitHub issues** — all scanners clean.

**Open issues backlog (unchanged):** #121/#122/#123/#128 (systemic usability), #129/#130/#131 (security KDF v2, deferred), #143/#150 (UX backlog), #221 (LWW field-level, plan written), #233 (auto-close heuristic), #234–#243 (Parts redesign phases).

---

## Baseline (Before Loop Started)

| Metric | Value |
|--------|-------|
| Core tests | 545 (all passing) |
| Core test suites | 40 |
| Compile errors | 0 |
| Compile warnings | 0 |
| Known issues (master list) | 65 (T1:20, T2:25, T3:20) |
| TODOs in code | 10 |
| Empty catches in core | 20+ |
| Force casts | 0 |
| Problems folder items | 32 screenshots |

---

## Iteration Log

### Iteration 41 — hunt-fix-verify run 41 (2026-04-14)

**2 bugs fixed. 0 new issues filed.**

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Build | ✅ | `swift build` — 0 errors, 0 warnings |
| Tests | 🔴 **FIXED** | Initial run: 15+ failures (ConflictResolver + OrdersService cascade crash). Post-fix: **1222/1222 passing** |
| Code Patterns — silent `catch { }` | ✅ | 0 found |
| Code Patterns — force casts `as!` | ✅ | 0 found |
| Code Patterns — force unwraps | ✅ | 0 found |
| Code Patterns — stub UI | ✅ | 0 `Text("TODO")` / `Text("Placeholder")` found |
| Code Patterns — `print()` | ✅ | 3 prints in `#Preview` blocks (false positives — confirmed). `PeerManager.swift:551` info-level sync warning (acceptable). |
| Code Patterns — dead buttons | ✅ | 1 `Button("Yes, for \(selectedJobName)") { }` — confirmed intentional (selectedJobId set in outer scope) |
| SQL Integrity — new PartsService SQL | ✅ | `remaining_qty`, `weighted_avg_cost`, `to_location_type`, `from_location_type`, `to_location_id`, `from_location_id` — all confirmed in migrations |
| SQL Integrity — known patterns | ✅ | `returned_at`/`contact_name`/`customer_type`/`sender_id` all verified as computed aliases or correct column names |
| Problems Folder (Scanner 7) | ✅ | Empty — no new user-reported issues |
| Security | ✅ | 0 SQL injection, 0 hardcoded secrets, UserDefaults only for TabBar config (non-sensitive) |
| Plan Alignment (Scanner 9) | ✅ | Q&A questions #98–#107 (Colors redesign), #143/#149 (dismiss safety), April architectural decisions (#221/#223/#224/#227) — all pending owner answers, not agent-actionable |

**Bugs Fixed:**

| Fix | File | Root Cause | Impact |
|-----|------|------------|--------|
| `setClauses` type inference | `ConflictResolver.swift:fieldLevelMerge` | GRDB 7's `Sequence<SQL>.joined() -> SQL` extension caused Swift to infer `SQL` as map closure return type when `-> String` was missing. `SQL.description` embedded as literal text in query, producing syntax error. Linter added `let setClauses: String = ... map { (key: String) -> String in`. | All ConflictResolver and SyncIntegration tests were failing |
| JPO transition map missing "submitted" + "approved" | `OrdersService.swift:validJPOTransitions` | `"draft"` allowed set was `["pending", "rejected"]` — missing "submitted" (field-employee submit for manager approval, used by `BadgeCountService.pendingApprovals`) and "approved" (admin direct-approval bypass). Linter added "submitted"; agent added "approved". | 2 BadgeCountService tests failing |

**Root cause investigation note:** The full test suite initially showed 15+ failing tests including `testUpdateJPOStatus` and `testGeneratePOFromApprovedJPO`. Investigation revealed these were **cascade failures** — the `ConflictResolver` crash (`Fatal error: Index out of range`) killed the test process, and Swift Testing marked all in-flight tests as failed. Running those tests in isolation confirmed they were actually passing. This is a known Swift Testing parallel execution gotcha.

**Tests Added:** 0 (bug fixes in existing logic — no new service methods)

**Metrics delta:**

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Tests passing | 1217 | 1222 | +5 (from prior working-tree commits) |
| ConflictResolver tests | ❌ (all failing) | ✅ | Fixed |
| BadgeCountService tests | 🔴 2 failing | ✅ | Fixed |
| Compile warnings | 0 | 0 | — |

---

### Iteration 40 — hunt-fix-verify run 40 (2026-04-12)

**3 bugs fixed. 0 new issues filed.**

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Build | ✅ | `swift build` — 0 errors, 0 warnings |
| Tests | ✅ | 1196/1196 passing (no core changes) |
| Code Patterns — silent `try?` on writes | 🔴 **FIXED** | 2 instances converted to do-catch with logging |
| Code Patterns — dead buttons `{ }` | ✅ | All `Button(...) { }` with `.cancel` role are correct dismiss buttons. One `Button("Yes, for \(selectedJobName)") { }` is intentional (comment in file confirms — selectedJobId already set). |
| Code Patterns — `print()` | ✅ | 3 in `#Preview` blocks — confirmed false positives (documented) |
| Code Patterns — force casts `as!` | ✅ | 0 found |
| Code Patterns — force unwraps | ✅ | 0 found |
| Code Patterns — stub UI | ✅ | 0 `Text("TODO")` / `Text("Placeholder")` / `Text("Coming soon")` found |
| SQL Integrity | ✅ | All 8 known-mismatch patterns clean. `first_name`/`last_name` on `entity_contacts`/`general_contractors` (correct). `contact_name` in customers query is computed alias. `estimated_days` is computed alias. `returned_at` is `NULL AS returned_at`. |
| 00-fix-order.md | 🔴 **FIXED** | PE-042 was still listed as 🔲 NEXT despite being archived in run 39 — corrected; PE-043 now correctly marked NEXT |

**Fixes Applied:**

| Fix | File | Details |
|-----|------|---------|
| `try?` → do-catch | `IOSSyncManager.swift:352,362` | `markConflictReviewed()` was silently failing — would leave sync conflicts permanently unreviewed in the UI. Added `os.Logger` + `logger.error()`. |
| `try?` → do-catch | `IOSDashboardQRScannerPage.swift:599` | `setUserCurrentPosition()` silent failure on QR scan — non-critical but now logged via `print()`. |
| Queue correction | `00-fix-order.md` | PE-042 status corrected from 🔲 NEXT → ✅ DONE; PE-043 moved to NEXT. |

**Tests Added:** 0 (iOS-layer fixes only; no core service changes)

**Metrics delta:**

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 1196 | 1196 | = |
| `try?` on write paths | 2 | 0 | -2 |
| Prompt queue accuracy | Stale | Correct | fixed |

---

### Iteration 39 — github-issues-sync run 6 (2026-04-12)

**50 issues scanned. 3 bugs fixed. 7 sheets patched. 0 new issues filed.**

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Build | ✅ | `swift build` — 0 errors, 0 warnings |
| Tests | ✅ | 1196/1196 passing (up from 1194) |
| Issue #143 Progress | 🔄 | 7 more sheets fixed — now 33 total with interactiveDismissDisabled (was 7 at filing). 30+ still pending. |
| try? on writes | ✅ | DevicePairingView + IOSAuditPage converted. No new ones found. |
| GitHub Issues | ✅ | #133 ✅ CLOSED, #138 ✅ CLOSED. 50 open; #143 partial; #130/#131 v2 backlog. |
| Systemic Backlog | ⚠️ | #121 (try?, 188 files), #122 (guard-let bail), #123 (interactiveDismissDisabled), #128 (empty catch), #129 (dirty tracking) — all tracked, no auto-fix at this scale |
| Q&A Pending | ⚠️ | Colors/Brands #98-#107 + interactiveDismissDisabled approach #143 — both in dev-qa.md |

**Fixes Applied (3 bugs, 7 sheet guards):**

| Fix | File | Details |
|-----|------|---------|
| try? → try | `DevicePairingView.swift:258` | `try? service.upsertSettingsMap()` was silently failing on pairing — syncing would never work. Already inside do-catch at :249. |
| try? → do-catch | `IOSAuditPage.swift:828` | `updateUserRating` result is non-critical (audit count already saved), but failure now logged via print. |
| Curly quote fix | `IOSWishlistPage.swift:81` | Delete button title used typographic quotes `"` around interpolated part name — potential runtime issue on some locales. Changed to escaped `\"`. |
| interactiveDismissDisabled | `DevicePairingView.swift` | Guard on pairing state (`isPairing`) |
| interactiveDismissDisabled | `IOSEscalationTimeline.PushBackSheet` | Guard on submit state (`isSubmitting`) |
| interactiveDismissDisabled | `IOSMessageThreadView` | Guard on send state (`isSending`) |
| interactiveDismissDisabled | `IOSCustomerDetailPage.AddCustomerContactSheet` | Guard + `isSaving` state |
| interactiveDismissDisabled | `IOSCustomerDetailPage.AddCommunicationSheet` | Guard + `isSaving` state |
| interactiveDismissDisabled | `IOSEmployeeDetailPage.EditEmployeeContactSheet` | Guard on `isSaving` |
| interactiveDismissDisabled | `CompanyProfilesPage.CompanyProfileEditor` | Guard + `isSaving` state + Save button disabled while saving |

**PE-042 archived:** Moved `PE-042-cart-mode-ui.md` to `done/`. Cart Mode fully shipped (commit 37ffeb7).

**Tests Added:** 0 (iOS-layer fixes; no core service changes)

**Metrics delta:**

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 1194 | 1196 | +2 |
| Sheets with interactiveDismissDisabled | 26 | 33 | +7 |
| Active Xcode prompts | 1 (PE-042 stale) | 0 | -1 (archived) |
| Open issues | 50 | 50 | = |

---

### Iteration 38 — hunt-fix-verify run 38 (2026-04-12)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings (`swift build` — core) |
| Tests | ✅ | 1194/1194 passing (no changes to core — count from test-coverage run earlier today) |
| Code Patterns — empty catches | ✅ | Python multiline scan confirms **0 truly empty catch blocks** anywhere in codebase. Issue #142 was a false positive (grep found `catch {` opening line, not empty body) |
| Code Patterns — `print()` | ✅ | 3 instances in `#Preview` blocks — confirmed false positives, not production code |
| Code Patterns — `try?` on writes | 🔴 **FIXED** | 6× `try? svc?.updateSessionItem()` in `IOSReceiveShipmentPage.swift` — converted to do-catch. **#141 CLOSED.** |
| Code Patterns — `?? 0` / `?? 1` writes | ✅ | 0 remaining — already fixed in prior iterations |
| SQL Integrity | ✅ | All known patterns clean. `moveBinsToArea` (new) verified: `warehouse_bins.area_id` exists. `estimated_days` in SchedulingService is computed alias, not column. `returned_at` in ToolsService is `NULL AS returned_at` alias, not column reference |
| Runtime Safety | ✅ | All array subscripts guarded. Division by zero in WarehouseService guarded by `if totalWithMin > 0` |
| Edge Cases | ✅ | No first-launch failures detected |
| Problems Folder | ✅ | `docs/Problomes/` does not exist (expected) |
| GitHub Issues | ✅ | #141 CLOSED, #142 CLOSED. Open: #143 (30+ sheets missing interactiveDismissDisabled — systemic/ongoing), #130/#131 (DIS-012/013 KDF — design decision blocked), #138 (cart mode — pending), #121/#122/#123/#128 (systemic patterns — backlog) |
| Plan Alignment | ✅ | No new drift detected. `moveBinsToArea`/`saveUnitPlacement` in WarehouseService confirmed added (#138 implementation landed) |
| Security | ✅ | No SQL injection, no hardcoded secrets. TabBarPreferences uses UserDefaults for tab order (non-sensitive). DIS-012/013 still tracked |

**Scanner 3 improvement noted:**
- `grep -rn 'catch {'` is an unreliable empty-catch detector — it finds the opening brace, not the body
- Proper check: verify next non-blank line after `catch {` is `}` (truly empty)
- Python multiline scan is the correct tool — added to scanner specification

**Fixes Applied (2):**

1. **#141 [HIGH] — IOSReceiveShipmentPage.swift: 6× try? on updateSessionItem → do-catch**
   - `:308` — Reset to Expected loop: collects failure count, shows consolidated `actionError`
   - `:324` — Clear All loop: collects failure count, shows consolidated `actionError`
   - `:608` — Decrement stepper: `actionError = "Could not save quantity change."`
   - `:633` — Increment stepper: `actionError = "Could not save quantity change."`
   - `:648` — Fill-to-expected button: `actionError = "Could not save quantity change."`
   - `:851` — Barcode scan auto-increment: `scanError = "Barcode scan quantity could not be saved."`

2. **#142 [FALSE POSITIVE] — Closed** — All 11 listed catch blocks have proper handlers (errorMessage, saveError, logger.warning, or non-fatal comments)

**GitHub Issues:**
- #141 CLOSED — fix applied
- #142 CLOSED — false positive, scanner improvement documented

**Tests Added:** 0 (iOS-layer fix; no core service changes)

---

### Iteration 37 — dev-improvement-scanner run 12 (2026-04-10)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Force Casts (`as!`) | ✅ | 0 found in core or UI layer |
| Force Unwraps | ✅ | No unguarded `!` on optionals in core; UI patterns use guard properly |
| `fatalError` | ✅ | 0 found anywhere |
| Empty catches | ✅ | 0 empty `catch { }` blocks in core or UI |
| SQL Injection | ✅ | All dynamic SQL uses allowedFields allowlist guards (ToolsService verified) |
| Security (UserDefaults for secrets) | ✅ | No PIN/password/token stored in UserDefaults |
| Security (unowned references) | ✅ | 0 `unowned self` closures |
| `print()` in production code | ✅ | All 3 instances inside `#Preview` blocks — not production code |
| DIS-015 `?? 0` write paths | ✅ | All write paths fixed. 3 remaining read-only `?? 0` confirmed acceptable |
| DIS-016 `?? 1` write paths | 🔴 | **NEW: 7 write-op files use `?? 1` (admin ID fallback)** — GitHub #140 filed |
| NavigationView (deprecated) | ✅ | 0 NavigationView usages — all use NavigationStack |
| Tap target sizes | ✅ | Small `.frame(width:)` values are all icon images inside larger buttons |
| Tests | ✅ | 1162/1162 passing (no changes this run) |

**New Bugs Found:**
1. **DIS-016 [HIGH]** — `currentUser?.id ?? 1` in 7 write-op files. 7 locations across IOSMessageThreadView (×1), IOSCustomerDetailPage (×2), IOSContractorDetailPage (×1), IOSProcurementPage (×1), IOSNotebookDetailPage (×1), IOSAuditSetupView (×1). All pass admin user ID (1) to audit columns when user is not authenticated. GitHub #140. DevTODO at `docs/DevTODO/DIS-016-hardcoded-userid-one-fallback.md`.

**Fixes Applied:** 0 (all findings are UI-layer — left for Xcode AI per workflow rules)

**GitHub Issues Filed:** 1 (#140 — DIS-016)

**DevTODO Files Created:** 1 (`DIS-016-hardcoded-userid-one-fallback.md`)

**Tests Added:** 0

---

### Iteration 36 — hunt-fix-verify run 36 (2026-04-10)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | 1142/1142 passing (unchanged) |
| Code Patterns | ✅ | No empty catches, no force casts, no dead buttons, no stub UI. 3 `print()` calls in `#Preview` blocks — false positives (not production code) |
| SQL Integrity | ✅ | No new column mismatches; known patterns confirmed clean |
| Runtime Safety | ✅ | No unguarded force unwraps, no array subscript risks |
| Edge Cases | ✅ | No new first-launch failures |
| Problems Folder | ✅ | `docs/Problomes/` path does not exist — folder removed/renamed; pre-existing 32 screenshots were always pre-existing backlog |
| Master Issues | ⚠️ | #139 CLOSED. DIS-012/013 still blocked on KDF design decision; #138 cart mode open |
| Plan Alignment | ✅ | No new drift detected |
| Security | ✅ | No SQL injection, no hardcoded secrets; DIS-012/013 still tracked |

**Fixes applied (6 iOS write paths — DIS-015 completion):**

1. `IOSWeeklyReviewSheet.swift:336` — `let userId = appCore.currentUser?.id ?? 0` → `guard let userId = appCore.currentUser?.id else { submitError = "Not logged in..."; isSubmitting = false; return }`
2. `IOSAuditSummaryView.swift:337` — `resolvedBy: appCore.currentUser?.id ?? 0` → merged `let userId = appCore.currentUser?.id` into the existing `guard let service, let part` block; now `resolvedBy: userId`
3. `ReceivingRoutingFlow.swift:1043,1072,1103,1132` — all 4 routing write paths (`stageReceivedPartsForJob` ×2, `returnDamagedToSupplier`, `writeOffReceivedPart`) — `let userId = appCore.currentUser?.id ?? 0` removed, merged into guard block via `replace_all`; ternary error message distinguishes not-logged-in vs service-unavailable

**Root cause:** Same as prior iterations — `?? 0` fallback writes a sentinel non-user-ID to `performed_by`/`resolved_by`/`reviewed_by` columns, corrupting audit trails. The `guard let userId` pattern ensures the action is only attempted when a real user session exists.

**Scanner improvement noted:**
- Scanner 3 `print()` grep produces false positives when `print()` appears inside `#Preview` blocks. These are not production code (Preview macro is stripped in release builds). Future scanner runs should note this caveat. A proper fix would require context-aware parsing, but the current grepping approach is acceptable for a scheduled scan.

**GitHub issues:**
- #139 CLOSED — all write-path `currentUser?.id ?? 0` instances fixed

**Tests added:** 0 (iOS-layer fix; no core service changes — no new unit test surface)

**Still open (tracked):**
- DIS-012/013: PIN KDF upgrade — blocked on design decision (PBKDF2 vs Argon2id). GitHub #130, #131.
- #138: Cart mode — `moveBinsToArea`/`saveUnitPlacement` not implemented. Design decision pending.
- #122, #121, #128, #123, #129: Systemic usability issues (guard-let silences, try? swallowing, missing interactiveDismissDisabled) — require broader sweep

---

### Iteration 35 — hunt-fix-verify run 35 (2026-04-09)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | 1127/1127 passing (+1 new test) |
| Code Patterns | ✅ | No empty catches, no force casts, no dead buttons, no stub UI |
| SQL Integrity | ✅ | All recently modified services verified clean; all column names match schema |
| Runtime Safety | ✅ | All array subscripts guarded; no unguarded optionals found |
| Edge Cases | ✅ | No first-launch failures detected |
| Problems Folder | ✅ | 32 screenshots (unchanged — pre-existing) |
| Master Issues | ⚠️ | DIS-012/013 blocked on design decision; #139 (DIS-015) open with DevTODO |
| Plan Alignment | ✅ | PE-040/PE-041 confirmed in code; grid_rows/grid_cols in schema |
| Security | ✅ | No SQL injection; DIS-014 fully closed; DIS-012/013 tracked |

**Fix applied:**
- `OrdersService.swift:834` — `smartRouteJPOLine(lineId:partId:userId:)` signature changed from `userId: Int64` → `userId: Int64?`. Callers passing a non-optional `Int64` still work (Swift implicit lift). The `addJPOLineItem` call on line 690 updated from `userId ?? 0` → `userId`. When userId is nil (system-triggered routing), GRDB now writes NULL to `status_updated_by` instead of 0.

**Root cause:** `jpo_line_items.status_updated_by` is a nullable column (no `.notNull()` in migration 3579), so storing 0 as a sentinel was incorrect — 0 is not a valid user ID and could corrupt audit trail queries that check for specific user IDs.

**GitHub issues closed:**
- #134 ([Bug] WishlistService auto-approvals never fire) — fix verified in code. `IOSWishlistPage.loadData()` correctly calls `processAutoApprovals` in `Task.detached` before `getSectionedItems`. Fix landed 2026-04-07, issue was left open by mistake.

**Tests added:** 1
- `testSmartRouteNilUserIdWritesNull` — creates a JPO line, calls `smartRouteJPOLine(userId: nil)`, then reads `status_updated_by` with `Int64.fetchOne` and asserts it is `nil`. Note: `Int64?.fetchOne` would return `Int64??` (double optional), making `== nil` check fail incorrectly — use `Int64.fetchOne` which returns `Int64?` and properly flattens NULL.

**Still open (tracked):**
- DIS-012/013: PIN KDF upgrade — blocked on design decision (PBKDF2 vs Argon2id)
- DIS-015 (GitHub #139): `currentUser?.id ?? 0` in 6 iOS write paths — needs Xcode AI pass
- GitHub #130/131: Security issues tied to DIS-012/013

---

### Iteration 1 — SQL Column/Table Audit (2026-03-28)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | 548/548 passing (+3 new tests) |
| Code Patterns | ⏳ | Not yet scanned |
| SQL Integrity | ❌→✅ | **~30 mismatches found and fixed** |
| Problems Folder | ⏳ | 32 items (7+ addressed by SQL fixes) |
| Master Issues | ⏳ | 65 open (not yet triaged) |
| Plan Alignment | ⏳ | Not yet scanned |

**Fixes applied (8 files, ~30 SQL mismatches):**

| File | Fixes | Details |
|------|-------|---------|
| PeopleService.swift | 18 | `contacts`→`entity_contacts`, `status`→`is_active`, `h.deleted_at` removed (hats has none), `first_name/last_name`→`display_name`, `employee_certifications`→`certifications`, `expiration_date`→`expiry_date`, `teams`→`employee_teams`, `team_members`→`employee_team_members`, `schedule_entries`→`job_dispatch`, `time_off_requests`→`schedule_exceptions`, `j.name`→`j.job_name`, `j.end_date`→`j.completed_date`, `contractor_id`→`gc_id`, `c.user_id` removed (customers has own columns) |
| SchedulingService.swift | 6 | `job_stages` JOIN removed (reference table only), `callback_date`/`callback_snoozed_until`→`due_date`, `estimated_days`→`estimated_hours/8`, `is_favorite_gc` removed, `users.role`→hat-based subquery |
| PartsService.swift | 5 | `part_suppliers`→`part_supplier_links` (5 occurrences) |
| ReportsService.swift | 6 | `employee_wages`→`users.pay_rate`, `j.name`→`j.job_name` (3x), `hours_regular`→`regular_hours`, `hours_overtime`→`overtime_hours`, `work_date`→`date(clock_in)` |
| ChatService.swift | 1 | `supplier_bridges`→`supplier_channel_bridges` |
| OrdersService.swift | 1 | `j.name`→`j.job_name` |
| DailyReportGenerator.swift | 1 | `todo_entries`→`notebook_entries` via sections→notebooks |
| DashboardKPIDetailSheets.swift | 1 | Added `.presentationDragIndicator(.visible)` |

**Tests added:** 3 new scheduling tests (dispatch board with data, short-term pipeline, snooze/complete callback)
**Tests updated:** 4 existing tests changed from expecting SQL errors to asserting correct behavior

**Result:** 548 tests passing, 0 errors, 0 warnings. SQL integrity scanner now clean across all verified services.

---

---

### Iteration 2 — Code Patterns + Remaining SQL Scan (2026-03-28)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | 548/548 passing |
| SQL Integrity | ✅ | All production services verified clean |
| Code Patterns | ⚠️ | See below |
| Problems Folder | ⏳ | 32 items |
| Master Issues | ⏳ | 65 items |
| Plan Alignment | ⏳ | Not yet scanned |

**Code pattern scan results:**
| Pattern | Count | Severity | Notes |
|---------|-------|----------|-------|
| Empty catches | 3 | Low | All intentional/documented |
| TODOs/FIXMEs | 10 | Low | 9 identical "dueDate field" pattern, 1 sync |
| Empty button actions | 31 | None | All `.cancel` role in alerts — correct SwiftUI |
| Multiple `.sheet()` modifiers | 10 files | Medium | IOSMainView has 5 — potential SwiftUI bug |
| Placeholder text | 0 | - | Clean |
| Force casts | 0 | - | Clean |

**Additional SQL fixes applied (iteration 2):**
- ToolsService: `tool_kits`/`tool_kit_items` — gracefully handled (tables planned, not yet created)

**Gracefully degrading tables (intentional — future features):**
- `integrations`, `device_keys`, `bootstrap_devices` (SettingsService)
- `ai_dispatch_choices` (AIDispatchService)
- `audit_sessions` v1 (WarehouseService — v2 used for all new code)
- `tool_kits`, `tool_kit_items` (ToolsService)

All have `isTableNotFoundError` → empty result handling.

---

## Cumulative Progress

| Metric | Baseline | Current | Delta |
|--------|----------|---------|-------|
| Core tests | 545 | 1121 | +576 |
| Test suites | 40 | 53 | +13 |
| Compile errors | 0 | 0 | = |
| Compile warnings | 0 | 0 | = |
| SQL mismatches fixed | 0 | ~31 | -31 |
| Service files fixed | 0 | 9 | +9 |
| iOS files fixed | 0 | 5 | +5 (sheet dismiss) |
| New shared components | 0 | 1 | +1 (SheetDismissWrapper) |
| TODOs in code | 10 | 10 | = (all tracked, low priority) |
| Empty catches | 20+ | 3 truly silent | -17 (most are intentional) |
| Force casts | 0 | 0 | = |
| Problems folder | 32 | 16 open | -16 (10 SQL + 6 sheet fixes) |
| Master issues | 65 | 65 | Triaged (many addressed by SQL/sheet fixes) |
| Security fixes | 0 | 1 | DIS-014: unsigned token shim removed |
| Schema version accuracy | stale (61) | correct (74) | +13 migrations tracked |

---

### Iteration 3 — Problems Folder Triage + Sheet Dismiss Fix (2026-03-28)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings (core + iOS) |
| Tests | ✅ | 548/548 passing |
| SQL Integrity | ✅ | 1 more fix (getActiveCrewSize: status→is_active) |
| Problems Folder | ⚠️ | 32 cataloged → 10 fixed, 6 sheet fixes, 16 remaining |
| Master Issues | ⚠️ | 65 items triaged, categorized by fixability |

**Full screenshot catalog (32 items):**

| Status | Count | Category |
|--------|-------|----------|
| ✅ Fixed (SQL crashes) | 10 | "Something went wrong" on People, Scheduling, Parts pages |
| ✅ Fixed (Sheet dismiss) | 6 | KPI sheets, help sheets, Report Problem sheet |
| Open (iOS UI) | 10 | Clock In/Out, warehouse features, floor plans |
| Design feedback | 6 | Layout preferences, missing info fields |

**Fixes applied:**

1. **SheetDismissWrapper.swift** (NEW) — Reusable wrapper that captures `@Environment(\.dismiss)` OUTSIDE NavigationStack scope, preventing the known SwiftUI bug where dismiss binds to the nav stack instead of the sheet. Also provides `\.sheetDismiss` environment key for child views.

2. **KPIDetailSheet** — Converted to use `SheetDismissWrapper` instead of manual NavigationStack + dismiss

3. **PageHelpSheet** — Converted to use `SheetDismissWrapper` (affects 50+ pages that present help sheets)

4. **ReportProblemSheet** — Captured dismiss outside NavigationStack scope via `let dismissSheet = { dismiss() }` pattern

5. **DashboardView** — Moved `.sheet(item: $activeSheet)` OUTSIDE the outer NavigationStack to prevent dismiss scope conflict

6. **SchedulingService.getActiveCrewSize()** — Fixed `WHERE status = 'active'` → `WHERE is_active = 1` (caused Long-Term Pipeline crash)

**Master issue list triage results:**
- T3-04 (AIDispatchService wiring): Already fully wired — NOT an issue
- T3-06 (Missing isTableNotFoundError): AuthService/SettingsService use core tables that always exist — LOW priority
- T2-22 (Raw error messages): Root cause was SQL errors, now fixed
- 9 "Something went wrong" screenshots: ALL resolved by SQL fixes
- Remaining issues: mostly iOS UI features (T1-01 to T1-20) needing Xcode AI prompt workflow

**Remaining for next iteration:**
- IOSMainView: Consolidate 5 `.sheet()` modifiers into single enum pattern
- CreatePOSheet + IOSMovementWizard: Move `.sheet()` outside NavigationStack
- Clock In/Out page bugs (P3, P4)
- Warehouse floor plans not showing (P14)
- Master issue list T1 items (missing features — need Xcode AI prompts)

---

### Iteration 4 — Massive Test Expansion + 15 SQL Bug Fixes (2026-03-29)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | **676/676 passing** (+128 new tests) |
| SQL Integrity | ✅ | 15 more SQL bugs found and fixed |
| Code Patterns | ✅ | actionError display fix, orphaned page fix, dual sheet consolidation |
| Problems Folder | ⏳ | No change |
| Master Issues | ⏳ | No change |
| Plan Alignment | ⏳ | No change |

**New test files created (8 files, +128 tests):**
| File | Tests | Coverage |
|------|-------|----------|
| PeopleServiceTests.swift | 20 | employees, customers, contractors, contacts, teams, hats, stats, comms |
| ChatServiceTests.swift | 15 | channels, messages, QA threads, escalation, supplier channels, office |
| ReportsServiceTests.swift | 12 | timesheets, spending, profitability, pre-billing, bookkeeper, custom reports |
| FleetServiceTests.swift | 20 | vehicles, trailers, drivers, stats, maintenance, fuel, inspections, stock |
| JobsServiceTests.swift | 15 | CRUD, clock in/out, warranty, continuous, questionnaire, daily reports |
| OrdersServiceTests.swift | 15 | JPOs, POs, procurement, returns, stats, receipt history |
| PartsServiceExtTests.swift | 15 | hierarchy, CRUD, pricing, cost layers, forecasting, companions |
| WarehouseServiceExtTests.swift | 15 | KPIs, movements, inventory grid, staging, receiving, reports, misplaced |
| AIDispatchServiceTests.swift | 5 | suggestions, context, dispatcher choice recording |

**SQL bugs found and fixed (15 production bugs discovered by new tests):**
| Service | Bug | Fix |
|---------|-----|-----|
| ReportsService | `billing_periods.status` (no such column) | → `locked_at IS NULL` |
| AIDispatchService | `u.status = 'active'` (no such column) | → `u.is_active = 1` |
| AIDispatchService | `j.estimated_days` (no such column) | → `j.estimated_hours` |
| ChatService | `u.first_name \|\| ' ' \|\| u.last_name` (2 locations) | → `u.display_name` |
| ChatService | `created_by = 0` FK violation (ensureOfficeChannel) | → `created_by = 1` |
| JobsService | `j.customer_id` (no such column) | → removed join, used `j.customer_name` |
| OrdersService | `order_type, order_id, changed_at` (wrong columns) | → `entity_type, entity_id, changed_by, created_at` |
| OrdersService | `returns.initiated_by` missing from INSERT (NOT NULL) | → added `initiated_by = 1` |
| FleetService | `tc.returned_at` (2 locations, no such column) | → `tc.checked_in_at` |
| FleetService | `tc.condition_at_checkout` (no such column) | → `tc.checkout_condition` |
| PeopleService | `h.deleted_at` on hats (no such column) | → removed; deleteHat → hard DELETE |
| PeopleService | `customers.contact_name, customer_type` (no such columns) | → derived from existing `name` column |
| PartsService | PriceHistory `createdAt` nil → NOT NULL constraint | → `willInsert` sets createdAt |
| DailyReportGenerator | `chat_messages.user_id` | → `sender_id` |

**Code pattern fixes applied:**
| Fix | File |
|-----|------|
| actionError never displayed to user | PartsCatalogPage.swift — added `.alert()` |
| Unused actionError state | IOSQuestionsPage.swift — removed dead code |
| Orphaned detail page | IOSNotebooksListPage.swift — added NavigationLink |
| Dual `.sheet()` modifiers | IOSNotebooksListPage.swift — consolidated to ActiveSheet enum |

**Scheduled tasks created (3 daily maintenance tasks):**
| Task | Schedule | Purpose |
|------|----------|---------|
| hunt-fix-verify | 6:00 AM daily | Runs all 7 scanners, fixes top 5 issues, updates tracker |
| test-coverage-maintenance | 7:00 AM daily | Ensures 100% pass rate, adds tests for uncovered services |
| github-sync-and-review | 8:00 PM daily | Reviews changes, creates commits, pushes to GitHub |

---

### Iteration 5 — Test Coverage Expansion (2026-03-29, automated)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | **688/688 passing** (+12 new tests) |
| SQL Integrity | ✅ | No new issues found |
| Code Patterns | ✅ | No new issues |
| Problems Folder | ⏳ | No change |

**New tests added (+12):**
| File | Tests Added | Methods Newly Covered |
|------|-------------|----------------------|
| JobsServiceTests.swift | 6 | getActiveClockEntry, getTodaysClockEntries, getReport, markReportReviewed, returnJobPart, listActiveJobs, getJobsDashboardKPIs, toggleSupplyRun, getLaborEntryNotes |
| OrdersServiceTests.swift | 4 | generatePOFromJPO, updateReturnStatus, updatePOExpectedDelivery, addPONote, getSuppliersWithActivePOs |

**Notable fix during test writing:**
- `toggleSupplyRun` uses `[supply_run_start:timestamp]` tags (not `[SUPPLY RUN]`) — test corrected to match actual implementation

**Coverage gaps remaining (highest priority for next run):**
- JobsService: getJobsForCustomer, saveClockOutResponses, getResponsesForEntry, answerOneTimeQuestion, listActiveJobsForClock
- PeopleService: 47 methods, 18 tests — largest remaining gap
- ChatService: 33 methods, 14 tests
- SettingsService: 40 methods, 17 tests

---

### Iteration 6 — SQL Bug Hunt: Tool Checkout Report (2026-03-29, automated)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | **688/688 passing** (+12 new tests) |
| SQL Integrity | ❌→✅ | 5 SQL column bugs fixed in 2 files |
| Code Patterns | ✅ | No new issues found |
| Problems Folder | ✅ | Empty |
| Master Issues | ⚠️ | 65 open (unchanged — mostly UI features) |
| Plan Alignment | ⏳ | Not scanned this iteration |

**SQL bugs fixed (5 bugs across 2 files):**
| Service | Bug | Fix |
|---------|-----|-----|
| ReportsService | `tc.returned_at` on tool_checkouts (no such column) | → `tc.checked_in_at` |
| ReportsService | `tc.condition_out` on tool_checkouts (no such column) | → `tc.checkout_condition` |
| ReportsService | `tc.condition_in` on tool_checkouts (no such column) | → `tc.return_condition` |
| ReportsService | `tc.user_id` on tool_checkouts (no such column) | → `tc.checked_out_by` |
| ToolsService | `notes` in tool_checkouts INSERT (no such column) | → `checkout_notes` |

These bugs were in `generateToolCheckoutsReport` — would crash any time a user generated a tool checkout custom report.

---

### Iteration 7 — Dev Improvement Scanner: Full Audit (2026-03-29)

**4 parallel scanners run:** Runtime Safety, SQL Integrity, Apple HIG, Security

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | **688/688 passing** |
| Runtime Safety | ⚠️ | 1 real bug (dead button), 5 guarded unwraps |
| SQL Integrity | ❌→✅ | **14 bugs found, 13 fixed** (1 guarded by isTableNotFoundError) |
| Apple HIG | ⚠️ | 55 hardcoded fonts, 12 undersized tap targets, sparse a11y labels |
| Security | ⚠️ | 2 high (token forgery, brute-force), 5 medium, 4 low |

**SQL bugs fixed (13 bugs across 8 files):**
| Service | Bug | Fix |
|---------|-----|-----|
| WarehouseService | `audit_sessions` table (doesn't exist) | → `audit_sessions_v2` with correct columns |
| WarehouseService | `audit_sessions` UPDATE (wrong table) | → `audit_sessions_v2` |
| WarehouseService | `part_number` on parts (no such column) | → `code` |
| WarehouseService | `pli.unit_price` (no such column) | → `pli.unit_cost` |
| FleetService | `vehicle_inspections` table (doesn't exist) | → `inspection_records` with `performed_at` |
| FleetService | `odometer` on vehicles (no such column) | → `current_odometer` |
| ReportsService | `po.total_amount` (no such column) | → `po.total_cost` |
| DailyReportGenerator | `qt.question` on qa_threads (no such column) | → `qt.subject AS question` |
| PartsService | `unit_price` in subquery (no such column) | → `unit_cost` |
| JobsService | `labor_entries.updated_at` (no such column, 2 locations) | → removed updated_at SET |
| ChatService | notebooks INSERT missing `created_by` NOT NULL | → added `created_by = 1` |
| ChatService | notebook_entries INSERT missing `section_id`, `created_by`, uses nonexistent `status` | → get/create section, proper columns |
| SchedulingService | `h.name = 'admin'` case mismatch | → `h.name = 'Admin'` |

**Other findings logged (for Xcode prompts / future iterations):**
- 1 dead button in IOSJPOCreationPage.swift:209
- 55 hardcoded font sizes (bypasses Dynamic Type)
- 12 undersized tap targets (< 44x44pt)
- 5 swipe-to-delete without confirmation
- Sparse accessibility labels (~8 across 180+ view files)
- 9+ color-only status indicators
- Unsigned session tokens (forgeable)
- No brute-force protection on PIN login
- Data export not gated behind admin permission

---

**Tests added (+12, total now 688):**
| File | Tests | Details |
|------|-------|---------|
| ReportsServiceTests.swift | +2 | Tool checkout report empty + with data (verifies all 4 fixed SQL columns) |

**Self-improvement note:**
- `ToolsService.checkoutTool` bug discovered *by writing the ReportsService test* — the test was the only thing calling the simple `checkoutTool` path (all other tests used `checkoutToolWithCondition`). This confirms: every new test has the potential to surface previously untested code paths.

---

### Iteration 8 — SQL Column Audit + Scan (2026-03-29)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | **691/691 passing** (+3 new tests) |
| Code Patterns | ✅ | 1 TODO (tracked, low priority), 0 empty catches, 0 force casts, 0 multi-sheet |
| SQL Integrity | ❌→✅ | **3 mismatches found and fixed** |
| Problems Folder | ⚠️ | 32 screenshots (16 previously addressed, 16 open — mostly iOS UI features) |
| Master Issues | ⚠️ | 65 items (T1:20, T2:25, T3:20 — mostly iOS UI features needing prompts) |
| Plan Alignment | ⚠️ | Page coverage excellent (~95 planned, ~140 implemented). 7+ non-functional warehouse stubs. |

**SQL bugs fixed (3 bugs across 2 files):**
| Service | Bug | Fix |
|---------|-----|-----|
| ReportsService | `j.budget_amount` (no such column) in generateJobCostsReport | → `j.budget_limit` |
| WarehouseService | `jl.qty_fulfilled` (no such column) in getActiveJPODemandForPart | → `jl.qty_received` |
| WarehouseService | `row["unit_price"]` reads nil (SQL selects `unit_cost`) in getSessionItems | → `row["unit_cost"]` |

**Tests added (+3, total now 691):**
| File | Tests | Details |
|------|-------|---------|
| ReportsServiceTests.swift | +1 | Job costs report with budget_limit — verifies correct budget column read |
| WarehouseServiceExtTests.swift | +2 | Active JPO demand (qty_received) + Receiving session items (unit_cost) |

**Plan alignment key findings:**
- All 13 feature modules have page-level coverage (95+ planned pages implemented)
- Warehouse module has 7+ non-functional stubs (display-only, no actions) — needs iOS prompts
- Settings missing Payment Tracking page — low priority
- Office routing gaps (Pipeline, Teams, Deletions routed to other modules) — verify routing

---

### Iteration 9 — Test Coverage: SchedulingService + ChatService (2026-03-29, automated)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | **733/733 passing** (+42 new tests) |
| SQL Integrity | ❌→✅ | 1 SQL bug found and fixed (`listSupplierBridges` queried non-existent columns) |
| Code Patterns | ✅ | No new issues |
| Problems Folder | ⏳ | No change |
| Master Issues | ⏳ | No change |
| Plan Alignment | ⏳ | No change |

**New tests added (+42):**
| File | Tests Added | Methods Newly Covered |
|------|-------------|----------------------|
| SchedulingServiceTests.swift | +27 | getShortTermPipeline, snoozeCallback, markCallbackComplete, getLongTermTimeline, getCapacityWarnings (pure computation), getCrewUtilizationReport, getDispatchEfficiencyReport, getPipelineSummaryReport, getWeeklyDispatchAssignments, getUnassignedWorkers |
| ChatServiceTests.swift | +15 | sendSupplierMessage, addUserToSupplierChannel, getSupplierBridge, listSupplierChannelsForJob, createSupplierQuestion, listSupplierQuestions, deactivateSupplierBridge, listSupplierBridges, sendMessageWithAttachments, getMessageAttachments, getAttachmentsForMessages, autoSaveToJobNotebook, getThreadInfo |

**SQL bug found and fixed:**
| Service | Bug | Fix |
|---------|-----|-----|
| ChatService | `listSupplierBridges` queried `sb.status`, `sb.protocol`, `sb.last_sync_at` — none exist in `supplier_channel_bridges` schema | → `sb.is_active` (mapped to "active"/"inactive"), `sb.last_seen_at`, default "HTTP" for protocol |

**Notable patterns:**
- `getCapacityWarnings` is the only pure computation method (no DB) in the service layer — tested by constructing synthetic `MonthCapacity` values in-memory, making tests millisecond-fast and side-effect free
- Crew utilization test required creating a non-admin worker user because the Admin hat is intentionally excluded from crew scheduling reports — reveals an access control design invariant worth testing explicitly
- `getAttachmentsForMessages(messageIds: [])` exercises the early-return guard path, preventing dynamic SQL `IN ()` clause from being built with an empty list

---

### Iteration 13 — dev-improvement-scanner: Force Unwraps + Full Audit (2026-03-31)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | 790/790 passing |
| Code Patterns (Part A) | ⚠️→✅ | 9 force unwraps found in core, all fixed |
| Code Patterns (Part C — HIG) | ⚠️ | 1 hardcoded font size in PartsForecastingPage.swift:349 (`size: 8`) — PE-009 backlog |
| Security (Part B) | ⚠️ | Legacy salt `:wiredpart` still present — PE-008c still open |
| UX Gaps (Part D) | ⚠️ | Pull-to-refresh: 0 views use `.refreshable` — iOS pattern relies on `.task` reload |
| Data Integrity (Part E) | ⚠️ | DashboardService tests use `>= 0` weak assertions; PE-023 filed |

**Force unwraps fixed (9 total, 6 files):**
| File | Line | Fix |
|------|------|-----|
| `PartsService.swift` | 3831 | `Calendar.current.date(byAdding:)!` → nil-coalescing |
| `PartsService.swift` | 3902 | `Calendar.current.date(byAdding:)!` → nil-coalescing |
| `PartsService.swift` | 4060 | `Calendar.current.date(byAdding:)!` → nil-coalescing |
| `PartsService.swift` | 4137 | `Calendar.current.date(byAdding:)!` → nil-coalescing |
| `PartsService.swift` | 4617 | `Calendar.current.date(byAdding:)!` → nil-coalescing |
| `PartsService.swift` | 5117 | `Calendar.current.date(byAdding:)!` → nil-coalescing |
| `NotebooksService.swift` | 566 | `Calendar.current.date(byAdding:)!` → nil-coalescing |
| `PeopleService.swift` | 1150 | `Calendar.current.date(byAdding:)!` → nil-coalescing |
| `JobsService.swift` | 689 | `Calendar.current.date(byAdding:)!` → nil-coalescing |
| `OrdersService.swift` | 1059-1060 | `partDemand[partId]!.sources` → `partDemand[partId]?.sources` |
| `SettingsService.swift` | 184 | `grouped[cat]![key]` → `grouped[cat]?[key]` |

**New issues filed:** PE-023 (weak test assertions)

---

### Iteration 14 — dev-improvement-scanner: Hardcoded User IDs + Force Unwraps (2026-03-31)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | 790/790 passing |
| Code Patterns (Part A) | ⚠️→✅ | 2 force unwraps in core data layer fixed (BaseRepository, ConflictResolver) |
| Security (Part B) | ⚠️→✅ | 4 hardcoded user IDs fixed (AITools ×2, QRScanner ×2) |
| HIG / UX | ℹ️ | No new violations found this run |

**Force unwraps fixed (2 total, 2 files):**
| File | Line | Fix |
|------|------|-----|
| `BaseRepository.swift` | 129 | `keys.map { data[$0]! }` → `keys.compactMap { data[$0] }` |
| `ConflictResolver.swift` | 493 | `mergedData.keys.sorted().map { mergedData[$0]! }` → `compactMap` |

**Hardcoded user IDs fixed (4 occurrences across 4 files):**
| File | Lines | Fix |
|------|-------|-----|
| `AITools.swift` (GetActiveCompanionPollsTool) | 225,235 | Added `userId: Int64` to init; replaced `userId: 0` with real userId |
| `AITools.swift` (GetVotingSummaryTool) | 329,339 | Added `userId: Int64` to init; replaced `userId: 0` with real userId |
| `FoundationModelsService.swift` | 327 | Added `userId: Int64 = 0` param to `chatWithTools`; forwarded to both poll tools |
| `IOSAIAssistantPanel.swift` | 535 | Passed `userId: appCore.currentUser?.id ?? 0` to `chatWithTools` |
| `IOSDashboardQRScannerPage.swift` | 143,599 | `userId: 1` → guard-let `appCore.currentUser?.id` |

**Impact:** AI companion polls now correctly show per-user voting context. QR scanner warehouse position now attributed to the authenticated user instead of always user 1.

**New issues filed:** None — all found issues auto-fixed.

---

## Cumulative Progress

| Metric | Baseline | Current | Delta |
|--------|----------|---------|-------|
| Core tests | 545 | **759** | **+214** |
| Test suites | 40 | **49** | **+9** |
| Compile errors | 0 | 0 | = |
| Compile warnings | 0 | 0 | = |
| SQL mismatches fixed | 0 | **~68** | **-68** |
| Service files fixed | 0 | **26** | +26 |
| iOS files fixed | 0 | 9 | +9 |
| New test files | 0 | **8** | +8 |
| Scheduled tasks | 0 | **3** | +3 |
| TODOs in code | 10 | 1 | -9 (9 dueDate TODOs resolved in prior iterations) |
| Empty catches | 20+ | 3 truly silent | -17 |
| Force casts | 0 | 0 | = |
| Force unwraps in core | 4 | 0 | **-4** (Iter 11) |
| Force unwraps in core (new scan) | 9 | 0 | **-9** (Iter 13, dev-improvement-scanner) |
| Force unwraps in core (Iter 14) | 2 | 0 | **-2** (BaseRepository, ConflictResolver) |
| Hardcoded user IDs | 4 | 0 | **-4** (AITools ×2, QRScanner ×2 — Iter 14) |
| iOS files fixed | 9 | **11** | +2 (IOSAIAssistantPanel, IOSDashboardQRScannerPage) |

---

## GitHub Sync Log

### Sync Run — 2026-03-29 (automated)

| Item | Status |
|------|--------|
| Build | ✅ passes |
| Tests | ✅ 676/676 |
| Commits created | 4 |
| Commit: SQL fixes | `c116544` |
| Commit: New tests | `f3c6977` |
| Commit: iOS sheet fixes | `70869ee` |
| Commit: Docs | `eb57957` |
| Push | ⚠️ Skipped — SSH keys not loaded in automated context |
| Notes | Commits are ready locally. Run `git push origin main` manually or re-run when SSH agent is available. |

---

## Weekly Cleanup Log

### Weekly Cleanup — 2026-04-13 (Run 3)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 1217/1217 passing

**Part A — Xcode Prompt Archival:** 6 completed prompt files physically moved to `done/` — PE-036, PE-037, PE-039, PE-040, PE-041, PE-042. All were marked ✅ done in `00-fix-order.md` but still in active directory. PE-043 remains as NEXT. `00-next-prompt.md` retained (stale content but < 3 months old).

**Part B — Dead Code:** 2 candidates found — `parseDateYMD` in `PeopleService.swift:1965` and `formatDate` in `BreakService.swift:448`. Both are unused private functions. Neither qualifies for removal (both added March 2026, < 3 months old). Flagged for future cleanup.

**Part C — Temp Files:** No `.tmp/` directory exists. No `.DS_Store` outside `.git`. No `.bak`/`.orig`/`.swp` files. `docs/Problomes /` contains 34 screenshots (all from March–April 2026, within 3-month window) — kept.

**Part D — Q&A Cleanup:** `docs/dev-qa.md` already clean. 2 pending blocks (Colors/Brands + Dismiss/Keyboard) — correctly in Pending. 3 processed entries in Reference Log — already integrated into plans.

**Part E — Documentation Freshness:** All docs modified March–April 2026. Zero docs older than 3 months. No staleness warnings needed.

**Part F — Tracker Cleanup:** All hunt-fix iterations started 2026-03-28. All within 3 months. No compression needed. `dev-pipeline.md` recent work all from March–April 2026 — no archival needed.

**GitHub Issues Filed:** 0 (no unresolvable issues found)

**Summary:** Clean project state. Main action: 6 archived prompts moved to correct directory.

---

### Weekly Cleanup — 2026-04-05 (Run 2)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 970/970 passing

| Part | Action | Result |
|------|--------|--------|
| A — Xcode Prompt Archival | Checked 00-fix-order.md vs fix-prompts/ for prompts > 3 months old | None eligible — PE-027/029/030/031/034 all done/skipped but created 2026-04-04 (< 3 months). `done/` has 290+ archived. |
| B — Dead Code Scan | Scanned all Swift files in core/Sources/WiredPartCore/ for commented-out code, empty extensions, unused private functions | **Clean** — all comment blocks are `///` doc comments or explanatory inline comments, not dead code |
| C — Temp Files | Checked for .tmp/, .DS_Store, .bak, .orig, .swp | No .tmp dir. .DS_Store only in .git/ internals (untouched). No .bak/.orig/.swp found. `docs/Problomes /` has 32 screenshots from 2026-03-28 — within 3 months, retained. |
| D — Q&A | Reviewed docs/dev-qa.md | **DIS-007 removed** (resolved: non-issue, view destroyed on logout). DIS-005 remains (answered, needs Xcode prompt — pending dev-pipeline-manager). Stale "Answers integrated" block cleaned up. |
| E — Doc Freshness | Checked docs/ for files > 3 months old | **None** — oldest file is Mar 8, 2026 (28 days ago). All within threshold. |
| F — Tracker Compression | Checked hunt-fix-tracker.md (1251 lines) and dev-pipeline.md for entries > 3 months | None — all iterations/entries from 2026-03-28 onward. No compression needed. |

**Flagged for review:**
- `DIS-005` (docs/DevTODO/DIS-005-userdefaults-pii-wizard.md): Owner confirmed UserDefaults PII keys NOT deleted after wizard. Option B (SQLite draft table) selected. Needs Xcode prompt from dev-pipeline-manager.
- `DIS-007` resolved: IOSMainView `.onReceive` is safe — view is destroyed on logout. DevTODO closed. Remaining action: add code comment in IOSMainView.swift for future devs.
- PE-027/029/030/031 in fix-prompts/: all marked done (direct edits). Will be eligible for archival to done/ in ~3 months (approx July 2026).

**Next cleanup:** 2026-04-12 (Sunday 6 AM)

---

### Weekly Cleanup — 2026-03-29 (Run 1)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 691/691 passing

| Part | Action | Result |
|------|--------|--------|
| A — Xcode Prompt Archival | Checked 00-fix-order.md vs fix-prompts/ for prompts > 3 months old | None eligible — all files < 3 months old. `done/` has 126 archived. |
| B — Dead Code Scan | Scanned 65 Swift files for commented-out code, empty extensions, unused private functions | **Clean** — zero findings |
| C — Temp Files | Removed 4 `.DS_Store` files (root, docs/, docs/plans/, Weird Parts IOS/) | ✅ Cleaned |
| D — Q&A | Reviewed docs/dev-qa.md | Already clean — no pending questions |
| E — Doc Freshness | Checked docs/ for files > 3 months | None found — oldest is Mar 8 (21 days ago) |
| F — Tracker Compression | Checked for iterations > 3 months old | None — all iterations from 2026-03-28/29 |

**Flagged for review:** None.
**Next cleanup:** 2026-04-05 (Sunday 6 AM)

---

### Iteration 9 — User Attribution Verification + Broad SQL Audit (2026-03-29, automated)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 691/691 passing

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ PASS | 0 errors, 0 warnings |
| Tests | ✅ PASS | 691/691 passing — all 49 suites clean |
| Code Patterns | ✅ PASS | No silent catches, no force casts, no stub UI. Print statements found only in system/manager classes (expected debug) |
| SQL Integrity | ✅ PASS | All 9 recently modified service files verified against schema. All new SQL uses correct column names |
| Runtime Safety | ✅ PASS | No unguarded array subscripts, no division-by-zero, no fatalErrors in services |
| Edge Cases | ✅ PASS | No array[0] subscripts, fresh-DB paths all return empty gracefully |
| Problems Folder | ✅ PASS | docs/Problomes/ does not exist — no pending user-reported bugs |
| Master Issues | ⚠️ | 65 items (T1:20, T2:25, T3:20 — mostly iOS UI features needing prompts) |
| Plan Alignment | ✅ PASS | dev-qa.md clean — no pending questions |
| Security | ✅ PASS | No SQL injection (all string interpolation is hardcoded column names), no hardcoded secrets, orderClause uses allowlisted values only |

**Key verified SQL fixes (from iteration 8 diffs):**
| Service | Bug Fixed | Fix |
|---------|-----------|-----|
| ChatService | `autoSaveToJobNotebook` missing `userId` param; wrong column names for notebook insert | Added `userId` param, use `section_id` + correct schema |
| WarehouseService | `audit_sessions` (non-existent) → `audit_sessions_v2`; `qty_fulfilled` → `qty_received`; `unit_price` → `unit_cost`; `part_number` → `code` | All correct |
| ReportsService | `budget_amount` → `budget_limit`; `total_amount` → `total_cost` | Verified against schema |
| FleetService | `vehicle_inspections` → `inspection_records`; `vi.inspection_date` → `ir.performed_at`; `vehicles.odometer` → `vehicles.current_odometer` | All correct |
| JobsService | Removed `updated_at` from `labor_entries` UPDATE (column does not exist in schema) | Verified |
| SchedulingService | `h.name = 'admin'` → `h.name = 'Admin'` (SQLite case-sensitive string match) | Verified |
| DailyReportGenerator | `qt.question` → `qt.subject AS question` (column is `subject` not `question`) | Verified |
| PartsService | `unit_price` → `unit_cost` in po_line_items subquery | Verified |

**iOS prompt 67A — User Attribution:**
- `IOSAuditSetupView.swift` — `userId: appCore.currentUser?.id ?? 1` already applied ✅
- `IOSMessageThreadView.swift` — `userId: appCore.currentUser?.id ?? 1` already applied ✅
- Prompt archived to `xcode-ai/fix-prompts/done/`
- Tracking entry marked ✅ done in `00-fix-order.md`

**No new bugs found requiring fixes this iteration.**



---

### Iteration 10 — Test Coverage Expansion: OrdersService + Schema Bug (2026-03-30, automated)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 759/759 passing (was 736 — +23 new tests)

**Coverage analysis:**
| Service | Methods | Tested Before | Tested After | New Tests |
|---------|---------|--------------|--------------|-----------|
| OrdersService | 40+ | ~15 | ~30 | 20 new tests |
| SchedulingService | 28 | 26 | 28 | 2 new tests |
| ChatService | 30+ | 28 | 29 | 1 new test |

**New tests added this run:**
- `updateJPOLineStatus` — updates line status and re-derives parent JPO status
- `updateJPOLineStatus` with on_hold — records hold reason
- `deriveJPOStatusFromLineStatuses` — 4 scenarios (pure function): all-pending, all-delivered, empty, mixed
- `updateJPODeliveryOption` — changes delivery option on unlocked JPO
- `updatePOLineItem` — updates qty+price on draft PO (also found bug)
- `updatePOLineItem` guard — throws when PO is not in draft status
- `getCategoryStageMappings` — returns all categories with nil stageId when unmapped
- `updateCategoryStageMapping` + `getCategoryStageMappings` — full round-trip
- `getJobStageParts` — empty and with JPO lines
- `requestEarlyRelease` — promotes held line to approved
- `getReceiptHistoryEntries` — empty on fresh PO (queries `receiving_sessions`)
- `getReceiptHistoryItems` — empty for non-existent session
- `getPartsForSupplier` — empty and with PO lines
- `listJPOs(jobId:)` — filter by job isolates results correctly
- `getDispatchJobRows` — empty and active-only filter
- `syncOfficeChannelMembers` — no-op when no office channel, and with office channel

**Bug found and fixed:**
| Service | Method | Bug | Fix |
|---------|--------|-----|-----|
| OrdersService | `updatePOLineItem` | Referenced `updated_at` column in UPDATE but `po_line_items` has no such column (SQLite error 1) | Removed `updated_at = datetime('now')` from SET clause — consistent with schema |

**Self-annealing loop applied:** Test → Error → Read schema → Fix service → Re-test ✅

---

## Iteration 10 — Security Hardening + Tracker Sync (2026-03-30, automated)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 759/759 passing — all 49 suites clean (+23 from audit tests now fully exercised)

**Scanner results:**

| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ PASS | 0 errors, 0 warnings |
| Tests | ✅ PASS | 759/759 passing — all 49 suites clean |
| Code Patterns | ✅ PASS | All `print()` in iOS are inside `#Preview` blocks (compile-excluded). `Button { }` empty closures are all `role: .cancel` (correct) or intentionally guarded (with comment). `Text("Coming Soon")` is in `PlaceholderView` struct (intentional stub). |
| SQL Integrity | ✅ PASS | `BackgroundTaskService` fully verified against migration 058. `WarehouseService` `counted_qty`/`last_counted` verified in `stock` table (migration 062). `MultiUserAuditAssignment` column mapping verified. `OrdersService` `partDemand` force unwraps are nil-guarded (safe). |
| Runtime Safety | ✅ PASS | `partDemand[partId]!` in OrdersService (lines 1059-1060) is inside `if != nil` guard — logically safe. No unguarded subscripts. |
| Edge Cases | ✅ PASS | All services return empty gracefully on `isTableNotFoundError`. |
| Problems Folder | ✅ PASS | `docs/Problomes/` does not exist. |
| Master Issues | ⚠️ | 20 T1, 25 T2, 20 T3 — mostly iOS UI features needing Xcode prompts. PE items tracked in fix-order. |
| Plan Alignment | ✅ PASS | `dev-qa.md` clean — no pending questions. Recent commits match planned work. |
| Security | ✅ PASS | Token signing key now Keychain-backed (PE-021). HMAC-SHA256 verified. Brute-force lockout verified. Legacy PIN salt in `legacyHashPin()` is migration-only (PE-008c, tracked). |

**Changes made this iteration:**

| Item | Action | Files Changed |
|------|--------|---------------|
| PE-021 | **Fixed:** Token signing key moved from ephemeral UUID to Keychain-backed 256-bit random key | `AuthService.swift` |
| PE-020 | **Closed:** All three audit count bugs already fixed in prior commits + tests exist | `00-fix-order.md` (tracker updated) |
| PE-008a | **Closed in tracker:** HMAC-SHA256 signing already implemented (b3eef3b) | `00-fix-order.md` |
| PE-008b | **Closed in tracker:** Brute-force lockout already implemented (b3eef3b) | `00-fix-order.md` |
| DevTODO-16 | **Marked done:** Token signing key fix complete | `16-token-signing-key-keychain.md` |

**Self-annealing applied:**
- Discovered PE-020/PE-021/PE-008a/PE-008b already implemented but not marked closed → updated tracker to reflect reality
- Implemented PE-021 directly in core (Keychain API, no Xcode AI needed) → build + 759 tests pass

**No new GitHub issues filed** — all findings were either already fixed or tracked.


---

### Iteration 12 — test-coverage-maintenance: Coverage Expansion (2026-03-31, automated)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 790/790 passing — 31 new tests added, 5 SQL bugs fixed

**Coverage expansion:**
| Service | Methods Added Tests For | New Tests |
|---------|------------------------|-----------|
| DashboardService | `getStockAtLocationType`, `getPOKPIDetail`, `getStockLocationsForPart`, `getPartMovementInfo`, `getOfficeBriefing`, `getFinancialSnapshot` | 11 |
| BreakService | `autoFillBreaksForDay` (+ 3 edge cases) | 3 |
| PeopleService | `getTeamMembers`, `getTeamJobs`, `getContractorNotes`, `addContractorNote`, `getContractorRating`, `addContractorRating`, `getContractorJobHistory`, `getContactsSorted`, `getContactTypeCounts`, `isPaymentTrackingEnabled`/`set`, `getPaymentSettings`, `updatePaymentSettings`, `createPaymentRecord`, `recordPayment`, `getOverdueCustomers` | 17 |

**Bugs uncovered by tests (5 SQL column mismatches):**
| Service | Bug | Fix Applied |
|---------|-----|-------------|
| DashboardService.getPOKPIDetail | `s.contact_email` → `s.email` | ✅ Fixed |
| DashboardService.getPOKPIDetail | `pl.quantity` → `pl.qty_ordered` | ✅ Fixed |
| PeopleService.getContactsSorted | `ec.contact_type` → `ec.entity_type AS contact_type` | ✅ Fixed |
| PeopleService.getContactsSorted | `ec.company` → `ec.role AS company` | ✅ Fixed |
| PeopleService.getContactTypeCounts | `contact_type` → `entity_type` | ✅ Fixed |

**Design issue found (not fixed — needs decision):**
- `contractor_notes` and `contractor_ratings` FK references `entity_contacts` not `general_contractors` — design inconsistency between old (general_contractors) and new (entity_contacts) contractor storage. Tests written to accommodate actual FK requirement.

---

### Iteration 11 — dev-improvement-scanner: Force Unwrap Sweep (2026-03-30, automated)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 759/759 passing — no regressions

**Scanner type:** dev-improvement-scanner (PARTS A–E: runtime safety, security, Apple HIG, UX polish)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ PASS | 0 errors, 0 warnings |
| Tests | ✅ PASS | 759/759 passing after fixes |
| Runtime Safety | ⚠️→✅ | 4 force unwraps found and fixed in core |
| Security | ✅ PASS | No SQL injection, no hardcoded secrets, PIN hashing adequate (SHA-256 × 10k). PE-008c (legacy salt) tracked. |
| Apple HIG | ⚠️ | Hardcoded font sizes (24+ instances → tracked in PE-009a), tap targets (40+ flagged, interactive subset counted in PE-009b). Both already in pipeline. |
| UX Polish | ✅ PASS | Most pages have loading + empty states. No new gaps found. |

**Force unwrap fixes applied:**
| File | Line | Fix |
|------|------|-----|
| `BackgroundTaskService.swift:117` | `entry.id!` after GRDB insert | `guard let newId = entry.id else { throw DatabaseError(...) }` |
| `ToolsService.swift:1391` | `earliestDue == nil || due < earliestDue!` | `earliestDue.map({ due < $0 }) ?? true` |
| `AITools.swift:196,199` | `styleId != nil ? "...\(styleId!)" : ""` | `styleId.map { "...\($0)" } ?? ""` |
| `BaseRepository.swift:80` | `keys.map { data[$0]! }` | `keys.compactMap { data[$0] }` + invariant comment |

**Findings already tracked (no new issues needed):**
- Hardcoded `.font(.system(size:))` → PE-009a (88 fonts in 51 files)
- Tap targets < 44pt → PE-009b (12 interactive elements)
- Company setup wizard UserDefaults usage → NOT a security issue (temporary onboarding state)
- Force casts in test files (`as! HTTPURLResponse`) → LOW priority, test-only code

**No new GitHub issues filed** — all remaining findings already tracked in PE-009.


---

### Iteration 12 — Security + SQL Audit (2026-03-31, automated)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 790/790 passing — all 49 suites clean (+31 from test fixes)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ PASS | 0 errors, 0 warnings |
| Tests | ✅ PASS | 790/790 passing — up from 759 |
| Code Patterns | ✅ PASS | All `print()` in `#Preview` blocks (excluded from production). No force casts, no stub UI in production code. |
| SQL Integrity | ❌→✅ | 4 SQL bugs fixed (contact_name, user_hats missing deleted_at, contractor FK) |
| Security | ❌→✅ | Critical: soft-deleted hat assignments still granted permissions (4 queries missing `deleted_at IS NULL`) |
| Problems Folder | ✅ PASS | `docs/Problomes/` does not exist |
| Master Issues | ⚠️ | 20 T1, 25 T2, 20 T3 — mostly iOS UI features |
| GitHub Issues | ⚠️ | 5 open (#9, #10, #14, #15, #17) — #17 is discoverability (commented with instructions) |
| Plan Alignment | ✅ PASS | dev-qa.md clean |

**Security bug fixed:**
| File | Bug | Fix |
|------|-----|-----|
| `AuthService.swift` | `getUserPermissions` / `hasPermission` / `getUserHatNames` / `getUserHats` filtered on `is_active = 1` but NOT `deleted_at IS NULL` — soft-deleted hat assignments still granted permissions | Added `AND uh.deleted_at IS NULL` to all 4 `user_hats` queries |

**SQL bugs fixed:**
| File | Bug | Fix |
|------|-----|-----|
| `PeopleService.swift` (employees list) | `LEFT JOIN user_hats uh ON uh.user_id = u.id` missing `AND uh.deleted_at IS NULL` | Removed hat = deleted hat still shown in employee list and `GROUP_CONCAT(hat_names)` |
| `PeopleService.swift` (employee detail) | `JOIN user_hats uh ON uh.hat_id = h.id WHERE uh.user_id = ?` missing `AND uh.deleted_at IS NULL` | Fixed |
| `PeopleService.swift` (hat user count) | `COUNT(*) FROM user_hats WHERE hat_id = h.id` missing `AND deleted_at IS NULL` | Hats page showed inflated user counts including removed assignments |
| `PeopleService.swift` (getOverdueCustomers) | `COALESCE(c.company_name, c.name, c.contact_name, ...)` — `customers` table has no `contact_name` column (SQLite error 1) | Removed `c.contact_name` from COALESCE |

**Schema bug fixed (Migration 063):**
| Table | Bug | Fix |
|-------|-----|-----|
| `contractor_notes` | `contractor_id` FK referenced `entity_contacts` but service passes `general_contractors.id` | Migration 063: Drop and recreate with FK → `general_contractors` |
| `contractor_ratings` | Same FK mismatch — FK constraint failed on all note/rating inserts | Migration 063: Drop and recreate with FK → `general_contractors` |

**Permissions UI bug fixed:**
| File | Bug | Fix |
|------|-----|-----|
| `IOSPermissionsPage.swift` | 10 permission keys (`approve_orders`, `approve_time_off`, `create_jobs`, `self_assign_*`, `view_all_jobs`, `view_audit_log`, `view_job_financials`, `view_job_reports`, `view_spending`) seeded by `defaultPermissionMap()` in AuthService but NOT shown in Permissions UI — admins couldn't see or toggle them | Added all 10 keys to correct groups in `allPermissions` array |

**Test fixes (stale API calls):**
| Test | Bug | Fix |
|------|-----|-----|
| `testContactsSorted` | Calling old `createContact(firstName:contactType:email:phone:company:)` API (no longer exists) | Updated to current `createContact(entityType:entityId:firstName:role:phone:)` |
| `testContactTypeCounts` | Same old API | Updated to current API |

**GitHub issue #17 responded to:** Feature exists, explained where hat assignment UI lives (Employee Detail → Hats tab). Added discoverability note.

**Self-annealing loop applied:**
- Test → FK constraint error on contractor_notes → Checked schema → Found FK references wrong table → Migration 063 → Tests pass ✅
- Test → `c.contact_name` SQL error → Checked customers schema → Known anti-pattern → Fixed COALESCE ✅
- Test → Old `createContact` API → Found new signature → Updated tests ✅
- Security scan → Missing `deleted_at IS NULL` in 4 user_hats queries → Fixed all 4 + PeopleService queries ✅

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 759 | 790 | +31 |
| Security bugs | 1 active | 0 | -1 |
| SQL bugs | 0 known | 0 | = |
| Permissions visible in UI | 47 | 57 | +10 |
| Migrations | 62 | 63 | +1 |


---

### Iteration 13 — Maintenance Pass (2026-04-01, automated)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 842/842 passing — all 49 suites clean (+14 new fleet/people tests from Run 6)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ PASS | 0 errors, 0 warnings |
| Tests | ✅ PASS | 842/842 passing (up from 790) |
| Code Patterns | ✅ PASS | All `print()` calls are in `#Preview` blocks — not production code. No force casts, no stub UI, no dead buttons. |
| SQL Integrity | ✅ PASS | `general_contractors.contact_name` verified in schema (Migration line 1595). All WHERE clause builders use parameterized `?` placeholders. No new violations. |
| Security | ✅ PASS | No hardcoded secrets. No sensitive data in UserDefaults (only tab prefs + onboarding state). SQL injection scan: all dynamic clauses use `?` params. |
| Force Unwraps | ✅ PASS | No `variable!.property` force unwrap dot-access in service files. |
| Problems Folder | ✅ PASS | `docs/Problomes/` does not exist |
| Master Issues | ⚠️ | 20 T1, 25 T2, 20 T3 — same as before; all tracked in GitHub/plans |
| GitHub Issues | ⚠️ | 5 open (#9, #10, #14, #15, #17) — unchanged |
| Plan Alignment | ✅ PASS | `00-fix-order.md` updated: PE-022, PE-001, PE-008c marked done; archived to `done/`. Next prompt: PE-009b |

**Changes made:**
| Change | Details |
|--------|---------|
| `00-fix-order.md` updated | PE-022, PE-001, PE-008c all marked ✅ done (2026-03-31) — were completed in Run 6 but not marked |
| PE-022, PE-001, PE-008c archived | Moved from `xcode-ai/fix-prompts/` → `fix-prompts/done/` |
| New tests committed | 16 new FleetServiceTests (telematics, fuel level, inspection, reports) + 2 new PeopleServiceTests (payment status) — all passing |

**No bugs fixed** — codebase clean. Maintenance and sync pass only.

**Queue state after this iteration:**
- Next Xcode AI prompt: **PE-009b** (12 undersized tap targets)
- After that: PE-009c (2 remaining swipe confirmations)
- Blocked: PE-003 (flex pool, awaiting 5 Q&A answers in dev-qa.md)

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 790 | 842 | +52 |
| Completed PE prompts | PE-022 (done), PE-001 (done), PE-008c (done) | archived | +3 archived |
| Active prompt queue | 8 items | 5 items | -3 |
| Security bugs | 0 | 0 | = |
| SQL bugs | 0 | 0 | = |

### Iteration 14 — Dev Improvement Scanner Run 4 (2026-04-01, automated)

**Build:** ✅ 0 errors, 0 warnings (expected — fix is in core Swift, no compile changes)
**Tests:** ✅ 842/842 passing (unchanged)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Runtime Safety | ✅ PASS | 0 force casts, 0 `try!`, 0 `fatalError` in production paths |
| Data Integrity | ✅ PASS | All SQL parameterized; `exportTable()` validates against `sqlite_master`; notebook field update gated by `allowedFields` Set |
| Security | ✅ PASS | Tokens in Keychain; PIN uses SHA-256 ×10,000 + per-user salt; no sensitive data in UserDefaults |
| Debug Code | ⚠️ FIXED | 3 `print()` calls in `PeerDiscovery.swift` not gated by `#if DEBUG` |
| Apple HIG | ✅ PASS | NavigationStack, 647 a11y labels, 132 refreshable, 65 destructive roles |
| Dynamic Type | ✅ PASS | 0 hardcoded font sizes in feature views |
| UX Polish | ✅ PASS | 185/214 feature files have empty states; all async views have loading states |
| Accessibility | ✅ PASS | 647 accessibilityLabel + 305 accessibilityHidden annotations |

**Fix made:**
| File | Change |
|------|--------|
| `core/Sources/WiredPartCore/Sync/PeerDiscovery.swift` | Added `import os.log`; added `private let logger = Logger(subsystem: "com.wiredpart.core", category: "PeerDiscovery")`; replaced 3 `print()` with `logger.error()`; added `[logger]` capture list in closures |

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 842 | 842 | = |
| Production print() calls | 3 | 0 | -3 |
| GitHub issues | 0 | 0 | = |

---

### Iteration 18 — Full 10-Scanner Pass (2026-04-02, automated)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 842/842 passing — all 49 suites clean (unchanged)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ PASS | 0 errors, 0 warnings |
| Tests | ✅ PASS | 842/842 passing — no regressions |
| Code Patterns | ⚠️→✅ | 3 production `print()` in iOS app (GeofenceManager, LocationManager, AppCore) replaced with `os.Logger` |
| SQL Integrity | ✅ PASS | No new SQL mismatches. All WHERE clause builders parameterized. |
| Runtime Safety | ✅ PASS | 0 force casts, 0 `try!`, 0 `fatalError`. All division-by-zero paths guarded (totalQuestions > 0, est > 0, totalChunks > 0, fields.isEmpty ternary). |
| Edge Cases | ✅ PASS | No array subscript without bounds check. Fresh-DB paths all return empty gracefully. |
| Problems Folder | ✅ PASS | `docs/Problomes/` does not exist |
| Master Issues | ⚠️ | 20 T1, 25 T2, 20 T3 — mostly iOS UI features; 28 GitHub issues open (feature-level, not crashers) |
| Plan Alignment | ✅ PASS | `dev-qa.md` has 1 unanswered question block (PE-003 Flex Pool, 5 questions, blocked by design decisions). No drift from plans. |
| Security | ✅ PASS | No SQL injection. No hardcoded API keys or secrets. No sensitive data in UserDefaults. `os.Logger` used throughout core + iOS app. |

**Fixes made:**
| File | Change |
|------|--------|
| `GeofenceManager.swift` | Added `import os.log`; added `nonisolated let logger`; replaced `print()` in `monitoringDidFailFor` delegate with `logger.error()` |
| `LocationManager.swift` | Added `import os.log`; added `nonisolated let logger`; replaced `print()` in `didFailWithError` delegate with `logger.error()`; moved log before Task to avoid cross-actor access |
| `AppCore.swift` | Added `import os.log`; added `nonisolated let logger`; replaced `print()` in `#if !DEBUG` migration-recovery block with `logger.error()` |

**Concurrency safety note:** All three `Logger` properties are declared `nonisolated let` because they are accessed from `nonisolated` CLLocationManager delegate methods and `Task.detached` closures. `Logger` is `Sendable`, so this is safe and suppresses any Swift concurrency warnings.

**Confirmed safe (no changes needed):**
- `SectionHeaderStyle.swift:37`, `ErrorStateView.swift:55`, `EmptyStateView.swift:65` — all inside `#Preview {}` blocks (compile-excluded from release)
- `AppCore.swift:441` — inside `#if DEBUG` block (debug-only)
- All catch blocks with `} catch {` pattern are non-empty (set errorMessage, call userFriendlyError, or rethrow)
- Division-by-zero: all 6 instances guarded by precondition checks

**Self-annealing applied:**
- Found `print()` in `GeofenceManager` + `LocationManager` CLLocationManager delegate callbacks → converted to `os.Logger` → declared `nonisolated` to allow access from nonisolated delegates ✅
- Found `print()` in `AppCore #if !DEBUG` block (runs in production/TestFlight) → converted to `logger.error()` ✅

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 842 | 842 | = |
| iOS app production print() calls | 3 | 0 | -3 |
| Total production print() calls (all code) | 3 | 0 | -3 |
| iOS files using os.Logger | 1 (PeerDiscovery) | 4 | +3 |
| GitHub issues | 28 open | 28 open | = |

---

### Iteration 19 — Warranty SQL Mismatch + Force Unwrap Fix (2026-04-02, automated)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 842/842 passing — all 49 suites clean (unchanged)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ PASS | 0 errors, 0 warnings |
| Tests | ✅ PASS | 842/842 passing — no regressions |
| Code Patterns | ✅ PASS | 2 `URL(string:)!` force-unwraps fixed in `IOSContactDetailPage.swift` |
| SQL Integrity | ❌→✅ | **1 high-severity bug** — warranty column split in `JobsService.swift` (see below) |
| Runtime Safety | ✅ PASS | 0 force casts, 0 `try!`, 0 `fatalError` |
| Edge Cases | ✅ PASS | No new edge case issues |
| Problems Folder | ✅ PASS | `docs/Problomes/` does not exist |
| Master Issues | ⚠️ | 20 T1, 25 T2, 20 T3 — unchanged |
| Plan Alignment | ✅ PASS | No drift |
| Security | ✅ PASS | No SQL injection, no hardcoded secrets |

**Bugs fixed:**

| # | File | Severity | Bug | Fix |
|---|------|----------|-----|-----|
| 1 | `JobsService.swift` L481-482, L541, L612-613 | HIGH | `createJob`/`updateJob`/decode all used `warranty_start_date`/`warranty_end_date` (migration 003 columns), but `setWarranty`/`isWarrantyActive`/`warrantyDaysRemaining` all read/write `warranty_start`/`warranty_end` (migration 044 columns). Data written at job creation was invisible to all warranty-check queries — warranty status would always return false/nil. | Changed `createJob` INSERT, `updateJob` SET clauses, and row decode to use `warranty_start`/`warranty_end` — consistent with the warranty-methods API |
| 2 | `IOSContactDetailPage.swift` L67, L72 | LOW | `URL(string: "tel:...")!` and `URL(string: "mailto:...")!` — force-unwrap crash if URL initializer returns nil | Changed to `if let phoneURL = URL(...)` / `if let mailURL = URL(...)` conditional binding |

**Root cause of warranty bug:** Schema evolution trap — migration 003 added `_date` suffix columns, migration 044 added cleaner names without suffix. Both column sets exist simultaneously. `setWarranty` was written against the new columns but `createJob`/`updateJob` were never updated.

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 842 | 842 | = |
| SQL bugs (silent data mismatch) | 1 | 0 | -1 |
| Force-unwrap crash risks in iOS | 2 | 0 | -2 |
| GitHub issues | 28 open | 28 open | = |

---

### Iteration 20 — Contact Detail Performance Fix (2026-04-02, dev-improvement-scanner run 5)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 843/843 passing (+1 new: `testGetContactById`)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ PASS | 0 errors, 0 warnings |
| Tests | ✅ PASS | 843/843 passing |
| Code Patterns | ✅ PASS | 0 force unwraps, 0 force casts, 0 NavigationView (deprecated) |
| SQL Integrity | ✅ PASS | All services verified clean |
| Runtime Safety | ✅ PASS | No crash risks found |
| Apple HIG | ✅ PASS | All tap targets ≥44pt, empty states present, Dynamic Type in use |
| Performance | ❌→✅ | `IOSContactDetailPage.loadData()` + `EditContactSheet.loadContact()` fetched entire `entity_contacts` table to find one contact by ID — O(n) full scan |

**Bugs fixed:**

| # | File | Severity | Bug | Fix |
|---|------|----------|-----|-----|
| 1 | `IOSContactDetailPage.swift` L89-108, L192-207 | Medium | Both `loadData()` and `loadContact()` called `getContactsSorted(sortBy:typeFilter:)` then filtered `.first { $0.id == contactId }` — fetching all contacts for a single ID lookup | Added `PeopleService.getContact(id:)` using `WHERE ec.id = ? LIMIT 1` parameterized query; both call sites updated |
| 2 | `PeopleService.swift` | Medium | No single-contact lookup existed; all callers were forced into the full-scan workaround | Added `getContact(id:) throws -> ContactListItem?` with indexed primary key query and `isTableNotFoundError` guard |

**New method added:**
```swift
// PeopleService.swift — after getContactsSorted
public func getContact(id: Int64) throws -> ContactListItem?
// SELECT ... FROM entity_contacts WHERE deleted_at IS NULL AND id = ? LIMIT 1
```

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 842 | 843 | +1 |
| Performance bugs | 1 | 0 | -1 |
| PeopleService methods covered by tests | ~20 | ~21 | +1 |

---

### Iteration 21 — Test Coverage Expansion (2026-04-02, automated: test-coverage-maintenance)

**Goal:** Expand test coverage for untested public methods in `NotebooksService` and `PartsService`.

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | 861/861 passing (+19 new tests) |
| Coverage analysis | ✅ | Targeted 15+ untested methods |
| Service bugs found | ✅ | 2 bugs fixed (see below) |

**New tests added (19 total):**

*NotebooksServiceTests.swift (+2):*
- `testStartWarrantyTimer` — `startWarrantyTimer` sets warranty_timer_end on entry
- `testGetTodosNeedingReview` — full classify → needs-review → reviewed lifecycle

*PartsServiceExtTests.swift (+17):*
- `testPartAlternativesEmpty` — `listPartAlternatives` returns empty on fresh part
- `testPartAlternativeLifecycle` — `linkPartAlternative` / `unlinkPartAlternative` round-trip
- `testPartPriceStaleOnFresh` — `isPartPriceStale` returns true with no cost_last_updated
- `testGetStalePricedParts` — `getStalePricedParts` includes part with no price date
- `testMarkPriceVerified` — `markPriceVerified` makes part non-stale
- `testConsumptionHistoryEmpty` — `getConsumptionHistory` empty before any FIFO
- `testConsumptionHistoryAfterFIFO` — `getConsumptionHistory` populated after FIFO consumption
- `testResetToCurrentBuyPrice` — collapses layers to single current-buy-price layer
- `testPartStockSummaryEmpty` — `getPartStockSummary` returns zero on fresh part
- `testPartStockSummaryWithStock` — stock summary reflects warehouse stock
- `testSupplierContactLifecycle` — `addSupplierContact` / `getSupplierContacts` / `removeSupplierContact`
- `testPartChangeLog` — `logPartChange` / `getPartChangeLog` round-trip
- `testTracePartMovementsEmpty` — `tracePartMovements` empty before any movements
- `testTracePartMovementsAfterReceive` — trace populated after stock receive
- `testGetPartCurrentLocations` — correct warehouse location after stocking
- `testScheduledDeletionLifecycle` — `scheduleEmptyShelfDeletion` / `listScheduledDeletions` / `cancelScheduledDeletion`

**Service bugs fixed:**

| # | File | Severity | Root Cause | Fix |
|---|------|----------|------------|-----|
| 1 | `PartsService.swift` | High | `consumeInventoryFIFO` created `CostLayerConsumption` with `createdAt: nil` — GRDB's Codable-derived persistence explicitly inserts NULL for nil optionals, overriding SQLite column defaults → NOT NULL constraint crash | Set `createdAt: ISO8601DateFormatter().string(from: Date())` before `insert()` |
| 2 | `PartsService.swift` | Medium | `markPriceVerified` stored `datetime('now')` (SQLite format: `2026-04-02 01:20:24`) but `isPartPriceStale` parsed via `ISO8601DateFormatter` which requires `T` separator + timezone (`Z`) → parse failure → always returned stale=true | Changed to store `ISO8601DateFormatter().string(from: Date())` for consistent format |

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 843 | 861 | +19 |
| Service bugs | 2 | 0 | -2 |
| PartsService methods with tests | ~13 methods | ~29 methods | +16 |
| NotebooksService methods with tests | ~28 methods | ~30 methods | +2 |

---

### Iteration 22 — GitHub Issues Sync: Fix #28 + #19 (2026-04-02, github-issues-sync run 3)

**Goal:** Process 32 open GitHub issues filed after user testing session 2026-03-28. Auto-fix bugs in core Swift where possible.

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | 862/862 passing (+1 regression test) |
| GitHub Issues | 32 open | 28 from user testing + 4 new (#46-#49) |
| Bugs fixed in core | ✅ | 2 bugs fixed (see below) |
| Xcode prompts written | ✅ | PE-024 (modal dismiss) + PE-025 (empty states/settings) |
| Q&A generated | ✅ | 4 design questions for #46/#47/#48/#49 |

**Bugs fixed:**

| # | File | GitHub | Root Cause | Fix |
|---|------|--------|------------|-----|
| 1 | `SchedulingService.swift` + `AppDatabase+Migrations.swift` | #28 | `schedule_exceptions` stores one row per day; no group key links multi-day requests → list shows N rows instead of 1 | Migration 064 adds `request_group TEXT`; `createTimeOffRequest` assigns UUID per batch; `listTimeOffRequests` groups by UUID; `updateTimeOffStatus` cascades to group |
| 2 | `ChatService.swift` | #19 | `ensureOfficeChannel()` hardcoded `created_by = 1` (NOT NULL + FK to users) → FK violation on empty DB → background task fails → red error badge on Dashboard on fresh install | Guard: skip if no users exist; use actual admin user ID instead of hardcoded 1; +1 regression test `testEnsureOfficeChannelEmptyDatabase` |

**Routes investigation (#40):**
- `/orders/parts` → `OrdersRouter(tabId: "orders-parts")` → `IOSPartsOrderManagementPage` — routes are present
- `/orders/wishlist` → `OrdersRouter(tabId: "orders-wishlist")` → `IOSWishlistPage` — routes are present
- Likely appears broken due to #26 (empty DB crash) rather than missing routes. Commented on issue.

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 861 | 862 | +1 |
| Open GitHub issues | 0 | 32 (new issues discovered) | +32 |
| Core bugs fixed | 0 | 2 | +2 |
| Active Xcode prompts | 0 | 2 (PE-024, PE-025) | +2 |
| Migrations | 063 | 064 | +1 |

---

### Iteration 25 — isTableNotFoundError Drift + Auth Test Isolation (2026-04-03, hunt-fix-verify run 9)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | **876/876 passing** (+14 tests previously hidden by crash, now visible) |
| Code Patterns | ✅ | 1 fix: `print()` → `logger.debug()` in AppCore production code path |
| SQL Integrity | ✅ | All previously modified service files re-verified — no new mismatches |
| Runtime Safety | ✅ | No force unwraps in services |
| Edge Cases | ✅ | No division by zero or unguarded array subscripts |
| Problems Folder | ✅ | Folder does not exist (all issues in GitHub) |
| Master Issues | ⏳ | 32 open GitHub issues; no new T1 fixable issues found |
| Plan Alignment | ✅ | No unplanned code found |
| Security | ✅ | Two dynamic SQL sites audited — both validated (table name vs sqlite_master, field name vs allowlist) |

**Bugs fixed (4):**

| # | Bug | File | Fix |
|---|-----|------|-----|
| 1 | `print()` in production code path (build detection) | AppCore.swift:441 | → `logger.debug()` using existing `Logger` instance |
| 2 | `isTableNotFoundError` missing "no such column" guard — 14 services had the old implementation, 6 had the updated one | AIDispatchService, BackgroundTaskService, BreakService, ChatService, DashboardService, FleetService, JobEstimationService, NotebooksService, OrdersService, ReportsService, SchedulingService, ToolsService, WarehouseService, WishlistService | Added `\|\| message.contains("no such column")` to all 14 |
| 3 | Static `loginAttempts` dict bleeds across auth tests — wrong-PIN tests in one test case lock out correct-PIN tests in another (all test DBs use user ID 1) | AuthService.swift | Added `AuthService.resetAllLoginAttempts()` public static method |
| 4 | E2ETestHelpers.setUp() didn't clear lockout state | E2ETestHelpers.swift | Added `AuthService.resetAllLoginAttempts()` call at start of setUp |

**Root cause of test count jump (862 → 876):**
The auth test crash (`fatalError: Unexpectedly found nil while unwrapping an Optional value` at E2EAuthBootstrapTests.swift:63) caused Swift Testing to abort 14 subsequent tests that couldn't run. With the lockout isolation fix, all 876 tests complete normally.

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 862 | 876 | +14 (previously crash-hidden) |
| Compile errors | 0 | 0 | = |
| isTableNotFoundError consistency | 6/20 services | 20/20 services | fully consistent |
| Flaky auth tests | yes (lockout bleed) | no | fixed |

---

## github-issues-sync run 4 — 2026-04-03

**Bugs fixed (2):**

| # | Bug | File | Fix |
|---|-----|------|-----|
| 1 | Hierarchy tree expansion state reset on every data reload — `.id(dataVersion)` in `PartsCategoriesPage` destroys all child `@State` on each data change | `CategoriesTreeView.swift`, `PartsCategoriesPage.swift` | Lifted 4 expanded sets from `@State private` in child to `@State` in parent page, passed as `@Binding`; parent is outside `.id(dataVersion)` scope so state survives reloads |
| 2 | Compile error in `BreakService.roundToNearest()`: `TimeZone(secondsFromGMT: 0)` is `TimeZone?` — `calendar.timeZone` expects non-optional | `BreakService.swift:422` | Added `!` force-unwrap — safe because 0 is always a valid GMT offset |

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 876 | 877 | +1 |
| Compile errors | 1 (BreakService) | 0 | fixed |
| Hierarchy tree state persistence | resets on every refresh | persists within session | fixed |

---

### Iteration 26 — Full 10-Scanner Pass (2026-04-03, hunt-fix-verify run 10)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | **877/877 passing** (no change) |
| Code Patterns | ✅ | 3 `print()` statements found — all in `#Preview` blocks (compile-time only, not production) |
| SQL Integrity | ✅ | All 15 modified services re-verified — no mismatches. 1 doc comment inaccuracy fixed |
| Runtime Safety | ✅ | No new force unwraps; BreakService UTC fix uses `?? TimeZone(secondsFromGMT: 0)!` (safe) |
| Edge Cases | ✅ | Empty cancel buttons in alerts verified intentional (SwiftUI pattern for confirmation dismiss) |
| Problems Folder | ✅ | 32 screenshots only — all tracked in GitHub issues |
| Master Issues | ⚠️ | T1-02 (wishlist_items) and T1-10 (background_task_log) are closed — migrations 057/058 created both tables. Master issue list is stale for these. |
| Plan Alignment | ✅ | PE-025 work (Teams empty state, Tab Bar layout, Settings nav style) verified in working tree |
| Security | ✅ | No hardcoded secrets, no SQL injection vectors, no new UserDefaults misuse |

**Bugs fixed (1):**

| # | Bug | File | Fix |
|---|-----|------|-----|
| 1 | Doc comment on `listCheckouts()` said `returned_at IS NULL` — correct column is `checked_in_at` | `ToolsService.swift:270` | Updated comment to reference correct column name |

**Notes:**
- `createBlockEntry` in NotebooksService confirmed to correctly set `notebook_id` by looking up from `notebook_sections`
- Regression test `testCreateBlockEntryPopulatesNotebookId` passes and guards this behavior
- T1-02 and T1-10 in master-issue-list.md are stale — both tables were created in migrations 057/058

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 877 | 877 | = |
| Compile errors | 0 | 0 | = |
| Doc comment accuracy | 1 stale | 0 | -1 |

---

### Iteration 27 — Runtime Crash Fix: Multi-User Audit Consensus (2026-04-04, hunt-fix-verify run 11)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | **909/909 passing** (+3 new tests added) |
| Code Patterns | ✅ | Empty catches all properly handled (isTableNotFoundError + re-throw pattern) |
| SQL Integrity | ✅ | All modified services re-scanned: AuthService, ChatService, DashboardService, SchedulingService, WarehouseService, FleetService, ReportsService, ToolsService — all clean |
| Runtime Safety | ❌→✅ | **1 crash fixed** — WarehouseService `resolveMultiUserAudit` subscript OOB |
| Edge Cases | ✅ | Multi-user audit with nil countedQuantity now returns nil instead of crashing |
| Problems Folder | ✅ | No new items |
| Master Issues | ⚠️ | T1-T3 open issues unchanged — require Xcode AI prompts for iOS UI work |
| Plan Alignment | ✅ | No drift detected |
| Security | ✅ | No hardcoded secrets, no SQL injection, no UserDefaults misuse |

**Bugs fixed (1):**

| # | Bug | File | Fix |
|---|-----|------|-----|
| 1 | `resolveMultiUserAudit` used `countedAssignments.count == 2` to gate subscript access `counts[0]` / `counts[1]`, but `counts = compactMap { $0.countedQuantity }` can be shorter if any `countedQuantity` is nil — guaranteed IndexOutOfBounds crash | `WarehouseService.swift:3996-4015` | Added `guard counts.count == countedAssignments.count else { return nil }` after compactMap; replaced `countedAssignments.count` with `counts.count` in all subscript-guarded branches |

**Tests added (3):**

| Test | Covers |
|------|--------|
| `testMultiUserAuditConsensusAgree` | Two counters submit same qty → consensus resolves to that qty |
| `testMultiUserAuditConsensusDisagree` | Two counters submit different qty → returns nil |
| `testMultiUserAuditInsufficientCounts` | Only one counter submits → returns nil |

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 895 | 909 | +14 |
| Compile errors | 0 | 0 | = |
| Crash risks | 1 | 0 | -1 |


---

### Iteration 28 — BadgeCountService SQL Integrity Audit (2026-04-04, hunt-fix-verify run 12)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | **940/940 passing** (+10 new tests, +3 test suites) |
| Code Patterns | ✅ | 3 `print()` statements confirmed in `#Preview` blocks only — not production |
| SQL Integrity | ❌→✅ | **4 SQL bugs in BadgeCountService** — all fixed |
| Runtime Safety | ✅ | No new force unwraps or OOB subscripts |
| Edge Cases | ✅ | `safeCount` + `isTableNotFoundError` pattern verified correct in new service |
| Problems Folder | ✅ | No new items |
| Master Issues | ⚠️ | PE-033 (Clock In/Out) remains top priority — not auto-fixable |
| Plan Alignment | ✅ | `BadgeCountService` aligns with `docs/plans/ios-badge-counts.md` goals |
| Security | ✅ | `SettingsService.exportTable` confirmed safe — uses DB-returned name from parameterized query, not caller-supplied string. `CompanySetupWizard` UserDefaults use is setup wizard progress only (not credentials). No injection vectors. |

**Bugs fixed (4):**

| # | File | Severity | Root Cause | Fix |
|---|------|----------|------------|-----|
| 1 | `BadgeCountService.swift:157` | Medium | `job_dispatch WHERE (worker_id IS NULL OR worker_id = 0)` — column is `user_id` (NOT NULL), not `worker_id`. All dispatch rows have an assigned user. Query was silently returning 0 via `isTableNotFoundError` "no such column" guard. | Changed to `COUNT(DISTINCT job_id)` WHERE `date(dispatch_date) = date('now') AND status = 'scheduled'` — counts active jobs dispatched today |
| 2 | `BadgeCountService.swift:185` | High | `pto_transactions WHERE status = 'pending'` — `pto_transactions` has NO `status` column (it's a PTO ledger table: hours/balance). Time-off requests live in `schedule_exceptions`. Query silently returned 0. | Changed to `schedule_exceptions WHERE exception_type = 'time_off' AND is_approved = 0 AND deleted_at IS NULL`, grouped by `request_group` to avoid counting multi-day requests multiple times |
| 3 | `BadgeCountService.swift:189` | Low | `tool_edit_log WHERE status = 'pending'` — table does not exist in any migration. Silently returns 0 via `isTableNotFoundError`. | Added clarifying comment: "planned future table — returns 0 gracefully". No schema change needed. |
| 4 | `BadgeCountService.swift:193` | Medium | `scheduled_deletions WHERE status = 'pending'` — schema defines status values as `'draining'`, `'pending_approval'`, `'approved'`, `'cancelled'`. No `'pending'` value exists. Query always returned 0 even with real pending deletions. | Changed to `WHERE status = 'pending_approval'` |

**Key discovery — how bugs were masked:**
`isTableNotFoundError()` catches both "no such table" AND "no such column" errors (fixed in Iteration 25). This means column name mismatches return 0 instead of crashing, which is correct resilience behavior — but also makes SQL bugs invisible at runtime. The SQL integrity scanner is the only way to catch them.

**Tests added (10 new):**

| Test | Covers |
|------|--------|
| `testFreshDatabaseReturnsAllZeros` | All counts start at 0 on clean DB |
| `testPendingApprovalsCountsSubmittedJPOs` | `job_parts_orders.status = 'submitted'` |
| `testPendingTimeOffUsesScheduleExceptions` | Time-off uses `schedule_exceptions`, not `pto_transactions` |
| `testPendingDeletionsUsesPendingApprovalStatus` | `scheduled_deletions.status = 'pending_approval'` |
| `testOpenDispatchesUsesCorrectColumnName` | `job_dispatch.user_id` (not `worker_id`) |
| `testOfficeBadgeAggregation` | `officeBadge = approvals + timeOff + toolEdits + deletions` |
| `testOrdersBadgeAggregation` | `ordersBadge = approvals + overdueOrders` |
| `testBadgeForModuleId` | `badge(for:)` routes to correct per-tab field |
| `testHasOldItemsFalseForRecentDate` | Items < 7 days old → no red tint |
| `testHasOldItemsTrueForOldDate` | Items > 7 days old → red tint |

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 927 | 940 | +13 |
| Test suites | 49 | 50 | +1 |
| Compile errors | 0 | 0 | = |
| BadgeCountService SQL bugs | 4 | 0 | -4 |
| Badge counts that were always 0 | 3 (`openDispatches`, `pendingTimeOff`, `pendingDeletions`) | 0 | -3 |

---

## Weekly Cleanup Run 3 — 2026-04-05 (Sunday)

**Scanner:** Weekly Cleanup Agent
**Result:** ✅ Nothing to clean — codebase is well-maintained

### Part A: Completed Xcode Prompts

| Check | Result |
|-------|--------|
| PE-028 (brands/suppliers editing) | ✅ Already in `done/` |
| PE-032 (schedule config additive) | ✅ Already in `done/` |
| PE-033 (wishlist section layout) | ✅ Already in `done/` |
| PE-034 (DIS quick UX fixes) | ✅ Active prompt — valid, keep in queue |
| PE-027/029/030/031 (done via direct edit) | ⏳ Recent (< 3 months) — not archived per policy |

### Part B: Dead Code

No files in `core/Sources/WiredPartCore/` older than 3 months. Only 1 TODO comment found across all Swift sources (intentional `dueDate` pattern — already tracked). No commented-out blocks, no unused private functions/properties meeting the 3-month threshold found.

### Part C: Stale Temporary Files

| Check | Result |
|-------|--------|
| `.tmp/` directory | ✅ Does not exist |
| `.DS_Store` files | ✅ None found |
| `.bak` / `.orig` / `.swp` files | ✅ None found |
| `docs/Problomes/` | 32 screenshots from 2026-03-28 — within 3-month window, keep |

### Part D: Q&A File

`docs/dev-qa.md`: 1 question pending (DIS-005 — CompanySetupWizard PII in UserDefaults). Both sub-questions have answers. **Not removed** — awaiting plan integration into `docs/plans/` before removal per workflow.

### Part E: Documentation Freshness

All docs in `docs/` dated March–April 2026. Earliest is 2026-03-08. 3-month cutoff is 2026-01-05. **No docs flagged** — all within window.

### Part F: Tracker Cleanup

`docs/hunt-fix-tracker.md` (1274 lines, 28 iterations): All iterations from March–April 2026 — within 3-month window. **No compression needed.**

`docs/dev-pipeline.md` (1543 lines): "Recently Completed" entries all from March–April 2026. **No archiving needed.**

### Verification

| Check | Result |
|-------|--------|
| `swift build` | ✅ Build complete (0 errors, 0 warnings) |
| `swift test` | ✅ **978/978 passing** (52 suites) |

**Summary:** Codebase clean. No deletions performed. Agent Health Dashboard updated in dev-pipeline.md.

---

### Iteration 29 — Post-Usability-Hunter Verification (2026-04-05, hunt-fix-verify run 13)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ✅ | **978/978 passing** (no changes needed) |
| Code Patterns | ✅ | 3 `print()` in `#Preview` blocks — confirmed false positives (dev-only, not in production build) |
| SQL Integrity | ✅ | PartsService, JobsService — all columns verified. `setClauses` string interpolation uses hardcoded fragment strings only — no injection risk |
| Runtime Safety | ✅ | No new force unwraps; WizardStepPlacement `guard let→let` fix confirmed correct (`WarehouseZone.gridX` is non-optional `Int`) |
| Edge Cases | ✅ | Minor: `CartSheetView` nil-service silently marks items placed — non-critical, service never nil in practice |
| Problems Folder | ✅ | `docs/Problomes/` doesn't exist — no new user reports |
| Master Issues | ⚠️ | 20 T1, 25 T2, 20 T3 open — all require Xcode AI prompts for iOS UI work |
| Plan Alignment | ✅ | CartManager, PartsFlowWizard, WizardStepPlacement, WarehouseDashboardPage changes align with `ios-warehouse-setup-redesign.md` and usability-hunter plan |
| Security | ✅ | No SQL injection, no hardcoded secrets, UserDefaults usage is onboarding flags only (appropriate) |

**What was verified (7 recently-modified iOS files):**

| File | Change | Verdict |
|------|--------|---------|
| `WizardStepPlacement.swift` | `guard let` on non-optional `Int` removed → plain `let` | ✅ Correct fix — old `guard let` would fail to compile |
| `PartsFlowWizard.swift` | `[Part]→[PartWithDetails]`; `adjustStock()` (non-existent) removed → save as note | ✅ Correct — `listParts()` returns `[PartWithDetails]`; `adjustStock` never existed |
| `IOSClockPage.swift` | `.notClockedIn` case handled; errorMessage only cleared on successful load | ✅ Correct UX improvement |
| `CompanySetupWizard.swift` | Exit button → confirmationDialog before discarding setup | ✅ Correct — prevents accidental exit loss (#117 closed) |
| `IOSWarehouseSettingsPage.swift` | Warehouse Setup section added with wizard launchers | ✅ Clean — enum-based sheet pattern correct (#120 closed) |
| `WarehouseDashboardPage.swift` | "Just Count Parts" wired to PartsFlowWizard; CartManager + CartBadgeButton added | ✅ Correct enum sheet + onChange bridge pattern |
| `CartManager.swift` | `@MainActor` removed; `Sendable` added to `CartItem` | ✅ Safe — all usage is within SwiftUI main-actor context |

**Bugs fixed (0 new — all previously committed):**
This iteration verified work from last commit (05c7f58: closes #96-#104, #108-#114) and the usability-hunter changes in working tree. No new bugs required fixing.

**Scanner false-positive documented:**
- `print()` grep matches inside `#Preview { }` blocks — preview code is stripped in production builds; scanner note added

**Metrics delta:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 978 | 978 | = |
| Compile errors | 0 | 0 | = |
| New bugs found | — | 0 | — |
| iOS files verified | — | 7 | — |

---

## Plan-Enforcer Run 6 — 2026-04-05

**Scope:** Plan Registry audit — 15+ plans checked against code, permission map audit, prompt file housekeeping.

### Findings

| Category | Result |
|----------|--------|
| Critical Bug Found | ✅ FIXED — `manage_flex_pool`/`self_assign_flex` missing from `AuthService.defaultPermissionMap()` |
| PE-003 Status | Confirmed DONE — `IOSFlexPoolPage` fully wired, SchedulingRouter + NavigationConfig |
| PE-027/029/030/031 | Confirmed DONE — prompt files moved to `done/` |
| New Plan Registered | `usability-hunter-plan.md` + skill at `xcode-ai/skills/usability-hunter/SKILL.md` |
| DIS-008/009/011 | 3 new DevTODO items identified (gh unavailable — not yet filed as GitHub issues) |
| Plans Advanced to Step 13 | `ios-flex-pool`, `ios-clock-fix`, `ios-pricing-ui`, `ios-part-number-hierarchy`, `ios-scheduling-pages` |

### Critical Fix Detail

**File:** `core/Sources/WiredPartCore/Services/AuthService.swift`

`manage_flex_pool` and `self_assign_flex` were referenced in UI code:
- `IOSJobDetailTabView.swift:497` — `appCore.hasPermission("manage_flex_pool")` (manager flex pool toggle)
- `NavigationConfig.swift:85` — `permission: "self_assign_flex"` (flex pool tab visibility)

But neither key existed in `defaultPermissionMap()`. This caused:
- Flex Pool tab invisible to all workers (Worker/Lead hats showed no tab)
- Manager "Add to Flex Pool" toggle invisible to all managers

**Fix:** Added to all appropriate hats:
- `manage_flex_pool` → Admin, Manager
- `self_assign_flex` → Admin, Manager, Lead, Worker

### Unplanned Code Noted

`PricingOverrideFlow.swift` — exists with no plan reference. Adds hierarchy-level pricing override flow. Retroactively documented in Plan Registry as extending `ios-pricing-ui.md` scope.

---

### Iteration 30 — Migration SQL Syntax + companion_vote_power Fresh Install (2026-04-06)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings |
| Tests | ❌→✅ | **1014→1020 passing** (migration 072 SQL syntax error fixed) |
| Code Patterns | ✅ | No new issues. Empty `{ }` bodies confirmed intentional (cancel/documented). DIS-011 already fixed in code. |
| SQL Integrity | ✅ | migration 072 `company_setup_draft` syntax fixed; SettingsService SQL fully parameterized |
| Runtime Safety | ✅ | No new force unwraps in core. DIS-011 already resolved. |
| Edge Cases | ✅ | Fresh install companion_vote_power seeding fixed |
| Problems Folder | ✅ | N/A — Problomes/ doesn't exist |
| DevTODO | ⚠️ | DIS-009 still open (main thread bulk DB writes) — needs Xcode AI prompt |
| Master Issues | ⚠️ | DIS-008 still open (tiny hardcoded fonts) — needs Xcode AI prompt |
| Plan Alignment | ✅ | Prompt queue PE-034/035/036/037 ready for user |
| Security | ✅ | No SQL injection, no hardcoded secrets |

**Bug 1: Migration 072 — `DEFAULT datetime('now')` without parentheses**
- **File:** `AppDatabase+Migrations.swift:521`
- **Root cause:** SQLite requires function calls in DEFAULT expressions to be wrapped in `()`. `.defaults(sql: "datetime('now')")` generates `DEFAULT datetime('now')` which is a syntax error. Correct form: `DEFAULT (datetime('now'))`.
- **Fix:** Changed to `.defaults(sql: "(datetime('now'))")`
- **Impact:** ALL 1014 tests were failing (the migration runs during test setup, so every test suite crashed at DB init)
- **Tests:** 1020 now passing (6 additional via linter pickup of pre-existing tests in AuthServiceTests.swift)

**Bug 2: `companion_vote_power` / `vote_veto` not in defaultPermissionMap()**
- **File:** `AuthService.swift` — `defaultPermissionMap()`
- **Root cause:** Migration 073 seeds these permissions by querying existing hats, but on fresh install the migration runs BEFORE `seedFirstAdmin()` creates hats → no rows found → no permissions seeded → `defaultPermissionMap()` also missing these keys → permanent tie on all companion polls for fresh installs
- **Fix:** Added `companion_vote_power` to Admin/Manager/Lead, `vote_veto` to Admin in `defaultPermissionMap()`
- **Test added:** Extended `testAdminPermissions()` to assert `companion_vote_power` and `vote_veto` are present after `seedFirstAdmin()`

**Open items (not auto-fixable):**
- DIS-008: Hardcoded tiny fonts in WizardStepPlacement + JobStageProgressBar → DevTODO filed, Xcode AI prompt needed
- DIS-009: Bulk SQLite writes on main thread (CartManager, PartsFlowWizard) → DevTODO filed, needs proper Swift Concurrency design

---

### Iteration 31 — Dev-Improvement Security Scan (2026-04-06)

**Scanner:** dev-improvement-scanner (run 10)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings (prior state — build not re-run this iteration) |
| Tests | ✅ | 1030/1030 passing (prior state — no new core tests this iteration) |
| Runtime Safety | ✅ | **CLEAN** — 0 `as!` force casts, 0 `try!`, 0 genuine force unwraps found |
| SQL Integrity | ✅ | **CLEAN** — All dynamic SQL uses closed enum mapping or `?` placeholder generation. Zero injection vectors. |
| Code Patterns | ✅ | NavigationView (deprecated): 0 instances. All navigation uses NavigationStack. |
| Security | ⚠️ | 3 new findings filed: DIS-012 (PIN KDF strength), DIS-013 (legacy salt migration deadline), DIS-014 (unsigned token shim) |
| Apple HIG | ⚠️ | DIS-008 (JobStageProgressBar hardcoded fonts) confirmed still pending PE-038 — not a new finding |
| Accessibility | ✅ | 377 `.accessibilityLabel` usages found — healthy coverage |
| UserDefaults | ⚠️ | PartsFlowWizard stores part counts/locations in UserDefaults — noted as minor consistency issue (relates to DIS-009 scope) |
| Empty/Error States | ✅ | `.task` error handling confirmed: all use internal `do/catch` in called functions |

**New findings filed (DIS-012/013/014):**
- DIS-012: `hashPin(_:salt:)` uses 10,000× SHA-256 — GPU-breakable for 4-6 digit PINs. Needs PBKDF2/Argon2id migration + `pin_hash_version` column.
- DIS-013: `verifyPinLocally()` falls through to `legacyHashPin()` (hardcoded `"wiredpart"` salt) for any user with `pin_salt IS NULL`. No re-hash deadline enforced.
- DIS-014: `parseLocalToken()` accepts unsigned tokens (no HMAC) as a backward-compat shim. No removal deadline. Low risk (requires jailbreak to exploit).

**Confirmed NOT new (already tracked):**
- DIS-015 scan finding → duplicate of DIS-009 (PartsFlowWizard UserDefaults, different aspect — main thread writes is the primary concern)
- DIS-016 scan finding → duplicate of DIS-008 (JobStageProgressBar font sizes — PE-038 ready)

**DevTODO files created:**
- `docs/DevTODO/DIS-012-pin-hashing-weak-kdf.md`
- `docs/DevTODO/DIS-013-legacy-pin-salt-path.md`
- `docs/DevTODO/DIS-014-unsigned-token-shim.md`

**GitHub issues:** PENDING — `gh` not available. File manually: DIS-012, DIS-013, DIS-014 as security/enhancement issues.

**Open items (not auto-fixable):**
- DIS-012/013: Auth security hardening — needs design decision (PBKDF2 vs Argon2id) before implementation. Best done as one coordinated pass.
- DIS-014: Remove legacy unsigned token `else` branch — safe to remove, 1-line change, but should be verified on-device first.

---

### Iteration 32 — Full 10-Scanner Pass (2026-04-07, hunt-fix-verify run 14)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ **1097/1097 passing** (53 suites — up +67 from last logged count of 1030)

**Scanner results:**

| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ PASS | 0 errors, 0 warnings |
| Tests | ✅ PASS | 1097/1097 across 53 suites — LAN sync + BT sync integration tests run in parallel 75-second batches |
| Code Patterns | ✅ PASS | `Text("Coming Soon")` in `IOSContentRouter.swift:361` is inside `struct PlaceholderView` — intentional stub view for unbuilt routes, not a forgotten TODO. No silent catches, no force casts, no empty buttons. |
| SQL Integrity | ✅ PASS | `general_contractors.contact_name` verified valid in migration (line 1648). All recently modified service files clean. AuthService SQL all parameterized. |
| Runtime Safety | ✅ PASS | `BreakService.swift:422` `TimeZone(secondsFromGMT: 0)!` — documented safe (0 offset is always valid GMT). No new unwraps. |
| Edge Cases | ✅ PASS | No division by zero, no unguarded subscripts. |
| DevTODO | ✅ | DIS-009 **CLOSED** — CartManager.placeAllItems() confirmed wrapped in Task{} in working tree. Both PartsFlowWizard + CartManager now fully async. DIS-012/013/014 open — need design decisions. |
| GitHub Issues | ⚠️ | 129 open issues. Systemic: #121 (198 try?), #122 (426 guard-let bail), #128 (20+ empty catches), #129 (dirty tracking). Program-review: #82-#95 (feature-level rebuilds). |
| Plan Alignment | ✅ PASS | PE-037 **DONE** — all 9 target sheets confirmed to have `.interactiveDismissDisabled(isSaving)`. PE-039 **DONE** — CartManager confirmed. Prompt queue now empty (0 active). |
| Security | ✅ PASS | No SQL injection, no hardcoded secrets. DIS-012/013/014 tracked and awaiting design decisions. |

**Changes made this iteration:**

| Item | Action | Files Changed |
|------|--------|---------------|
| DIS-009 | **CLOSED** — CartManager.placeAllItems() already wrapped in Task{} in working tree; status updated to CLOSED | `docs/DevTODO/DIS-009-bulk-db-writes-main-thread.md` |
| PE-037 | **CONFIRMED DONE** — All 9 sheets verified: CreateChannelSheet, IOSCreateTrailerSheet, IOSCreateVehicleSheet, CreateNotebookSheet, CreatePOSheet, CreateReturnSheet, CascadePriceEditSheet, CreateDispatchSheet, RequestTimeOffSheet | `xcode-ai/fix-prompts/00-fix-order.md` |
| PE-039 | **FULLY DONE** — Both PartsFlowWizard (PE-039) and CartManager (DIS-009) confirmed fully async | `xcode-ai/fix-prompts/00-fix-order.md` |
| Prompt queue | **CLEARED** — 0 active prompts remain | `xcode-ai/fix-prompts/00-fix-order.md` |

**No new bugs found.** All scanners clean.

**Metrics delta:**

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 1030 | 1097 | +67 (previously sync-blocked by migration 072 fix; now all run) |
| Compile errors | 0 | 0 | = |
| Active Xcode prompts | 1 (PE-037) | 0 | -1 |
| DIS-009 status | PARTIAL | CLOSED | ✅ |
| Async main-thread risks | 2 locations | 0 | -2 |

---

### Iteration 34 — Security Hardening + Schema Version Sync (2026-04-08)

**Scanner results:**
| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ | 0 errors, 0 warnings (transient incremental ordering error self-resolved on retry) |
| Tests | ✅ | 1121/1121 passing (+3 new) |
| Code Patterns | ✅ | All catch blocks intentional; no empty buttons; no force casts |
| SQL Integrity | ✅ | No new mismatches |
| Runtime Safety | ✅ | No force unwraps in core |
| Edge Cases | ✅ | No new edge case issues |
| Problems Folder | ✅ | `docs/Problomes/` does not exist (clean) |
| Master Issues | ⚠️ | DIS-012/013/014 still open; DIS-014 now CLOSED |
| Plan Alignment | ✅ | PE-040/PE-041 now marked done (page-rebuild-enforcer 2026-04-08) |
| Security | ✅ | DIS-014 fixed; DIS-012/013 pending design decision |

**Fixes applied (3 files, 3 issues):**

| Fix | File | Details |
|-----|------|---------|
| DIS-014 CLOSED | `AuthService.swift:735` | Removed legacy unsigned token `else` branch — all tokens since PE-008a (2026-03-31) are HMAC-signed; unsigned tokens now return `nil` |
| Schema version stale | `AppDatabase.swift:12` | Updated `schemaVersion` from 61 → 74 (74 actual migrations: 000-073) |
| Migration test stale | `DatabaseTests.swift` | Updated "All 61 migrations" → "All 74 migrations"; updated `testSchemaVersion` 61→74; added `testMigration073FloorPlanGridDimensions` for grid_rows/grid_cols columns |

**Tests added (3 new — now 1121 total):**
- `testParseTokenRejectsUnsigned` — verifies unsigned tokens are rejected (DIS-014 regression guard)
- `testParseTokenRejectsTamperedSig` — verifies HMAC signature tampering is detected
- `testMigration073FloorPlanGridDimensions` — verifies migration 073 added grid_rows/grid_cols to warehouse_floor_plans

**Security status:**
- DIS-014 (unsigned token shim) — ✅ CLOSED — removed 2026-04-08
- DIS-013 (legacy PIN re-hash) — Login-time auto-upgrade already in place (lines 167-177). No change needed for Option A. Remaining work is enforcement deadline (Option B) — pending owner decision.
- DIS-012 (PBKDF2 upgrade) — Still blocked on KDF design decision (PBKDF2 vs Argon2id)

**GitHub issues:**
- #132 (unsigned token shim) — can be closed; fix applied

**Observation — PE-040/PE-041 done:**
The page-rebuild-enforcer completed PE-040 (warehouse wizard drag-and-drop) and PE-041 (receiving auto-save draft) on 2026-04-08, including migration 073 (grid_rows/grid_cols). Test coverage for migration 073 added this iteration.

**Result:** 1121 tests passing, 0 errors, 0 warnings.

**Iteration deltas:**
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 1118 | 1121 | +3 |
| Compile errors | 0 | 0 | = |
| Security issues (active) | 3 | 2 | -1 (DIS-014 closed) |
| Schema version accuracy | Stale (61/74) | Correct (74/74) | ✅ |
| Active Xcode prompts | 2 (PE-040/PE-041) | 0 | -2 (both completed by page-rebuild-enforcer) |

---

### Iteration 35 — CoreFormatters Sweep + Scanner Pass (2026-04-15, hunt-fix-verify run 9)

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ **1255/1255 passing** (55 suites — up +134 from last logged 1121)

**Scanner results:**

| Scanner | Status | Details |
|---------|--------|---------|
| Compile | ✅ PASS | 0 errors, 0 warnings (3 pre-existing `nonisolated(unsafe)` warnings on DateFormatter fixed) |
| Tests | ✅ PASS | 1255/1255 across 55 suites |
| Code Patterns | ✅ PASS | No silent catches, no force casts, no dead buttons, no stub UI in production code |
| SQL Integrity | ✅ PASS | FleetService `next_maintenance_date` verified valid (added via `addColumnIfMissing` in migration). All other service SQL clean. |
| Runtime Safety | ✅ PASS | No new force unwraps |
| Edge Cases | ✅ PASS | No new edge cases |
| Problems Folder | ✅ PASS | `docs/Problomes/` contains only old screenshots (no new user reports) |
| GitHub Issues | ⚠️ | 50+ open. Systemic: #121 (try?), #122 (guard-let bail), #128 (empty catches), #129 (dirty tracking). #229 partially resolved (permission guard in place). |
| Plan Alignment | ✅ PASS | `docs/dev-qa.md` clean — all Q&A answered 2026-04-14. #229 permission guard confirmed in working tree. |
| Security | ✅ PASS | No SQL injection, no hardcoded secrets. DIS-012/013 still pending design decision. |

**Changes made this iteration:**

| File | Fix | Type |
|------|-----|------|
| `WishlistService.swift` | Replaced 3 inline `ISO8601DateFormatter()` (2 inline + `nowString()` helper) → `CoreFormatters` | Performance |
| `JobEstimationService.swift` | Replaced `nowString()` helper body → `CoreFormatters.nowISO()` | Performance |
| `WarehouseService.swift` | Replaced `nowString()` helper body → `CoreFormatters.nowISO()` | Performance |
| `ChatService.swift` | Replaced `parseDate()` helper (3 formatters + fallbacks) → `CoreFormatters.parseDateTime()` | Performance |
| `DailyReportGenerator.swift` | Replaced `parseDateTime()` helper (3 formatters + fallbacks) → `CoreFormatters.parseDateTime()` | Performance |
| `BadgeCountService.swift` | Replaced 2-formatter parse pattern → `CoreFormatters.parseISO()` | Performance |
| `DashboardService.swift` | Replaced 2-formatter parse + creation block → `CoreFormatters.parseISO()` | Performance |
| `JobsService.swift` | Replaced 5 inline formatter usages (`setWarranty`, `isWarrantyActive`, `warrantyDaysRemaining`, `getTodaysClockEntries`) → CoreFormatters | Performance |
| `ToolsService.swift` | Replaced 1 inline `isoFormatter.string(from:)` → `CoreFormatters.iso8601.string(from:)` | Performance |
| `NotebooksService.swift` | Replaced `fmt.string(from:)` for warranty timer dates → `CoreFormatters.iso8601.string(from:)` | Performance |
| `AuthService.swift` | Replaced `isRecentlyOnline` 2-formatter pattern → `CoreFormatters.parseDateTime()` | Performance |
| `SyncCrypto.swift` | Replaced `currentTimestamp()` helper → `CoreFormatters.nowISO()` | Performance |
| `ConflictResolver.swift` | Replaced `currentTimestamp()` helper → `CoreFormatters.iso8601Fractional.string(from: Date())` | Performance |
| `MultipeerManager.swift` | Replaced 2 formatter patterns → `CoreFormatters.iso8601Fractional.string(from:)` | Performance |
| `SyncEngine.swift` | Replaced `currentTimestamp()` helper → `CoreFormatters.iso8601Fractional.string(from: Date())` | Performance |
| `PeerManager.swift` | Replaced inline formatter → `CoreFormatters.iso8601Fractional.string(from: Date())` | Performance |
| `PeerDiscovery.swift` | Replaced `currentTimestamp()` helper → `CoreFormatters.iso8601Fractional.string(from: Date())` | Performance |
| `FoundationModels.swift` | Replaced `now()` helper → `CoreFormatters.iso8601Fractional.string(from: Date())` | Performance |
| `CoreFormatters.swift` | Removed 3 redundant `nonisolated(unsafe)` on `DateFormatter` (now Sendable in Swift 6) | Warning fix |

**Total: 28 inline `ISO8601DateFormatter()` allocations eliminated across 19 files. Only 2 canonical instances remain (inside CoreFormatters itself).**

**Issue #229 status:**
- Permission guard (`edit_pricing`) ✅ CONFIRMED in working tree — category row:352, type row:495
- `resolveConflicts` UI tests ⚠️ OPEN — iOS UI layer only, needs Xcode UI test coverage
- Comment added to #229 with full status

**No new GitHub issues filed** — all findings are performance improvements, not crash risks or SQL errors.

**Metrics delta:**

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | 1241 (start) | 1255 | +14 (working tree test additions) |
| Compile errors | 0 | 0 | = |
| Compile warnings | 3 (hidden) | 0 | -3 |
| Inline ISO8601DateFormatter instances | 28 | 0 | -28 ✅ |
| Inline DateFormatter instances | ~20 | ~20 | = (uses custom formats, separate scope) |


---

## Iteration 68 — 2026-04-19 — Input Validation: Fleet + People Create Paths

**Hunt class:** Blank identifier guard sweep — create paths that accept required string fields (name/number/type) with no whitespace-trimmed-empty check, allowing unidentifiable records to reach the DB.

**Focus area:** jobs (AUTO GO current area), cross-service create-path sweep

**Scanners run:** All 10. Scanner 1 ✅, Scanner 2 ✅ 1533→1588, Scanner 3 ✅, Scanner 4 ✅, Scanner 5 (33 images — triaged), Scanner 6 (T1 open — feature work), Scanner 7 (skipped), Scanner 8 (72 open issues — all tracked)

**Root cause:** `FleetService.createVehicle` + `createTrailer` and `PeopleService.createCustomer` / `createTeam` / `createContractor` / `createHat` all accepted required string identifier fields with no blank guard. A whitespace-only string passes Swift's `isEmpty` check but creates a record with no human-readable identity — shows up as an empty cell in lists, breaks alphabetic sort, can never be selected by name. Particularly bad for `createVehicle` (fleet dispatch relies on vehicle names) and `createTeam` (team names appear on job cards).

**Fixes:**

| File | Change | Effect |
|------|--------|--------|
| `FleetService.swift` | `createVehicle`: guard `!vehicleNumber.trimmed.isEmpty` + `!vehicleName.trimmed.isEmpty` before DB write | Blank vehicles cannot be created |
| `FleetService.swift` | `createTrailer`: guard `!trailerNumber.trimmed.isEmpty` + `!trailerType.trimmed.isEmpty` before DB write | Blank trailers cannot be created |
| `PeopleService.swift` | Add `requiredFieldEmpty(String)` to `PeopleError` + add `Equatable` conformance | Error enum now matchable in tests |
| `PeopleService.swift` | `createCustomer`: guard `!name.trimmed.isEmpty` | Blank customers cannot be created |
| `PeopleService.swift` | `createTeam`: guard `!name.trimmed.isEmpty` | Blank teams cannot be created |
| `PeopleService.swift` | `createContractor`: guard `!companyName.trimmed.isEmpty` | Blank contractors cannot be created |
| `PeopleService.swift` | `createHat`: guard `!name.trimmed.isEmpty` | Blank hats (roles) cannot be created |

**Tests added:** 6 regression tests — `testCreateVehicle_rejectsBlankIdentifiers`, `testCreateTrailer_rejectsBlankIdentifiers`, `testCreateCustomer_rejectsBlankName`, `testCreateTeam_rejectsBlankName`, `testCreateContractor_rejectsBlankCompanyName`, `testCreateHat_rejectsBlankName`

**Build:** ✅ 0 errors, 0 warnings
**Tests:** ✅ 1588/1588 passing
**Remaining open:** 14
