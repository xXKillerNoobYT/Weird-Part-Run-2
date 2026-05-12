import XCTest

final class MyTruckTrailerNavigationTests: XCTestCase {
    func testAttachedTrailerNavigatesOnlyWhenTrailerIdExists() throws {
        let source = try String(contentsOfFile: fleetSourcePath("IOSMyTruckPage.swift"), encoding: .utf8)

        XCTAssertTrue(
            source.contains("if let trailerId = stats.trailerId"),
            "The attached trailer row should only become navigable when the stats payload includes a trailer id."
        )
        XCTAssertTrue(
            source.contains("NavigationLink(destination: IOSTrailerDetailPage(trailerId: trailerId))"),
            "The attached trailer row should navigate to the trailer detail page with the attached trailer id."
        )
        XCTAssertTrue(
            source.contains("} else {\n                    trailerRow(stats)\n                }"),
            "When the trailer id is unavailable, the attached trailer row should render without NavigationLink chrome."
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
