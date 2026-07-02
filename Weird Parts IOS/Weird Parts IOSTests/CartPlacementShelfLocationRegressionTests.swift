import XCTest

/// Regression coverage for issue #1253: warehouse cart placement destroyed
/// free-form part notes by writing a synthetic "Location: ..." string into
/// `parts.notes` while leaving real location metadata untouched.
///
/// Cart placement must record the destination in the dedicated
/// `shelf_location` column and must never write to the part notes field.
final class CartPlacementShelfLocationRegressionTests: XCTestCase {
    func testCartPlacementWritesShelfLocationNotNotes() throws {
        let source = try Self.readCartManagerSource()

        XCTAssertTrue(
            source.contains("try service.updatePart(id: partId, shelfLocation: location)"),
            "Cart placement should record the destination in the part's dedicated shelf_location column."
        )
        XCTAssertFalse(
            source.contains("updatePart(id: partId, notes:"),
            "Cart placement must never write to the part notes field — that destroyed user-entered notes (issue #1253)."
        )
        XCTAssertFalse(
            source.contains("notes: \"Location:"),
            "Cart placement must not fabricate synthetic Location notes."
        )
    }

    func testCartPlacementStatesMetadataScopeInUI() throws {
        let source = try Self.readCartManagerSource()

        XCTAssertTrue(
            source.contains("Placing updates each part's recorded shelf location."),
            "The cart sheet should state that placement updates recorded location metadata, not stock quantities."
        )
        XCTAssertTrue(
            source.contains("use Guided Movement"),
            "The cart sheet should point users at Guided Movement for real inventory ledger moves."
        )
        XCTAssertTrue(
            source.contains("Bins are marked placed for reference only."),
            "A bins-only cart must not claim shelf locations are being updated (bins are reference-only)."
        )
    }

    func testCartPlacementTrimsLocationBeforeSaving() throws {
        let source = try Self.readCartManagerSource()

        XCTAssertTrue(
            source.contains("guard let location = currentPlacements[item.id]?")
                && source.contains(".trimmingCharacters(in: .whitespacesAndNewlines)")
                && source.contains("!location.isEmpty"),
            "Cart placement should trim the entered location and skip whitespace-only values."
        )
        XCTAssertFalse(
            source.contains("in: .whitespaces)"),
            "All cart trimming must use .whitespacesAndNewlines — a looser character set on the enable check lets newline-only input enable Place All and then place nothing."
        )
    }

    private static func readCartManagerSource(
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent("CartManager.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
