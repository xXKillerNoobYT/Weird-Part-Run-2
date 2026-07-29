import XCTest

/// Exercises the assistant's deterministic command seam without depending on
/// Foundation Models. Run this suite on both iPhone and iPad destinations.
final class AIFilterCommandFixtureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-UITestingAIFilterCommandFixture",
        ]
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["aiFilterCommandFixture"].waitForExistence(timeout: 30),
            "The deterministic assistant fixture should mount inside IOSAIAssistantPanel."
        )
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testExplicitSamePageNarrowCommandMutatesOnlyRegisteredTarget() {
        applyDraft()

        XCTAssertTrue(purchaseOrdersValue.label.contains("draft"))
        XCTAssertTrue(jposValue.label.contains("all"))
    }

    @MainActor
    func testBroadCommandShowsConfirmationAndCancellationLeavesFiltersUnchanged() {
        applyDraft()
        app.descendants(matching: .any)["aiFilterFixtureShowAll"].tap()

        let confirmation = app.buttons["Apply Filter Change"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(
            purchaseOrdersValue.label.contains("draft"),
            "A broad command must not mutate before confirmation."
        )

        let cancel = app.buttons["Keep Current Filter"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        XCTAssertTrue(
            purchaseOrdersValue.label.contains("draft"),
            "Cancelling a broad command must leave the active filter unchanged."
        )
        XCTAssertTrue(jposValue.label.contains("all"))
    }

    @MainActor
    func testBroadCommandMutatesOnlyAfterVisibleConfirmation() {
        applyDraft()
        app.descendants(matching: .any)["aiFilterFixtureShowAll"].tap()

        let confirmation = app.buttons["Apply Filter Change"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()

        XCTAssertTrue(waitForPurchaseOrdersValue(containing: "all"))
        XCTAssertTrue(jposValue.label.contains("all"))
    }

    @MainActor
    func testClearAndClearAllCommandsRequireConfirmation() {
        for command in ["aiFilterFixtureClear", "aiFilterFixtureClearAll"] {
            applyDraft()
            app.descendants(matching: .any)[command].tap()

            let confirmation = app.buttons["Apply Filter Change"].firstMatch
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5), "\(command) should require confirmation.")
            XCTAssertTrue(purchaseOrdersValue.label.contains("draft"))

            let cancel = app.buttons["Keep Current Filter"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 3))
            cancel.tap()
            XCTAssertTrue(purchaseOrdersValue.label.contains("draft"))
        }
    }

    @MainActor
    func testFixtureCannotBypassRejectedAuthorizationCommand() {
        applyDraft()
        app.descendants(matching: .any)["aiFilterFixtureUnauthorized"].tap()

        XCTAssertTrue(
            purchaseOrdersValue.label.contains("draft"),
            "A command for a different page must not alter the page explicitly requested by the user."
        )
        XCTAssertTrue(
            jposValue.label.contains("all"),
            "The rejected command must not alter its own registered target either."
        )
    }

    private var purchaseOrdersValue: XCUIElement {
        app.descendants(matching: .any)["aiFilterFixturePurchaseOrdersValue"]
    }

    private var jposValue: XCUIElement {
        app.descendants(matching: .any)["aiFilterFixtureJPOsValue"]
    }

    private func applyDraft() {
        let applyDraft = app.descendants(matching: .any)["aiFilterFixtureApplyDraft"]
        XCTAssertTrue(applyDraft.waitForExistence(timeout: 5))
        applyDraft.tap()
        XCTAssertTrue(purchaseOrdersValue.waitForExistence(timeout: 3))
    }

    private func waitForPurchaseOrdersValue(containing value: String) -> Bool {
        let predicate = NSPredicate(
            format: "identifier == %@ AND label CONTAINS[c] %@",
            "aiFilterFixturePurchaseOrdersValue",
            value
        )
        return app.descendants(matching: .any)
            .matching(predicate)
            .firstMatch
            .waitForExistence(timeout: 3)
    }
}
