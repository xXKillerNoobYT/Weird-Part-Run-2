//
//  Weird_Parts_IOSTests.swift
//  Weird Parts IOSTests
//
//  Created by Isaac Aznoe on 3/15/26.
//

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

    @Test func uiTestingFixturesSeedJPOFlowDataForQASmoke() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let auth = AuthService(db: db)

        try AppCore.seedUITestingFixtures(db: db, authService: auth)

        let parts = PartsService(db: db, auth: auth)
        let jobs = JobsService(db: db)
        let orders = OrdersService(db: db)
        let users = try auth.getActiveUsers()
        let userId = try #require(users.first { $0.displayName == "UITest Owner" }?.id)
        let job = try #require(try jobs.listJobs(status: "active").first { $0.jobNumber == "UITEST-JPO-001" })
        let jpo = try #require(try orders.listJPOs(jobId: job.id, status: "draft").first { $0.orderNumber == "UITEST-JPO-001" })
        let detail = try orders.getJPODetail(id: jpo.id)

        #expect(userId > 0)
        #expect(try parts.listCategories().contains { $0.name == "UITesting Electrical" })
        #expect(try parts.listParts(search: "UITesting QA", limit: 10).count >= 2)
        #expect(detail.lines.count >= 2)
        #expect(detail.lines.allSatisfy { $0.partId != nil })
    }
}
