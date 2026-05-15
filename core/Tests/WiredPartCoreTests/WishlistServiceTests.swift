import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("WishlistService Tests")
struct WishlistServiceTests {

    private func freshEnv() throws -> (E2ETestHelpers.TestEnvironment, WishlistService) {
        let env = try E2ETestHelpers.setUp()
        let wishlist = WishlistService(db: env.db, auth: env.auth)
        return (env, wishlist)
    }

    // MARK: - CRUD

    @Test("Add and list wishlist items")
    func testAddAndList() throws {
        let (_, wishlist) = try freshEnv()

        let item = try wishlist.addItem(
            partName: "12 AWG THHN Red",
            qtySuggested: 500,
            reason: "Running low on job site",
            priority: "high",
            sourceType: "manual",
            requestedBy: "Field Team"
        )
        #expect(item.partName == "12 AWG THHN Red")
        #expect(item.qtySuggested == 500)
        #expect(item.priority == "high")

        let items = try wishlist.listItems()
        #expect(items.count == 1)
    }

    @Test("Get item by ID")
    func testGetItem() throws {
        let (_, wishlist) = try freshEnv()

        let created = try wishlist.addItem(partName: "Conduit 3/4")
        let fetched = try wishlist.getItem(id: created.id!)
        #expect(fetched?.partName == "Conduit 3/4")
    }

    @Test("Update wishlist item")
    func testUpdateItem() throws {
        let (_, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "Old Name", qtySuggested: 10)
        let updated = try wishlist.updateItem(id: item.id!, partName: "New Name", qtySuggested: 20)
        #expect(updated.partName == "New Name")
        #expect(updated.qtySuggested == 20)
    }

    @Test("Delete wishlist item")
    func testDeleteItem() throws {
        let (_, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "To Delete")
        try wishlist.deleteItem(id: item.id!)

        let fetched = try wishlist.getItem(id: item.id!)
        #expect(fetched == nil)
    }

    // MARK: - Status Workflow

    @Test("Approve item changes status")
    func testApproveItem() throws {
        let (env, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "Needs Approval")
        let approved = try wishlist.approveItem(id: item.id!, byUserId: env.adminUserId)
        #expect(approved.status == "approved")
    }

    @Test("Dismiss item changes status")
    func testDismissItem() throws {
        let (env, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "Not Needed")
        let dismissed = try wishlist.dismissItem(id: item.id!, byUserId: env.adminUserId, reason: "No longer needed for this project")
        #expect(dismissed.status == "dismissed")
    }

    @Test("Send to procurement changes status")
    func testSendToProcurement() throws {
        let (env, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "Ready to Order")
        let approved = try wishlist.approveItem(id: item.id!, byUserId: env.adminUserId)
        let sent = try wishlist.sendToProcurement(id: approved.id!, byUserId: env.adminUserId)
        #expect(sent.status == "sent_to_procurement")
    }

    @Test("Reopen dismissed item")
    func testReopenItem() throws {
        let (env, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "Reopen Me")
        _ = try wishlist.dismissItem(id: item.id!, byUserId: env.adminUserId, reason: "Duplicate item in inventory")
        let reopened = try wishlist.reopenItem(id: item.id!, byUserId: env.adminUserId)
        #expect(reopened.status == "pending")
    }

    // MARK: - Status Counts

    @Test("Status counts reflect actual data")
    func testStatusCounts() throws {
        let (env, wishlist) = try freshEnv()

        _ = try wishlist.addItem(partName: "Pending 1")
        _ = try wishlist.addItem(partName: "Pending 2")
        let item3 = try wishlist.addItem(partName: "To Approve")
        _ = try wishlist.approveItem(id: item3.id!, byUserId: env.adminUserId)

        let counts = try wishlist.getStatusCounts()
        #expect(counts.pending == 2)
        #expect(counts.approved == 1)
    }

    // MARK: - Filters

    @Test("List items with status filter")
    func testListWithFilter() throws {
        let (env, wishlist) = try freshEnv()

        _ = try wishlist.addItem(partName: "Pending Item")
        let approved = try wishlist.addItem(partName: "Approved Item")
        _ = try wishlist.approveItem(id: approved.id!, byUserId: env.adminUserId)

        let pendingOnly = try wishlist.listItems(status: "pending")
        #expect(pendingOnly.count == 1)
        #expect(pendingOnly[0].partName == "Pending Item")

        let approvedOnly = try wishlist.listItems(status: "approved")
        #expect(approvedOnly.count == 1)
    }

