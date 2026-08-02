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
import XCTest
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

private enum ManualBackupLedgerReloadTestError: Error {
    case unavailable
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
    @Test func shopServerAddressNormalizationTrimsValidValuesAndRejectsBlankValues() async throws {
        #expect(IOSSyncManager.normalizedShopServerAddress(nil) == nil)
        #expect(IOSSyncManager.normalizedShopServerAddress("") == nil)
        #expect(IOSSyncManager.normalizedShopServerAddress(" \n\t ") == nil)
        #expect(IOSSyncManager.normalizedShopServerAddress("  http://127.0.0.1:8080\n") == "http://127.0.0.1:8080")
        #expect(IOSSyncManager.normalizedShopServerAddress("  192.168.1.10:8080  ") == "192.168.1.10:8080")
    }

    @MainActor
    @Test func whitespaceOnlyShopServerAddressDoesNotEnableSync() async throws {
        let previousBluetooth = UserDefaults.standard.bool(forKey: "bluetooth_sync_enabled")
        UserDefaults.standard.set(false, forKey: "bluetooth_sync_enabled")
        defer { UserDefaults.standard.set(previousBluetooth, forKey: "bluetooth_sync_enabled") }

        let db = try AppDatabase.openInMemoryDatabase()
        let settings = SettingsService(db: db)
        try settings.upsertSetting(key: "shop_server_address", value: " \n\t ", category: "sync")
        let manager = IOSSyncManager()
        manager.configure(db: db, settingsService: settings)

        #expect(!manager.isSyncAvailable)

        await manager.syncNow()

        #expect(manager.syncStatus == .idle)
        #expect(manager.errorMessage == "Sync not configured. Set up in Settings → Sync.")
    }

    @MainActor
    @Test func trimmedShopServerAddressStillEnablesSync() async throws {
        let previousBluetooth = UserDefaults.standard.bool(forKey: "bluetooth_sync_enabled")
        UserDefaults.standard.set(false, forKey: "bluetooth_sync_enabled")
        defer { UserDefaults.standard.set(previousBluetooth, forKey: "bluetooth_sync_enabled") }

        let db = try AppDatabase.openInMemoryDatabase()
        let settings = SettingsService(db: db)
        try settings.upsertSetting(key: "shop_server_address", value: "  http://127.0.0.1:9\n", category: "sync")
        let manager = IOSSyncManager()
        manager.configure(db: db, settingsService: settings)

        #expect(manager.isSyncAvailable)
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
        // Migration 112's backfill + the trigger-logged setting writes above all
        // land in _change_log; clear it so syncStatusDescription reads "Ready"
        // instead of "N changes waiting to sync".
        try await db.writer.write { try $0.execute(sql: "DELETE FROM _change_log") }
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

        manager.startPeerDiscovery()
        #expect(manager.errorMessage == "Peer discovery unavailable: Company ID is not configured. Open Settings and verify the company profile before starting peer discovery.")

        manager.startOnboardingPeerDiscovery()

        #expect(manager.isScanning)
        #expect(manager.errorMessage == nil)
        #expect(manager.syncStatus == .idle)
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

    @Test func bootstrapFallbackUsesOnlyApprovedKeychainStatuses() {
        #expect(AppCore.shouldUseLocalBootstrapKeyFallback(for: errSecMissingEntitlement))
        #expect(AppCore.shouldUseLocalBootstrapKeyFallback(for: errSecNotAvailable))
        #expect(!AppCore.shouldUseLocalBootstrapKeyFallback(for: errSecInteractionNotAllowed))
        #expect(!AppCore.shouldUseLocalBootstrapKeyFallback(for: errSecAuthFailed))
    }

    @Test func bootstrapFallbackPersistsForApprovedReadFailureAndCleansUp() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BootstrapFallback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let unavailableKeychain = AppCore.BootstrapKeychainAccess(
            read: { (errSecMissingEntitlement, nil) },
            add: { _ in
                Issue.record("fallback must be used before a Keychain write")
                return errSecParam
            },
            delete: { errSecSuccess }
        )

        let first = try AppCore.deviceBootstrapKeyHex(
            processArguments: [],
            keychain: unavailableKeychain,
            fallbackDirectory: directory
        )
        let second = try AppCore.deviceBootstrapKeyHex(
            processArguments: [],
            keychain: unavailableKeychain,
            fallbackDirectory: directory
        )
        let fallbackURL = try AppCore.localFallbackBootstrapKeyURL(in: directory)

        #expect(first.count == 64)
        #expect(first == second)
        #expect(FileManager.default.fileExists(atPath: fallbackURL.path))
        #expect(try fallbackURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        try AppCore.deleteLocalFallbackBootstrapKey(in: directory)
        #expect(!FileManager.default.fileExists(atPath: fallbackURL.path))
    }

