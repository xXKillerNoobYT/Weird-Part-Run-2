import XCTest

/// Regression coverage for GitHub #1081 / Paperclip WEI-4327.
///
/// The Part Match photo picker must surface photo-library transfer and decode
/// failures instead of silently keeping an empty or stale image state.
final class CameraMatchPhotoImportRegressionTests: XCTestCase {
    func testPhotoPickerImportUsesExplicitErrorHandling() throws {
        let source = try Self.readCameraMatchSource()
        let importSection = try Self.section(
            named: "private func loadPhotoPickerItem",
            in: source,
            endingBefore: "// MARK: - Match"
        )

        XCTAssertFalse(
            importSection.contains("try?"),
            "Photo picker import failures must not be swallowed with try?."
        )
        let normalized = Self.normalizedWhitespace(importSection)

        XCTAssertTrue(
            normalized.contains("do {") && normalized.contains("catch") &&
                normalized.contains("try await item.loadTransferable(type: Data.self)"),
            "Photo picker import should explicitly catch transfer failures."
        )
        XCTAssertTrue(
            importSection.contains("Could not load that photo. Try another image or use Camera."),
            "Photo transfer failures need an actionable visible error."
        )
        XCTAssertTrue(
            importSection.contains("Could not read that photo. Try another image or use Camera."),
            "Invalid image bytes need a distinct decode error."
        )
        XCTAssertTrue(
            normalized.contains("try Task.checkCancellation()"),
            "Photo picker import should avoid stale async completions overwriting newer picker state."
        )
    }

    func testPhotoPickerImportClearsStaleImageResultsAndErrors() throws {
        let source = try Self.readCameraMatchSource()
        let importSection = try Self.section(
            named: "private func loadPhotoPickerItem",
            in: source,
            endingBefore: "// MARK: - Match"
        )
        let normalized = Self.normalizedWhitespace(importSection)

        XCTAssertTrue(
            normalized.contains("selectedImage = nil matchResults = [] errorMessage = nil"),
            "Starting a new photo import should clear stale image/results/errors before async loading."
        )
        XCTAssertTrue(
            normalized.contains("selectedImage = uiImage matchResults = [] errorMessage = nil"),
            "A successful photo import should install the new image and clear stale match results/errors."
        )
    }

    private static func section(named startMarker: String, in source: String, endingBefore endMarker: String) throws -> String {
        guard let start = source.range(of: startMarker) else {
            XCTFail("Missing section starting with \(startMarker)")
            return ""
        }
        let afterStart = source[start.lowerBound...]
        guard let end = afterStart.range(of: endMarker) else {
            XCTFail("Missing section ending before \(endMarker)")
            return ""
        }
        return String(afterStart[..<end.lowerBound])
    }

    private static func normalizedWhitespace(_ source: String) -> String {
        source
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func readCameraMatchSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Scanning")
            .appendingPathComponent("IOSCameraMatchView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
