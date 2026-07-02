import XCTest

/// Regression coverage for issue #1198: the walking-path editor's Clear
/// action wiped and immediately persisted the saved path (and removed
/// individual stops) with no confirmation or undo affordance.
final class WalkingPathClearConfirmationRegressionTests: XCTestCase {
    func testClearingSavedPathRequiresConfirmation() throws {
        let source = try Self.readWalkingPathSource()

        // Clear must route through the confirmation flag, never persist directly.
        XCTAssertTrue(
            source.contains("showClearConfirm = true"),
            "Clearing a saved path must ask for confirmation before persisting (issue #1198)."
        )
        XCTAssertTrue(
            source.contains("\"Clear walking path?\""),
            "The confirmation dialog must state that the saved path is being cleared."
        )
        XCTAssertTrue(
            source.contains("Button(\"Clear saved path\", role: .destructive) { clearSavedPath() }"),
            "Only the explicit destructive confirmation button may call the persisting clear."
        )
        // The unconfirmed one-tap clear+persist must not exist anymore.
        XCTAssertFalse(
            source.contains("pathStops = []\n            saveStops([])"),
            "clearPath() must not clear and persist in one unconfirmed step."
        )
    }

    func testPreviewDismissalStaysImmediate() throws {
        let source = try Self.readWalkingPathSource()

        XCTAssertTrue(
            source.contains("if isPreviewing {\n            previewStops = nil\n        } else {\n            showClearConfirm = true\n        }"),
            "Dismissing a non-persisted preview must stay immediate and must not show the saved-path warning."
        )
    }

    func testRemovingSingleStopOffersUndo() throws {
        let source = try Self.readWalkingPathSource()

        XCTAssertTrue(
            source.contains("lastRemovedStop = (areaId, index)"),
            "Removing a saved stop should record it for undo."
        )
        XCTAssertTrue(
            source.contains("Button(\"Undo\") { undoRemoveStop() }"),
            "The undo bar must restore the removed stop."
        )
        XCTAssertTrue(
            source.contains("pathStops.insert(removed.areaId, at: min(removed.index, pathStops.count))"),
            "Undo must restore the stop at its original position (clamped)."
        )
        XCTAssertTrue(
            source.contains(".accessibilityIdentifier(\"walkingPathUndoBar\")"),
            "The undo bar needs a stable accessibility identifier for UI tests."
        )
    }

    private static func readWalkingPathSource(
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent("WizardStepWalkingPath.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
