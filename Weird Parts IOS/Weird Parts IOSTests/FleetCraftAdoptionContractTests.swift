import XCTest

/// Adoption contract for the panel-quality craft pass over the Fleet area
/// (#1421 Wave 2, docs/plans/panel-quality-uplift.md).
///
/// Intentional source-token adoption checks (scans for `"fleet-` identifier
/// prefixes, `.rowAccessibility(`, `.contextMenu`) pinning area-level floors
/// set by the 2026-07-07 pass (the area was 1/19 files before it) — not
/// user-visible copy assertions, so pages can keep evolving.
final class FleetCraftAdoptionContractTests: XCTestCase {

    func testFleetAreaUsesStableAccessibilityIdentifiers() throws {
        var filesWithIds = 0
        for page in try Self.allFleetSourceFiles() {
            if try Self.readFleetSource(named: page).contains("\"fleet-") { filesWithIds += 1 }
        }
        XCTAssertGreaterThanOrEqual(
            filesWithIds, 16,
            "Fleet pages carrying stable 'fleet-' accessibility identifiers dropped below the Wave-2 adoption floor."
        )
    }

    func testFleetAreaUsesTheSharedRowAccessibilityKit() throws {
        var filesUsingKit = 0
        for page in try Self.allFleetSourceFiles() {
            if try Self.readFleetSource(named: page).contains(".rowAccessibility(") { filesUsingKit += 1 }
        }
        XCTAssertGreaterThanOrEqual(
            filesUsingKit, 12,
            "Fleet pages using the shared .rowAccessibility kit dropped below the Wave-2 adoption floor."
        )
    }

    func testFleetAreaOffersContextMenuSecondInputPaths() throws {
        var filesWithMenus = 0
        for page in try Self.allFleetSourceFiles() {
            if try Self.readFleetSource(named: page).contains(".contextMenu") { filesWithMenus += 1 }
        }
        XCTAssertGreaterThanOrEqual(
            filesWithMenus, 3,
            "Fleet pages offering a context-menu second input path dropped below the Wave-2 adoption floor."
        )
    }

    /// The driver-assignment selection state must stay audible: the row's
    /// accessibilityValue is the only non-visual cue (the checkmark is hidden).
    /// Pins the structural condition (a selection-dependent value), not the
    /// word — copy/localization can change without breaking this.
    func testAssignDriverSelectionStateIsAudible() throws {
        let source = try Self.readFleetSource(named: "IOSAssignDriverSheet.swift")
        XCTAssertNotNil(
            source.range(
                of: #"value:\s*selectedEmployeeId\s*==\s*employee\.id\s*\?"#,
                options: .regularExpression
            ),
            "IOSAssignDriverSheet lost its selection-conditional accessibility value — the hidden checkmark must never be the only cue for which driver is selected."
        )
    }

    // MARK: - Source loading

    private static func fleetDirectory(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // "Weird Parts IOS" project directory
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Fleet")
    }

    private static func allFleetSourceFiles() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: fleetDirectory().path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
    }

    private static func readFleetSource(named filename: String) throws -> String {
        try String(contentsOf: fleetDirectory().appendingPathComponent(filename), encoding: .utf8)
    }
}
