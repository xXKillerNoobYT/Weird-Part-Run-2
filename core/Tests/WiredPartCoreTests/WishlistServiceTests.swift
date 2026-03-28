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
        let dismissed = try wishlist.dismissItem(id: item.id!, by: "Manager")
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
        _ = try wishlist.dismissItem(id: item.id!, by: "Manager")
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
}
