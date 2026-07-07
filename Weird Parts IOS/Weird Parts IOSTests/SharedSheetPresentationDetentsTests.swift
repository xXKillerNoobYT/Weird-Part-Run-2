import XCTest

final class SharedSheetPresentationDetentsTests: XCTestCase {
    func testSharedHelpAndDismissWrappersUseMediumLargePresentationDetents() throws {
        for file in ["PageHelpSheet.swift", "SheetDismissWrapper.swift"] {
            let source = try String(contentsOfFile: sharedSourcePath(file), encoding: .utf8)
            XCTAssertTrue(
                source.contains(".presentationDetents([.medium, .large])"),
                "\(file) should provide medium/large sheet detents for app-wide short informational sheets."
            )
            XCTAssertTrue(
                source.contains(".presentationDragIndicator(.visible)"),
                "\(file) should expose a visible drag indicator with its detents."
            )
        }
    }

    func testSharedFormSheetPinsLargePresentationDetent() throws {
        let source = try String(contentsOfFile: sharedSourcePath("FormSheet.swift"), encoding: .utf8)
        XCTAssertTrue(
            source.contains(".presentationDetents([.large])"),
            "FormSheet should keep create/edit forms full-size while making the detent explicit."
        )
        XCTAssertTrue(
            source.contains(".presentationDragIndicator(.visible)"),
            "FormSheet should expose a visible drag indicator with its explicit detent."
        )
    }

    func testQRScanSheetUsesMediumPresentationDetent() throws {
        let source = try String(contentsOfFile: scanningSourcePath("QRScanSheet.swift"), encoding: .utf8)
        XCTAssertTrue(
            source.contains(".presentationDetents([.medium])"),
            "QRScanSheet should use a medium sheet detent for quick scan/manual-entry flows."
        )
        XCTAssertTrue(
            source.contains(".presentationDragIndicator(.visible)"),
            "QRScanSheet should expose a visible drag indicator with its detent."
        )
    }

    private func sharedSourcePath(_ fileName: String) -> String {
        appSourceRoot()
            .appendingPathComponent("Shared")
            .appendingPathComponent(fileName)
            .path
    }

    private func scanningSourcePath(_ fileName: String) -> String {
        appSourceRoot()
            .appendingPathComponent("Scanning")
            .appendingPathComponent(fileName)
            .path
    }

    private func appSourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Weird Parts IOS")
    }
}