    @Test func bootstrapFallbackExistingKeyRepairsBackupExclusion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BootstrapFallback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fallbackURL = try AppCore.localFallbackBootstrapKeyURL(in: directory)
        let existingKey = Data(repeating: 0xa5, count: 32)
        try existingKey.write(to: fallbackURL, options: .atomic)

        var unexcludedValues = URLResourceValues()
        unexcludedValues.isExcludedFromBackup = false
        var mutableURL = fallbackURL
        try mutableURL.setResourceValues(unexcludedValues)

        let keyHex = try AppCore.localFallbackBootstrapKeyHex(in: directory)

        #expect(keyHex == String(repeating: "a5", count: 32))
        #expect(
            try fallbackURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
        )
    }

    @Test func bootstrapFallbackUsesNotAvailableButRejectsLockedKeychain() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BootstrapFallback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let unavailableKeychain = AppCore.BootstrapKeychainAccess(
            read: { (errSecNotAvailable, nil) },
            add: { _ in
                Issue.record("fallback must be used before a Keychain write")
                return errSecParam
            },
            delete: { errSecSuccess }
        )
        let lockedKeychain = AppCore.BootstrapKeychainAccess(
            read: { (errSecInteractionNotAllowed, nil) },
            add: { _ in
                Issue.record("locked keychain must not attempt a write")
                return errSecParam
            },
            delete: { errSecSuccess }
        )

        _ = try AppCore.deviceBootstrapKeyHex(
            processArguments: [],
            keychain: unavailableKeychain,
            fallbackDirectory: directory
        )
        do {
            _ = try AppCore.deviceBootstrapKeyHex(
                processArguments: [],
                keychain: lockedKeychain,
                fallbackDirectory: directory
            )
            Issue.record("locked keychain unexpectedly used fallback")
        } catch let CipherKeyError.keychainAccessFailed(status) {
            #expect(status == errSecInteractionNotAllowed)
        }
        let fallbackURL = try AppCore.localFallbackBootstrapKeyURL(in: directory)
        #expect(FileManager.default.fileExists(atPath: fallbackURL.path))
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

    @Test func receiveShipmentBarcodeCountStartsFromZeroForFreshExpectedQuantity() throws {
        let base = receivingBarcodeScanBaseQuantity(
            displayedQty: 10,
            persistedReceivedQty: 0,
            hasScannerCount: false,
            hasManualQuantityEdit: false
        )

        #expect(base + 1 == 1)
    }

    @Test func receiveShipmentBarcodeCountContinuesAfterScannerOrManualQuantity() throws {
        #expect(receivingBarcodeScanBaseQuantity(
            displayedQty: 1,
            persistedReceivedQty: 0,
            hasScannerCount: true,
            hasManualQuantityEdit: false
        ) + 1 == 2)

        #expect(receivingBarcodeScanBaseQuantity(
            displayedQty: 10,
            persistedReceivedQty: 0,
            hasScannerCount: false,
            hasManualQuantityEdit: true
        ) + 1 == 11)

        #expect(receivingBarcodeScanBaseQuantity(
            displayedQty: 4,
            persistedReceivedQty: 4,
            hasScannerCount: false,
            hasManualQuantityEdit: false
        ) + 1 == 5)
    }

    @Test func receiveShipmentDifferentPriceValidationBlocksBlankOrZeroActualPrices() throws {
        let items = [
            ReceiveShipmentPriceValidationItem(id: 10, partName: "Breaker"),
            ReceiveShipmentPriceValidationItem(id: 11, partName: "Panel"),
            ReceiveShipmentPriceValidationItem(id: 12, partName: "Fuse"),
            ReceiveShipmentPriceValidationItem(id: 13, partName: "Disconnect")
        ]

        let message = receiveShipmentDifferentPriceValidationMessage(
            for: items,
            priceVerifications: [
                10: .different(newPrice: 0),
                11: .different(newPrice: -1),
                12: .different(newPrice: .nan),
                13: .different(newPrice: .infinity)
            ]
        )

        #expect(message == "Enter a valid actual price greater than $0.00 for: Breaker, Panel, Fuse, Disconnect.")
    }

    @Test func receiveShipmentDifferentPriceValidationAllowsPositiveActualPrices() throws {
        let message = receiveShipmentDifferentPriceValidationMessage(
            for: [ReceiveShipmentPriceValidationItem(id: 10, partName: "Breaker")],
            priceVerifications: [10: .different(newPrice: 12.50)]
        )

        #expect(message == nil)
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

    @Test func manualBackupPrunesOldestBackupsAndSidecars() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSBackupRetentionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        for day in 1...9 {
            let backupURL = tempRoot.appendingPathComponent(String(format: "wiredpart-backup-2026-06-%02d-120000.sqlite", day))
            try Data("backup \(day)".utf8).write(to: backupURL)
            try Data("wal \(day)".utf8).write(to: URL(fileURLWithPath: backupURL.path + "-wal"))
            try Data("shm \(day)".utf8).write(to: URL(fileURLWithPath: backupURL.path + "-shm"))
        }
        let unrelatedSQLite = tempRoot.appendingPathComponent("operator-notes.sqlite")
        try Data("not a wiredpart manual backup".utf8).write(to: unrelatedSQLite)

        try IOSBackupFileCopier.pruneBackups(in: tempRoot)

        let retained = try IOSBackupFileCopier.manualBackupSnapshotFiles(in: tempRoot)
        #expect(retained.map(\.lastPathComponent) == (3...9).reversed().map { String(format: "wiredpart-backup-2026-06-%02d-120000.sqlite", $0) })
        #expect(FileManager.default.fileExists(atPath: unrelatedSQLite.path), "Retention should only manage wiredpart manual backup snapshots")
        for day in 1...2 {
            let removedBackupURL = tempRoot.appendingPathComponent(String(format: "wiredpart-backup-2026-06-%02d-120000.sqlite", day))
            #expect(!FileManager.default.fileExists(atPath: removedBackupURL.path))
            #expect(!FileManager.default.fileExists(atPath: removedBackupURL.path + "-wal"))
            #expect(!FileManager.default.fileExists(atPath: removedBackupURL.path + "-shm"))
        }
    }

    @Test func manualBackupRetentionRejectsInvalidLimits() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSBackupRetentionLimitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        #expect(throws: IOSBackupFileCopier.InvalidRetentionLimit.self) {
            try IOSBackupFileCopier.pruneBackups(in: tempRoot, retaining: -1)
        }
    }

    @Test func manualBackupSnapshotRemovalDeletesSidecars() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSBackupSnapshotRemovalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let backupURL = tempRoot.appendingPathComponent("wiredpart-backup-2026-06-10-120000.sqlite")
        try Data("backup".utf8).write(to: backupURL)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: backupURL.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: backupURL.path + "-shm"))

        try IOSBackupFileCopier.removeSQLiteSnapshot(at: backupURL)

        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: backupURL.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: backupURL.path + "-shm"))
    }

    @Test func manualBackupReloadFailureWithholdsCompletionAccessibilityValueAndSurfacesError() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSManualBackupReloadFailureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceURL = tempRoot.appendingPathComponent("wiredpart-live.sqlite")
        let destinationURL = tempRoot.appendingPathComponent("wiredpart-backup-2026-07-24-120000.sqlite")
        try Data("database".utf8).write(to: sourceURL)
        var reloadAttemptedAfterSnapshot = false

        let outcome = IOSManualBackupOperation.createSnapshot(
            from: sourceURL,
            to: destinationURL,
            in: tempRoot
        ) {
            reloadAttemptedAfterSnapshot = FileManager.default.fileExists(atPath: destinationURL.path)
            throw ManualBackupLedgerReloadTestError.unavailable
        }

        #expect(reloadAttemptedAfterSnapshot, "Ledger reload should run only after the snapshot and retention work complete")
        #expect(outcome.completionAccessibilityValue == nil, "A failed ledger reload must withhold the Backup created accessibility value")
        #expect(outcome.failure is ManualBackupLedgerReloadTestError, "The ledger reload failure must remain available for the visible backup error state")
    }

    @Test func manualBackupCheckpointIncludesWALChanges() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSBackupCheckpointTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceURL = tempRoot.appendingPathComponent("wiredpart-live.sqlite")
        let destinationURL = tempRoot.appendingPathComponent("wiredpart-backup.sqlite")
        let source = try DatabasePool(path: sourceURL.path)
        try source.write { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 0")
            try db.execute(sql: "CREATE TABLE backup_probe(id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO backup_probe(value) VALUES (?)", arguments: ["committed-in-wal"])
        }

        #expect(FileManager.default.fileExists(atPath: sourceURL.path + "-wal"), "Test fixture should keep committed data in a WAL sidecar")
        try IOSBackupFileCopier.checkpointAndCopySQLiteSnapshot(from: source, sourceURL: sourceURL, to: destinationURL)
        #expect(!FileManager.default.fileExists(atPath: destinationURL.path + "-wal"), "Checkpointed snapshots should not depend on a copied WAL sidecar")

        let restored = try DatabaseQueue(path: destinationURL.path)
        let restoredValue = try restored.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM backup_probe WHERE id = 1")
        }
        #expect(restoredValue == "committed-in-wal")
    }

    @Test func fullDatabaseExportCheckpointsAndIncludesWALChanges() throws {
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

        try IOSDatabaseExportSnapshotter.exportSQLiteSnapshot(from: source, sourceURL: sourceURL, to: destinationURL)

        let exported = try DatabaseQueue(path: destinationURL.path)
        let exportedValue = try exported.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM export_probe WHERE id = 1")
        }
        #expect(exportedValue == "committed-in-wal")
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

    @MainActor
    @Test func warehouseMovementDatePartitionKeepsMalformedRowsOutOfActiveQueue() throws {
        let cutoff = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 8)))
        let recent = Self.warehouseMovement(id: 1, reason: "Recent", createdAt: "2026-06-10 08:30:00")
        let old = Self.warehouseMovement(id: 2, reason: "Old", createdAt: "2026-06-01 08:30:00")
        let malformed = Self.warehouseMovement(id: 3, reason: "Malformed", createdAt: "not-a-date")
        let missing = Self.warehouseMovement(id: 4, reason: "Missing", createdAt: nil)

        let movements = [recent, old, malformed, missing]
        let active = WarehouseMovementDatePartitioning.activeMovements(movements, cutoff: cutoff)
        let history = WarehouseMovementDatePartitioning.completedHistoryMovements(movements, cutoff: cutoff)

        #expect(active.map(\.id) == [recent.id])
        #expect(history.map(\.id) == [old.id, malformed.id, missing.id])
        #expect(WarehouseMovementDatePartitioning.displayDate(malformed.createdAt) == "Unknown date")
        #expect(WarehouseMovementDatePartitioning.displayDate(missing.createdAt) == "Unknown date")
    }

    @Test func pricingBulkEditRejectsNegativeOrNonFinitePercentInputs() {
        #expect(PricingBulkEditSheet.isValidNonNegativePercent("0"))
        #expect(PricingBulkEditSheet.isValidNonNegativePercent(" 12.5 "))
        #expect(!PricingBulkEditSheet.isValidNonNegativePercent("-0.01"))
        #expect(!PricingBulkEditSheet.isValidNonNegativePercent("nan"))
        #expect(!PricingBulkEditSheet.isValidNonNegativePercent("inf"))
        #expect(!PricingBulkEditSheet.isValidNonNegativePercent("not a number"))
    }

    @Test func manualPricingMarginHistoryLogsMarginValues() throws {
        let fields = try PricingEditSheet.priceChangeLogFields(
            pricingMode: "margin",
            useFixedPrice: false,
            fixedSellPrice: 0,
            markupText: "80",
            marginText: "25",
            currentMarkup: 80,
            currentMargin: 10,
            currentSellPrice: 110
        )

        #expect(fields.changeType == "margin_change")
        #expect(fields.oldValue == 10)
        #expect(fields.newValue == 25)
        #expect(PricingEditSheet.formatPriceHistoryValues(changeType: fields.changeType, oldValue: fields.oldValue, newValue: fields.newValue) == "10.0% → 25.0%")
    }

    @Test func manualPricingRejectsImpossibleMarginPercent() {
        #expect(throws: ManualPricingInputValidator.ValidationError.percentTooHigh(fieldName: "Margin", maxExclusive: 100)) {
            try ManualPricingInputValidator.parseMarginPercent("100", fieldName: "Margin")
        }
    }

    static func warehouseMovement(id: Int64, reason: String, createdAt: String?) -> WarehouseService.MovementRow {
        WarehouseService.MovementRow(
            id: id,
            partId: 10,
            partName: "QA Part",
            qty: 1,
            fromLocationType: nil,
            fromLocationId: nil,
            toLocationType: "warehouse",
            toLocationId: 1,
            movementType: "received",
            reason: reason,
            notes: nil,
            performedBy: 1,
            performedByName: "Tester",
            createdAt: createdAt
        )
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

final class ReceiveShipmentPriceVerificationXCTests: XCTestCase {
    func testDifferentPriceValidationBlocksBlankZeroNegativeAndNonFiniteActualPrices() throws {
        let items = [
            ReceiveShipmentPriceValidationItem(id: 10, partName: "Blank"),
            ReceiveShipmentPriceValidationItem(id: 11, partName: "Negative"),
            ReceiveShipmentPriceValidationItem(id: 12, partName: "NaN"),
            ReceiveShipmentPriceValidationItem(id: 13, partName: "Infinity"),
            ReceiveShipmentPriceValidationItem(id: 14, partName: "Panel")
        ]

        let message = receiveShipmentDifferentPriceValidationMessage(
            for: items,
            priceVerifications: [
                10: .different(newPrice: 0),
                11: .different(newPrice: -1),
                12: .different(newPrice: .nan),
                13: .different(newPrice: .infinity),
                14: .matches
            ]
        )

        XCTAssertEqual(message, "Enter a valid actual price greater than $0.00 for: Blank, Negative, NaN, Infinity.")
    }

    func testDifferentPriceValidationAllowsPositiveActualPrices() throws {
        let message = receiveShipmentDifferentPriceValidationMessage(
            for: [ReceiveShipmentPriceValidationItem(id: 10, partName: "Breaker")],
            priceVerifications: [10: .different(newPrice: 12.50)]
        )

        XCTAssertNil(message)
    }
}
