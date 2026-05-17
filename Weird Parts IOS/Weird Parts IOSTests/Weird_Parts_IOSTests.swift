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
    @Test func warehouseAuditTabStaysWithinInitialPhoneToolbarViewport() async throws {
        let warehouseTabs = appModules.first { $0.id == "warehouse" }?.tabs ?? []
        let auditIndex = try #require(warehouseTabs.firstIndex { $0.id == "warehouse-audit" })

        #expect(auditIndex <= 2)
    }
}
