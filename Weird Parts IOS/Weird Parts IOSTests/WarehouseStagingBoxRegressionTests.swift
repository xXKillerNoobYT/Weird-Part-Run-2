import XCTest

final class WarehouseStagingBoxRegressionTests: XCTestCase {
    func testStagingPageLoadsBoxContentsAndDeliveryActions() throws {
        let source = try Self.readStagingPageSource()

        XCTAssertTrue(
            source.contains("boxContents = Dictionary(grouping: try service.listStagingBoxContents()"),
            "Staging page should reload persisted box contents with boxes so assignments survive page reload."
        )
        XCTAssertTrue(
            source.contains("assignStagedItemToBox(stagingTagId: item.id, boxId: box.id)"),
            "Staging page should expose staged-item assignment into a physical box."
        )
        XCTAssertTrue(
            source.contains("updateStagingBoxDeliveryState(boxId: boxId, status: status)"),
            "Staging page should route loaded/delivered/returned-cancelled transitions through the service."
        )
        XCTAssertTrue(
            source.contains("removeStagedItemFromBox(stagingTagId: content.stagingTagId, boxId: box.id)"),
            "Staging page should allow removing a persisted box content assignment without clearing the staged item."
        )
    }

    private static func readStagingPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent("IOSStagingPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