    // MARK: - Auto-Approve & Sections (PE-033)

    @Test("Manual item gets autoApproveAt set to ~14 days from now")
    func testAutoApproveAtSetOnManualCreate() throws {
        let (_, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "Manual Wire", sourceType: "manual")
        #expect(item.autoApproveAt != nil)

        // Parse and verify it's approximately 14 days in the future (±30 seconds tolerance)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let autoDate = formatter.date(from: item.autoApproveAt!)!
        let expected = Date().addingTimeInterval(14 * 24 * 3600)
        let diff = abs(autoDate.timeIntervalSince(expected))
        #expect(diff < 30, "autoApproveAt should be ~14 days from now, diff was \(diff)s")
    }

    @Test("Forecast item does not get autoApproveAt")
    func testForecastItemNoAutoApproveAt() throws {
        let (_, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "Forecast Wire", sourceType: "forecast", certaintyScore: 0.85)
        #expect(item.autoApproveAt == nil)
        #expect(item.certaintyScore == 0.85)
    }

    @Test("Dismiss requires a reason — empty throws error")
    func testDismissRequiresReason() throws {
        let (env, wishlist) = try freshEnv()
        let item = try wishlist.addItem(partName: "Test Item")

        #expect(throws: WishlistService.WishlistError.self) {
            try wishlist.dismissItem(id: item.id!, byUserId: env.adminUserId, reason: "")
        }

