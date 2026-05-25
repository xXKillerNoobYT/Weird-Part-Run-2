import XCTest

final class WarehouseAuditPageRegressionTests: XCTestCase {
    func testVerificationSheetStateAndPresenterAreDeclaredExactlyOnce() throws {
        let source = try Self.readWarehouseAuditPageSource()

        XCTAssertEqual(
            Self.occurrences(of: "@State private var selectedItemForVerification: CountingItem?", in: source),
            1,
            "IOSAuditPage should declare selectedItemForVerification state exactly once to avoid Swift invalid redeclaration errors."
        )
        XCTAssertEqual(
            Self.occurrences(of: ".sheet(item: $selectedItemForVerification)", in: source),
            1,
            "IOSAuditPage should present the verification sheet from a single .sheet binding to avoid duplicate modifiers and compile instability."
        )
    }

    private static func readWarehouseAuditPageSource(
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

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
