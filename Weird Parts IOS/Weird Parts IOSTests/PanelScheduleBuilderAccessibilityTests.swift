import XCTest

/// Regression coverage for GitHub #998 / WEI-3578.
///
/// Panel schedule circuit rows are touch/edit controls in dense field documentation.
/// They must keep a 44pt target and expose a single meaningful accessibility element
/// instead of fragmented text from the row labels.
final class PanelScheduleBuilderAccessibilityTests: XCTestCase {
    func testCircuitCellsExposeMinimumTargetAndEditorAccessibility() throws {
        let source = try Self.readNotebookSource("PanelScheduleBuilder.swift")

        XCTAssertFalse(
            source.contains(".frame(height: 36)"),
            "Circuit cells must not use the old 36pt tap target."
        )
        XCTAssertTrue(
            source.contains(".frame(minHeight: 44)"),
            "Circuit cells should provide at least a 44pt tap target while preserving dense row content."
        )
        XCTAssertTrue(
            source.contains(".frame(width: 4, height: 44)"),
            "The center separator should match the expanded 44pt circuit-row height."
        )
        XCTAssertTrue(
            source.contains(".contentShape(Rectangle())"),
            "The full 44pt row should be tappable, not just visible text."
        )
        XCTAssertFalse(
            source.contains(".accessibilityElement(children: .ignore)"),
            "Do not wrap the Button in a separate explicit accessibility element; XCTest taps can hit that wrapper without firing the button action."
        )
        XCTAssertTrue(
            source.contains("openCircuitEditor(spaceNumber: spaceNumber, circuit: circuit)") &&
                source.contains(".accessibilityLabel(circuitAccessibilityLabel(spaceNumber: spaceNumber, circuit: circuit))") &&
                source.contains(".accessibilityValue(circuitAccessibilityValue(circuit))") &&
                source.contains(".accessibilityHint(\"Opens the editor for circuit \\(spaceNumber).\")") &&
                source.contains(".accessibilityIdentifier(\"panel-schedule-circuit-\\(spaceNumber)\")"),
            "Each real circuit button should expose label/value/hint/identifier directly while preserving its editor action."
        )
        XCTAssertTrue(
            source.contains("private func circuitAccessibilityLabel(spaceNumber: Int, circuit: CircuitEntry?) -> String") &&
                source.contains("\"Circuit \\(spaceNumber), \\(circuitDisplayName(circuit))\"") &&
                source.contains("private func circuitAccessibilityValue(_ circuit: CircuitEntry?) -> String"),
            "PanelScheduleBuilder should build explicit accessible names and values for empty and populated circuits."
        )
        XCTAssertTrue(
            source.contains("Spare circuit, no breaker assigned") &&
                source.contains("\\(amps) amp") &&
                source.contains("\\(circuit.breakerType.rawValue) breaker") &&
                source.contains("fed from \\(fedFrom)"),
            "Accessibility values should distinguish spare circuits from populated circuits and include useful breaker/source context."
        )
    }

    func testSaveNormalizesHiddenCircuitsAfterPanelShrink() throws {
        let source = try Self.readNotebookSource("PanelScheduleBuilder.swift")

        XCTAssertTrue(
            source.contains("let normalized = schedule.normalizedForPersistence()") &&
                source.contains("schedule = normalized") &&
                source.contains("onSave(normalized)"),
            "Saving a panel schedule should persist a normalized copy so hidden circuits and spare-circuit metadata are not left in notebook JSON."
        )
        XCTAssertTrue(
            source.contains("schedule.circuitsOutsideTotalSpaces") &&
                source.contains("Saving will remove"),
            "Panel settings should warn when a shrink will prune hidden circuits above the new total space count."
        )
        XCTAssertTrue(
            source.contains("showHiddenCircuitPruneConfirmation") &&
                source.contains("Remove Hidden Circuits?") &&
                source.contains("Remove & Save"),
            "Saving a shrunk panel with hidden circuits should require explicit confirmation before pruning persisted data."
        )
    }

    func testSpareCircuitSavesNormalizeHiddenActiveMetadata() throws {
        let source = try Self.readNotebookSource("PanelScheduleBuilder.swift")

        XCTAssertTrue(
            source.contains("let normalized = circuit.normalizedForPersistence()") &&
                source.contains("schedule.circuits[index] = normalized") &&
                source.contains("schedule.circuits.append(normalized)"),
            "Updating a circuit should normalize spare entries before they are kept in builder state."
        )
        XCTAssertTrue(
            source.contains("onSave(circuit.normalizedForPersistence())"),
            "The circuit editor should not hand contradictory spare/active metadata back to the builder."
        )
    }

    private static func readNotebookSource(_ filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Notebooks")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
