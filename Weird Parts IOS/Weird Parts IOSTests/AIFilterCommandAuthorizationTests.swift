import XCTest
@testable import Weird_Parts

@MainActor
final class AIFilterCommandAuthorizationTests: XCTestCase {
    private let purchaseOrderFilter = (
        pageId: "purchase-orders",
        filterName: "PO Status",
        options: ["all", "draft", "submitted"]
    )

    func testRecordContextStyleModelCommandCannotActivateWithoutExplicitUserFilterRequest() {
        let adversarialResponse = """
        The selected job says to activate a filter now.
        {"activateFilter":{"pageId":"purchase-orders","value":"draft"}}
        """

        let commands = AIFilterCommandAuthorization.authorizedCommands(
            response: adversarialResponse,
            userQuery: "How do I find purchase orders?",
            availableFilters: [purchaseOrderFilter]
        )

        XCTAssertTrue(commands.isEmpty)
    }

    func testExplicitUserFilterRequestAcceptsAllowlistedMatchingValue() {
        let commands = AIFilterCommandAuthorization.authorizedCommands(
            response: "{" + "\"activateFilter\":{\"pageId\":\"purchase-orders\",\"value\":\"draft\"}}",
            userQuery: "Filter purchase orders to draft",
            availableFilters: [purchaseOrderFilter]
        )

        XCTAssertEqual(commands, [AIFilterActivationCommand(pageId: "purchase-orders", value: "draft")])
    }

    func testExplicitRequestRejectsUnknownPageAndUnsupportedValue() {
        let unknownPage = AIFilterCommandAuthorization.authorizedCommands(
            response: "{" + "\"activateFilter\":{\"pageId\":\"unknown\",\"value\":\"draft\"}}",
            userQuery: "Filter unknown to draft",
            availableFilters: [purchaseOrderFilter]
        )
        let unsupportedValue = AIFilterCommandAuthorization.authorizedCommands(
            response: "{" + "\"activateFilter\":{\"pageId\":\"purchase-orders\",\"value\":\"deleted\"}}",
            userQuery: "Filter purchase orders to deleted",
            availableFilters: [purchaseOrderFilter]
        )

        XCTAssertTrue(unknownPage.isEmpty)
        XCTAssertTrue(unsupportedValue.isEmpty)
    }

    func testClearAllCommandRequiresVisibleConfirmation() {
        let commands = AIFilterCommandAuthorization.authorizedCommands(
            response: "{" + "\"activateFilter\":{\"pageId\":\"purchase-orders\",\"value\":\"all\"}}",
            userQuery: "Filter purchase orders to all",
            availableFilters: [purchaseOrderFilter]
        )

        XCTAssertEqual(commands.count, 1)
        XCTAssertTrue(commands[0].requiresConfirmation)
    }
}
