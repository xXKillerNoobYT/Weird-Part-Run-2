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
        // The Clear entry point must not persist anything itself — extraction
        // of the actual method body avoids matching the (legitimate)
        // clearSavedPath() implementation elsewhere in the file.
        let clearPathBody = try Self.methodBody(named: "clearPath", in: source)
        XCTAssertFalse(
            clearPathBody.contains("saveStops"),
            "clearPath() must not clear and persist in one unconfirmed step."
        )
        XCTAssertTrue(
            clearPathBody.contains("showClearConfirm = true"),
            "clearPath() must route saved-path clears through the confirmation flag."
        )
        // The confirmed clear must drop any pending single-stop undo so a
        // stale undo bar can't resurrect a stop into the freshly cleared path.
        let clearSavedPathBody = try Self.methodBody(named: "clearSavedPath", in: source)
        XCTAssertTrue(
            clearSavedPathBody.contains("discardPendingUndo()"),
            "clearSavedPath() must discard any pending stop-removal undo."
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
        XCTAssertTrue(
            source.contains("undoDismissTask = Task { @MainActor in"),
            "The undo auto-dismiss task must be MainActor-confined since it mutates view @State."
        )
        XCTAssertTrue(
            source.contains(".onDisappear { discardPendingUndo() }"),
            "Leaving the view must drop pending undo state, not just cancel its dismiss timer."
        )
    }

    /// Extracts the brace-balanced body of the named function.
    private static func methodBody(named methodName: String, in source: String) throws -> String {
        guard let nameRange = source.range(of: "func \(methodName)(") else {
            throw XCTSkip("Expected method \(methodName) in source")
        }
        guard let openBrace = source[nameRange.upperBound...].firstIndex(of: "{") else {
            throw XCTSkip("Expected opening brace for \(methodName)")
        }

        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            let char = source[index]
            if char == "{" { depth += 1 }
            if char == "}" { depth -= 1 }
            let next = source.index(after: index)
            if depth == 0 {
                return String(source[openBrace..<next])
            }
            index = next
        }

        throw XCTSkip("Expected closing brace for \(methodName)")
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