        #expect(throws: WishlistService.WishlistError.self) {
            try wishlist.dismissItem(id: item.id!, byUserId: env.adminUserId, reason: "   ")
        }
    }

    @Test("Dismiss with valid reason saves dismiss_reason")
    func testDismissWithReason() throws {
        let (env, wishlist) = try freshEnv()
        let item = try wishlist.addItem(partName: "Dismiss Me")
        let reason = "Already have plenty in stock at the main warehouse"

        let dismissed = try wishlist.dismissItem(id: item.id!, byUserId: env.adminUserId, reason: reason)
        #expect(dismissed.status == "dismissed")
        #expect(dismissed.dismissReason == reason)

        // Verify persisted
        let fetched = try wishlist.getItem(id: item.id!)
        #expect(fetched?.dismissReason == reason)
    }

    @Test("processAutoApprovals approves expired items, leaves unexpired")
    func testProcessAutoApprovals() throws {
        let (env, wishlist) = try freshEnv()

        // Create a manual item then manually backdate its auto_approve_at to the past
        let item = try wishlist.addItem(partName: "Should Auto-Approve", sourceType: "manual")
        let pastDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)) // 1 hour ago
        try env.db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE wishlist_items SET auto_approve_at = ? WHERE id = ?",
                arguments: [pastDate, item.id!]
            )
        }

        // Create another that's not yet expired
        _ = try wishlist.addItem(partName: "Not Yet Due", sourceType: "manual")

        let count = try wishlist.processAutoApprovals(byUserId: nil)
        #expect(count == 1)

        // Verify the backdated one is now approved
        let approved = try wishlist.getItem(id: item.id!)
        #expect(approved?.status == "approved")
        #expect(approved?.approvedBy == "System (Auto)")

        // The other should still be pending
        let allPending = try wishlist.listItems(status: "pending")
        #expect(allPending.count == 1)
        #expect(allPending[0].partName == "Not Yet Due")
    }

    @Test("getSectionedItems returns items in correct sections")
    func testGetSectionedItems() throws {
        let (_, wishlist) = try freshEnv()

        _ = try wishlist.addItem(partName: "Manual Part", sourceType: "manual")
        _ = try wishlist.addItem(partName: "Forecast Part", sourceType: "forecast", certaintyScore: 0.72)
        _ = try wishlist.addItem(partName: "System Part", sourceType: "system")

        let sections = try wishlist.getSectionedItems()
        #expect(sections.userAdded.count == 1)
        #expect(sections.userAdded[0].partName == "Manual Part")

        #expect(sections.forecastDemand.count == 1)
        #expect(sections.forecastDemand[0].partName == "Forecast Part")
        #expect(sections.forecastDemand[0].certaintyScore == 0.72)

        #expect(sections.autoAdded.count == 1)
        #expect(sections.autoAdded[0].partName == "System Part")
    }

    // MARK: - Edge Cases & Error Paths

    @Test("getItem returns nil for non-existent ID")
    func testGetItemNil() throws {
        let (_, wishlist) = try freshEnv()
        let item = try wishlist.getItem(id: 9999)
        #expect(item == nil)
    }

    @Test("approveItem throws itemNotFound for missing item")
    func testApproveItemNotFound() throws {
        let (env, wishlist) = try freshEnv()
        #expect(throws: WishlistService.WishlistError.itemNotFound(9999)) {
            try wishlist.approveItem(id: 9999, byUserId: env.adminUserId)
        }
    }

    @Test("approveItem throws alreadyProcessed when item is not pending")
    func testApproveItemAlreadyApproved() throws {
        let (env, wishlist) = try freshEnv()
        let item = try wishlist.addItem(partName: "Double-Approve Part", sourceType: "manual")
        _ = try wishlist.approveItem(id: item.id!, byUserId: env.adminUserId)
        // Approving again should throw alreadyProcessed with the item's id and current status
        #expect(throws: WishlistService.WishlistError.alreadyProcessed(item.id!, "approved")) {
            _ = try wishlist.approveItem(id: item.id!, byUserId: env.adminUserId)
        }
    }

    @Test("sendToProcurement throws invalidStatus when item is still pending")
    func testSendToProcurementNotApproved() throws {
        let (env, wishlist) = try freshEnv()
        let item = try wishlist.addItem(partName: "Pending Part", sourceType: "manual")
        // Item is pending — can't send to procurement yet
        #expect(throws: (any Error).self) {
            try wishlist.sendToProcurement(id: item.id!, byUserId: env.adminUserId)
        }
    }

    @Test("reopenItem throws invalidStatus when item is not dismissed")
    func testReopenItemNotDismissed() throws {
        let (env, wishlist) = try freshEnv()
        let item = try wishlist.addItem(partName: "Active Part", sourceType: "manual")
        // Item is pending — reopen should throw invalidStatus
        #expect(throws: (any Error).self) {
            try wishlist.reopenItem(id: item.id!, byUserId: env.adminUserId)
        }
    }

    @Test("deleteItem throws itemNotFound for non-existent ID")
    func testDeleteItemNotFound() throws {
        let (_, wishlist) = try freshEnv()
        #expect(throws: WishlistService.WishlistError.itemNotFound(9999)) {
            try wishlist.deleteItem(id: 9999)
        }
    }

    @Test("getSectionedItems with statusFilter only returns matching items")
    func testGetSectionedItemsWithFilter() throws {
        let (env, wishlist) = try freshEnv()
        _ = try wishlist.addItem(partName: "Pending Manual", sourceType: "manual")
        let approved = try wishlist.addItem(partName: "Approved Manual", sourceType: "manual")
        _ = try wishlist.approveItem(id: approved.id!, byUserId: env.adminUserId)

        // Filter to approved only — should not include pending item
        let sections = try wishlist.getSectionedItems(statusFilter: "approved")
        #expect(sections.userAdded.count == 1)
        #expect(sections.userAdded[0].partName == "Approved Manual")
    }

    // MARK: - Partial-Update / Perf (Issue #328)

    @Test("Rapid-fire approve sequence: each mutation returns the correct updated item without re-fetching sections")
    func testRapidFireApprovals() throws {
        let (env, wishlist) = try freshEnv()

        // Add 5 manual items
        var items: [WishlistItem] = []
        for i in 1...5 {
            items.append(try wishlist.addItem(partName: "RapidPart \(i)", sourceType: "manual"))
        }

        // Approve all 5 in rapid succession — each returned value must be immediately correct
        for item in items {
            let updated = try wishlist.approveItem(id: item.id!, byUserId: env.adminUserId)
            #expect(updated.status == "approved", "Returned item should be approved immediately")
            #expect(updated.id == item.id, "Returned item ID must match")
            #expect(updated.approvedBy != nil, "approvedBy should be populated")
        }

        // A single getSectionedItems call (simulating pull-to-refresh) should reflect all 5
        let sections = try wishlist.getSectionedItems()
        #expect(sections.userAdded.count == 5)
        #expect(sections.userAdded.allSatisfy { $0.status == "approved" })
    }

    @Test("Pull-to-refresh after mutations reflects latest state across all sections")
    func testPullToRefreshAfterMutations() throws {
        let (env, wishlist) = try freshEnv()

        let manual = try wishlist.addItem(partName: "Manual Part", sourceType: "manual")
        let forecast = try wishlist.addItem(partName: "Forecast Part", sourceType: "forecast", certaintyScore: 0.9)
        let system = try wishlist.addItem(partName: "System Part", sourceType: "system")

        // Mutate each item using the mutation return values (partial-update path)
        let approvedManual = try wishlist.approveItem(id: manual.id!, byUserId: env.adminUserId)
        #expect(approvedManual.status == "approved")

        let dismissedForecast = try wishlist.dismissItem(id: forecast.id!, byUserId: env.adminUserId, reason: "Not needed right now")
        #expect(dismissedForecast.status == "dismissed")

        let approvedSystem = try wishlist.approveItem(id: system.id!, byUserId: env.adminUserId)
        let sentSystem = try wishlist.sendToProcurement(id: approvedSystem.id!, byUserId: env.adminUserId)
        #expect(sentSystem.status == "sent_to_procurement")

        // Pull-to-refresh: getSectionedItems must return the authoritative post-mutation state
        let freshSections = try wishlist.getSectionedItems()
        let manualItem = freshSections.userAdded.first { $0.id == manual.id }
        let forecastItem = freshSections.forecastDemand.first { $0.id == forecast.id }
        let systemItem = freshSections.autoAdded.first { $0.id == system.id }

        #expect(manualItem?.status == "approved")
        #expect(forecastItem?.status == "dismissed")
        #expect(systemItem?.status == "sent_to_procurement")
    }

    // MARK: - Permission-Denied Tests

    @Test("approveItem throws insufficientPermissions for user without capability")
    func testApproveItemInsufficientPermissions() throws {
        let (env, wishlist) = try freshEnv()
        let unprivUserId = try env.auth.createUser(displayName: "Unprivileged User", pin: "5678")
        let item = try wishlist.addItem(partName: "Locked Item")
        #expect(throws: WishlistService.WishlistError.insufficientPermissions(required: "wishlist.approve")) {
            try wishlist.approveItem(id: item.id!, byUserId: unprivUserId)
        }
    }

    @Test("dismissItem throws insufficientPermissions for user without capability")
    func testDismissItemInsufficientPermissions() throws {
        let (env, wishlist) = try freshEnv()
        let unprivUserId = try env.auth.createUser(displayName: "Unprivileged User", pin: "5678")
        let item = try wishlist.addItem(partName: "Locked Item")
        #expect(throws: WishlistService.WishlistError.insufficientPermissions(required: "wishlist.dismiss")) {
            try wishlist.dismissItem(id: item.id!, byUserId: unprivUserId, reason: "Some reason")
        }
    }

    @Test("sendToProcurement throws insufficientPermissions for user without capability")
    func testSendToProcurementInsufficientPermissions() throws {
        let (env, wishlist) = try freshEnv()
        let unprivUserId = try env.auth.createUser(displayName: "Unprivileged User", pin: "5678")
        let item = try wishlist.addItem(partName: "Ready to Order")
        let approved = try wishlist.approveItem(id: item.id!, byUserId: env.adminUserId)
        #expect(throws: WishlistService.WishlistError.insufficientPermissions(required: "wishlist.send_to_procurement")) {
            try wishlist.sendToProcurement(id: approved.id!, byUserId: unprivUserId)
        }
    }

    @Test("reopenItem throws insufficientPermissions for user without capability")
    func testReopenItemInsufficientPermissions() throws {
        let (env, wishlist) = try freshEnv()
        let unprivUserId = try env.auth.createUser(displayName: "Unprivileged User", pin: "5678")
        let item = try wishlist.addItem(partName: "Dismissed Item")
        _ = try wishlist.dismissItem(id: item.id!, byUserId: env.adminUserId, reason: "Not needed")
        #expect(throws: WishlistService.WishlistError.insufficientPermissions(required: "wishlist.reopen")) {
            try wishlist.reopenItem(id: item.id!, byUserId: unprivUserId)
        }
    }

    @Test("processAutoApprovals succeeds for Owner (Admin) user")
    func testProcessAutoApprovalsAsOwnerSucceeds() throws {
        let (env, wishlist) = try freshEnv()

        // Backdate an item's auto_approve_at so it is expired
        let item = try wishlist.addItem(partName: "Auto-Approve Eligible", sourceType: "manual")
        let pastDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        try env.db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE wishlist_items SET auto_approve_at = ? WHERE id = ?",
                arguments: [pastDate, item.id!]
            )
        }

        // Admin user has wishlist.auto_approve — should succeed
        let count = try wishlist.processAutoApprovals(byUserId: env.adminUserId)
        #expect(count == 1)

        let approved = try wishlist.getItem(id: item.id!)
        #expect(approved?.status == "approved")
        #expect(approved?.approvedBy == "TestAdmin")
    }

    @Test("processAutoApprovals throws insufficientPermissions for Office user")
    func testProcessAutoApprovalsAsOfficeUserDeniedThrowsInsufficientPermissions() throws {
        let (env, wishlist) = try freshEnv()

        // Create an unprivileged user (no hats, no wishlist.auto_approve permission)
        let officeUserId = try env.auth.createUser(displayName: "Office User", pin: "9999")

        #expect(throws: WishlistService.WishlistError.insufficientPermissions(required: "wishlist.auto_approve")) {
            try wishlist.processAutoApprovals(byUserId: officeUserId)
        }
    }

    @Test("processAutoApprovals with nil userId uses System (Auto) attribution")
    func testProcessAutoApprovalsWithNilUserIdUsesSystemAttribution() throws {
        let (env, wishlist) = try freshEnv()

        // Backdate an item's auto_approve_at so it is expired
        let item = try wishlist.addItem(partName: "Background Auto-Approve", sourceType: "manual")
        let pastDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        try env.db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE wishlist_items SET auto_approve_at = ? WHERE id = ?",
                arguments: [pastDate, item.id!]
            )
        }

        // Nil userId — system path, no permission check
        let count = try wishlist.processAutoApprovals(byUserId: nil)
        #expect(count == 1)

        let approved = try wishlist.getItem(id: item.id!)
        #expect(approved?.status == "approved")
        #expect(approved?.approvedBy == "System (Auto)")
    }

    // MARK: - Below-MIN Routing

    @Test("Below-MIN truck stock pulls from shop before creating wishlist demand")
    func testBelowMinTruckRoutesShopTransferFirst() throws {
        let (env, wishlist) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env, name: "BelowMinTruckCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Truck Fuse", categoryId: catId)
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "TRK-MIN-1",
            vehicleName: "Minimum Truck",
            vehicleType: "truck",
            make: nil,
            model: nil,
            year: nil,
            color: nil,
            vin: nil,
            licensePlate: nil,
            notes: nil
        )

        try env.parts.setLocationStockTarget(
            partId: partId,
            locationType: "truck",
            locationId: vehicleId,
            minStock: 5,
            targetStock: 10,
            maxStock: 20
        )
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 20, locationType: "shop", locationId: 1)
        try env.fleet.addVehicleStockItem(
            actorId: env.adminUserId,
            vehicleId: vehicleId,
            partName: "Truck Fuse",
            quantity: 2,
            stockType: "truck_stock",
            partId: partId
        )

        let result = try wishlist.routeBelowMinimumStock(
            partId: partId,
            locationType: "truck",
            locationId: vehicleId,
            actorUserId: env.adminUserId,
            certaintyOverride: 0.95
        )

        #expect(result.action == "shop_transfer")
        #expect(result.quantity == 8)
        #expect(result.movementId != nil)

        let counts = try env.db.writer.read { db in
            let shopQty = try Int.fetchOne(db, sql: """
                SELECT qty FROM stock
                WHERE part_id = ? AND location_type = 'shop' AND location_id = 1
                """, arguments: [partId]) ?? 0
            let truckQty = try Int.fetchOne(db, sql: """
                SELECT quantity FROM vehicle_stock
                WHERE part_id = ? AND vehicle_id = ? AND stock_type = 'truck_stock'
                """, arguments: [partId, vehicleId]) ?? 0
            let wishlistCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wishlist_items WHERE part_id = ?", arguments: [partId]) ?? 0
            let movementCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM stock_movements WHERE part_id = ? AND movement_type = 'restock_from_shop'", arguments: [partId]) ?? 0
            return (shopQty, truckQty, wishlistCount, movementCount)
        }

        #expect(counts.0 == 12)
        #expect(counts.1 == 10)
        #expect(counts.2 == 0)
        #expect(counts.3 == 1)

        let second = try wishlist.routeBelowMinimumStock(
            partId: partId,
            locationType: "truck",
            locationId: vehicleId,
            actorUserId: env.adminUserId,
            certaintyOverride: 0.95
        )
        #expect(second.action == "none")
    }

    @Test("Below-MIN high-certainty shortage creates one approved wishlist item with location context")
    func testBelowMinHighCertaintyCreatesDedupedWishlist() throws {
        let (env, wishlist) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env, name: "BelowMinWishlistCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Shop Breaker", categoryId: catId)

        try env.parts.setLocationStockTarget(
            partId: partId,
            locationType: "shop",
            locationId: 1,
            minStock: 4,
            targetStock: 9,
            maxStock: 16
        )

        let first = try wishlist.routeBelowMinimumStock(
            partId: partId,
            locationType: "shop",
            locationId: 1,
            actorUserId: env.adminUserId,
            certaintyOverride: 0.88
        )
        let second = try wishlist.routeBelowMinimumStock(
            partId: partId,
            locationType: "shop",
            locationId: 1,
            actorUserId: env.adminUserId,
            certaintyOverride: 0.88
        )

        #expect(first.action == "wishlist")
        #expect(first.wishlistItem?.status == "approved")
        #expect(first.wishlistItem?.qtySuggested == 9)
        #expect(first.wishlistItem?.reason == "Below MIN at shop #1")
        #expect(second.action == "wishlist")
        #expect(second.reusedExistingAction)
        #expect(second.wishlistItem?.id == first.wishlistItem?.id)

        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wishlist_items WHERE part_id = ?", arguments: [partId]) ?? 0
        }
        #expect(count == 1)
    }

    @Test("Below-MIN low-certainty shortage routes one physical audit before wishlist")
    func testBelowMinLowCertaintyRoutesDedupedAudit() throws {
        let (env, wishlist) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env, name: "BelowMinAuditCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Audit Coupling", categoryId: catId)

        try env.parts.setLocationStockTarget(
            partId: partId,
            locationType: "warehouse",
            locationId: 3,
            minStock: 3,
            targetStock: 7,
            maxStock: 12
        )

        let first = try wishlist.routeBelowMinimumStock(
            partId: partId,
            locationType: "warehouse",
            locationId: 3,
            actorUserId: env.adminUserId,
            certaintyOverride: 0.42
        )
        let second = try wishlist.routeBelowMinimumStock(
            partId: partId,
            locationType: "warehouse",
            locationId: 3,
            actorUserId: env.adminUserId,
            certaintyOverride: 0.42
        )

        #expect(first.action == "physical_audit")
        #expect(first.auditSessionId != nil)
        #expect(second.action == "physical_audit")
        #expect(second.reusedExistingAction)
        #expect(second.auditSessionId == first.auditSessionId)

        let counts = try env.db.writer.read { db in
            let audits = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audit_sessions_v2 WHERE session_type = 'physical_count'") ?? 0
            let wishlistItems = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wishlist_items WHERE part_id = ?", arguments: [partId]) ?? 0
            return (audits, wishlistItems)
        }
        #expect(counts.0 == 1)
        #expect(counts.1 == 0)
    }

    @Test("Below-MIN truck audit is restricted to assigned truck user without manager override")
    func testBelowMinTruckAuditRequiresAssignedTruckUser() throws {
        let (env, wishlist) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env, name: "TruckAuditPermissionCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Truck Audit Clamp", categoryId: catId)
        let userId = try env.auth.createUser(displayName: "Truck Auditor", pin: "2468")
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "TRK-AUD-1",
            vehicleName: "Audit Truck",
            vehicleType: "truck",
            make: nil,
            model: nil,
            year: nil,
            color: nil,
            vin: nil,
            licensePlate: nil,
            notes: nil
        )

        try env.db.writer.write { db in
            try db.execute(sql: "INSERT INTO hats (name, level) VALUES ('Audit Only', 5)")
            let hatId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO hat_permissions (hat_id, permission_key) VALUES (?, 'perform_audit')", arguments: [hatId])
            try db.execute(sql: "INSERT INTO user_hats (user_id, hat_id, is_active) VALUES (?, ?, 1)", arguments: [userId, hatId])
        }

        try env.parts.setLocationStockTarget(
            partId: partId,
            locationType: "truck",
            locationId: vehicleId,
            minStock: 2,
            targetStock: 5,
            maxStock: 8
        )

        #expect(throws: WishlistService.WishlistError.restrictedToAssignedTruckUser(locationId: vehicleId)) {
            try wishlist.routeBelowMinimumStock(
                partId: partId,
                locationType: "truck",
                locationId: vehicleId,
                actorUserId: userId,
                certaintyOverride: 0.25
            )
        }

        try env.fleet.assignDriver(
            actorId: env.adminUserId,
            vehicleId: vehicleId,
            userId: userId,
            assignmentType: "primary",
            isTakeHome: false
        )

        let result = try wishlist.routeBelowMinimumStock(
            partId: partId,
            locationType: "truck",
            locationId: vehicleId,
            actorUserId: userId,
            certaintyOverride: 0.25
        )
        #expect(result.action == "physical_audit")
        #expect(result.auditSessionId != nil)
    }
}
