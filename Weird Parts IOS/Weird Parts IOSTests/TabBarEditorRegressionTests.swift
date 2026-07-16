import XCTest
@testable import Weird_Parts

final class TabBarEditorRegressionTests: XCTestCase {
    @MainActor
    func testFourVisibleModuleFixtureHasNoMoreDestinationOrFastDemoteActions() {
        let visibleIds = ["dashboard", "jobs", "chat", "scheduling"]
        let layout = TabBarEditorLayout(orderedIds: visibleIds)

        XCTAssertEqual(layout.bottomIds, visibleIds)
        XCTAssertTrue(layout.moreIds.isEmpty)
        XCTAssertFalse(
            layout.hasMoreDestination,
            "A four-visible-module permission fixture must not expose a More divider or destination."
        )
        XCTAssertFalse(
            layout.exportsFastDemoteActions,
            "Fast rows must not export enabled 'Move … to More menu' actions when the More destination is absent."
        )
    }

    @MainActor
    func testFiveVisibleModuleFixtureKeepsMoreDestinationAndDemoteActions() {
        let visibleIds = ["dashboard", "jobs", "chat", "scheduling", "warehouse"]
        let layout = TabBarEditorLayout(orderedIds: visibleIds)

        XCTAssertEqual(layout.bottomIds, ["dashboard", "jobs", "chat", "scheduling"])
        XCTAssertEqual(layout.moreIds, ["warehouse"])
        XCTAssertTrue(layout.hasMoreDestination)
        XCTAssertTrue(layout.exportsFastDemoteActions)
    }

    @MainActor
    func testFourthFastRowDroppedImmediatelyBelowDividerChangesModuleOrder() {
        let original = ["dashboard", "jobs", "chat", "scheduling", "warehouse", "orders"]
        let layout = TabBarEditorLayout(orderedIds: original)

        let moved = layout.movingModules(fromRenderedOffsets: IndexSet(integer: 3), toRenderedOffset: 5)

        XCTAssertEqual(moved, ["dashboard", "jobs", "chat", "warehouse", "scheduling", "orders"])
        XCTAssertNotEqual(moved, original, "Crossing the divider downward must not persist as a no-op.")
    }

    @MainActor
    func testFastRowDropsBeyondDividerPreserveRenderedModuleSlot() {
        let original = ["dashboard", "jobs", "chat", "scheduling", "warehouse", "orders"]
        let layout = TabBarEditorLayout(orderedIds: original)
        let cases: [(destination: Int, expected: [String])] = [
            (5, ["dashboard", "jobs", "chat", "warehouse", "scheduling", "orders"]),
            (6, ["dashboard", "jobs", "chat", "warehouse", "scheduling", "orders"]),
            (7, ["dashboard", "jobs", "chat", "warehouse", "orders", "scheduling"]),
        ]

        for testCase in cases {
            let moved = layout.movingModules(
                fromRenderedOffsets: IndexSet(integer: 3),
                toRenderedOffset: testCase.destination
            )

            XCTAssertEqual(
                moved,
                testCase.expected,
                "Rendered destination \(testCase.destination) must account for the divider exactly once."
            )
        }
    }

    @MainActor
    func testFirstMoreRowDroppedImmediatelyAboveDividerChangesModuleOrder() {
        let original = ["dashboard", "jobs", "chat", "scheduling", "warehouse", "orders"]
        let layout = TabBarEditorLayout(orderedIds: original)

        let moved = layout.movingModules(fromRenderedOffsets: IndexSet(integer: 5), toRenderedOffset: 4)

        XCTAssertEqual(moved, ["dashboard", "jobs", "chat", "warehouse", "scheduling", "orders"])
        XCTAssertNotEqual(moved, original, "Crossing the divider upward must not persist as a no-op.")
    }

    @MainActor
    func testMovedModuleOrderSurvivesSaveAndReload() {
        let userId = Int64.random(in: 1_000_000...Int64.max)
        let defaultsKey = "tabOrder_\(userId)"
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let original = ["dashboard", "jobs", "chat", "scheduling", "warehouse", "orders"]
        let expected = TabBarEditorLayout(orderedIds: original)
            .movingModules(fromRenderedOffsets: IndexSet(integer: 3), toRenderedOffset: 5)
        let savingPreferences = TabBarPreferences()
        savingPreferences.load(userId: userId)
        savingPreferences.tabOrder = expected
        savingPreferences.save()

        let reopenedPreferences = TabBarPreferences()
        reopenedPreferences.load(userId: userId)

        XCTAssertEqual(reopenedPreferences.tabOrder, expected)
    }

    func testSourceKeepsMoreDividerAndFastDemoteButtonBehindDestinationCheck() throws {
        let source = try Self.readTabBarEditorSource()

        XCTAssertTrue(
            source.contains("if !moreIds.isEmpty {\n            items.append(.moreDivider)"),
            "The More divider must stay absent for four-or-fewer visible modules."
        )
        XCTAssertTrue(
            source.contains("if !isFastAccess || hasMoreDestination {"),
            "Fast-row demote buttons must only be exported when a real More destination exists."
        )
        XCTAssertTrue(source.contains("\"Move \\(module.label) to More menu\""))
    }

    private static func readTabBarEditorSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Navigation")
            .appendingPathComponent("TabBarEditorView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
