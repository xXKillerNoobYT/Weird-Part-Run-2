import XCTest

final class QRScanSheetRegressionTests: XCTestCase {
    func testScanResultCallbackRunsInsideMainActorDismissBlock() throws {
        let source = try String(contentsOfFile: scanningSourcePath("QRScanSheet.swift"), encoding: .utf8)
        let normalized = normalizedSource(source)

        XCTAssertTrue(
            normalized.contains("awaitMainActor.run{"),
            "QRScanSheet should use MainActor.run for result-state and dismissal updates."
        )
        XCTAssertTrue(
            normalized.contains("ifshouldAutoComplete{dismiss()onResult(result)}"),
            "QRScanSheet must invoke onResult(result) in the same MainActor block as dismiss()."
        )
        XCTAssertFalse(
            normalized.contains("awaitMainActor.run{dismiss()}onResult(result)"),
            "QRScanSheet must not invoke the parent state callback after leaving MainActor."
        )
    }

    func testDuplicateScanGuardPreventsOverlappingProcessing() throws {
        let source = try String(contentsOfFile: scanningSourcePath("QRScanSheet.swift"), encoding: .utf8)
        let normalized = normalizedSource(source)

        XCTAssertTrue(
            normalized.contains("letshouldSkip=awaitMainActor.run{ifisProcessing{returntrue}"),
            "QRScanSheet should claim its processing slot on MainActor before async lookup work."
        )
        XCTAssertTrue(
            normalized.contains("ifletcurrent=resultCode,current==payload,resultIsFound{returntrue}"),
            "QRScanSheet should retain the completed-payload duplicate guard."
        )
        XCTAssertTrue(
            normalized.contains("isProcessing=true") && normalized.contains("ifshouldSkip{return}"),
            "Overlapping scans should return without starting another lookup."
        )
    }

    private func normalizedSource(_ source: String) -> String {
        source.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    private func scanningSourcePath(_ fileName: String) -> String {
        appSourceRoot().appendingPathComponent("Scanning").appendingPathComponent(fileName).path
    }

    private func appSourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Weird Parts IOS")
    }
}
