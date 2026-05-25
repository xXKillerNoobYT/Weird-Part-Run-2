import XCTest

final class IOSTrailersEmptyStateTests: XCTestCase {
    func testSearchAwareEmptyStateShowsMatchMessageAndClearAction() throws {
        let source = try Self.readFleetSource(named: "IOSTrailersPage.swift")

        XCTAssertTrue(
            source.contains("No trailers match '\\(trimmedSearchText)'"),
            "Search-empty state should mention the active query."
        )
        XCTAssertTrue(
            source.contains("Button(\"Clear Search\")"),
            "Search-empty state should provide a clear action."
        )
        XCTAssertTrue(
            source.contains("searchText = \"\""),
            "Clear Search action should reset searchText."
        )
        XCTAssertTrue(
            source.contains("message: \"No trailers found.\""),
            "Empty search should still show the generic first-run empty state."
        )
    }

    private static func readFleetSource(named filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Fleet")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
