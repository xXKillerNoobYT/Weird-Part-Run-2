import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("WishlistService Tests")
struct WishlistServiceTests {

    private func freshEnv() throws -> (E2ETestHelpers.TestEnvironment, WishlistService) {
        let env = try E2ETestHelpers.setUp()
        let wishlist = WishlistService(db: env.db)
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
        let (_, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "Needs Approval")
        let approved = try wishlist.approveItem(id: item.id!, by: "Manager")
        #expect(approved.status == "approved")
    }

    @Test("Dismiss item changes status")
    func testDismissItem() throws {
        let (_, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "Not Needed")
        let dismissed = try wishlist.dismissItem(id: item.id!, by: "Manager", reason: "No longer needed for this project")
        #expect(dismissed.status == "dismissed")
    }

    @Test("Send to procurement changes status")
    func testSendToProcurement() throws {
        let (_, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "Ready to Order")
        let approved = try wishlist.approveItem(id: item.id!, by: "Manager")
        let sent = try wishlist.sendToProcurement(id: approved.id!)
        #expect(sent.status == "sent_to_procurement")
    }

    @Test("Reopen dismissed item")
    func testReopenItem() throws {
        let (_, wishlist) = try freshEnv()

        let item = try wishlist.addItem(partName: "Reopen Me")
        _ = try wishlist.dismissItem(id: item.id!, by: "Manager", reason: "Duplicate item in inventory")
        let reopened = try wishlist.reopenItem(id: item.id!)
        #expect(reopened.status == "pending")
    }

    // MARK: - Status Counts

    @Test("Status counts reflect actual data")
    func testStatusCounts() throws {
        let (_, wishlist) = try freshEnv()

        _ = try wishlist.addItem(partName: "Pending 1")
        _ = try wishlist.addItem(partName: "Pending 2")
        let item3 = try wishlist.addItem(partName: "To Approve")
        _ = try wishlist.approveItem(id: item3.id!, by: "Boss")

        let counts = try wishlist.getStatusCounts()
        #expect(counts.pending == 2)
        #expect(counts.approved == 1)
    }

    // MARK: - Filters

    @Test("List items with status filter")
    func testListWithFilter() throws {
        let (_, wishlist) = try freshEnv()

        _ = try wishlist.addItem(partName: "Pending Item")
        let approved = try wishlist.addItem(partName: "Approved Item")
        _ = try wishlist.approveItem(id: approved.id!, by: "Mgr")

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
        let (_, wishlist) = try freshEnv()
        let item = try wishlist.addItem(partName: "Test Item")

        #expect(throws: WishlistService.WishlistError.self) {
            try wishlist.dismissItem(id: item.id!, by: "Manager", reason: "")
        }

        #expect(throws: WishlistService.WishlistError.self) {
            try wishlist.dismissItem(id: item.id!, by: "Manager", reason: "   ")
        }
    }

    @Test("Dismiss with valid reason saves dismiss_reason")
    func testDismissWithReason() throws {
        let (_, wishlist) = try freshEnv()
        let item = try wishlist.addItem(partName: "Dismiss Me")
        let reason = "Already have plenty in stock at the main warehouse"

        let dismissed = try wishlist.dismissItem(id: item.id!, by: "Boss", reason: reason)
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

        let count = try wishlist.processAutoApprovals(by: "System")
        #expect(count == 1)

        // Verify the backdated one is now approved
        let approved = try wishlist.getItem(id: item.id!)
        #expect(approved?.status == "approved")
        #expect(approved?.approvedBy == "System")

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
}
