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
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

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
}
