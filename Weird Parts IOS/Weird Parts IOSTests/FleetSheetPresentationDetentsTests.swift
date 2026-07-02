import XCTest

final class FleetSheetPresentationDetentsTests: XCTestCase {
    func testHeavyFleetSheetsPinLargePresentationDetent() throws {
        let sheetFiles = [
            "IOSCreateVehicleSheet.swift",
            "IOSCreateTrailerSheet.swift",
            "IOSAssignDriverSheet.swift",
            "PreTripInspectionView.swift"
        ]

        for file in sheetFiles {
            let source = try String(contentsOfFile: fleetSourcePath(file), encoding: .utf8)
            XCTAssertTrue(
                source.contains(".presentationDetents([.large])"),
                "\(file) should explicitly pin the large sheet detent."
            )
        }
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
