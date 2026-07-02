import XCTest

/// Regression coverage for issue #1244: the Warehouse Leaderboard podium
/// stayed bound to the unfiltered top three while the Rankings list
/// narrowed under a search, showing unrelated users above the results —
/// and filtered rows were renumbered from #1, misstating overall rank.
final class WarehouseLeaderboardSearchRegressionTests: XCTestCase {
    func testPodiumIsHiddenWhileSearchIsActive() throws {
        let source = try Self.readLeaderboardSource()

        XCTAssertTrue(
            source.contains("if searchText.isEmpty, leaderboard.count >= 3 {"),
            "The overall podium must be hidden while a search is active (issue #1244)."
        )
        XCTAssertTrue(
            source.contains("Section(searchText.isEmpty ? \"Rankings\" : \"Search Results\")"),
            "The list section should be retitled during search so the narrowed scope is clear."
        )
    }

    func testFilteredRowsKeepOverallRank() throws {
        let source = try Self.readLeaderboardSource()

        XCTAssertTrue(
            source.contains("leaderboardRow(rank: overallRank(of: rating), rating: rating)"),
            "Filtered rows must display the user's overall rank, not a renumbered filtered position."
        )
        XCTAssertTrue(
            source.contains("leaderboard.firstIndex(where: { $0.userId == rating.userId })"),
            "overallRank must be derived from the unfiltered leaderboard."
        )
        XCTAssertFalse(
            source.contains("leaderboardRow(rank: index + 1"),
            "Rows must not be renumbered from the filtered array's indices."
        )
    }

    private static func readLeaderboardSource(
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent("IOSWarehouseLeaderboardPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
