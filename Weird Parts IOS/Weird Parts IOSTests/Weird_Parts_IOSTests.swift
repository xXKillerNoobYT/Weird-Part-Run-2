//
//  Weird_Parts_IOSTests.swift
//  Weird Parts IOSTests
//
//  Created by Isaac Aznoe on 3/15/26.
//

import Foundation
import Testing
import WiredPartCore
@testable import Weird_Parts


struct Weird_Parts_IOSTests {

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
