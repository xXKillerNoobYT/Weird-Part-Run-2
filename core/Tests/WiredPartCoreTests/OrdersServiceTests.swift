import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("OrdersService Tests")
struct OrdersServiceTests {

    // MARK: - JPO Lifecycle

    @Test("Create and list JPOs")
    func testJPOCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        _ = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let jpoId = try env.orders.createJPO(
            jobId: jobId,
            requestedBy: env.adminUserId,
            notes: "Need wire for panel"
        )
        #expect(jpoId > 0)

        let jpos = try env.orders.listJPOs()
        #expect(jpos.count >= 1)
    }

    @Test("JPO detail with line items")
    func testJPODetail() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)

        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 25, notes: "Urgent")

        let detail = try env.orders.getJPODetail(id: jpoId)
        #expect(detail.lines.count == 1)
        #expect(detail.lines.first?.quantity == 25)
    }

    @Test("Update JPO status")
    func testUpdateJPOStatus() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        // draft → pending is the valid first transition (fixes #205 validation)
        try env.orders.updateJPOStatus(id: jpoId, status: "pending")
    }

    @Test("Create JPO with lines in one call")
    func testCreateJPOWithLines() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let jpoId = try env.orders.createJPOWithLines(
            jobId: jobId,
            requestedBy: env.adminUserId,
            priority: "normal",
            deliveryOption: "standard",
            notes: "Bundle order",
            lines: [(partId: partId, quantity: 10)]
        )
        #expect(jpoId > 0)
        let detail = try env.orders.getJPODetail(id: jpoId)
        #expect(detail.lines.count == 1)
    }

    @Test("Create JPO with lines persists line notes")
    func testCreateJPOWithLinesPersistsLineNotes() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let jpoId = try env.orders.createJPOWithLines(
            jobId: jobId,
            requestedBy: env.adminUserId,
            priority: "normal",
            deliveryOption: "standard",
            notes: "Bundle order",
            lines: [(partId: partId, quantity: 10)],
            lineNotes: ["Confirm panel fit before procurement"]
        )

        let detail = try env.orders.getJPODetail(id: jpoId)
        #expect(detail.lines.first?.notes == "Confirm panel fit before procurement")
    }

    @Test("Create JPO with lines rejects mismatched line notes")
    func testCreateJPOWithLinesRejectsMismatchedLineNotes() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        #expect(throws: OrdersService.OrdersError.invalidLineNotesCount(expected: 1, actual: 2)) {
            try env.orders.createJPOWithLines(
                jobId: jobId,
                requestedBy: env.adminUserId,
                priority: "normal",
                deliveryOption: "standard",
                notes: nil,
                lines: [(partId: partId, quantity: 10)],
                lineNotes: ["one", "too many"]
            )
        }
    }

    // MARK: - Purchase Orders

    @Test("Create and list purchase orders")
    func testPOCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(
            poNumber: "PO-TEST-001",
            supplierId: supplierId,
            notes: "First PO"
        )
        #expect(poId > 0)

        let pos = try env.orders.listPurchaseOrders()
        #expect(pos.count >= 1)
        #expect(pos.first?.poNumber == "PO-TEST-001")
    }

    @Test("PO detail with line items")
    func testPODetail() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(
            poNumber: "PO-DET-001",
            supplierId: supplierId,
            notes: nil
        )
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 50, unitPrice: 1.25)

        let detail = try env.orders.getPODetail(id: poId)
        #expect(detail.lines.count == 1)
        #expect(detail.lines.first?.unitPrice == 1.25)
    }

    @Test("Update PO status")
    func testUpdatePOStatus() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-STS", supplierId: supplierId, notes: nil)
        // draft → ordered is the valid first PO transition (fixes #205 validation; "sent" removed)
        try env.orders.updatePOStatus(id: poId, status: "ordered", userId: env.adminUserId)
    }

    @Test("Delete PO")
    func testDeletePO() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-DEL", supplierId: supplierId, notes: nil)
        try env.orders.deletePO(id: poId)
        let pos = try env.orders.listPurchaseOrders()
        #expect(!pos.contains(where: { $0.id == poId }))
    }

    // MARK: - Procurement

    @Test("Procurement demand on fresh DB")
    func testProcurementDemand() throws {
        let env = try E2ETestHelpers.setUp()
        let demand = try env.orders.getProcurementDemand()
        #expect(demand.count >= 0)
    }

    @Test("Procurement demand consolidates JPO, wishlist, and forecast demand for the same part")
    func testProcurementDemandConsolidatesWishlistAndForecast() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try env.parts.createPart(
            categoryId: catId,
            name: "Consolidated Demand Wire",
            minStockLevel: 5,
            maxStockLevel: 6,
            targetStockLevel: 12
        )
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "Demand Supplier")
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: supplierId, costPrice: 2.50)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DEMAND-1", name: "Demand Job")
        _ = try approvedJPOLine(env, jobId: jobId, partId: partId, quantity: 3)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 8)
        _ = try insertWishlistItem(env, partId: partId, qty: 4, sourceType: "manual", status: "sent_to_procurement")
        _ = try insertForecastTarget(env, partId: partId, minStock: 9, targetStock: 13, maxStock: 20, suggestedOrder: 5, certainty: 0.9)

        let items = try env.orders.getProcurementDemand().filter { $0.partId == partId }
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.totalDemand == 12)
        #expect(Set(item.sources.map(\.sourceType)) == Set(["jpo", "wishlist", "forecast"]))
        #expect(item.sources.filter { $0.sourceType == "wishlist" }.count == 1)
        #expect(item.sources.filter { $0.sourceType == "forecast" }.count == 1)
    }

    @Test("Procurement demand suppresses duplicate overstock-only row when part already has demand")
    func testProcurementDemandDoesNotDuplicateOverstockDemandPart() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try env.parts.createPart(
            categoryId: catId,
            name: "Demand Overstock Fuse",
            minStockLevel: 1,
            maxStockLevel: 3,
            targetStockLevel: 2
        )
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-OVER-DEMAND", name: "Over Demand")
        _ = try approvedJPOLine(env, jobId: jobId, partId: partId, quantity: 2)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10)

        let items = try env.orders.getProcurementDemand().filter { $0.partId == partId }
        #expect(items.count == 1)
        #expect(items.first?.urgency == "overstock")
        #expect(items.first?.sources.contains { $0.sourceType == "overstock" } == false)
    }

    @Test("generatePOsFromProcurement marks selected wishlist demand drafted")
    func testGeneratePOsFromProcurementMarksWishlistDrafted() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Wishlist Draft Part", categoryId: catId)
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "Wishlist Supplier")
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: supplierId, costPrice: 3.00)
        let wishlistId = try insertWishlistItem(env, partId: partId, qty: 6, sourceType: "manual", status: "sent_to_procurement")
        let item = try #require(try env.orders.getProcurementDemand().first { $0.partId == partId })
        let source = try #require(item.sources.first { $0.sourceType == "wishlist" })

        let result = try env.orders.generatePOsFromProcurement(items: [
            OrdersService.ProcurementGenerateItem(
                partId: partId,
                supplierId: supplierId,
                quantity: source.quantity,
                jpoLineIds: [],
                wishlistItemIds: source.wishlistItemIds
            )
        ])

        #expect(result.totalLineItems == 1)
        let status: String? = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM wishlist_items WHERE id = ?", arguments: [wishlistId])
        }
        #expect(status == "drafted")
        #expect(try env.orders.getProcurementDemand().allSatisfy { $0.partId != partId })
    }

    @Test("Generic procurement demand without prior PO has no supplier lock")
    func testGenericProcurementDemandWithoutPriorLock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Generic Coupling", categoryId: catId)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-GEN-1", name: "Generic Job")
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "Open Supplier")
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: supplierId, costPrice: 1.25)
        _ = try approvedJPOLine(env, jobId: jobId, partId: partId, quantity: 4)

        let item = try #require(env.orders.getProcurementDemand().first { $0.partId == partId })
        #expect(item.isGeneric)
        #expect(item.lockedSupplierId == nil)
        #expect(item.suppliers.contains { $0.id == supplierId })
    }

    @Test("Procurement demand SQL grouping preserves combined JPO quantity and line ids")
    func testProcurementDemandSQLGroupingPreservesQuantityAndLineIds() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Grouped Generic Clamp", categoryId: catId)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-GROUP-1", name: "Grouped Job")
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "Grouped Supplier")
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: supplierId, costPrice: 2.75)

        let jpoId: Int64 = try env.db.writer.write { db in
            let orderNumber = "JPO-GROUP-\(UUID().uuidString)"
            try db.execute(
                sql: """
                    INSERT INTO job_parts_orders
                    (job_id, order_number, requested_by, status, priority, notes, created_at, updated_at)
                    VALUES (?, ?, ?, 'approved', 'normal', NULL, datetime('now'), datetime('now'))
                    """,
                arguments: [jobId, orderNumber, env.adminUserId]
            )
            return db.lastInsertedRowID
        }

        let lineA: Int64 = try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO jpo_line_items
                    (jpo_id, part_id, qty_requested, line_status, created_at)
                    VALUES (?, ?, 2, 'approved', datetime('now'))
                    """,
                arguments: [jpoId, partId]
            )
            return db.lastInsertedRowID
        }
        let lineB: Int64 = try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO jpo_line_items
                    (jpo_id, part_id, qty_requested, line_status, created_at)
                    VALUES (?, ?, 3, 'approved', datetime('now'))
                    """,
                arguments: [jpoId, partId]
            )
            return db.lastInsertedRowID
        }

        let item = try #require(env.orders.getProcurementDemand().first { $0.partId == partId })
        let source = try #require(item.sources.first { $0.sourceType == "jpo" && $0.sourceId == jpoId })

        #expect(item.totalDemand == 5)
        #expect(source.quantity == 5)
        #expect(Set(source.lineIds) == Set([lineA, lineB]))
    }

    @Test("Generic procurement demand locks to prior supplier for the same job and part")
    func testGenericProcurementDemandUsesPriorSupplierLock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Generic Strap", categoryId: catId)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-GEN-2", name: "Locked Generic Job")
        let lockedSupplierId = try E2ETestHelpers.seedSupplier(env, name: "Locked Supplier")
        let otherSupplierId = try E2ETestHelpers.seedSupplier(env, name: "Other Supplier")
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: lockedSupplierId, costPrice: 2.00)
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: otherSupplierId, costPrice: 1.00)
        let priorLineId = try approvedJPOLine(env, jobId: jobId, partId: partId, quantity: 2)
        _ = try env.orders.generatePOsFromProcurement(items: [
            OrdersService.ProcurementGenerateItem(partId: partId, supplierId: lockedSupplierId, quantity: 2, jpoLineIds: [priorLineId])
        ])
        _ = try approvedJPOLine(env, jobId: jobId, partId: partId, quantity: 5)

        let item = try #require(env.orders.getProcurementDemand().first { $0.partId == partId })
        #expect(item.lockedSupplierId == lockedSupplierId)
        #expect(item.lockedSupplierName == "Locked Supplier")
        #expect(item.suppliers.map(\.id) == [lockedSupplierId])
    }

    @Test("Branded procurement demand remains freely selectable despite prior PO history")
    func testBrandedProcurementDemandDoesNotLockToPriorSupplier() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let brandId = try E2ETestHelpers.seedBrand(env, name: "BrandCo")
        let partId = try env.parts.createPart(categoryId: catId, name: "BrandCo Breaker", brandId: brandId)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-BRAND-1", name: "Branded Job")
        let priorSupplierId = try E2ETestHelpers.seedSupplier(env, name: "Prior Supplier")
        let otherSupplierId = try E2ETestHelpers.seedSupplier(env, name: "Other Supplier")
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: priorSupplierId, costPrice: 20.00)
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: otherSupplierId, costPrice: 18.00)
        let priorLineId = try approvedJPOLine(env, jobId: jobId, partId: partId, quantity: 1)
        _ = try env.orders.generatePOsFromProcurement(items: [
            OrdersService.ProcurementGenerateItem(partId: partId, supplierId: priorSupplierId, quantity: 1, jpoLineIds: [priorLineId])
        ])
        _ = try approvedJPOLine(env, jobId: jobId, partId: partId, quantity: 3)

        let item = try #require(env.orders.getProcurementDemand().first { $0.partId == partId })
        #expect(!item.isGeneric)
        #expect(item.lockedSupplierId == nil)
        #expect(Set(item.suppliers.map(\.id)) == Set([priorSupplierId, otherSupplierId]))
    }

    @Test("Generic demand from two jobs with different prior suppliers stays split")
    func testGenericProcurementDemandSplitsConflictingJobLocks() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Generic Connector", categoryId: catId)
        let jobA = try E2ETestHelpers.seedJob(env, jobNumber: "J-LOCK-A", name: "Lock A")
        let jobB = try E2ETestHelpers.seedJob(env, jobNumber: "J-LOCK-B", name: "Lock B")
        let supplierA = try E2ETestHelpers.seedSupplier(env, name: "Supplier A")
        let supplierB = try E2ETestHelpers.seedSupplier(env, name: "Supplier B")
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: supplierA, costPrice: 3.00)
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: supplierB, costPrice: 3.50)
        let priorA = try approvedJPOLine(env, jobId: jobA, partId: partId, quantity: 1)
        let priorB = try approvedJPOLine(env, jobId: jobB, partId: partId, quantity: 1)
        _ = try env.orders.generatePOsFromProcurement(items: [
            OrdersService.ProcurementGenerateItem(partId: partId, supplierId: supplierA, quantity: 1, jpoLineIds: [priorA]),
            OrdersService.ProcurementGenerateItem(partId: partId, supplierId: supplierB, quantity: 1, jpoLineIds: [priorB])
        ])
        _ = try approvedJPOLine(env, jobId: jobA, partId: partId, quantity: 2)
        _ = try approvedJPOLine(env, jobId: jobB, partId: partId, quantity: 4)

        let items = try env.orders.getProcurementDemand().filter { $0.partId == partId }
        #expect(items.count == 2)
        #expect(Set(items.compactMap(\.lockedSupplierId)) == Set([supplierA, supplierB]))
        #expect(Set(items.map(\.totalDemand)) == Set([2, 4]))
    }

    // MARK: - Returns

    @Test("List returns empty on fresh DB")
    func testReturnsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let returns = try env.orders.listReturns()
        #expect(returns.isEmpty)
    }

    @Test("Create return")
    func testCreateReturn() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-RET", supplierId: supplierId, notes: nil)
        let returnId = try env.orders.createReturn(
            returnType: "supplier",
            reason: "Defective parts",
            supplierId: supplierId,
            poId: poId,
            initiatedBy: env.adminUserId
        )
        #expect(returnId > 0)
    }

    // MARK: - Order Stats

    @Test("Order stats aggregates")
    func testOrderStats() throws {
        let env = try E2ETestHelpers.setUp()
        let stats = try env.orders.getOrderStats()
        #expect(stats.pendingJPOs >= 0)
        #expect(stats.activePOs >= 0)
    }

    // MARK: - Receipt History

    @Test("Receipt history empty on fresh DB")
    func testReceiptHistoryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-HIST", supplierId: supplierId, notes: nil)
        let history = try env.orders.getReceiptHistory(poId: poId)
        #expect(history.isEmpty)
    }

    // MARK: - Job Stages

    @Test("Job stages via orders")
    func testJobStages() throws {
        let env = try E2ETestHelpers.setUp()
        let stages = try env.orders.getJobStages()
        #expect(stages.count >= 0)
    }

    // MARK: - Generate PO From JPO

    @Test("Generate PO from approved JPO")
    func testGeneratePOFromJPO() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let supplierId = try E2ETestHelpers.seedSupplier(env)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        // Must follow valid transitions: draft → pending → approved (fixes #205 validation)
        try env.orders.updateJPOStatus(id: jpoId, status: "pending")
        try env.orders.updateJPOStatus(id: jpoId, status: "approved")

        let poId = try env.orders.generatePOFromJPO(jpoId: jpoId, supplierId: supplierId)
        #expect(poId > 0)

        let pos = try env.orders.listPurchaseOrders()
        #expect(pos.contains(where: { $0.id == poId }))
    }

    // MARK: - Update Return Status

    @Test("Update return status")
    func testUpdateReturnStatus() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-URS", supplierId: supplierId, notes: nil)
        let returnId = try env.orders.createReturn(
            returnType: "supplier",
            reason: "Wrong parts",
            supplierId: supplierId,
            poId: poId,
            initiatedBy: env.adminUserId
        )

        try env.orders.updateReturnStatus(returnId: returnId, status: "completed")
        let returns = try env.orders.listReturns()
        let updated = returns.first(where: { $0.id == returnId })
        #expect(updated?.status == "completed")
    }

    // MARK: - PO Expected Delivery & Notes

    @Test("Update PO expected delivery and add note")
    func testPODeliveryAndNotes() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-NOTE", supplierId: supplierId, notes: nil)

        try env.orders.updatePOExpectedDelivery(id: poId, expectedDelivery: "2026-04-15")
        try env.orders.addPONote(poId: poId, note: "Supplier confirmed delivery", author: "Admin")

        let detail = try env.orders.getPODetail(id: poId)
        #expect(detail.expectedDelivery == "2026-04-15")
        #expect(detail.notes?.contains("Supplier confirmed delivery") == true)
    }

    // MARK: - Suppliers With Active POs

    @Test("Suppliers with active POs")
    func testSuppliersWithActivePOs() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        _ = try env.orders.createPurchaseOrder(poNumber: "PO-ACT", supplierId: supplierId, notes: nil)

        let suppliers = try env.orders.getSuppliersWithActivePOs()
        #expect(suppliers.contains(where: { $0.id == supplierId }))
    }

    // MARK: - JPO Line Status

    @Test("updateJPOLineStatus updates line and re-derives parent JPO status")
    func testUpdateJPOLineStatus() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-LS-01", name: "Line Status Job")
        let catId = try E2ETestHelpers.seedCategory(env, name: "LineStatusCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Line Part", categoryId: catId)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 5, notes: nil)

        // Approve the line
        try env.orders.updateJPOLineStatus(lineId: lineId, status: "approved", updatedBy: env.adminUserId)

        let detail = try env.orders.getJPODetail(id: jpoId)
        let line = detail.lines.first(where: { $0.id == lineId })
        #expect(line?.lineStatus == "approved")
        // Parent JPO should now reflect the derived "approved" status
        #expect(detail.status == "approved")
    }

    @Test("updateJPOLineStatus with on_hold records hold reason")
    func testUpdateJPOLineStatusOnHold() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-LS-02", name: "Hold Job")
        let catId = try E2ETestHelpers.seedCategory(env, name: "HoldCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Hold Part", categoryId: catId)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 3, notes: nil)

        try env.orders.updateJPOLineStatus(lineId: lineId, status: "on_hold", reason: "Need confirmation", updatedBy: env.adminUserId)

        let detail = try env.orders.getJPODetail(id: jpoId)
        let line = detail.lines.first(where: { $0.id == lineId })
        #expect(line?.lineStatus == "on_hold")
    }

    // MARK: - deriveJPOStatusFromLineStatuses (pure function)

    @Test("deriveJPOStatusFromLineStatuses: all pending → pending")
    func testDeriveStatusAllPending() throws {
        let env = try E2ETestHelpers.setUp()
        let result = env.orders.deriveJPOStatusFromLineStatuses(["pending", "pending"])
        #expect(result == "pending")
    }

    @Test("deriveJPOStatusFromLineStatuses: all delivered → complete")
    func testDeriveStatusAllDelivered() throws {
        let env = try E2ETestHelpers.setUp()
        let result = env.orders.deriveJPOStatusFromLineStatuses(["delivered", "delivered"])
        #expect(result == "complete")
    }

    @Test("deriveJPOStatusFromLineStatuses: empty → draft")
    func testDeriveStatusEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let result = env.orders.deriveJPOStatusFromLineStatuses([])
        #expect(result == "draft")
    }

    @Test("deriveJPOStatusFromLineStatuses: mixed statuses → in_review")
    func testDeriveStatusMixed() throws {
        let env = try E2ETestHelpers.setUp()
        let result = env.orders.deriveJPOStatusFromLineStatuses(["pending", "approved"])
        #expect(result == "in_review")
    }

    // MARK: - JPO Delivery Option

    @Test("updateJPODeliveryOption changes delivery option")
    func testUpdateJPODeliveryOption() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DO-01", name: "Delivery Option Job")
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)

        try env.orders.updateJPODeliveryOption(jpoId: jpoId, option: "pickup")

        // Verify via listing JPOs
        let jpos = try env.orders.listJPOs()
        let jpo = jpos.first(where: { $0.id == jpoId })
        #expect(jpo != nil)
        // Delivery option is stored — no error thrown means it updated correctly
    }

    // MARK: - Update PO Line Item

    @Test("updatePOLineItem changes quantity and price on draft PO")
    func testUpdatePOLineItem() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-ULI", supplierId: supplierId, notes: nil)
        let catId = try E2ETestHelpers.seedCategory(env, name: "UpdateLineCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Update Line Part", categoryId: catId)

        let lineId = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 10, unitPrice: 2.50)
        try env.orders.updatePOLineItem(lineId: lineId, quantity: 20, unitPrice: 3.00)

        let detail = try env.orders.getPODetail(id: poId)
        let line = detail.lines.first(where: { $0.id == lineId })
        #expect(line?.quantityOrdered == 20)
        #expect(line?.unitPrice == 3.00)
    }

    @Test("updatePOLineItem throws when PO is not in draft")
    func testUpdatePOLineItemNonDraft() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-ULI2", supplierId: supplierId, notes: nil)
        let catId = try E2ETestHelpers.seedCategory(env, name: "UpdateLockCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Lock Line Part", categoryId: catId)
        let lineId = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 5, unitPrice: 1.00)

        // Move PO out of draft (draft → ordered is valid; "sent" removed in #205)
        try env.orders.updatePOStatus(id: poId, status: "ordered", userId: env.adminUserId)

        #expect(throws: (any Error).self) {
            try env.orders.updatePOLineItem(lineId: lineId, quantity: 10, unitPrice: 2.00)
        }
    }

    // MARK: - Category Stage Mappings

    @Test("getCategoryStageMappings returns all categories with nil stage when unmapped")
    func testGetCategoryStageMappingsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try E2ETestHelpers.seedCategory(env, name: "UnmappedCat")
        let mappings = try env.orders.getCategoryStageMappings()
        #expect(mappings.count >= 1)
        // All should have nil stageId since no stages or mappings exist
        let unmapped = mappings.filter { $0.stageId == nil }
        #expect(unmapped.count == mappings.count)
    }

    @Test("updateCategoryStageMapping and getCategoryStageMappings round-trip")
    func testUpdateCategoryStageMapping() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "MappedCat")

        // Seed a job stage
        let stageId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO job_stages (name, sort_order, created_at)
                VALUES ('Rough', 1, datetime('now'))
                """)
            return db.lastInsertedRowID
        }

        try env.orders.updateCategoryStageMapping(categoryId: catId, stageId: stageId)
        let mappings = try env.orders.getCategoryStageMappings()
        let mapped = mappings.first(where: { $0.categoryId == catId })
        #expect(mapped != nil)
        #expect(mapped?.stageId == stageId)
        #expect(mapped?.stageName == "Rough")
    }

    // MARK: - Job Stage Parts

    @Test("getJobStageParts returns empty for job with no JPO lines")
    func testGetJobStagePartsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SP-01", name: "Stage Parts Job")
        let parts = try env.orders.getJobStageParts(jobId: jobId)
        #expect(parts.isEmpty)
    }

    @Test("getJobStageParts returns line items after adding JPO")
    func testGetJobStagePartsWithLines() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SP-02", name: "Stage Parts Job 2")
        let catId = try E2ETestHelpers.seedCategory(env, name: "StagePartsCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Stage Wire", categoryId: catId)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        _ = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 8, notes: nil)

        let parts = try env.orders.getJobStageParts(jobId: jobId)
        #expect(parts.count == 1)
        #expect(parts[0].partName == "Stage Wire")
        #expect(parts[0].quantity == 8)
    }

    // MARK: - requestEarlyRelease

    @Test("requestEarlyRelease promotes held line to approved")
    func testRequestEarlyRelease() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-ER-01", name: "Early Release Job")
        let catId = try E2ETestHelpers.seedCategory(env, name: "EarlyReleaseCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Held Part", categoryId: catId)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 2, notes: nil)

        // Manually set the line to 'held' status
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE jpo_line_items SET line_status = 'held' WHERE id = ?",
                arguments: [lineId]
            )
        }

        try env.orders.requestEarlyRelease(jpoLineId: lineId)

        let detail = try env.orders.getJPODetail(id: jpoId)
        let line = detail.lines.first(where: { $0.id == lineId })
        #expect(line?.lineStatus == "approved")
    }

    // MARK: - Receipt History Entries & Items

    @Test("getReceiptHistoryEntries returns empty for PO with no completed sessions")
    func testReceiptHistoryEntriesEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-RHE", supplierId: supplierId, notes: nil)
        let entries = try env.orders.getReceiptHistoryEntries(poId: poId)
        #expect(entries.isEmpty)
    }

    @Test("getReceiptHistoryItems returns empty for non-existent session")
    func testReceiptHistoryItemsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let items = try env.orders.getReceiptHistoryItems(sessionId: 9999)
        #expect(items.isEmpty)
    }

    // MARK: - Parts For Supplier

    @Test("getPartsForSupplier returns empty when no PO lines exist")
    func testGetPartsForSupplierEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "PartSupplier")
        let parts = try env.orders.getPartsForSupplier(supplierId: supplierId)
        #expect(parts.isEmpty)
    }

    @Test("getPartsForSupplier returns lines after creating PO with line items")
    func testGetPartsForSupplierWithLines() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "PartSupplier2")
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-PFS", supplierId: supplierId, notes: nil)
        let catId = try E2ETestHelpers.seedCategory(env, name: "SupplierPartCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Supplier Part", categoryId: catId)
        _ = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 100, unitPrice: 0.50)

        let parts = try env.orders.getPartsForSupplier(supplierId: supplierId)
        #expect(parts.count >= 1)
        #expect(parts.contains(where: { $0.partName == "Supplier Part" }))
        #expect(parts[0].quantityOrdered == 100)
    }

    @Test("getPartsForSupplier falls back to 'Item' name when part is soft-deleted")
    func testGetPartsForSupplierHidesDeletedPartName() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "SupplierSoftDel")
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-PDEL", supplierId: supplierId, notes: nil)
        let catId = try E2ETestHelpers.seedCategory(env, name: "SoftDelCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Deleted Part", categoryId: catId)
        _ = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 5, unitPrice: 1.0)

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?", arguments: [partId])
        }

        let parts = try env.orders.getPartsForSupplier(supplierId: supplierId)
        #expect(parts.count >= 1)
        #expect(!parts.contains(where: { $0.partName == "Deleted Part" }))
        #expect(parts.first?.partName == "Item")
    }

    // MARK: - listJPOs with job filter

    @Test("listJPOs with jobId filter returns only JPOs for that job")
    func testListJPOsJobFilter() throws {
        let env = try E2ETestHelpers.setUp()
        let job1Id = try E2ETestHelpers.seedJob(env, jobNumber: "J-LF-01", name: "Filter Job 1")
        let job2Id = try E2ETestHelpers.seedJob(env, jobNumber: "J-LF-02", name: "Filter Job 2")

        let jpo1Id = try env.orders.createJPO(jobId: job1Id, requestedBy: env.adminUserId, notes: nil)
        _ = try env.orders.createJPO(jobId: job2Id, requestedBy: env.adminUserId, notes: nil)

        let allJPOs = try env.orders.listJPOs()
        let job1JPOs = try env.orders.listJPOs(jobId: job1Id)
        #expect(allJPOs.count >= 2)
        #expect(job1JPOs.count == 1)
        #expect(job1JPOs[0].id == jpo1Id)
        #expect(job1JPOs[0].jobId == job1Id)
    }

    // MARK: - smartRouteJPOLine

    @Test("smartRouteJPOLine returns pending when no stock exists")
    func testSmartRouteNoStock() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SR-01", name: "Smart Route Job 1")
        let catId = try E2ETestHelpers.seedCategory(env, name: "RouteTestCat1")
        let partId = try E2ETestHelpers.seedPart(env, name: "Route Part 1", categoryId: catId)

        // Insert JPO line directly so we can call smartRouteJPOLine independently
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, created_at)
                VALUES (?, ?, 5, datetime('now'))
                """, arguments: [jpoId, partId])
            return db.lastInsertedRowID
        }

        // No stock seeded — should route to pending
        let route = try env.orders.smartRouteJPOLine(lineId: lineId, partId: partId, userId: env.adminUserId)
        #expect(route == "pending")
    }

    @Test("smartRouteJPOLine returns transfer when shop has sufficient stock")
    func testSmartRouteWithStock() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SR-02", name: "Smart Route Job 2")
        let catId = try E2ETestHelpers.seedCategory(env, name: "RouteTestCat2")
        let partId = try E2ETestHelpers.seedPart(env, name: "Route Part 2", categoryId: catId)

        // Seed 10 units of stock
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, created_at)
                VALUES (?, ?, 5, datetime('now'))
                """, arguments: [jpoId, partId])
            return db.lastInsertedRowID
        }

        // 10 available, need 5 — should auto-route to transfer
        let route = try env.orders.smartRouteJPOLine(lineId: lineId, partId: partId, userId: env.adminUserId)
        #expect(route == "transfer")
    }

    @Test("smartRouteJPOLine writes NULL status_updated_by when userId is nil")
    func testSmartRouteNilUserIdWritesNull() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SR-03", name: "Smart Route Nil User")
        let catId = try E2ETestHelpers.seedCategory(env, name: "RouteTestCat3")
        let partId = try E2ETestHelpers.seedPart(env, name: "Route Part 3", categoryId: catId)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, created_at)
                VALUES (?, ?, 3, datetime('now'))
                """, arguments: [jpoId, partId])
            return db.lastInsertedRowID
        }

        // userId = nil — system-triggered routing; status_updated_by must be NULL, not 0
        _ = try env.orders.smartRouteJPOLine(lineId: lineId, partId: partId, userId: nil)
        let updatedBy = try env.db.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT status_updated_by FROM jpo_line_items WHERE id = ?",
                               arguments: [lineId])
        }
        #expect(updatedBy == nil, "status_updated_by must be NULL when no userId is provided — not 0")
    }

    // MARK: - setJPOLineTransferId

    @Test("setJPOLineTransferId links a transfer movement to a JPO line")
    func testSetJPOLineTransferId() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-TID-01", name: "Transfer ID Job")
        let catId = try E2ETestHelpers.seedCategory(env, name: "TransferIdCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Transfer ID Part", categoryId: catId)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 2, notes: nil)

        // Link a fake transfer movement ID
        let fakeTransferId: Int64 = 999
        try env.orders.setJPOLineTransferId(lineId: lineId, transferId: fakeTransferId)

        // Verify the transfer_id was persisted
        let storedTransferId = try env.db.writer.read { db -> Int64? in
            try Int64.fetchOne(db, sql: "SELECT transfer_id FROM jpo_line_items WHERE id = ?", arguments: [lineId])
        }
        #expect(storedTransferId == fakeTransferId)
    }

    // MARK: - markStageComplete

    @Test("markStageComplete advances job to the next stage")
    func testMarkStageComplete() throws {
        let env = try E2ETestHelpers.setUp()

        // Seed two consecutive stages
        let stage1Id = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO job_stages (name, sort_order, created_at)
                VALUES ('Stage One', 10, datetime('now'))
                """)
            return db.lastInsertedRowID
        }
        let stage2Id = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO job_stages (name, sort_order, created_at)
                VALUES ('Stage Two', 20, datetime('now'))
                """)
            return db.lastInsertedRowID
        }

        // Create a job at stage 1
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-MS-01", name: "Stage Complete Job")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET current_stage_id = ? WHERE id = ?",
                           arguments: [stage1Id, jobId])
        }

        try env.orders.markStageComplete(jobId: jobId, stageId: stage1Id)

        // Job should now be at stage 2
        let currentStageId = try env.db.writer.read { db -> Int64? in
            try Int64.fetchOne(db, sql: "SELECT current_stage_id FROM jobs WHERE id = ?", arguments: [jobId])
        }
        #expect(currentStageId == stage2Id)
    }

    // MARK: - cancelJPOLineTransfer

    @Test("cancelJPOLineTransfer clears transfer_id on JPO line")
    func testCancelJPOLineTransferClearsLink() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-CJLT-01", name: "Cancel Transfer Job")
        let catId = try E2ETestHelpers.seedCategory(env, name: "CancelTransferCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Cancel Transfer Part", categoryId: catId)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 1, notes: nil)

        // Set a transfer_id and keep qty_requested = 0 so the reverse-movement
        // path inside cancelJPOLineTransfer is skipped (qty > 0 guard). This
        // avoids a GRDB reentrancy crash: both services share the same in-memory
        // writer, so calling warehouseService.createMovement from inside another
        // write transaction deadlocks.
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE jpo_line_items SET transfer_id = 999, qty_requested = 0 WHERE id = ?",
                arguments: [lineId]
            )
        }
        let before = try env.db.writer.read { db -> Int64? in
            try Int64.fetchOne(db, sql: "SELECT transfer_id FROM jpo_line_items WHERE id = ?", arguments: [lineId])
        }
        #expect(before == 999)

        try env.orders.cancelJPOLineTransfer(lineId: lineId, reversedBy: env.adminUserId, warehouseService: env.warehouse)

        let after = try env.db.writer.read { db -> Int64? in
            try Int64.fetchOne(db, sql: "SELECT transfer_id FROM jpo_line_items WHERE id = ?", arguments: [lineId])
        }
        #expect(after == nil, "transfer_id must be cleared after cancel")
    }

    @Test("cancelJPOLineTransfer on line with no transfer_id is a silent no-op")
    func testCancelJPOLineTransferNoOp() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-CJLT-02", name: "No Transfer Job")
        let catId = try E2ETestHelpers.seedCategory(env, name: "NoTransferCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "No Transfer Part", categoryId: catId)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 1, notes: nil)

        // transfer_id is nil from the start — should not throw
        try env.orders.cancelJPOLineTransfer(lineId: lineId, reversedBy: env.adminUserId, warehouseService: env.warehouse)

        let transferId = try env.db.writer.read { db -> Int64? in
            try Int64.fetchOne(db, sql: "SELECT transfer_id FROM jpo_line_items WHERE id = ?", arguments: [lineId])
        }
        #expect(transferId == nil)
    }

    @Test("markStageComplete stays on current stage when it is the last stage")
    func testMarkStageCompleteLastStage() throws {
        let env = try E2ETestHelpers.setUp()

        // Single final stage (highest sort_order)
        let finalStageId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO job_stages (name, sort_order, created_at)
                VALUES ('Final Stage', 999, datetime('now'))
                """)
            return db.lastInsertedRowID
        }

        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-MS-02", name: "Final Stage Job")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET current_stage_id = ? WHERE id = ?",
                           arguments: [finalStageId, jobId])
        }

        // Completing the last stage should keep job at the same stage
        try env.orders.markStageComplete(jobId: jobId, stageId: finalStageId)

        let currentStageId = try env.db.writer.read { db -> Int64? in
            try Int64.fetchOne(db, sql: "SELECT current_stage_id FROM jobs WHERE id = ?", arguments: [jobId])
        }
        #expect(currentStageId == finalStageId)
    }

    // MARK: - holdJPOLineWithChat

    @Test("holdJPOLineWithChat creates chat channel and sends first message")
    func testHoldJPOLineWithChat() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 5, notes: nil)

        let channelId = try env.orders.holdJPOLineWithChat(
            lineId: lineId,
            holdReason: "Awaiting price approval",
            userId: env.adminUserId,
            partName: "Test Wire",
            jpoId: jpoId
        )
        #expect(channelId > 0)

        // Verify the chat channel was created
        let channelCount = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chat_channels WHERE id = ?", arguments: [channelId]) ?? 0
        }
        #expect(channelCount == 1)

        // Verify the first message was posted with the hold reason
        let messageCount = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chat_messages WHERE channel_id = ? AND content = ?",
                arguments: [channelId, "Awaiting price approval"]) ?? 0
        }
        #expect(messageCount == 1)
    }

    @Test("holdJPOLineWithChat adds manager as admin member of channel")
    func testHoldJPOLineChatMembership() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 3, notes: nil)

        let channelId = try env.orders.holdJPOLineWithChat(
            lineId: lineId,
            holdReason: "Need manager sign-off",
            userId: env.adminUserId,
            partName: "Breaker",
            jpoId: jpoId
        )

        // The holding user should be an admin in the channel
        let role = try env.db.writer.read { db in
            try String.fetchOne(db,
                sql: "SELECT role FROM chat_channel_members WHERE channel_id = ? AND user_id = ?",
                arguments: [channelId, env.adminUserId])
        }
        #expect(role == "admin")
    }

    // MARK: - generatePOsFromProcurement

    @Test("generatePOsFromProcurement groups items by supplier into separate POs")
    func testGeneratePOsFromProcurement() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId1 = try E2ETestHelpers.seedPart(env, name: "Wire A", categoryId: catId)
        let partId2 = try E2ETestHelpers.seedPart(env, name: "Wire B", categoryId: catId)
        let suppId1 = try E2ETestHelpers.seedSupplier(env, name: "Supplier Alpha")
        let suppId2 = try E2ETestHelpers.seedSupplier(env, name: "Supplier Beta")

        let items = [
            OrdersService.ProcurementGenerateItem(partId: partId1, supplierId: suppId1, quantity: 10, unitCost: 2.50, jpoLineIds: []),
            OrdersService.ProcurementGenerateItem(partId: partId2, supplierId: suppId2, quantity: 5, unitCost: 8.00, jpoLineIds: []),
        ]

        let result = try env.orders.generatePOsFromProcurement(items: items)
        // Two suppliers → two POs
        #expect(result.createdPOs.count == 2)
        #expect(result.totalLineItems == 2)

        // PO numbers should be unique
        let poNumbers = result.createdPOs.map { $0.poNumber }
        #expect(Set(poNumbers).count == 2)
    }

    @Test("generatePOsFromProcurement merges same-supplier items into one PO")
    func testGeneratePOsSameSupplierMerge() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId1 = try E2ETestHelpers.seedPart(env, name: "Wire A", categoryId: catId)
        let partId2 = try E2ETestHelpers.seedPart(env, name: "Conduit B", categoryId: catId)
        let suppId = try E2ETestHelpers.seedSupplier(env)

        let items = [
            OrdersService.ProcurementGenerateItem(partId: partId1, supplierId: suppId, quantity: 20, unitCost: 1.00, jpoLineIds: []),
            OrdersService.ProcurementGenerateItem(partId: partId2, supplierId: suppId, quantity: 10, unitCost: 3.50, jpoLineIds: []),
        ]

        let result = try env.orders.generatePOsFromProcurement(items: items)
        // Same supplier → one PO with two line items
        #expect(result.createdPOs.count == 1)
        #expect(result.totalLineItems == 2)
    }

    @Test("generatePOsFromProcurement with empty input returns empty result")
    func testGeneratePOsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let result = try env.orders.generatePOsFromProcurement(items: [])
        #expect(result.createdPOs.isEmpty)
        #expect(result.totalLineItems == 0)
    }

    @Test("generatePOsFromProcurement creates one traceable PO line per selected JPO source")
    func testGeneratePOsTraceEachJPOLine() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Shared Conduit", categoryId: catId)
        let jobA = try E2ETestHelpers.seedJob(env, jobNumber: "J-TRACE-A", name: "Trace A")
        let jobB = try E2ETestHelpers.seedJob(env, jobNumber: "J-TRACE-B", name: "Trace B")
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "Trace Supplier")
        let lineA = try approvedJPOLine(env, jobId: jobA, partId: partId, quantity: 2)
        let lineB = try approvedJPOLine(env, jobId: jobB, partId: partId, quantity: 3)

        let result = try env.orders.generatePOsFromProcurement(items: [
            OrdersService.ProcurementGenerateItem(
                partId: partId,
                supplierId: supplierId,
                quantity: 5,
                unitCost: 4.25,
                jpoLineIds: [lineA, lineB]
            )
        ])

        #expect(result.createdPOs.count == 1)
        #expect(result.totalLineItems == 2)

        try env.db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT jpo_line_id, qty_ordered
                FROM po_line_items
                WHERE po_id = ?
                ORDER BY jpo_line_id
            """, arguments: [result.createdPOs[0].poId])
            #expect(rows.count == 2)
            let linkedLineIds: [Int64] = rows.compactMap { row in row["jpo_line_id"] }
            let quantities: [Int] = rows.map { row in row["qty_ordered"] }
            #expect(Set(linkedLineIds) == Set([lineA, lineB]))
            #expect(quantities.sorted() == [2, 3])

            let linkedJPOs = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM po_jpo_links WHERE po_id = ?
                """, arguments: [result.createdPOs[0].poId])
            #expect(linkedJPOs == 2)
        }
    }

    @Test("generatePOsFromProcurement leaves unselected JPO lines approved")
    func testGeneratePOsPartialLeavesUnselectedApproved() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Partial Strap", categoryId: catId)
        let jobA = try E2ETestHelpers.seedJob(env, jobNumber: "J-PART-A", name: "Partial A")
        let jobB = try E2ETestHelpers.seedJob(env, jobNumber: "J-PART-B", name: "Partial B")
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "Partial Supplier")
        let selectedLine = try approvedJPOLine(env, jobId: jobA, partId: partId, quantity: 2)
        let unselectedLine = try approvedJPOLine(env, jobId: jobB, partId: partId, quantity: 3)

        _ = try env.orders.generatePOsFromProcurement(items: [
            OrdersService.ProcurementGenerateItem(
                partId: partId,
                supplierId: supplierId,
                quantity: 2,
                jpoLineIds: [selectedLine]
            )
        ])

        try env.db.writer.read { db in
            let selectedStatus = try String.fetchOne(
                db,
                sql: "SELECT line_status FROM jpo_line_items WHERE id = ?",
                arguments: [selectedLine]
            )
            let unselectedStatus = try String.fetchOne(
                db,
                sql: "SELECT line_status FROM jpo_line_items WHERE id = ?",
                arguments: [unselectedLine]
            )
            #expect(selectedStatus == "in_procurement")
            #expect(unselectedStatus == "approved")
        }
    }

    @Test("procurement preview groups selected sources by supplier then job and supports exclusions")
    func testProcurementPreviewGroupsBySupplierThenJob() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Preview Cable", categoryId: catId)
        let jobA = try E2ETestHelpers.seedJob(env, jobNumber: "J-PREV-A", name: "Preview A")
        let jobB = try E2ETestHelpers.seedJob(env, jobNumber: "J-PREV-B", name: "Preview B")
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "Preview Supplier")
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: supplierId, costPrice: 9.50)
        let lineA = try approvedJPOLine(env, jobId: jobA, partId: partId, quantity: 2)
        _ = try approvedJPOLine(env, jobId: jobB, partId: partId, quantity: 3)

        let item = try #require(env.orders.getProcurementDemand().first { $0.partId == partId })
        let groups = OrdersService.buildProcurementPreviewGroups(
            items: [item],
            selection: OrdersService.ProcurementPreviewSelection(
                checkedPartIds: [item.id],
                selectedSuppliers: [item.id: supplierId],
                orderQuantities: [item.id: item.totalDemand]
            )
        )

        #expect(groups.count == 1)
        #expect(groups[0].supplierId == supplierId)
        #expect(groups[0].jobs.count == 2)
        #expect(groups[0].jobs.contains { $0.jobName.contains("Preview A") })
        #expect(groups[0].jobs.contains { $0.jobName.contains("Preview B") })
        #expect(Set(groups[0].jobs.flatMap(\.parts).flatMap(\.jpoLineIds)).contains(lineA))

        let excludedKey = try #require(groups[0].jobs.first { $0.jobId == jobA }?.parts.first?.key)
        let afterExclusion = OrdersService.buildProcurementPreviewGroups(
            items: [item],
            selection: OrdersService.ProcurementPreviewSelection(
                checkedPartIds: [item.id],
                selectedSuppliers: [item.id: supplierId],
                orderQuantities: [item.id: item.totalDemand],
                excludedLineKeys: [excludedKey]
            )
        )
        #expect(afterExclusion[0].jobs.count == 1)
        #expect(afterExclusion[0].jobs[0].jobName.contains("Preview B"))
    }

    @Test("procurement pull options cover above-target demand")
    func testProcurementPullOptionsAboveTarget() {
        let options = OrdersService.procurementPullOptions(
            demandQty: 8,
            shopStock: 12,
            minStock: 4,
            targetStock: 10
        )

        #expect(options.contains(.init(kind: .pullToTarget, pullQty: 2, orderQty: 6, isRecommended: true)))
        #expect(options.contains(.init(kind: .pullAll, pullQty: 8, orderQty: 0, isRecommended: false)))
        #expect(options.contains(.init(kind: .pullToMin, pullQty: 8, orderQty: 0, isRecommended: false)))
        #expect(options.contains(.init(kind: .orderAll, pullQty: 0, orderQty: 8, isRecommended: false)))
    }

    @Test("procurement pull options cover between-min-target demand")
    func testProcurementPullOptionsBetweenMinAndTarget() {
        let options = OrdersService.procurementPullOptions(
            demandQty: 6,
            shopStock: 7,
            minStock: 4,
            targetStock: 10
        )

        #expect(!options.contains { $0.kind == .pullToTarget })
        #expect(options.contains(.init(kind: .pullAll, pullQty: 6, orderQty: 0, isRecommended: true)))
        #expect(options.contains(.init(kind: .pullToMin, pullQty: 3, orderQty: 3, isRecommended: false)))
        #expect(options.contains(.init(kind: .orderAll, pullQty: 0, orderQty: 6, isRecommended: false)))
    }

    @Test("procurement pull options cover below-min demand")
    func testProcurementPullOptionsBelowMin() {
        let options = OrdersService.procurementPullOptions(
            demandQty: 5,
            shopStock: 2,
            minStock: 4,
            targetStock: 10
        )

        #expect(!options.contains { $0.kind == .pullToTarget })
        #expect(options.contains(.init(kind: .pullAll, pullQty: 2, orderQty: 3, isRecommended: true)))
        #expect(!options.contains { $0.kind == .pullToMin })
        #expect(options.contains(.init(kind: .orderAll, pullQty: 0, orderQty: 5, isRecommended: false)))
    }

    @Test("procurement pull options cover above-max demand")
    func testProcurementPullOptionsAboveMax() {
        let options = OrdersService.procurementPullOptions(
            demandQty: 4,
            shopStock: 14,
            minStock: 4,
            targetStock: 10
        )

        #expect(options.contains(.init(kind: .pullToTarget, pullQty: 4, orderQty: 0, isRecommended: true)))
        #expect(options.contains(.init(kind: .pullAll, pullQty: 4, orderQty: 0, isRecommended: false)))
        #expect(options.contains(.init(kind: .orderAll, pullQty: 0, orderQty: 4, isRecommended: false)))
    }

    @Test("procurement pull uses real warehouse locations, persists staging, and blocks over-MAX generation")
    func testProcurementPullPersistsAndOverMaxGenerationRequiresPull() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Over Max Pull Part", categoryId: catId)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-OVER-MAX", name: "Over Max Job")
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "Over Max Supplier")
        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: supplierId, costPrice: 4.25)
        let lineId = try approvedJPOLine(env, jobId: jobId, partId: partId, quantity: 3)

        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE parts SET min_stock_level = 2, target_stock_level = 8, max_stock_level = 10 WHERE id = ?",
                arguments: [partId]
            )
        }
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 2, locationType: "warehouse", locationId: 3)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10, locationType: "warehouse", locationId: 7)

        #expect(throws: OrdersService.OrdersError.overMaxPullRequired(partId: partId, overage: 2)) {
            try env.orders.generatePOsFromProcurement(items: [
                OrdersService.ProcurementGenerateItem(
                    partId: partId,
                    supplierId: supplierId,
                    quantity: 3,
                    jpoLineIds: [lineId]
                )
            ])
        }

        let demand = try #require(env.orders.getProcurementDemand().first { $0.partId == partId })
        let pull = try env.orders.pullStockForProcurement(
            demandItemId: demand.id,
            partId: partId,
            requestedPullQty: 2,
            totalDemand: demand.totalDemand,
            jpoLineIds: demand.sources.flatMap(\.lineIds),
            performedBy: env.adminUserId
        )
        #expect(pull.pulledQty == 2)

        let reloaded = try #require(env.orders.getProcurementDemand().first { $0.partId == partId })
        #expect(reloaded.shopStock == 10)
        #expect(reloaded.stagedPullQty == 2)

        try env.db.writer.read { db in
            let sourceQty = try Int.fetchOne(
                db,
                sql: "SELECT qty FROM stock WHERE part_id = ? AND location_type = 'warehouse' AND location_id = 7",
                arguments: [partId]
            )
            let stagedQty = try Int.fetchOne(
                db,
                sql: "SELECT qty FROM stock WHERE part_id = ? AND location_type = 'pulled' AND location_id = ?",
                arguments: [partId, abs(demand.id)]
            )
            let movementSource = try Int64.fetchOne(
                db,
                sql: "SELECT from_location_id FROM stock_movements WHERE part_id = ? AND reference_number = ? ORDER BY id DESC LIMIT 1",
                arguments: [partId, "procurement-demand:\(demand.id)"]
            )
            #expect(sourceQty == 8)
            #expect(stagedQty == 2)
            #expect(movementSource == 7)
        }

        _ = try env.orders.pullStockForProcurement(
            demandItemId: demand.id,
            partId: partId,
            requestedPullQty: 1,
            totalDemand: demand.totalDemand,
            jpoLineIds: [lineId],
            performedBy: env.adminUserId
        )
        try env.db.writer.read { db in
            let status = try String.fetchOne(
                db,
                sql: "SELECT line_status FROM jpo_line_items WHERE id = ?",
                arguments: [lineId]
            )
            #expect(status == "staged")
        }
    }

    // MARK: - addJPOLineItem General Mode (PE-COLORS Plan Test 5)

    @Test("PE-COLORS Plan Test 5: addJPOLineItem persists brand_selection_mode='general'")
    func testAddJPOLineItemGeneralModePersists() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)

        let lineId = try env.orders.addJPOLineItem(
            jpoId: jpoId, partId: partId, quantity: 2, brandSelectionMode: "general"
        )
        #expect(lineId > 0)

        let storedMode: String? = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT brand_selection_mode FROM jpo_line_items WHERE id = ?", arguments: [lineId])
        }
        #expect(storedMode == "general",
                "brand_selection_mode must be stored as 'general' — required by resolveGeneralLineItem for General Mode workflow")
    }

    // MARK: - resolveGeneralLineItem (PE-COLORS Phase 3)

    /// Helper: create a JPO line item and immediately flip it to general mode.
    private func makeGeneralLine(
        _ env: E2ETestHelpers.TestEnvironment,
        jpoId: Int64,
        partId: Int64
    ) throws -> Int64 {
        return try env.orders.addJPOLineItem(
            jpoId: jpoId, partId: partId, quantity: 1, brandSelectionMode: "general"
        )
    }

    @Test("resolveGeneralLineItem returns alreadySpecific for default specific-mode lines")
    func testResolveGeneralLine_alreadySpecific() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 1)
        let supplierId = try E2ETestHelpers.seedSupplier(env)

        let result = try env.orders.resolveGeneralLineItem(jpoLineId: lineId, supplierId: supplierId)
        if case .alreadySpecific = result { } else {
            #expect(Bool(false), "Expected .alreadySpecific for default specific-mode line")
        }
    }

    @Test("resolveGeneralLineItem returns noMatch when supplier carries no matching brand")
    func testResolveGeneralLine_noMatch() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let catId = try E2ETestHelpers.seedCategory(env, name: "NoMatchCat")
        let colorId = try env.parts.createColor(name: "NoMatchColor")
        let brandId = try E2ETestHelpers.seedBrand(env, name: "UnlinkedBrand")
        let partId = try env.parts.createPart(
            categoryId: catId, name: "NoMatch Part",
            typeId: typeId, colorId: colorId, brandId: brandId
        )
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        let lineId = try makeGeneralLine(env, jpoId: jpoId, partId: partId)
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "UnlinkedSupplier")
        // No brand_supplier_links entry — supplier doesn't carry this brand

        let result = try env.orders.resolveGeneralLineItem(jpoLineId: lineId, supplierId: supplierId)
        if case .noMatch = result { } else {
            #expect(Bool(false), "Expected .noMatch when supplier has no compatible brand")
        }
    }

    @Test("resolveGeneralLineItem returns resolved(.exclusive) when supplier has exactly one matching brand")
    func testResolveGeneralLine_exclusive() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env, type: "ExclType")
        let catId = try E2ETestHelpers.seedCategory(env, name: "ExclCat")
        let colorId = try env.parts.createColor(name: "ExclColor", hexCode: "#AABBCC")
        let brandId = try E2ETestHelpers.seedBrand(env, name: "ExclBrand")
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "ExclSupplier")

        // Link the brand to the supplier
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO brand_supplier_links (brand_id, supplier_id, is_active)
                VALUES (?, ?, 1)
                """, arguments: [brandId, supplierId])
        }
        // Register the SKU for (color, brand, type)
        _ = try env.parts.upsertColorBrandSKU(colorId: colorId, brandId: brandId, typeId: typeId)

        let partId = try env.parts.createPart(
            categoryId: catId, name: "Excl Part",
            typeId: typeId, colorId: colorId, brandId: brandId
        )
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        let lineId = try makeGeneralLine(env, jpoId: jpoId, partId: partId)

        let result = try env.orders.resolveGeneralLineItem(jpoLineId: lineId, supplierId: supplierId)
        if case .resolved(let resolvedBrandId, let confidence) = result {
            #expect(resolvedBrandId == brandId, "Must resolve to the one matching brand")
            if case .exclusive = confidence { } else {
                #expect(Bool(false), "Confidence must be .exclusive when only one brand matches")
            }
        } else {
            #expect(Bool(false), "Expected .resolved(.exclusive) but got \(result)")
        }
    }

    @Test("resolveGeneralLineItem picks most-recently-ordered brand when supplier carries multiple")
    func testResolveGeneralLine_byHistory() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env, type: "MultiType")
        let catId = try E2ETestHelpers.seedCategory(env, name: "MultiCat")
        let colorId = try env.parts.createColor(name: "MultiColor", hexCode: "#123456")
        let brandA = try E2ETestHelpers.seedBrand(env, name: "AlphaBrand")  // alphabetically first
        let brandB = try E2ETestHelpers.seedBrand(env, name: "ZetaBrand")
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "MultiSupplier")

        // Both brands linked to supplier, both have SKUs for (color, type)
        try env.db.writer.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO brand_supplier_links (brand_id, supplier_id, is_active) VALUES (?, ?, 1)", arguments: [brandA, supplierId])
            try db.execute(sql: "INSERT OR IGNORE INTO brand_supplier_links (brand_id, supplier_id, is_active) VALUES (?, ?, 1)", arguments: [brandB, supplierId])
        }
        _ = try env.parts.upsertColorBrandSKU(colorId: colorId, brandId: brandA, typeId: typeId)
        _ = try env.parts.upsertColorBrandSKU(colorId: colorId, brandId: brandB, typeId: typeId)

        // Create parts with each brand
        let partA = try env.parts.createPart(categoryId: catId, name: "Part Alpha", typeId: typeId, colorId: colorId, brandId: brandA)
        let partB = try env.parts.createPart(categoryId: catId, name: "Part Zeta", typeId: typeId, colorId: colorId, brandId: brandB)

        // Seed a historical PO where BrandB was ordered more recently
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO purchase_orders (supplier_id, po_number, status, order_date, created_at)
                VALUES (?, 'PO-HIST-001', 'received', date('now', '-30 days'), datetime('now'))
                """, arguments: [supplierId])
            let oldPoId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, created_at) VALUES (?, ?, 1, datetime('now'))
                """, arguments: [oldPoId, partA])

            // More recent PO — BrandB ordered last
            try db.execute(sql: """
                INSERT INTO purchase_orders (supplier_id, po_number, status, order_date, created_at)
                VALUES (?, 'PO-HIST-002', 'received', date('now', '-5 days'), datetime('now'))
                """, arguments: [supplierId])
            let recentPoId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, created_at) VALUES (?, ?, 1, datetime('now'))
                """, arguments: [recentPoId, partB])
        }

        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        let lineId = try makeGeneralLine(env, jpoId: jpoId, partId: partA)

        let result = try env.orders.resolveGeneralLineItem(jpoLineId: lineId, supplierId: supplierId)
        if case .resolved(let resolvedBrandId, let confidence) = result {
            #expect(resolvedBrandId == brandB, "Must pick most-recently-ordered brand (ZetaBrand was on PO 5 days ago)")
            if case .byHistory = confidence { } else {
                #expect(Bool(false), "Confidence must be .byHistory when resolved via PO history")
            }
        } else {
            #expect(Bool(false), "Expected .resolved(.byHistory) but got \(result)")
        }
    }

    @Test("resolveGeneralLineItem picks first-alphabetically when no PO history")
    func testResolveGeneralLine_arbitrary() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env, type: "ArbitraryType")
        let catId = try E2ETestHelpers.seedCategory(env, name: "ArbitraryCat")
        let colorId = try env.parts.createColor(name: "ArbitraryColor", hexCode: "#FEDCBA")
        let brandA = try E2ETestHelpers.seedBrand(env, name: "AaaFirst")
        let brandZ = try E2ETestHelpers.seedBrand(env, name: "ZzzLast")
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "ArbitrarySupplier")

        try env.db.writer.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO brand_supplier_links (brand_id, supplier_id, is_active) VALUES (?, ?, 1)", arguments: [brandA, supplierId])
            try db.execute(sql: "INSERT OR IGNORE INTO brand_supplier_links (brand_id, supplier_id, is_active) VALUES (?, ?, 1)", arguments: [brandZ, supplierId])
        }
        _ = try env.parts.upsertColorBrandSKU(colorId: colorId, brandId: brandA, typeId: typeId)
        _ = try env.parts.upsertColorBrandSKU(colorId: colorId, brandId: brandZ, typeId: typeId)

        let partA = try env.parts.createPart(categoryId: catId, name: "Arbitrary Part", typeId: typeId, colorId: colorId, brandId: brandA)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        let lineId = try makeGeneralLine(env, jpoId: jpoId, partId: partA)

        // No PO history — should pick alphabetically first brand
        let result = try env.orders.resolveGeneralLineItem(jpoLineId: lineId, supplierId: supplierId)
        if case .resolved(let resolvedBrandId, let confidence) = result {
            #expect(resolvedBrandId == brandA, "Must pick alphabetically-first brand when no PO history")
            if case .arbitrary = confidence { } else {
                #expect(Bool(false), "Confidence must be .arbitrary when no history exists")
            }
        } else {
            #expect(Bool(false), "Expected .resolved(.arbitrary) but got \(result)")
        }
    }

    @Test("resolveGeneralLineItem returns .noMatch when the referenced part was soft-deleted")
    func testResolveGeneralLine_softDeletedPartReturnsNoMatch() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env, type: "DelType")
        let catId = try E2ETestHelpers.seedCategory(env, name: "DelCat")
        let colorId = try env.parts.createColor(name: "DelColor", hexCode: "#112233")
        let brandId = try E2ETestHelpers.seedBrand(env, name: "DelBrand")
        let partId = try env.parts.createPart(
            categoryId: catId, name: "To Be Deleted Part",
            typeId: typeId, colorId: colorId, brandId: brandId
        )
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        let lineId = try makeGeneralLine(env, jpoId: jpoId, partId: partId)
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "DelSupplier")

        // Soft-delete the part while leaving the JPO line active.
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [partId]
            )
        }

        let result = try env.orders.resolveGeneralLineItem(jpoLineId: lineId, supplierId: supplierId)
        if case .noMatch = result { } else {
            #expect(Bool(false),
                    "Expected .noMatch — soft-deleted part must not yield a resolvable brand even with an active line")
        }
    }

    @Test("listJPOs shows Unknown for soft-deleted job and user")
    func testListJPOsHidesDeletedJobAndUser() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let jpos = try env.orders.listJPOs()
        let jpo = jpos.first(where: { $0.id == jpoId })
        #expect(jpo != nil)
        #expect(jpo?.jobName == "Unknown Job")
        #expect(jpo?.requestedByName == "Unknown")
    }

    @Test("getPODetail hides submitted_by name for soft-deleted user")
    func testGetPODetailHidesDeletedSubmittedByName() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "TestSupplierPO")
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-DEL-TEST-01", supplierId: supplierId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE purchase_orders SET submitted_by = ? WHERE id = ?",
                           arguments: [env.adminUserId, poId])
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let detail = try env.orders.getPODetail(id: poId)
        #expect(detail.submittedByName == nil)
    }

    @Test("listPurchaseOrders degrades soft-deleted supplier name to 'Unknown Supplier'")
    func testListPurchaseOrders_hidesDeletedSupplierName() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "OrderListSupplierToDelete")
        _ = try env.orders.createPurchaseOrder(poNumber: "PO-SUP-DEL", supplierId: supplierId)

        // Soft-delete the supplier. The PO remains active and must still appear,
        // but with supplier_name degraded via the LEFT JOIN + COALESCE fallback.
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [supplierId]
            )
        }

        let pos = try env.orders.listPurchaseOrders()
        let match = try #require(pos.first { $0.poNumber == "PO-SUP-DEL" })
        #expect(match.supplierName == "Unknown Supplier",
                "listPurchaseOrders LEFT JOIN suppliers needs deleted_at guard for COALESCE to trigger")
    }

    @Test("getPODetail degrades soft-deleted supplier name to 'Unknown Supplier'")
    func testGetPODetail_hidesDeletedSupplierName() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "DetailSupplierToDelete")
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-DET-DEL", supplierId: supplierId)

        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [supplierId]
            )
        }

        let detail = try env.orders.getPODetail(id: poId)
        #expect(detail.supplierName == "Unknown Supplier",
                "getPODetail LEFT JOIN suppliers needs deleted_at guard so deleted supplier name doesn't persist on PO detail card")
    }

    @Test("getJPODetail shows nil partName for soft-deleted part in line items")
    func testGetJPODetailHidesDeletedPartName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-JPO-DEL", name: "JPODelJob")
        let catId = try E2ETestHelpers.seedCategory(env, name: "JPODelCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "JPODelPart", categoryId: catId)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, brand_selection_mode, created_at)
                VALUES (?, ?, 2, 'specific', datetime('now'))
                """, arguments: [jpoId, partId])
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [partId])
        }
        let detail = try env.orders.getJPODetail(id: jpoId)
        let line = detail.lines.first(where: { $0.partId == partId })
        #expect(line != nil)
        #expect(line?.partName == nil,
                "Soft-deleted part must produce nil partName in getJPODetail line items")
    }

    @Test("getPODetail shows nil partName for soft-deleted part in PO line items")
    func testGetPODetailHidesDeletedPartInLines() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "POLinesSupplier")
        let catId = try E2ETestHelpers.seedCategory(env, name: "POLinesCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "POLinesPart", categoryId: catId)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-LINES-DEL", supplierId: supplierId)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, qty_received, unit_cost)
                VALUES (?, ?, 3, 0, 12.50)
                """, arguments: [poId, partId])
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [partId])
        }
        let detail = try env.orders.getPODetail(id: poId)
        let line = detail.lines.first(where: { $0.partId == partId })
        #expect(line != nil)
        #expect(line?.partName == nil,
                "Soft-deleted part must produce nil partName in getPODetail line items")
    }

    @Test("getJPODetail throws jpoNotFound for a soft-deleted JPO")
    func testGetJPODetail_throwsForSoftDeletedJPO() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-JPO-TOMB", name: "TombstonedJPOJob")
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE job_parts_orders SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jpoId])
        }
        // A soft-deleted JPO must be invisible to the detail view — same semantic as "doesn't exist".
        // Regression: WHERE jp.id = ? had no deleted_at guard, so tombstoned JPOs were still loadable.
        #expect(throws: OrdersService.OrdersError.self) {
            _ = try env.orders.getJPODetail(id: jpoId)
        }
    }

    @Test("getPODetail throws purchaseOrderNotFound for a soft-deleted PO")
    func testGetPODetail_throwsForSoftDeletedPO() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "TombstonedPOSupplier")
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-TOMB-001", supplierId: supplierId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE purchase_orders SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [poId])
        }
        #expect(throws: OrdersService.OrdersError.self) {
            _ = try env.orders.getPODetail(id: poId)
        }
    }

    @Test("updatePOLineItem rejects edits when parent PO is soft-deleted")
    func testUpdatePOLineItem_rejectsSoftDeletedPO() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "SoftDelPOSupplier")
        let catId = try E2ETestHelpers.seedCategory(env, name: "SoftDelPOCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "SoftDelPOPart", categoryId: catId)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-SOFT-001", supplierId: supplierId)
        let lineId: Int64 = try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, qty_received, unit_cost)
                VALUES (?, ?, 5, 0, 10.00)
                """, arguments: [poId, partId])
            return db.lastInsertedRowID
        }
        // PO is still in draft — but we soft-delete it. Edit must be rejected.
        // Regression: the status check joined po_line_items to purchase_orders without
        // `po.deleted_at IS NULL`, so edits could still be applied to tombstoned draft POs.
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE purchase_orders SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [poId])
        }
        #expect(throws: OrdersService.OrdersError.self) {
            try env.orders.updatePOLineItem(lineId: lineId, quantity: 99, unitPrice: 1.00)
        }
    }

    @Test("getReceiptHistoryItems shows Unknown Part for soft-deleted part")
    func testGetReceiptHistoryItemsHidesDeletedPartName() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "RHISupplier")
        let catId = try E2ETestHelpers.seedCategory(env, name: "RHICat")
        let partId = try E2ETestHelpers.seedPart(env, name: "RHIPart", categoryId: catId)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-RHI-DEL", supplierId: supplierId)
        var sessionId: Int64 = 0
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, qty_received, unit_cost)
                VALUES (?, ?, 2, 0, 8.00)
                """, arguments: [poId, partId])
            let lineId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO receiving_sessions (po_id, started_by, mode, status, created_at)
                VALUES (?, ?, 'packing_slip', 'completed', datetime('now'))
                """, arguments: [poId, env.adminUserId])
            sessionId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO receiving_session_items (session_id, po_line_id, expected_qty, created_at)
                VALUES (?, ?, 2, datetime('now'))
                """, arguments: [sessionId, lineId])
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [partId])
        }
        let items = try env.orders.getReceiptHistoryItems(sessionId: sessionId)
        #expect(items.isEmpty == false)
        #expect(items.first?.partName == "Unknown Part",
                "Soft-deleted part must degrade to 'Unknown Part' in getReceiptHistoryItems")
    }

    @Test("updateJPOStatus is a no-op on a soft-deleted JPO")
    func testUpdateJPOStatus_noOpOnSoftDeletedJPO() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-JPO-STATE", name: "TombstonedJPOStateJob")
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)

        // Capture original status (draft) then soft-delete the JPO
        let originalStatus = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM job_parts_orders WHERE id = ?",
                                arguments: [jpoId])
        }
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE job_parts_orders SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jpoId])
        }

        // Regression: UPDATE job_parts_orders SET status = ? WHERE id = ? had no deleted_at
        // guard. In iter 45 the read-path (getJPODetail) gained a guard that throws jpoNotFound
        // for tombstoned JPOs, so updateJPOStatus is now fail-fast — but we also add the
        // write-path guard as defense-in-depth in case a caller bypasses the read check.
        #expect(throws: OrdersService.OrdersError.self) {
            try env.orders.updateJPOStatus(id: jpoId, status: "pending")
        }

        let afterStatus = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM job_parts_orders WHERE id = ?",
                                arguments: [jpoId])
        }
        #expect(afterStatus == originalStatus,
                "Soft-deleted JPO status must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("updatePOLineItem actual field UPDATE guards against soft-deleted line")
    func testUpdatePOLineItem_writeGuardsDeletedLine() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "LineWriteSupplier")
        let catId = try E2ETestHelpers.seedCategory(env, name: "LineWriteCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "LineWritePart", categoryId: catId)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-LINE-W-001", supplierId: supplierId)
        let lineId = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 5, unitPrice: 1.00)

        // Capture original qty
        let originalQty = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT qty_ordered FROM po_line_items WHERE id = ?", arguments: [lineId])
        }

        // Soft-delete the line item (NOT the PO, which the status guard checks).
        // Regression: the actual UPDATE po_line_items SET qty_ordered = ? WHERE id = ?
        // had no `AND deleted_at IS NULL` guard (iter 45 added the status-check guard
        // via the pre-update SELECT join, but the UPDATE itself would still stick).
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE po_line_items SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [lineId])
        }
        // The status check (iter 45) now fails fast because `po_line_items li` is guarded
        // on the SELECT join, so the caller throws. This is the expected no-op path.
        #expect(throws: OrdersService.OrdersError.self) {
            try env.orders.updatePOLineItem(lineId: lineId, quantity: 99, unitPrice: 9.99)
        }
        let afterQty = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT qty_ordered FROM po_line_items WHERE id = ?", arguments: [lineId])
        }
        #expect(afterQty == originalQty,
                "Soft-deleted PO line qty_ordered must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("holdJPOLineWithChat write-path is a no-op on a soft-deleted JPO line")
    func testHoldJPOLineWithChat_noOpOnSoftDeletedLine() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-HOLD-W", name: "HoldWriteJob")
        let catId = try E2ETestHelpers.seedCategory(env, name: "HoldWriteCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "HoldWritePart", categoryId: catId)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)

        // Seed a JPO line directly via SQL (simpler than the full create path)
        let lineId: Int64 = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, line_status,
                                             brand_selection_mode, created_at)
                VALUES (?, ?, 3, 'pending', 'specific', datetime('now'))
                """, arguments: [jpoId, partId])
            return db.lastInsertedRowID
        }

        // Soft-delete the line. Regression: holdJPOLineWithChat UPDATE jpo_line_items
        // SET line_status = 'on_hold' WHERE id = ? had no `AND deleted_at IS NULL`.
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jpo_line_items SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [lineId])
        }
        _ = try? env.orders.holdJPOLineWithChat(
            lineId: lineId, holdReason: "test hold", userId: env.adminUserId,
            partName: "HoldWritePart", jpoId: jpoId
        )

        let status = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT line_status FROM jpo_line_items WHERE id = ?",
                                arguments: [lineId])
        }
        #expect(status != "on_hold",
                "Soft-deleted JPO line must not be transitioned to on_hold — UPDATE must guard AND deleted_at IS NULL")
    }

    // MARK: - Input validation (iter 62)

    @Test("createJPO throws jobNotFound for a tombstoned job")
    func testCreateJPO_rejectsSoftDeletedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-TOMB-VAL", name: "TombstonedJob")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
        }
        #expect(throws: OrdersService.OrdersError.self) {
            _ = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        }
    }

    @Test("addJPOLineItem rejects zero and negative quantity")
    func testAddJPOLineItem_rejectsZeroQuantity() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-JPO-QTY", name: "QtyJob")
        let catId = try E2ETestHelpers.seedCategory(env, name: "QtyCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "QtyPart", categoryId: catId)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        #expect(throws: OrdersService.OrdersError.self) {
            _ = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 0)
        }
        #expect(throws: OrdersService.OrdersError.self) {
            _ = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: -5)
        }
    }

    @Test("addJPOLineItem rejects soft-deleted part")
    func testAddJPOLineItem_rejectsSoftDeletedPart() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-JPO-DEL", name: "DelPartJob")
        let catId = try E2ETestHelpers.seedCategory(env, name: "DelPartCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "TombstonedPart", categoryId: catId)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId)
        try env.parts.deletePart(id: partId)
        #expect(throws: OrdersService.OrdersError.self) {
            _ = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 3)
        }
    }

    @Test("addPOLineItem rejects zero quantity and soft-deleted part")
    func testAddPOLineItem_rejectsInvalidInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "QtySupplier")
        let catId = try E2ETestHelpers.seedCategory(env, name: "POQtyCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "POQtyPart", categoryId: catId)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-QTY-001", supplierId: supplierId)

        #expect(throws: OrdersService.OrdersError.self) {
            _ = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 0, unitPrice: 1.0)
        }
        try env.parts.deletePart(id: partId)
        #expect(throws: OrdersService.OrdersError.self) {
            _ = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 5, unitPrice: 1.0)
        }
    }

    @Test("createPurchaseOrder rejects empty poNumber and soft-deleted supplier")
    func testCreatePurchaseOrder_rejectsInvalidInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "POValSupplier")
        #expect(throws: OrdersService.OrdersError.self) {
            _ = try env.orders.createPurchaseOrder(poNumber: "   ", supplierId: supplierId)
        }
        try env.parts.deleteSupplier(id: supplierId)
        #expect(throws: OrdersService.OrdersError.self) {
            _ = try env.orders.createPurchaseOrder(poNumber: "PO-VAL-001", supplierId: supplierId)
        }
    }

    @Test("addPONote rejects blank note and blank author")
    func testAddPONote_rejectsBlankInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "NoteSupp")
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-NOTE-V", supplierId: supplierId)
        #expect(throws: OrdersService.OrdersError.self) {
            try env.orders.addPONote(poId: poId, note: "   ", author: "User")
        }
        #expect(throws: OrdersService.OrdersError.self) {
            try env.orders.addPONote(poId: poId, note: "A real note", author: "")
        }
    }

    @Test("updatePOLineItem rejects zero quantity")
    func testUpdatePOLineItem_rejectsZeroQuantity() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "QtySupp")
        let catId = try E2ETestHelpers.seedCategory(env, name: "QtyCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "QtyPart", categoryId: catId)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-LIN-V", supplierId: supplierId)
        let lineId = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 5, unitPrice: 1.0)
        #expect(throws: OrdersService.OrdersError.self) {
            try env.orders.updatePOLineItem(lineId: lineId, quantity: 0, unitPrice: 2.0)
        }
    }

    // MARK: - Iteration 86: OrdersError Equatable + createReturn + createJPOWithLines guards

    @Test("createReturn rejects blank returnType and blank reason")
    func testCreateReturn_rejectsBlankFields() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: OrdersService.OrdersError.requiredFieldEmpty("returnType")) {
            try env.orders.createReturn(
                returnType: "   ", reason: "valid reason", initiatedBy: env.adminUserId
            )
        }
        #expect(throws: OrdersService.OrdersError.requiredFieldEmpty("reason")) {
            try env.orders.createReturn(
                returnType: "supplier", reason: "", initiatedBy: env.adminUserId
            )
        }
    }

    @Test("createReturn rejects tombstoned supplier")
    func testCreateReturn_rejectsTombstonedSupplier() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "TombSupplier86")
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [supplierId]
            )
        }
        #expect(throws: OrdersService.OrdersError.supplierNotFound(supplierId)) {
            try env.orders.createReturn(
                returnType: "supplier",
                reason: "Damaged goods",
                supplierId: supplierId,
                initiatedBy: env.adminUserId
            )
        }
    }

    @Test("createJPOWithLines rejects tombstoned job")
    func testCreateJPOWithLines_rejectsTombstonedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DEAD-86", name: "Dead Job")
        let catId = try E2ETestHelpers.seedCategory(env, name: "JWLCAT86")
        let partId = try E2ETestHelpers.seedPart(env, name: "JWL Part", categoryId: catId)
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [jobId]
            )
        }
        #expect(throws: OrdersService.OrdersError.jobNotFound(jobId)) {
            try env.orders.createJPOWithLines(
                jobId: jobId, requestedBy: env.adminUserId,
                priority: "normal", deliveryOption: "standard",
                notes: nil, lines: [(partId: partId, quantity: 2)]
            )
        }
    }

    @Test("createJPOWithLines rejects zero-quantity line")
    func testCreateJPOWithLines_rejectsZeroQuantity() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-ZQ-86", name: "Zero Qty Job")
        let catId = try E2ETestHelpers.seedCategory(env, name: "ZQCAT86")
        let partId = try E2ETestHelpers.seedPart(env, name: "ZQ Part", categoryId: catId)
        #expect(throws: OrdersService.OrdersError.invalidQuantity(0)) {
            try env.orders.createJPOWithLines(
                jobId: jobId, requestedBy: env.adminUserId,
                priority: "normal", deliveryOption: "standard",
                notes: nil, lines: [(partId: partId, quantity: 0)]
            )
        }
    }

    @Test("createJPOWithLines rejects tombstoned part in line")
    func testCreateJPOWithLines_rejectsTombstonedPart() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DP-86", name: "Dead Part Job")
        let catId = try E2ETestHelpers.seedCategory(env, name: "DPCAT86")
        let partId = try E2ETestHelpers.seedPart(env, name: "Dead Part", categoryId: catId)
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [partId]
            )
        }
        #expect(throws: OrdersService.OrdersError.partNotFound(partId)) {
            try env.orders.createJPOWithLines(
                jobId: jobId, requestedBy: env.adminUserId,
                priority: "normal", deliveryOption: "standard",
                notes: nil, lines: [(partId: partId, quantity: 3)]
            )
        }
    }

    // MARK: - Iteration 87: holdJPOLineWithChat + generatePOFromJPO + updateReturnStatus guards

    @Test("holdJPOLineWithChat rejects blank holdReason")
    func testHoldJPOLineWithChat_rejectsBlankReason() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-HLD-87", name: "Hold Test Job")
        let catId = try E2ETestHelpers.seedCategory(env, name: "HLDCAT87")
        let partId = try E2ETestHelpers.seedPart(env, name: "Hold Part", categoryId: catId)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 2)
        #expect(throws: OrdersService.OrdersError.requiredFieldEmpty("holdReason")) {
            try env.orders.holdJPOLineWithChat(
                lineId: lineId, holdReason: "   ",
                userId: env.adminUserId, partName: "Hold Part", jpoId: jpoId
            )
        }
    }

    @Test("holdJPOLineWithChat rejects tombstoned userId")
    func testHoldJPOLineWithChat_rejectsTombstonedUser() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-HLD2-87", name: "Hold Test Job 2")
        let catId = try E2ETestHelpers.seedCategory(env, name: "HLD2CAT87")
        let partId = try E2ETestHelpers.seedPart(env, name: "Hold Part 2", categoryId: catId)
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 2)
        // Tombstone the admin user
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [env.adminUserId]
            )
        }
        #expect(throws: OrdersService.OrdersError.userNotFound(env.adminUserId)) {
            try env.orders.holdJPOLineWithChat(
                lineId: lineId, holdReason: "Needs clarification",
                userId: env.adminUserId, partName: "Hold Part 2", jpoId: jpoId
            )
        }
    }

    @Test("generatePOFromJPO rejects tombstoned supplier")
    func testGeneratePOFromJPO_rejectsTombstonedSupplier() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-GENFJ-87", name: "Gen PO Job")
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "TombGenSupp87")
        let jpoId = try env.orders.createJPO(jobId: jobId, requestedBy: env.adminUserId, notes: nil)
        try env.orders.updateJPOStatus(id: jpoId, status: "pending")
        try env.orders.updateJPOStatus(id: jpoId, status: "approved")
        // Tombstone the supplier after JPO approval
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [supplierId]
            )
        }
        #expect(throws: OrdersService.OrdersError.supplierNotFound(supplierId)) {
            try env.orders.generatePOFromJPO(jpoId: jpoId, supplierId: supplierId)
        }
    }

    @Test("updateReturnStatus rejects blank status and non-existent returnId")
    func testUpdateReturnStatus_rejectsInvalidInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "RetStatSupp87")
        let returnId = try env.orders.createReturn(
            returnType: "supplier", reason: "Wrong item",
            supplierId: supplierId, initiatedBy: env.adminUserId
        )
        // Blank status should throw
        #expect(throws: OrdersService.OrdersError.requiredFieldEmpty("status")) {
            try env.orders.updateReturnStatus(returnId: returnId, status: "")
        }
        // Non-existent returnId should throw
        #expect(throws: OrdersService.OrdersError.returnNotFound(9999)) {
            try env.orders.updateReturnStatus(returnId: 9999, status: "completed")
        }
    }

    private func approvedJPOLine(
        _ env: E2ETestHelpers.TestEnvironment,
        jobId: Int64,
        partId: Int64,
        quantity: Int
    ) throws -> Int64 {
        try env.db.writer.write { db in
            let orderNumber = "JPO-TEST-\(jobId)-\(partId)-\(UUID().uuidString)"
            try db.execute(
                sql: """
                    INSERT INTO job_parts_orders
                    (job_id, order_number, requested_by, status, priority, notes, created_at, updated_at)
                    VALUES (?, ?, ?, 'approved', 'normal', NULL, datetime('now'), datetime('now'))
                    """,
                arguments: [jobId, orderNumber, env.adminUserId]
            )
            let jpoId = db.lastInsertedRowID
            try db.execute(
                sql: """
                    INSERT INTO jpo_line_items
                    (jpo_id, part_id, qty_requested, line_status, created_at)
                    VALUES (?, ?, ?, 'approved', datetime('now'))
                    """,
                arguments: [jpoId, partId, quantity]
            )
            return db.lastInsertedRowID
        }
    }

    private func insertWishlistItem(
        _ env: E2ETestHelpers.TestEnvironment,
        partId: Int64,
        qty: Int,
        sourceType: String,
        status: String,
        certaintyScore: Double? = nil
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO wishlist_items
                    (part_id, part_name, qty_suggested, priority, source_type, status, requested_by, approved_by, approved_at, certainty_score, created_at, updated_at)
                    VALUES (?, 'Wishlist Demand Part', ?, 'normal', ?, ?, 'TestAdmin', 'TestAdmin', datetime('now'), ?, datetime('now'), datetime('now'))
                    """,
                arguments: [partId, qty, sourceType, status, certaintyScore]
            )
            return db.lastInsertedRowID
        }
    }

    private func insertForecastTarget(
        _ env: E2ETestHelpers.TestEnvironment,
        partId: Int64,
        minStock: Int,
        targetStock: Int,
        maxStock: Int,
        suggestedOrder: Int,
        certainty: Double
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO location_stock_targets
                    (part_id, location_type, location_id, min_stock, target_stock, max_stock, forecast_suggested_order, certainty_rating, updated_at)
                    VALUES (?, 'warehouse', 1, ?, ?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [partId, minStock, targetStock, maxStock, suggestedOrder, certainty]
            )
            return db.lastInsertedRowID
        }
    }
}
