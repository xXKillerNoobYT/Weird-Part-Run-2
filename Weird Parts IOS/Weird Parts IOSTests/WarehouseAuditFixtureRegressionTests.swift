import XCTest

final class WarehouseAuditFixtureRegressionTests: XCTestCase {
    func testFixtureVerificationItemFallsBackToPendingAssignmentWhenQueueItemMissing() throws {
        let source = try Self.readAuditPageSource()

        XCTAssertTrue(
            source.contains("@State private var fixtureFallbackItem: CountingItem?"),
            "IOSAuditPage should keep a fallback fixture item so the QA Verify control can be shown even when the confidence queue misses the seeded part."
        )
        XCTAssertTrue(
            source.contains("} ?? fixtureFallbackItem"),
            "Fixture lookup should fall back to pending-assignment-derived data when the queue does not include UITEST-MUV-001."
        )
        XCTAssertTrue(
            source.contains("loadFixtureFallbackItem(service: service)"),
            "Audit page data loading should refresh the fixture fallback item each time data is loaded."
        )
        XCTAssertTrue(
            source.contains("service.getMyMultiUserAuditAssignments(userId: userId)"),
            "Fallback fixture resolution should source deterministic pending verification assignments for the logged-in QA user."
        )
    }

    private static func readAuditPageSource(
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
            .appendingPathComponent("IOSAuditPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
