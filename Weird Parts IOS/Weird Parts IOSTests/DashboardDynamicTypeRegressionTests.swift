import XCTest

final class DashboardDynamicTypeRegressionTests: XCTestCase {
    func testGettingStartedChecklistRowsAllowMultilineAtAccessibilitySizes() throws {
        let source = try Self.readDashboardViewSource()

        XCTAssertTrue(
            source.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"),
            "Dashboard should read dynamicTypeSize so the checklist can adapt at accessibility text sizes."
        )
        XCTAssertTrue(
            source.contains(".lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)"),
            "Checklist title/subtitle should remove line clamps at accessibility sizes to prevent clipping."
        )
        XCTAssertTrue(
            source.contains("if !isComplete && !dynamicTypeSize.isAccessibilitySize"),
            "Chevron affordance should be hidden at accessibility sizes so helper text keeps readable width."
        )
    }

    func testDashboardScrollContentAddsAccessibilityBottomInset() throws {
        let source = try Self.readDashboardViewSource()

        XCTAssertTrue(
            source.contains(".padding(.bottom, dynamicTypeSize.isAccessibilitySize ? DS.Space.xxxxl : 0)"),
            "Dashboard content should add extra bottom spacing at accessibility sizes so onboarding card content is not occluded by bottom chrome."
        )
    }

    private static func readDashboardViewSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Dashboard")
            .appendingPathComponent("DashboardView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
