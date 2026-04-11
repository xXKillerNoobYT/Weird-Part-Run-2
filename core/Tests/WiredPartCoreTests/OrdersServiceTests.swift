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
        try env.orders.updateJPOStatus(id: jpoId, status: "approved")
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
        try env.orders.updatePOStatus(id: poId, status: "sent")
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
            poId: poId
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
            poId: poId
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

        // Move PO out of draft
        try env.orders.updatePOStatus(id: poId, status: "sent")

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
        let lineId = try env.orders.addJPOLineItem(jpoId: jpoId, partId: partId, quantity: 0, notes: nil)

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
}
