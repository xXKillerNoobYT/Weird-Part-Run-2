import XCTest

/// Adoption contract for the panel-quality craft pass over the Settings area
/// (#1421 Wave 2, docs/plans/panel-quality-uplift.md).
///
/// These are intentional source-token adoption checks (scans for `"settings-`
/// identifier prefixes, `.rowAccessibility(`, `.contextMenu`) — NOT
/// user-visible copy assertions. They pin area-level adoption floors set by
/// the 2026-07-07 pass (the area was 0/39 files before it), so pages can keep
/// evolving without breaking them.
final class SettingsCraftAdoptionContractTests: XCTestCase {

    func testSettingsAreaUsesStableAccessibilityIdentifiers() throws {
        var filesWithIds = 0
        for page in try Self.allSettingsSourceFiles() {
            if try Self.readSettingsSource(named: page).contains("\"settings-") { filesWithIds += 1 }
        }
        XCTAssertGreaterThanOrEqual(
            filesWithIds, 35,
            "Settings pages carrying stable 'settings-' accessibility identifiers dropped below the Wave-2 adoption floor."
        )
    }

    func testSettingsAreaUsesTheSharedRowAccessibilityKit() throws {
        var filesUsingKit = 0
        for page in try Self.allSettingsSourceFiles() {
            if try Self.readSettingsSource(named: page).contains(".rowAccessibility(") { filesUsingKit += 1 }
        }
        XCTAssertGreaterThanOrEqual(
            filesUsingKit, 12,
            "Settings pages using the shared .rowAccessibility kit dropped below the Wave-2 adoption floor."
        )
    }

    func testSettingsAreaOffersContextMenuSecondInputPaths() throws {
        var filesWithMenus = 0
        for page in try Self.allSettingsSourceFiles() {
            if try Self.readSettingsSource(named: page).contains(".contextMenu") { filesWithMenus += 1 }
        }
        XCTAssertGreaterThanOrEqual(
            filesWithMenus, 6,
            "Settings pages offering a context-menu second input path dropped below the Wave-2 adoption floor."
        )
    }

    /// The database-reset flow must keep its layered safeguards: the PIN gate
    /// AND the final role-correct alert added by the Wave-2 pass.
    func testDatabaseResetKeepsFinalConfirmationLayer() throws {
        let source = try Self.readSettingsSource(named: "IOSDatabaseResetPage.swift")
        XCTAssertTrue(
            source.contains("Erase all data on this device?"),
            "Database reset lost its final confirmation alert — the wipe must never fire directly from the PIN screen."
        )
        XCTAssertTrue(
            source.contains("verifyAdminApproval"),
            "Database reset lost its admin-PIN verification gate."
        )
    }

    // MARK: - Source loading

    private static func settingsDirectory(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // project root
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Settings")
    }

    private static func allSettingsSourceFiles() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: settingsDirectory().path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
    }

    private static func readSettingsSource(named filename: String) throws -> String {
        try String(contentsOf: settingsDirectory().appendingPathComponent(filename), encoding: .utf8)
    }
}
