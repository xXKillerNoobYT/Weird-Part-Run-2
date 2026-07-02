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
            source.contains("if let rank = ranks[rating.userId] {"),
            "Filtered rows must display the user's overall rank and omit rows with no known rank instead of fabricating one."
        )
        XCTAssertTrue(
            source.contains("Dictionary(uniqueKeysWithValues: leaderboard.enumerated().map { ($0.element.userId, $0.offset + 1) })"),
            "Overall ranks must be derived once from the unfiltered leaderboard (O(1) per-row lookup)."
        )
        XCTAssertFalse(
            source.contains("leaderboardRow(rank: index + 1"),
            "Rows must not be renumbered from the filtered array's indices."
        )
        XCTAssertFalse(
            source.contains("?? 0) + 1"),
            "Rank lookups must not fall back to fabricating rank #1 for unknown users."
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
