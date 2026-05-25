import XCTest

final class FleetSheetPresentationDetentsTests: XCTestCase {
    func testFleetHeavySheetsDeclareLargePresentationDetent() throws {
        try assertSource(
            at: "Weird Parts IOS/Features/Fleet/IOSCreateVehicleSheet.swift",
            contains: ".presentationDetents([.large])"
        )
        try assertSource(
            at: "Weird Parts IOS/Features/Fleet/IOSCreateTrailerSheet.swift",
            contains: ".presentationDetents([.large])"
        )
        try assertSource(
            at: "Weird Parts IOS/Features/Fleet/IOSAssignDriverSheet.swift",
            contains: ".presentationDetents([.large])"
        )
        try assertSource(
            at: "Weird Parts IOS/Features/Fleet/PreTripInspectionView.swift",
            contains: ".presentationDetents([.large])"
        )
    }

    private func assertSource(
        at relativePath: String,
        contains expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try Self.readSource(relativePath: relativePath, file: file)
        XCTAssertTrue(source.contains(expected), "\(relativePath) should include \(expected)", file: file, line: line)
    }

    private static func readSource(relativePath: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
