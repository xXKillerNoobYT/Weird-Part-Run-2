//
//  Weird_Parts_IOSTests.swift
//  Weird Parts IOSTests
//
//  Created by Isaac Aznoe on 3/15/26.
//

import Testing
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
}
