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
        // The spine used to be fixed at 44pt (`.frame(width: 4, height: 44)`), which
        // left gaps beside rows that grow taller under Dynamic Type ("funny edges").
        // It now stretches to the full row height: width-only frame + fixedSize row.
        XCTAssertTrue(
            source.contains(".frame(width: 4)") &&
                source.contains(".fixedSize(horizontal: false, vertical: true)"),
            "The center spine should span the full circuit-row height (width-only frame + row fixedSize), not a fixed 44pt."
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
                // The hint is conditional since move-mode landed: editor hint normally,
                // placement hint while a circuit is being moved. Both must exist.
                source.contains("Opens the editor for circuit \\(spaceNumber).") &&
                source.contains("Moves the selected circuit here.") &&
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

    func testPanelSettingsKeepTypeAndSizeAsAnAtomicDraftUntilDone() throws {
        let source = try Self.readNotebookSource("PanelScheduleBuilder.swift")

        XCTAssertTrue(
            source.contains("@State private var draftPanelType: PanelType") &&
                source.contains("@State private var draftTotalSpaces: Int") &&
                source.contains("Picker(\"Type\", selection: $draftPanelType)") &&
                source.contains("Picker(\"Total Spaces\", selection: $draftTotalSpaces)"),
            "Panel type and size must remain in local draft state until the user confirms them."
        )
        XCTAssertTrue(
            source.contains("ForEach(draftPanelType.allowedTotalSpaces, id: \\.self)") &&
                source.contains("!newType.allowedTotalSpaces.contains(draftTotalSpaces)") &&
                source.contains("draftTotalSpaces = firstAllowedSpace"),
            "The size picker must derive options from the selected type and deterministically repair an invalid draft size after a type change."
        )
        XCTAssertTrue(
            source.contains("try schedule.updatePanelSettings(") &&
                source.contains("panelType: draftPanelType") &&
                source.contains("totalSpaces: draftTotalSpaces") &&
                source.contains("settingsValidationMessage = error.localizedDescription"),
            "Done must atomically submit the draft settings and surface the typed model error without changing the bound schedule on rejection."
        )
        XCTAssertTrue(
            source.contains("schedule.occupiedSpaces(for: circuit)") &&
                source.contains("occupiedSpace > draftTotalSpaces") &&
                source.contains("circuitOriginSpacesThatWouldBeHidden"),
            "The settings warning must account for the second occupied space of a double breaker, not just its origin space."
        )
    }

    func testSpareCircuitSavesNormalizeHiddenActiveMetadata() throws {
        let source = try Self.readNotebookSource("PanelScheduleBuilder.swift")

        // updateCircuit was refactored to validate on a `candidate` copy before
        // committing to `schedule` — the normalization invariant is unchanged, the
        // writes just target the candidate now.
        XCTAssertTrue(
            source.contains("let normalized = circuit.normalizedForPersistence()") &&
                source.contains("candidate.circuits[index] = normalized") &&
                source.contains("candidate.circuits.append(normalized)"),
            "Updating a circuit should normalize spare entries before they are kept in builder state."
        )
        XCTAssertTrue(
            source.contains("onSave(circuit.normalizedForPersistence())"),
            "The circuit editor should not hand contradictory spare/active metadata back to the builder."
        )
    }

    func testCircuitBackgroundKeepsBreakerSafetyColorReachableAlongsideClassification() throws {
        let source = try Self.readNotebookSource("PanelScheduleBuilder.swift")

        XCTAssertTrue(
            source.contains("private func circuitBackground(_ circuit: CircuitEntry?) -> Color"),
            "circuitBackground should remain the single source of circuit cell background color."
        )
        XCTAssertTrue(
            source.contains("case .gfci, .afci, .dualFunction: return .green.opacity(0.1)"),
            "GFCI/AFCI/dual-function breakers must keep their green safety highlight regardless of classification (#1379 review)."
        )

        // The breakerType switch (which carries the GFCI/AFCI/dual-function safety color)
        // must run before the classification switch bails out early for every non-special
        // case, otherwise any classified circuit makes the breaker-type coloring unreachable.
        guard let breakerSwitchRange = source.range(of: "switch circuit.breakerType {"),
              let classificationSwitchRange = source.range(of: "switch circuit.classification {") else {
            XCTFail("Expected both circuit.breakerType and circuit.classification switches in circuitBackground.")
            return
        }
        XCTAssertTrue(
            breakerSwitchRange.lowerBound < classificationSwitchRange.lowerBound,
            "The breaker-type safety-color switch must run before the classification switch so GFCI/AFCI/dual-function coloring is not shadowed by an early classification return."
        )
    }

    func testPanelLegendIncludesSafetyRelevantBreakerEntries() throws {
        let source = try Self.readNotebookSource("PanelScheduleBuilder.swift")

        XCTAssertTrue(
            source.contains("legendDot(.green, \"GFI/AFI\")"),
            "The panel legend must keep a GFI/AFI entry so sighted users can still identify safety breakers visually."
        )
        XCTAssertTrue(
            source.contains("legendDot(.yellow, \"Spare\")"),
            "The panel legend must keep a Spare entry."
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
