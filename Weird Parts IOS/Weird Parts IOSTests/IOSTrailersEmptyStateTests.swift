import XCTest

final class IOSTrailersEmptyStateTests: XCTestCase {
    func testTrailersPageShowsSearchAwareAndFirstRunEmptyStates() throws {
        let source = try String(contentsOfFile: fleetSourcePath("IOSTrailersPage.swift"), encoding: .utf8)

        XCTAssertTrue(
            source.contains("if isSearching"),
            "The empty state should branch on whether the user has entered a non-empty search query."
        )
        XCTAssertTrue(
            source.contains("message: \"No trailers match \\\"\\(trimmedSearchText)\\\".\""),
            "A non-empty search with no matches should show search-aware no-results copy."
        )
        XCTAssertTrue(
            source.contains("actionLabel: \"Clear Search\""),
            "The search no-results empty state should expose a clear-search affordance."
        )
        XCTAssertTrue(
            source.contains("searchText = \"\""),
            "The clear-search affordance should reset the trailers search text."
        )
        XCTAssertTrue(
            source.contains("message: \"No trailers found.\""),
            "An empty search with no trailers should keep the generic first-run empty state."
        )
        XCTAssertTrue(
            source.contains("searchText.trimmingCharacters(in: .whitespacesAndNewlines)"),
            "Whitespace-only input should not force the no-results search empty state."
        )
    }

    private func fleetSourcePath(_ fileName: String) -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Fleet")
            .appendingPathComponent(fileName)
            .path
    }
}
