import XCTest

/// Adoption contract for the panel-quality craft pass over the Orders area
/// (#1421 Wave 2, docs/plans/panel-quality-uplift.md).
///
/// Pins the area-level invariants the 2026-07-07 adoption pass established —
/// not exact strings, so pages can keep evolving:
///  1. Every Orders list/card page offers a context menu (rubric criterion 4:
///     ≥2 input paths to core actions). The area previously had zero.
///  2. The area uses stable `orders-` accessibility identifiers (UI-test
///     addressability, rubric criterion 2).
///  3. The area uses the shared `.rowAccessibility` kit rather than zero
///     adoption (it was 2 of 19 files before the pass).
final class OrdersCraftAdoptionContractTests: XCTestCase {

    /// Pages whose rows gained a context-menu second input path.
    private static let contextMenuPages = [
        "IOSJPOsPage.swift",
        "IOSPurchaseOrdersPage.swift",
        "IOSReturnsPage.swift",
        "IOSWishlistPage.swift",
        "IOSProcurementPage.swift",
        "IOSOrderStagingPage.swift",
        "IOSPartsOrderManagementPage.swift",
        "IOSJPODetailPage.swift",
        "IOSPODetailPage.swift",
    ]

    func testEveryAuditedOrdersPageOffersAContextMenu() throws {
        for page in Self.contextMenuPages {
            let source = try Self.readOrdersSource(named: page)
            XCTAssertTrue(
                source.contains(".contextMenu"),
                "\(page) lost its context menu — the Orders area must keep a second input path to row actions (panel-quality rubric criterion 4)."
            )
        }
    }

    func testOrdersAreaUsesStableAccessibilityIdentifiers() throws {
        var filesWithOrdersIds = 0
        for page in try Self.allOrdersSourceFiles() {
            let source = try Self.readOrdersSource(named: page)
            if source.contains("\"orders-") { filesWithOrdersIds += 1 }
        }
        XCTAssertGreaterThanOrEqual(
            filesWithOrdersIds, 8,
            "Orders pages carrying stable 'orders-' accessibility identifiers dropped below the adoption floor set by the Wave-2 craft pass."
        )
    }

    func testOrdersAreaUsesTheSharedRowAccessibilityKit() throws {
        var filesUsingKit = 0
        for page in try Self.allOrdersSourceFiles() {
            let source = try Self.readOrdersSource(named: page)
            if source.contains(".rowAccessibility(") { filesUsingKit += 1 }
        }
        XCTAssertGreaterThanOrEqual(
            filesUsingKit, 8,
            "Orders pages using the shared .rowAccessibility kit dropped below the adoption floor set by the Wave-2 craft pass."
        )
    }

    // MARK: - Source loading

    private static func ordersDirectory(file: StaticString = #filePath) -> URL {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        return testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS (project root)
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Orders")
    }

    private static func allOrdersSourceFiles() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: ordersDirectory().path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
    }

    private static func readOrdersSource(named filename: String) throws -> String {
        let url = ordersDirectory().appendingPathComponent(filename)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
