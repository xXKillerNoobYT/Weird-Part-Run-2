//
//  Weird_Parts_IOSTests.swift
//  Weird Parts IOSTests
//
//  Created by Isaac Aznoe on 3/15/26.
//

import Foundation
import GRDB
import Security
import Testing
import WiredPartCore
import os.log
@testable import Weird_Parts

private enum BootstrapAuditTestError: Error {
    case start
    case complete
    case operation
}

private enum MigrationRollbackRetryTestError: Error {
    case restore
    case migrate
    case open
}

private final class MockBootstrapTaskAuditor: AppCoreBackgroundTaskAuditing, @unchecked Sendable {
    var startedNames: [String] = []
    var completedIds: [Int64] = []
    var completedSummaries: [String?] = []
    var failedIds: [Int64] = []
    var startError: Error?
    var completeError: Error?

    func startTask(name: String, type: String, deviceId: String?) throws -> Int64 {
        if let startError {
            throw startError
        }
        startedNames.append(name)
        return 42
    }

    func completeTask(id: Int64, summary: String?, itemsProcessed: Int) throws {
        if let completeError {
            throw completeError
        }
        completedIds.append(id)
        completedSummaries.append(summary)
    }

    func failTask(id: Int64, error: String) throws {
        failedIds.append(id)
    }
}

private final class OperationProbe: @unchecked Sendable {
    var ran = false
}

private enum QuestionnaireBreakTestError: Error {
    case autoFillFailed
}

private enum PeerDiscoveryCompanyIdTestError: Error {
    case lookupFailed
}

private enum DispatchSheetLoadTestError: Error {
    case jobLoadFailed
    case employeeLoadFailed
}

private enum CreateNotebookJobPickerTestError: Error {
    case loadFailed
}

private enum ShortTermPipelineCallbackActionTestError: Error {
    case operationFailed
}

struct Weird_Parts_IOSTests {

    private func makeJobListItem(id: Int64, name: String, status: String) -> JobsService.JobListItem {
        JobsService.JobListItem(
            id: id,
            jobNumber: "JOB-\(id)",
            jobName: name,
            customerName: nil,
            status: status,
            priority: "normal",
            teamCount: 0,
            startDate: nil,
            dueDate: nil
        )
    }

    @MainActor
    @Test func createNotebookJobPickerIncludesInProgressJobsWithoutDuplicates() throws {
        let activeJob = makeJobListItem(id: 1, name: "Active Job", status: "active")
        let inProgressJob = makeJobListItem(id: 2, name: "Clocked Job", status: "in_progress")
        let duplicateActiveJob = makeJobListItem(id: 1, name: "Active Job Duplicate", status: "active")

        let jobs = try CreateNotebookJobPickerLoader.loadSelectableJobs { status, _ in
            switch status {
            case "active":
                return [activeJob, duplicateActiveJob]
            case "in_progress":
                return [inProgressJob, duplicateActiveJob]
            default:
                return []
            }
        }

        #expect(jobs.map(\.id) == [1, 2])
        #expect(jobs.map(\.status) == ["active", "in_progress"])
    }

