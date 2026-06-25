import XCTest

final class InventoryGridLocationSelectionRegressionTests: XCTestCase {
    func testInventoryGridReloadsWhenLocationTypeOrIdChanges() throws {
        let source = try Self.readInventoryGridPageSource()

        XCTAssertTrue(
            source.contains("private var selectedLocation: LocationOption"),
            "Inventory Grid should expose a full location selection value that includes both type and id."
        )
        XCTAssertTrue(
            source.contains(".onChange(of: selectedLocation)"),
            "Inventory Grid should observe the full location selection so Warehouse #N ↔ Truck #N reloads even when the numeric id is unchanged."
        )
        XCTAssertFalse(
            source.contains(".onChange(of: selectedLocationId)"),
            "Watching only selectedLocationId misses same-id location type changes and can leave stale inventory visible."
        )
        XCTAssertTrue(
            source.contains("lastLocationType = selectedLocationType"),
            "The reload trigger should persist the selected location type with the id."
        )
        XCTAssertTrue(
            source.contains("items = try service.getStockAtLocation(locationType: selectedLocationType, locationId: selectedLocationId)"),
            "Inventory fetches must remain type-aware and id-aware."
        )
    }

    private static func readInventoryGridPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent("IOSInventoryGridPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
