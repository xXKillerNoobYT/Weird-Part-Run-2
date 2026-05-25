import XCTest

final class ReceiveShipmentPageRegressionTests: XCTestCase {
    func testBarcodeFirstScanStartsFromZeroForExpectedPrefillItems() throws {
        let source = try Self.readReceiveShipmentPageSource()

        XCTAssertTrue(
            source.contains("@State private var scannerZeroStartItemIds: Set<Int64> = []"),
            "Receive shipment should track which fresh-session rows were prefilled from expected quantity so scanner behavior can avoid false overages."
        )
        XCTAssertTrue(
            source.contains("let shouldStartScanFromZero = scannerZeroStartItemIds.contains(item.id) && currentQty == item.expectedQty"),
            "Barcode scans should detect rows that are still in expected-prefill state before applying +1."
        )
        XCTAssertTrue(
            source.contains("let baselineQty = shouldStartScanFromZero ? 0 : currentQty"),
            "The first scan for expected-prefill rows should count from zero, so expected=10 first scan records 1."
        )
        XCTAssertTrue(
            source.contains("scannerZeroStartItemIds.insert(item.id)"),
            "Fresh session rows with no saved receipt quantity should be marked for scanner zero-start behavior."
        )
        XCTAssertTrue(
            source.contains("scannerZeroStartItemIds.remove(item.id)"),
            "Manual quantity actions or a completed scan should clear the zero-start marker so later scans increment from the current quantity."
        )
    }

    private static func readReceiveShipmentPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Orders")
            .appendingPathComponent("IOSReceiveShipmentPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
