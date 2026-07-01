import XCTest

/// Regression tests for GH #1081: Part Match photo imports must not fail silently.
final class PartMatchPhotoImportFailureTests: XCTestCase {
    func testPhotoImportUsesExplicitFailureHandling() throws {
        let source = try Self.readPartMatchSource()

        XCTAssertFalse(
            source.contains("try? await item?.loadTransferable(type: Data.self)") ||
                source.contains("try? await item.loadTransferable(type: Data.self)"),
            "Part Match photo import must not swallow photo-library transfer errors with try?."
        )
        XCTAssertTrue(
            source.contains("@MainActor") &&
                source.contains("private func loadSelectedPhoto(_ item: PhotosPickerItem?) async") &&
                source.contains("do {") &&
                source.contains("} catch {") &&
                source.contains("try await item.loadTransferable(type: Data.self)"),
            "Photo import should use a main-actor explicit do/catch load path so failures can be surfaced to the user safely."
        )
    }

    func testPhotoImportShowsActionableErrorsAndClearsStaleState() throws {
        let source = try Self.readPartMatchSource()

        XCTAssertTrue(
            source.contains("errorMessage = \"Could not load that photo. Try another image or use Camera.\"") &&
                source.contains("errorMessage = \"Could not read that photo. Try another image or use Camera.\""),
            "Photo transfer and decode failures must show actionable Part Match error copy."
        )
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: "selectedImage = nil").count - 1,
            2,
            "Photo transfer/decode failures must clear any stale selected image instead of leaving the old image visible."
        )
        XCTAssertTrue(
            source.contains("matchResults = []"),
            "Starting a new photo import must clear stale match results."
        )
        XCTAssertTrue(
            source.contains("selectedImage = uiImage") && source.contains("errorMessage = nil"),
            "A successful import should select the new image and clear stale errors."
        )
    }

    // MARK: - Helpers

    private static func readPartMatchSource(file: StaticString = #filePath) throws -> String {
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
