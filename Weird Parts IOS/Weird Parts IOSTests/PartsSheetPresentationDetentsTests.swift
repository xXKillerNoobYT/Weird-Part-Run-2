import XCTest

final class PartsSheetPresentationDetentsTests: XCTestCase {
    func testPartsSheetsDeclarePresentationDetents() throws {
        try assertContainsDetent(named: "PartsBrandsPage.swift", detent: ".presentationDetents([.medium, .large])", expectedCount: 2)
        try assertContainsDetent(named: "PartsSuppliersPage.swift", detent: ".presentationDetents([.medium, .large])", expectedCount: 2)
        try assertContainsDetent(named: "PartsPricingPage.swift", detent: ".presentationDetents([.medium, .large])", expectedCount: 1)
        try assertContainsDetent(named: "PartsPricingPage.swift", detent: ".presentationDetents([.large])", expectedCount: 1)
        try assertContainsDetent(named: "PartsCategoriesPage.swift", detent: ".presentationDetents([.medium, .large])", expectedCount: 1)
        try assertContainsDetent(named: "PartsForecastingPage.swift", detent: ".presentationDetents([.medium, .large])", expectedCount: 1)
        try assertContainsDetent(named: "PartsCompanionsPage.swift", detent: ".presentationDetents([.medium, .large])", expectedCount: 1)
        try assertContainsDetent(named: "PartsImportExportPage.swift", detent: ".presentationDetents([.medium, .large])", expectedCount: 1)
        try assertContainsDetent(named: "PartsCatalogPage.swift", detent: ".presentationDetents([.large])", expectedCount: 2)
    }

    private func assertContainsDetent(named filename: String, detent: String, expectedCount: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try Self.readPartsPageSource(named: filename, file: file)
        let actualCount = source.components(separatedBy: detent).count - 1
        XCTAssertEqual(
            actualCount,
            expectedCount,
            "\(filename) should contain \(expectedCount) occurrence(s) of \(detent).",
            file: file,
            line: line
        )
    }

    private static func readPartsPageSource(named filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Parts")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
