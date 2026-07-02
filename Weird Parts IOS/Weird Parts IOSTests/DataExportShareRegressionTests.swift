import XCTest

/// Source-level guards for the Data Export share-sheet polish (GH #1314).
///
/// Covers the three Copilot follow-up findings from PR #1313:
/// 1. Help/info copy must describe the temp-file + immediate share-sheet
///    handoff instead of claiming exports are saved to Documents.
/// 2. The `.share` active-sheet identity must be stable and must not embed
///    file paths.
/// 3. Selected-table export work must run off the main actor.
final class DataExportShareRegressionTests: XCTestCase {
    func testHelpCopyDescribesShareSheetHandoffNotDocumentsStorage() throws {
        let source = try Self.readSettingsSource(named: "IOSDataExportPage.swift")

        XCTAssertFalse(
            source.contains("saved to the app's Documents folder"),
            "Help copy must not claim exports are saved to the Documents folder — they are temp files handed to the share sheet."
        )
        XCTAssertFalse(
            source.contains("saved to this app's Documents folder"),
            "Info copy must not claim exports are saved to the Documents folder — they are temp files handed to the share sheet."
        )
        XCTAssertTrue(
            source.contains("The share sheet opens as soon as the export is ready"),
            "Help copy should explain the immediate share-sheet handoff."
        )
        XCTAssertTrue(
            source.contains("they are not stored inside the app"),
            "Info copy should explain that export files are temporary, not stored in the app."
        )
    }

    func testShareSheetIdentityIsStableAndPathFree() throws {
        let source = try Self.readSettingsSource(named: "IOSDataExportPage.swift")

        XCTAssertTrue(
            source.contains("case .share:") && source.contains("return \"share\""),
            "The .share active-sheet case should use a stable constant ID."
        )
        XCTAssertFalse(
            source.contains("urls.map(\\.path)"),
            "SwiftUI sheet identity must not embed export file paths."
        )
    }

    func testSelectedTableExportRunsOffMainActor() throws {
        let source = try Self.readSettingsSource(named: "IOSDataExportPage.swift")

        XCTAssertTrue(
            source.contains("enum IOSTableExportWriter") &&
            source.contains("nonisolated static func writeExports("),
            "Selected-table export serialization should live in a nonisolated writer helper."
        )
        XCTAssertTrue(
            source.contains("try IOSTableExportWriter.writeExports("),
            "performExport should route file work through the off-main writer helper."
        )
        XCTAssertTrue(
            source.contains("Task.detached(priority: .userInitiated)"),
            "Export work should be detached from the main actor so large exports cannot freeze Settings."
        )
    }

    private static func readSettingsSource(named filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Settings")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
