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

    func testInformationalQuestionAboutFilterCannotActivateMatchingCommand() {
        let commands = AIFilterCommandAuthorization.authorizedCommands(
            response: "{\"activateFilter\":{\"pageId\":\"purchase-orders\",\"value\":\"draft\"}}",
            userQuery: "What does the draft filter mean?",
            availableFilters: [purchaseOrderFilter]
        )

        XCTAssertTrue(commands.isEmpty)
    }

    func testHelpWordingCannotActivateMatchingCommand() {
        let commands = AIFilterCommandAuthorization.authorizedCommands(
            response: "{\"activateFilter\":{\"pageId\":\"purchase-orders\",\"value\":\"draft\"}}",
            userQuery: "How do I use the draft filter?",
            availableFilters: [purchaseOrderFilter]
        )

        XCTAssertTrue(commands.isEmpty)
    }

    func testNoModelCatalogFallbackClearAllQuestionIsGuidanceOnly() {
        let resolution = CatalogFilterFallbackResolution.response(
            for: "How do I clear all catalog filters?"
        )

        guard case .guidance(let message) = resolution else {
            return XCTFail("No-model catalog fallback must not produce an executable filter command.")
        }
        XCTAssertTrue(message.contains("won't change filters"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("done — cleared"))
    }

    func testNoModelCatalogFallbackCategoryAndBrandQuestionsAreGuidanceOnly() {
        let queries = [
            "How do category filters work?",
            "Which brand filters are available?"
        ]

        for query in queries {
            guard case .guidance(let message) = CatalogFilterFallbackResolution.response(for: query) else {
                return XCTFail("No-model catalog fallback must not produce an executable filter command for: \(query)")
            }
            XCTAssertTrue(message.contains("won't change filters"))
        }
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
