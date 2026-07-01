import XCTest

final class PartsCatalogPageRegressionTests: XCTestCase {
    func testCompactPartEditDismissesBeforeParentRefresh() throws {
        let source = try Self.readPartsCatalogPageSource()
        guard let sheetStart = source.range(of: "private struct QuickEditSheet") else {
            XCTFail("QuickEditSheet should exist.")
            return
        }
        guard let sheetEnd = source[sheetStart.upperBound...].range(of: "// MARK: - Part Form Sheet") else {
            XCTFail("QuickEditSheet should end before the full part form sheet.")
            return
        }

        let sheetSource = source[sheetStart.lowerBound..<sheetEnd.lowerBound]
        guard let saveStart = sheetSource.range(
            of: #"private\s+func\s+save\s*\(\)\s+async\s*\{"#,
            options: .regularExpression
        ) else {
            XCTFail("Quick edit save function should exist inside QuickEditSheet.")
            return
        }

        let saveSource = sheetSource[saveStart.lowerBound...]
        guard let dismissRange = saveSource.range(of: "dismiss()") else {
            XCTFail("Successful compact part edit should dismiss the sheet.")
            return
        }
        guard let onSaveRange = saveSource.range(of: "await onSave()") else {
            XCTFail("Successful compact part edit should still refresh the parent catalog.")
            return
        }

        XCTAssertLessThan(
            dismissRange.lowerBound,
            onSaveRange.lowerBound,
            "Successful compact part edit should dismiss the sheet before awaiting the parent catalog refresh."
        )
    }

    private static func readPartsCatalogPageSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Parts")
            .appendingPathComponent("PartsCatalogPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
