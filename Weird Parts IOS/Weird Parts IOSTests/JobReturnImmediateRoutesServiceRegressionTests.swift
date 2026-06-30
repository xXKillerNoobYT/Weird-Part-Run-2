import XCTest

/// Regression coverage for GH#1123: job-return immediate routes must not silently
/// succeed if the warehouse service disappears between return intake and routing.
final class JobReturnImmediateRoutesServiceRegressionTests: XCTestCase {
    func testImmediateRoutesUseAlreadyUnwrappedWarehouseService() throws {
        let source = try Self.readWarehouseSource(named: "IOSReceivingPage.swift")

        let helperSection = try Self.extractFunctionSection(named: "applyImmediateRoutes", from: source)
        XCTAssertTrue(
            helperSection.contains("warehouseService: WarehouseService"),
            "Immediate route helper should require the already-unwrapped WarehouseService from submitJobReturn."
        )
        XCTAssertFalse(
            helperSection.contains("appCore.warehouseService"),
            "Immediate route helper must not re-read appCore.warehouseService or silently return after the return intake has been created."
        )

        let submitBody = try Self.extractFunctionBody(named: "submitJobReturn", from: source)
        XCTAssertTrue(
            submitBody.contains("guard let warehouseService = appCore.warehouseService else"),
            "Job Return submit should still fail visibly before creating an intake when the warehouse service is unavailable."
        )
        XCTAssertTrue(
            submitBody.contains("warehouseService: warehouseService"),
            "Job Return submit should pass the unwrapped service into immediate routing so success is only shown after routing attempts run."
        )
    }

    private static func extractFunctionBody(named functionName: String, from source: String) throws -> String {
        return try extractFunctionSection(named: functionName, from: source)
    }

    private static func extractFunctionSection(named functionName: String, from source: String) throws -> String {
        guard let signatureRange = source.range(of: "func \(functionName)") else {
            XCTFail("Missing function \(functionName)")
            return ""
        }
        let section = String(source[signatureRange.lowerBound...])
        let body = try extractBlock(startingAt: "{", in: section)
        guard let bodyRange = section.range(of: body) else { return section }
        return String(section[..<bodyRange.upperBound])
    }

    private static func extractBlock(startingAt marker: String, in source: String) throws -> String {
        guard let markerRange = source.range(of: marker),
              let openBraceIndex = source[markerRange.lowerBound...].firstIndex(of: "{") else {
            XCTFail("Missing block marker \(marker)")
            return ""
        }

        var depth = 0
        var cursor = openBraceIndex
        while cursor < source.endIndex {
            let char = source[cursor]
            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openBraceIndex...cursor])
                }
            }
            cursor = source.index(after: cursor)
        }

        XCTFail("Unterminated block for marker \(marker)")
        return ""
    }

    private static func readWarehouseSource(named filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
