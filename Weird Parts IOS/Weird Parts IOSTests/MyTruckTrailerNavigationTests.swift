import XCTest

final class MyTruckTrailerNavigationTests: XCTestCase {
    func testAttachedTrailerUsesRealNavigationOnlyWhenTrailerIdExists() throws {
        let source = try Self.readFleetSource(named: "IOSMyTruckPage.swift")

        XCTAssertTrue(
            source.contains("if let trailerId = stats.trailerId"),
            "Trailer row should only become tappable when the stats payload includes trailerId."
        )
        XCTAssertTrue(
            source.contains("NavigationLink(destination: IOSTrailerDetailPage(trailerId: trailerId))"),
            "Attached trailer navigation should route to trailer detail with the attached trailer id."
        )
        XCTAssertTrue(
            source.contains("trailerRow(for: stats)"),
            "Trailer row rendering should be shared so static fallback has no fake navigation affordance."
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