    @MainActor
    @Test func createNotebookJobPickerPropagatesLoadFailures() throws {
        #expect(throws: CreateNotebookJobPickerTestError.self) {
            _ = try CreateNotebookJobPickerLoader.loadSelectableJobs { _, _ in
                throw CreateNotebookJobPickerTestError.loadFailed
            }
        }
    }

    struct LANPeerDiscoveryStartupError: Error, LocalizedError {
        var errorDescription: String? { "port unavailable" }
    }

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @MainActor
    @Test func qaResolvedStatusBucketIncludesServiceResolvedStatus() async throws {
        #expect(QAThreadStatusBuckets.isResolved("resolved"))
        #expect(QAThreadStatusBuckets.isResolved("answered"))
        #expect(QAThreadStatusBuckets.isResolved("closed"))
        #expect(!QAThreadStatusBuckets.isResolved("open"))
        #expect(!QAThreadStatusBuckets.isResolved("escalated"))
    }

    @Test func auditedBootstrapTaskStillRunsWhenAuditStartFails() throws {
        let auditor = MockBootstrapTaskAuditor()
        auditor.startError = BootstrapAuditTestError.start
        let operation = OperationProbe()

        AppCore.runAuditedBootstrapTask(
            name: "Test Bootstrap Task",
            type: "test",
            backgroundTaskService: auditor,
            logger: Logger(subsystem: "com.wiredpart.tests", category: "AppCore")
        ) {
            operation.ran = true
            return "Test complete"
        }

        #expect(operation.ran)
        #expect(auditor.completedIds.isEmpty)
        #expect(auditor.failedIds.isEmpty)
    }

    @Test func auditedBootstrapTaskDoesNotThrowWhenAuditCompletionFails() throws {
        let auditor = MockBootstrapTaskAuditor()
        auditor.completeError = BootstrapAuditTestError.complete
        let operation = OperationProbe()

        AppCore.runAuditedBootstrapTask(
            name: "Test Bootstrap Task",
            type: "test",
            backgroundTaskService: auditor,
            logger: Logger(subsystem: "com.wiredpart.tests", category: "AppCore")
        ) {
            operation.ran = true
            return "Test complete"
        }

        #expect(operation.ran)
        #expect(auditor.startedNames == ["Test Bootstrap Task"])
        #expect(auditor.failedIds.isEmpty)
    }

    @Test func auditedBootstrapTaskCompletesAuditRecordOnSuccess() throws {
        let auditor = MockBootstrapTaskAuditor()

        AppCore.runAuditedBootstrapTask(
            name: "Test Bootstrap Task",
            type: "test",
            backgroundTaskService: auditor,
            logger: Logger(subsystem: "com.wiredpart.tests", category: "AppCore")
        ) {
            "Test complete"
        }

        #expect(auditor.startedNames == ["Test Bootstrap Task"])
        #expect(auditor.completedIds == [42])
        #expect(auditor.completedSummaries == ["Test complete"])
        #expect(auditor.failedIds.isEmpty)
    }

    @Test func auditedBootstrapTaskRecordsOperationFailureWhenPossible() throws {
        let auditor = MockBootstrapTaskAuditor()

        AppCore.runAuditedBootstrapTask(
            name: "Test Bootstrap Task",
            type: "test",
            backgroundTaskService: auditor,
            logger: Logger(subsystem: "com.wiredpart.tests", category: "AppCore")
        ) {
            throw BootstrapAuditTestError.operation
        }

        #expect(auditor.completedIds.isEmpty)
        #expect(auditor.failedIds == [42])
    }

    @MainActor
    @Test func currentWalkthroughCompletionDoesNotBypassCompanySetupOnRelaunch() throws {
        let defaults = try temporaryDefaults()

        OnboardingCompletionDefaults.markCompleted(
            skippedModules: ["dashboard", "settings"],
            defaults: defaults
        )
        WiredPartIOSApp.migrateLegacyWelcomeFlags(defaults: defaults)

        #expect(defaults.bool(forKey: "hasCompletedOnboarding"))
        #expect(defaults.bool(forKey: "hasSeenModuleTour"))
        #expect(!defaults.bool(forKey: "hasSeenWelcome"))
        #expect(!defaults.bool(forKey: "hasCompletedCompanySetup"))
        #expect(defaults.data(forKey: "onboarding_skipped_modules") != nil)
    }

    @MainActor
    @Test func legacyWelcomeMigrationStillCompletesCompanySetupOnce() throws {
        let defaults = try temporaryDefaults()
        defaults.set(true, forKey: "hasSeenWelcome")

        WiredPartIOSApp.migrateLegacyWelcomeFlags(defaults: defaults)

        #expect(defaults.bool(forKey: "hasCompletedOnboarding"))
        #expect(defaults.bool(forKey: "hasCompletedCompanySetup"))
        #expect(!defaults.bool(forKey: "hasSeenWelcome"))
    }

    private func temporaryDefaults() throws -> UserDefaults {
        let suiteName = "WeirdPartsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestDefaultsError.unavailable
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private enum TestDefaultsError: Error {
        case unavailable
    }

    @MainActor
    @Test func shopServerAddressSettingsAreDeviceScoped() async throws {
        #expect(IOSSyncManager.settingSyncScope(for: "sync_server_address") == .device)
        #expect(IOSSyncManager.settingSyncScope(for: "shop_server_address") == .device)
    }

    @MainActor
    @Test func partsFlowDraftsAreScopedPerAuthenticatedUser() throws {
        let userA: Int64 = 101
        let userB: Int64 = 202
        PartsFlowDraftStore.clear(userId: userA)
        PartsFlowDraftStore.clear(userId: userB)
        UserDefaults.standard.removeObject(forKey: PartsFlowDraftStore.countsKey)
        UserDefaults.standard.removeObject(forKey: PartsFlowDraftStore.locationsKey)
        defer {
            PartsFlowDraftStore.clear(userId: userA)
            PartsFlowDraftStore.clear(userId: userB)
        }

        UserDefaults.standard.set(Data("legacy".utf8), forKey: PartsFlowDraftStore.countsKey)
        PartsFlowDraftStore.save(counts: [1: "7"], locations: [1: "Aisle 4"], userId: userA)

        #expect(PartsFlowDraftStore.scopedKey(PartsFlowDraftStore.countsKey, userId: userA) != PartsFlowDraftStore.countsKey)
        #expect(PartsFlowDraftStore.loadCounts(userId: userA) == [1: "7"])
        #expect(PartsFlowDraftStore.loadLocations(userId: userA) == [1: "Aisle 4"])
        #expect(PartsFlowDraftStore.loadCounts(userId: userB).isEmpty)
        #expect(PartsFlowDraftStore.loadLocations(userId: userB).isEmpty)
    }

    @MainActor
    @Test func movementWizardDraftsAreScopedPerAuthenticatedUser() throws {
        let userA: Int64 = 303
        let userB: Int64 = 404
        MovementWizardDraftStore.clear(userId: userA)
        MovementWizardDraftStore.clear(userId: userB)
        UserDefaults.standard.removeObject(forKey: MovementWizardDraftStore.baseKey)
        defer {
            MovementWizardDraftStore.clear(userId: userA)
            MovementWizardDraftStore.clear(userId: userB)
        }

        let draftData = Data("user-a-draft".utf8)
        UserDefaults.standard.set(Data("legacy".utf8), forKey: MovementWizardDraftStore.baseKey)
        MovementWizardDraftStore.save(draftData, userId: userA)

        #expect(MovementWizardDraftStore.key(userId: userA) != MovementWizardDraftStore.baseKey)
        #expect(MovementWizardDraftStore.loadData(userId: userA) == draftData)
        #expect(MovementWizardDraftStore.loadData(userId: userB) == nil)
    }

    @MainActor
    @Test func autoSyncTimerTickStopsWhenStoredOptOutBecomesFalse() async throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let settings = SettingsService(db: db)
        try settings.upsertSetting(key: "shop_server_address", value: "http://127.0.0.1:9", category: "sync")
        try settings.upsertSetting(key: "auto_sync", value: "false", category: "sync")
        let manager = IOSSyncManager()
        manager.configure(db: db, settingsService: settings)
        manager.startAutoSync(intervalSeconds: 60)

        await manager.handleAutoSyncTimerTick()

        #expect(manager.syncStatus == .idle)
        #expect(manager.syncStatusDescription == "Ready")
    }

    @MainActor
    @Test func autoSyncTimerTickRunsWhenStoredOptInStaysTrue() async throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let settings = SettingsService(db: db)
        try settings.upsertSetting(key: "shop_server_address", value: "http://127.0.0.1:9", category: "sync")
        try settings.upsertSetting(key: "auto_sync", value: "true", category: "sync")
        let manager = IOSSyncManager()
        manager.configure(db: db, settingsService: settings)

        await manager.handleAutoSyncTimerTick()

        #expect(manager.syncStatus != .idle)
    }

    @MainActor
    @Test func lanPeerDiscoveryStartupFailureSurfacesErrorAndStopsLanOnlyScan() async throws {
        let manager = IOSSyncManager()
        manager.isScanning = true

        manager.handleLanPeerDiscoveryStartupFailure(
            LANPeerDiscoveryStartupError(),
            hasActiveMultipeerDiscovery: false
        )

        #expect(manager.syncStatus == .error)
        #expect(manager.errorMessage == "LAN peer discovery failed: port unavailable")
        #expect(!manager.isScanning)
    }

    @MainActor
    @Test func lanPeerDiscoveryStartupFailureKeepsBluetoothScanTruthful() async throws {
        let manager = IOSSyncManager()
        manager.isScanning = true

        manager.handleLanPeerDiscoveryStartupFailure(
            LANPeerDiscoveryStartupError(),
            hasActiveMultipeerDiscovery: true
        )

        #expect(manager.syncStatus == .error)
        #expect(manager.errorMessage == "LAN peer discovery failed: port unavailable")
        #expect(manager.isScanning)
    }

    @MainActor
    @Test func peerDiscoveryCompanyIdResolutionUsesStoredNonEmptyValue() throws {
        let companyId = try IOSSyncManager.peerDiscoveryCompanyId {
            ["company_id": "  company-123  "]
        }

        #expect(companyId == "company-123")
    }

    @MainActor
    @Test func peerDiscoveryCompanyIdResolutionFailsClosedWhenMissing() throws {
        #expect(throws: IOSSyncManager.SyncError.self) {
            _ = try IOSSyncManager.peerDiscoveryCompanyId { [:] }
        }
        #expect(throws: IOSSyncManager.SyncError.self) {
            _ = try IOSSyncManager.peerDiscoveryCompanyId { ["company_id": "   "] }
        }
    }

    @MainActor
    @Test func peerDiscoveryCompanyIdResolutionPropagatesSettingsLookupFailure() throws {
        #expect(throws: PeerDiscoveryCompanyIdTestError.self) {
            _ = try IOSSyncManager.peerDiscoveryCompanyId {
                throw PeerDiscoveryCompanyIdTestError.lookupFailed
            }
        }
    }

    @MainActor
    @Test func peerDiscoveryCompanyIdFailureSurfacesErrorAndStopsScanning() throws {
        let manager = IOSSyncManager()
        manager.isScanning = true

        manager.handlePeerDiscoveryCompanyIdFailure(IOSSyncManager.SyncError.noCompanyIdConfigured)

        #expect(manager.syncStatus == .error)
        #expect(manager.errorMessage == "Peer discovery unavailable: Company ID is not configured. Open Settings and verify the company profile before starting peer discovery.")
        #expect(!manager.isScanning)
    }

    @MainActor
    @Test func onboardingPeerDiscoveryDoesNotRequireLocalCompanyId() throws {
        let previousBluetoothSetting = UserDefaults.standard.bool(forKey: "bluetooth_sync_enabled")
        defer { UserDefaults.standard.set(previousBluetoothSetting, forKey: "bluetooth_sync_enabled") }

        let manager = IOSSyncManager()
        defer { manager.stopPeerDiscovery() }
        manager.setBluetoothEnabled(true, startDiscovery: false)

        manager.startOnboardingPeerDiscovery()

        #expect(manager.isScanning)
        #expect(manager.errorMessage == nil)
        #expect(manager.syncStatus != .error)
    }

    @MainActor
    @Test func onboardingPeerDiscoveryKeepsLanAddressForPairing() throws {
        let source = try String(
            contentsOfFile: "Weird Parts IOS/Weird Parts IOS/Sync/IOSSyncManager.swift",
            encoding: .utf8
        )
        let pairingSource = try String(
            contentsOfFile: "Weird Parts IOS/Weird Parts IOS/Auth/DevicePairingView.swift",
            encoding: .utf8
        )

        #expect(source.contains("allowAnyCompanyPeerDiscovery: mode == .onboardingJoin"))
        #expect(source.contains("startMultipeer: mode == .existingCompanySync"))
        #expect(source.contains("address: peer.host.isEmpty || peer.port == 0 ? nil : \"\\(peer.host):\\(peer.port)\""))
        #expect(pairingSource.contains("guard let address = peer.address else"))
        #expect(pairingSource.contains("shop.address"))
    }

    @MainActor
    @Test func officeNavigationUsesOfficeOnlyGateAndFinancialRedactionGate() async throws {
        let leadPermissions = ["view_jobs", "manage_jobs", "view_orders"]
        let officePermissions = ["approve_orders", "show_dollar_values", "manage_jobs"]

        let officeModule = try #require(allModulesById["office"])
        #expect(!visibleModules(permissions: leadPermissions).contains(where: { $0.id == "office" }))
        #expect(visibleModules(permissions: officePermissions).contains(where: { $0.id == "office" }))

        let leadOfficeTabs = visibleTabs(for: officeModule, permissions: leadPermissions).map(\.id)
        let officeTabs = visibleTabs(for: officeModule, permissions: officePermissions).map(\.id)
        #expect(!leadOfficeTabs.contains("office-dashboard"))
        #expect(!leadOfficeTabs.contains("office-approvals"))
        #expect(officeTabs.contains("office-dashboard"))
        #expect(officeTabs.contains("office-approvals"))
        #expect(officeTabs.contains("office-spending"))
        #expect(financialValuesPermission == "show_dollar_values")
    }

    @MainActor
    @Test func warehouseAuditTabStaysWithinInitialPhoneToolbarViewport() async throws {
        let warehouseTabs = appModules.first { $0.id == "warehouse" }?.tabs ?? []
        let auditIndex = try #require(warehouseTabs.firstIndex { $0.id == "warehouse-audit" })

        #expect(auditIndex <= 2)
    }

    @Test func uiTestingLaunchUsesDeterministicDatabaseKey() throws {
        let keyHex = try AppCore.deviceBootstrapKeyHex(processArguments: ["Weird Parts", "-UITesting"])

        #expect(keyHex == "8f1df32f4be04d5fcde1e8e6ddf9187f53a4b68370d5aafc56f0d43f2e9732a1")
        #expect(keyHex.count == 64)
    }

    @Test func simulatorMissingEntitlementCanUseLocalBootstrapKeyFallback() {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        #expect(AppCore.shouldUseLocalBootstrapKeyFallback(for: errSecMissingEntitlement))
        #else
        #expect(!AppCore.shouldUseLocalBootstrapKeyFallback(for: errSecMissingEntitlement))
        #endif
        #expect(!AppCore.shouldUseLocalBootstrapKeyFallback(for: errSecAuthFailed))
    }

    @Test func debugCipherRecoveryOnlyMatchesDecryptNotADB() {
        let sqlCipherError = NSError(
            domain: "GRDB.DatabaseError",
            code: 26,
            userInfo: [NSLocalizedDescriptionKey: "SQLite error 26: file is not a database - while executing `PRAGMA journal_mode = WAL`"]
        )
        let unrelatedDatabaseError = NSError(
            domain: "GRDB.DatabaseError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "SQLite error 1: no such table: settings"]
        )

        #expect(AppCore.isRecoverableDebugCipherOpenFailure(sqlCipherError))
        #expect(!AppCore.isRecoverableDebugCipherOpenFailure(unrelatedDatabaseError))
    }

    @Test func debugCipherDatabaseResetGateIsSimulatorOnly() {
        let sqlCipherError = NSError(
            domain: "GRDB.DatabaseError",
            code: 26,
            userInfo: [NSLocalizedDescriptionKey: "SQLite error 26: file is not a database - while executing `PRAGMA journal_mode = WAL`"]
        )

        #if DEBUG && targetEnvironment(simulator)
        #expect(AppCore.shouldResetLocalDatabaseAfterCipherOpenFailure(sqlCipherError))
        #else
        #expect(!AppCore.shouldResetLocalDatabaseAfterCipherOpenFailure(sqlCipherError))
        #endif
    }

    @Test func migrationRollbackRestoresThenRetriesMigrationAndOpen() throws {
        var events: [String] = []

        let database = try AppCore.retryOpeningRestoredDatabase(
            backupPath: "/tmp/wired-part.sqlite.rollback",
            databasePath: "/tmp/wired-part.sqlite",
            keyHex: "device-key",
            restoreDatabase: { backupPath, databasePath in
                events.append("restore")
                #expect(backupPath == "/tmp/wired-part.sqlite.rollback")
                #expect(databasePath == "/tmp/wired-part.sqlite")
            },
            migratePlaintextDatabaseIfNeeded: { databasePath, keyHex in
                events.append("migrate")
                #expect(databasePath == "/tmp/wired-part.sqlite")
                #expect(keyHex == "device-key")
            },
            openEncryptedDatabase: { databasePath, keyHex in
                events.append("open")
                #expect(databasePath == "/tmp/wired-part.sqlite")
                #expect(keyHex == "device-key")
                return "opened-restored-database"
            }
        )

        #expect(events == ["restore", "migrate", "open"])
        #expect(database == "opened-restored-database")
    }

    @Test func migrationRollbackRequiresBackupBeforeRetry() {
        #expect(throws: AppCore.AppCoreError.self) {
            _ = try AppCore.retryOpeningRestoredDatabase(
                backupPath: nil,
                databasePath: "/tmp/wired-part.sqlite",
                keyHex: "device-key",
                restoreDatabase: { _, _ in throw MigrationRollbackRetryTestError.restore },
                migratePlaintextDatabaseIfNeeded: { _, _ in throw MigrationRollbackRetryTestError.migrate },
                openEncryptedDatabase: { _, _ in throw MigrationRollbackRetryTestError.open }
            ) as String
        }
    }

    @MainActor
    @Test func bulkHoldSelectionCarriesAllSelectedRowsIntoSheetSnapshot() throws {
        let first = OrdersService.JPOLineRow(
            id: 101,
            jpoId: 10,
            partId: 201,
            partName: "UITesting QA Switch",
            description: nil,
            quantity: 1,
            unitPrice: nil,
            notes: nil,
            priority: "medium",
            createdAt: nil
        )
        let second = OrdersService.JPOLineRow(
            id: 102,
            jpoId: 10,
            partId: 202,
            partName: "UITesting QA Breaker",
            description: nil,
            quantity: 2,
            unitPrice: nil,
            notes: nil,
            priority: "medium",
            createdAt: nil
        )
        let unselected = OrdersService.JPOLineRow(
            id: 103,
            jpoId: 10,
            partId: 203,
            partName: "UITesting QA Outlet",
            description: nil,
            quantity: 3,
            unitPrice: nil,
            notes: nil,
            priority: "medium",
            createdAt: nil
        )

        let selectedItems = IOSJPODetailBulkHoldSelection.selectedHoldItems(
            from: [first, second, unselected],
            selectedLineIds: [first.id, second.id]
        )

        #expect(selectedItems.map(\.id) == [first.id, second.id])
        #expect(IOSJPODetailBulkHoldSelection.sheetIdentifier(for: selectedItems) == "bulkHold-101-102")
    }

    @MainActor
    @Test func bulkHoldExcludesLinesWhoseTransferCancellationFailed() throws {
        let transferFailure = OrdersService.JPOLineRow(
            id: 201,
            jpoId: 20,
            partId: 301,
            partName: "UITesting Transfer Failure",
            description: nil,
            quantity: 1,
            unitPrice: nil,
            notes: nil,
            priority: "medium",
            createdAt: nil,
            lineStatus: "transfer",
            transferId: 9001
        )
        let transferSuccess = OrdersService.JPOLineRow(
            id: 202,
            jpoId: 20,
            partId: 302,
            partName: "UITesting Transfer Success",
            description: nil,
            quantity: 2,
            unitPrice: nil,
            notes: nil,
            priority: "medium",
            createdAt: nil,
            lineStatus: "transfer",
            transferId: 9002
        )
        let normalPendingLine = OrdersService.JPOLineRow(
            id: 203,
            jpoId: 20,
            partId: 303,
            partName: "UITesting Pending Line",
            description: nil,
            quantity: 3,
            unitPrice: nil,
            notes: nil,
            priority: "medium",
            createdAt: nil
        )

        let processableItems = IOSJPODetailBulkHoldSelection.processableHoldItems(
            from: [transferFailure, transferSuccess, normalPendingLine],
            failedTransferCancellationLineIds: [transferFailure.id]
        )

        #expect(processableItems.map(\.id) == [transferSuccess.id, normalPendingLine.id])
    }

    @MainActor
    @Test func receivingRoutingShowsActionableErrorForUnknownPartRoutes() throws {
        #expect(ReceivingRoutingValidation.missingLinkedPartError(partId: nil) == "This receiving item is no longer linked to an active part. Mark it as a wrong part or fix the PO line before routing damaged or used inventory.")
        #expect(ReceivingRoutingValidation.missingLinkedPartError(partId: 6) == nil)
    }

    @Test func subSchedulePageExposesExplicitSoftDeleteCancellationAction() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pageURL = repoRoot
            .appendingPathComponent("Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSSubSchedulePage.swift")
        let sheetURL = repoRoot
            .appendingPathComponent("Weird Parts IOS/Weird Parts IOS/Features/Scheduling/CreateSubcontractorScheduleSheet.swift")
        let pageSource = try String(contentsOf: pageURL, encoding: .utf8)
        let sheetSource = try String(contentsOf: sheetURL, encoding: .utf8)

        #expect(pageSource.contains("cancelSubcontractorSchedule"), "Sub schedule rows need an explicit cancel action wired to the service soft-delete API")
        #expect(pageSource.contains("Cancel Schedule"), "The destructive UI should be labelled as cancellation, not hidden behind edit/status changes")
        #expect(!sheetSource.contains("\"cancelled\""), "Editing status to cancelled leaves deleted_at NULL; cancellation must use the explicit soft-delete action")
    }

    @Test func qrScannerStartFailureIsSurfacedAndStreamFinished() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scannerURL = repoRoot
            .appendingPathComponent("Weird Parts IOS/Weird Parts IOS/Scanning/IOSQRScanner.swift")
        let scannerSource = try String(contentsOf: scannerURL, encoding: .utf8)

        #expect(!scannerSource.contains("try? scanner.startScanning()"), "Startup failures from DataScannerViewController must not be swallowed")
        #expect(scannerSource.contains("catch {"), "The modal scanner start path needs explicit do/catch error handling")
        #expect(scannerSource.contains("activeContinuation?.yield(.error(errorMessage))"), "Startup failures should emit an actionable QRScanEvent error")
        #expect(scannerSource.contains("activeContinuation?.finish()"), "Startup failures should finish the scan stream instead of leaving a dead sheet")
    }

    @Test func dispatchAssignmentConflictCheckFailureShowsActionError() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dispatchURL = repoRoot
            .appendingPathComponent("Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSDispatchPage.swift")
        let source = try String(contentsOf: dispatchURL, encoding: .utf8)

        #expect(source.contains("actionError = userFriendlyError(error, context: \"check time-off conflicts\")"))
        #expect(
            source.contains("actionError = userFriendlyError(error, context: \"check time-off conflicts\")\n            return"),
            "Conflict-check failures should stop assignment creation."
        )
    }

    @Test func createDispatchSheetShowsActionableLoadFailures() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sheetURL = repoRoot
            .appendingPathComponent("Weird Parts IOS/Weird Parts IOS/Features/Scheduling/CreateDispatchSheet.swift")
        let source = try String(contentsOf: sheetURL, encoding: .utf8)

        #expect(!source.contains("try? jobService.listJobs"), "Job load failures must not be swallowed into an empty active-jobs picker state")
        #expect(!source.contains("try? peopleService.listEmployees"), "Employee load failures must not be swallowed into an empty employee picker state")
        #expect(source.contains("jobLoadError = result.jobLoadError"), "Job load failures should be tracked separately from empty job results")
        #expect(source.contains("employeeLoadError = result.employeeLoadError"), "Employee load failures should be tracked separately from empty employee results")
        #expect(source.contains("userFriendlyError(error, context: context)"), "Service failures should be formatted as user-facing error copy")
        #expect(source.contains("Text(\"No active jobs\")"), "Legitimate empty job results should still show the empty-state copy")
        #expect(source.contains("Text(\"No employees found\")"), "Legitimate empty employee results should still show the empty-state copy")
        #expect(source.contains("Label(\"Retry\", systemImage: \"arrow.clockwise\")"), "Load failures should offer an actionable retry")
        #expect(
            !source.contains(".accessibilityLabel(retryLabel)\n        }\n        .accessibilityElement(children: .combine)"),
            "Load-failure rows must not combine the retry button into static failure copy"
        )
        #expect(source.contains("Retry loading jobs"), "Job retry control needs a specific accessibility label")
        #expect(source.contains("Retry loading employees"), "Employee retry control needs a specific accessibility label")
    }

    @Test @MainActor func questionnaireBreakAutofillDoesNotSwallowSubmitErrors() throws {
        var autoFillAttempts = 0

        do {
            try IOSQuestionnairePage.QuestionnaireBreakComplianceSubmitter.submit(
                verification: .allTaken,
                hadBreakButtons: false,
                missedBreaks: []
            ) {
                autoFillAttempts += 1
                throw QuestionnaireBreakTestError.autoFillFailed
            }
            Issue.record("Expected auto-fill failure to propagate")
        } catch QuestionnaireBreakTestError.autoFillFailed {
            #expect(autoFillAttempts == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test @MainActor func questionnaireBreakAutofillSkipsWhenExistingBreakButtonsWereUsed() throws {
        var autoFillAttempts = 0

        try IOSQuestionnairePage.QuestionnaireBreakComplianceSubmitter.submit(
            verification: .allTaken,
            hadBreakButtons: true,
            missedBreaks: []
        ) {
            autoFillAttempts += 1
        }

        #expect(autoFillAttempts == 0)
    }

    @Test @MainActor func questionnaireBreakAutofillRunsForForgotBreakPath() throws {
        var autoFillAttempts = 0

        try IOSQuestionnairePage.QuestionnaireBreakComplianceSubmitter.submit(
            verification: .forgot,
            hadBreakButtons: false,
            missedBreaks: ["morning_break", "lunch", "afternoon_break"]
        ) {
            autoFillAttempts += 1
        }

        #expect(autoFillAttempts == 1)
    }

    @Test func questionnaireSubmitRunsBreakVerificationBeforeSavingResponses() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pageURL = repoRoot
            .appendingPathComponent("Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSQuestionnairePage.swift")
        let pageSource = try String(contentsOf: pageURL, encoding: .utf8)

        #expect(!pageSource.contains("try? breakSvc.autoFillBreaksForDay"), "Break auto-fill failures in submit flow must not be swallowed")
        #expect(pageSource.contains("try handleBreakVerification()"), "Submit flow should fail and show error when break auto-fill fails")
        #expect(pageSource.contains("private func handleBreakVerification() throws"), "Break verification helper should throw to propagate save failures")
        let verificationCall = try #require(pageSource.range(of: "try handleBreakVerification()"))
        let responseSaveCall = try #require(pageSource.range(of: "try service.saveClockOutResponses"))
        #expect(verificationCall.lowerBound < responseSaveCall.lowerBound, "Break compliance auto-fill should succeed before questionnaire responses are saved")
    }

    @Test func supplierChannelCreationFailureShowsLoadError() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let suppliersURL = repoRoot
            .appendingPathComponent("Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift")
        let source = try String(contentsOf: suppliersURL, encoding: .utf8)

        #expect(source.contains("loadError = userFriendlyError(error, context: \"create supplier channel\")"))
    }

    @Test func manualBackupSidecarCopyFailureIsReportedAndCleanedUp() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSBackupFileCopierTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceURL = tempRoot.appendingPathComponent("wiredpart.sqlite")
        let sourceWALURL = URL(fileURLWithPath: sourceURL.path + "-wal")
        let destinationURL = tempRoot.appendingPathComponent("wiredpart-backup.sqlite")
        let destinationWALURL = URL(fileURLWithPath: destinationURL.path + "-wal")

        try Data("main database".utf8).write(to: sourceURL)
        try Data("wal sidecar".utf8).write(to: sourceWALURL)
        try Data("pre-existing destination blocks copy".utf8).write(to: destinationWALURL)

        do {
            try IOSBackupFileCopier.copySQLiteSnapshot(from: sourceURL, to: destinationURL)
            Issue.record("Expected WAL copy failure to propagate instead of reporting backup success")
        } catch {
            #expect(!FileManager.default.fileExists(atPath: destinationURL.path), "Failed sidecar backups must remove the partial main database copy")
            #expect(FileManager.default.fileExists(atPath: destinationWALURL.path), "Existing destination files unrelated to this attempt should not be removed")
        }
    }

    @Test func manualBackupSidecarCopiesAreNotSwallowedBeforeSuccessState() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let backupsPageURL = repoRoot
            .appendingPathComponent("Weird Parts IOS/Weird Parts IOS/Features/Settings/IOSBackupsPage.swift")
        let source = try String(contentsOf: backupsPageURL, encoding: .utf8)

        #expect(!source.contains("try? FileManager.default.copyItem"), "Manual backup WAL/SHM copy failures must not be swallowed")
        #expect(!source.contains("try? FileManager.default.removeItem"), "Failed manual backups must not swallow cleanup failures")
        #expect(source.contains("try IOSBackupFileCopier.copySQLiteSnapshot"), "Manual backup creation should use the throwing SQLite snapshot copier")
        #expect(source.contains("createdURLs.reversed()"), "Partial backup cleanup should remove sidecars before the main database")
        let snapshotCall = try #require(source.range(of: "try IOSBackupFileCopier.copySQLiteSnapshot"))
        let successState = try #require(source.range(of: "backupSuccess = true"))
        #expect(snapshotCall.lowerBound < successState.lowerBound, "Success state must only be set after all database sidecars are copied")
    }

    @Test func fullDatabaseExportUsesGRDBSnapshotAndIncludesWALChanges() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSDatabaseExportSnapshotterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceURL = tempRoot.appendingPathComponent("wiredpart-live.sqlite")
        let destinationURL = tempRoot.appendingPathComponent("wiredpart-export.sqlite")
        let source = try DatabasePool(path: sourceURL.path)
        try source.write { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 0")
            try db.execute(sql: "CREATE TABLE export_probe(id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO export_probe(value) VALUES (?)", arguments: ["committed-in-wal"])
        }

        #expect(FileManager.default.fileExists(atPath: sourceURL.path + "-wal"), "Test fixture should keep committed data in a WAL sidecar")

        try IOSDatabaseExportSnapshotter.exportSQLiteSnapshot(from: source, to: destinationURL)

        let exported = try DatabaseQueue(path: destinationURL.path)
        let exportedValue = try exported.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM export_probe WHERE id = 1")
        }
        #expect(exportedValue == "committed-in-wal")
    }

    @Test func fullDatabaseExportDoesNotCopyMainDatabaseFileDirectly() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let exportPageURL = repoRoot
            .appendingPathComponent("Weird Parts IOS/Weird Parts IOS/Features/Settings/IOSDataExportPage.swift")
        let source = try String(contentsOf: exportPageURL, encoding: .utf8)

        #expect(!source.contains("copyItem(at: URL(fileURLWithPath: dbPath), to: destURL)"), "Full database export must not copy only the main SQLite file")
        #expect(source.contains("try IOSDatabaseExportSnapshotter.exportSQLiteSnapshot"), "Full database export should use the GRDB snapshot helper")
        #expect(source.contains("Task.detached(priority: .userInitiated)"), "Full database export should run the snapshot off the main actor so large exports do not freeze Settings")
        #expect(source.contains("await MainActor.run"), "Full database export should return success and error state updates to the main actor")
        let snapshotCall = try #require(source.range(of: "try IOSDatabaseExportSnapshotter.exportSQLiteSnapshot"))
        let successState = try #require(source.range(of: "exportSuccess = true", range: snapshotCall.lowerBound..<source.endIndex))
        #expect(snapshotCall.lowerBound < successState.lowerBound, "Success state must only be set after the GRDB snapshot is complete")
    }

    @MainActor
    @Test func shortTermPipelineCallbackFailurePreservesSheetAndFormatsActionError() {
        var reloadCount = 0

        let result = IOSShortTermPipelineCallbackActionHandler.perform(
            context: "complete callback",
            operation: {
                throw ShortTermPipelineCallbackActionTestError.operationFailed
            },
            reload: {
                reloadCount += 1
            },
            errorFormatter: { _, context in "Could not \(context). Try again." }
        )

        #expect(result.errorMessage == "Could not complete callback. Try again.")
        #expect(!result.shouldDismissSheet)
        #expect(reloadCount == 0)
    }

    @MainActor
    @Test func shortTermPipelineCallbackSuccessReloadsAndDismissesSheet() {
        var reloadCount = 0
        var operationCount = 0

        let result = IOSShortTermPipelineCallbackActionHandler.perform(
            context: "snooze callback",
            operation: {
                operationCount += 1
            },
            reload: {
                reloadCount += 1
            },
            errorFormatter: { _, context in "Could not \(context). Try again." }
        )

        #expect(result.errorMessage == nil)
        #expect(result.shouldDismissSheet)
        #expect(operationCount == 1)
        #expect(reloadCount == 1)
    }

    @MainActor
    @Test func dispatchSheetJobLoadFailurePreservesEmployeeResultsAndShowsActionableJobError() throws {
        let loadedEmployee = PeopleService.EmployeeListItem(
            id: 42,
            displayName: "Field Tech",
            email: "tech@example.com",
            phone: nil,
            status: "active",
            role: "employee",
            hatNames: nil
        )

        let result = DispatchSheetLoadData.load(
            jobsProvider: { throw DispatchSheetLoadTestError.jobLoadFailed },
            employeesProvider: { [loadedEmployee] },
            errorFormatter: { _, context in "Couldn't \(context). Retry." }
        )

        #expect(result.jobs.isEmpty)
        #expect(result.employees.map(\.displayName) == ["Field Tech"])
        #expect(result.jobLoadError == "Couldn't load active jobs. Retry.")
        #expect(result.employeeLoadError == nil)
        #expect(result.hasLoadFailure)
    }

    @MainActor
    @Test func dispatchSheetEmployeeLoadFailurePreservesJobResultsAndShowsActionableEmployeeError() throws {
        let loadedJob = JobsService.JobListItem(
            id: 7,
            jobNumber: "JOB-7",
            jobName: "Warehouse Upgrade",
            customerName: nil,
            status: "active",
            priority: "medium",
            teamCount: 0,
            startDate: nil,
            dueDate: nil
        )

        let result = DispatchSheetLoadData.load(
            jobsProvider: { [loadedJob] },
            employeesProvider: { throw DispatchSheetLoadTestError.employeeLoadFailed },
            errorFormatter: { _, context in "Couldn't \(context). Retry." }
        )

        #expect(result.jobs.map(\.jobName) == ["Warehouse Upgrade"])
        #expect(result.employees.isEmpty)
        #expect(result.jobLoadError == nil)
        #expect(result.employeeLoadError == "Couldn't load employees. Retry.")
        #expect(result.hasLoadFailure)
    }

    @MainActor
    @Test func dispatchSheetBothLoadFailuresExposeBothActionableMessages() throws {
        let result = DispatchSheetLoadData.load(
            jobsProvider: { throw DispatchSheetLoadTestError.jobLoadFailed },
            employeesProvider: { throw DispatchSheetLoadTestError.employeeLoadFailed },
            errorFormatter: { _, context in "Couldn't \(context). Retry." }
        )

        #expect(result.jobs.isEmpty)
        #expect(result.employees.isEmpty)
        #expect(result.jobLoadError == "Couldn't load active jobs. Retry.")
        #expect(result.employeeLoadError == "Couldn't load employees. Retry.")
        #expect(result.hasLoadFailure)
    }

    @MainActor
    @Test func dispatchSheetEmptyResultsRemainLegitimateEmptyStatesWithoutLoadFailure() throws {
        let result = DispatchSheetLoadData.load(
            jobsProvider: { [] },
            employeesProvider: { [] },
            errorFormatter: { _, context in "Couldn't \(context). Retry." }
        )

        #expect(result.jobs.isEmpty)
        #expect(result.employees.isEmpty)
        #expect(result.jobLoadError == nil)
        #expect(result.employeeLoadError == nil)
        #expect(!result.hasLoadFailure)
    }

    @Test func uiTestingFixturesSeedJPOFlowDataForQASmoke() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let auth = AuthService(db: db)

        try AppCore.seedUITestingFixtures(db: db, authService: auth)

        let parts = PartsService(db: db, auth: auth)
        let jobs = JobsService(db: db)
        let orders = OrdersService(db: db)
        let users = try auth.getActiveUsers()
        var seededUserId: Int64?
        for user in users where user.displayName == "UITest Owner" {
            seededUserId = user.id
            break
        }
        let userId = try #require(seededUserId)

        let activeJobs = try jobs.listJobs(status: "active")
        var seededJobId: Int64?
        for job in activeJobs where job.jobNumber == "UITEST-JPO-001" {
            seededJobId = job.id
            break
        }
        let jobId = try #require(seededJobId)

        let activeJPOs = try orders.listJPOs(jobId: jobId, status: "draft")
        var seededJPOId: Int64?
        for jpo in activeJPOs where jpo.status == "draft" {
            seededJPOId = jpo.id
            break
        }
        let jpoId = try #require(seededJPOId)
        let detail = try orders.getJPODetail(id: jpoId)

        #expect(userId > 0)
        #expect(try parts.listCategories().contains { $0.name == "UITesting Electrical" })
        #expect(try parts.listParts(search: "UITesting QA", limit: 10).count >= 2)
        #expect(detail.lines.count >= 2)
        #expect(detail.lines.allSatisfy { $0.partId != nil })
    }
}

struct PartsFlowDraftStoreTests {
    @MainActor
    @Test func preservesAndClearsDraftCountsAndLocations() async throws {
        let userId: Int64 = 505
        PartsFlowDraftStore.clear(userId: userId)
        defer { PartsFlowDraftStore.clear(userId: userId) }

        PartsFlowDraftStore.save(
            counts: [101: "7", 202: ""],
            locations: [101: "Shelf A", 303: "Van 2"],
            userId: userId
        )

        #expect(PartsFlowDraftStore.loadCounts(userId: userId) == [101: "7", 202: ""])
        #expect(PartsFlowDraftStore.loadLocations(userId: userId) == [101: "Shelf A", 303: "Van 2"])

        PartsFlowDraftStore.clear(userId: userId)

        #expect(PartsFlowDraftStore.loadCounts(userId: userId).isEmpty)
        #expect(PartsFlowDraftStore.loadLocations(userId: userId).isEmpty)
    }
}
