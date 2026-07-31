import XCTest
import WiredPartCore
@testable import Weird_Parts

/// Regression coverage for GitHub #80 slice 3 (panel schedule PDF export),
/// re-landing rescued commit `22f5a5c31`.
@MainActor
final class PanelSchedulePDFExporterTests: XCTestCase {
    func testWriteToTemporaryFileProducesNonEmptyPDFInScopedDirectory() throws {
        var schedule = PanelSchedule(panelName: "Main Panel A")
        schedule.circuits = [
            CircuitEntry(spaceNumber: 1, breakerAmps: 20, breakerType: .single, circuitDescription: "Kitchen Outlets", isSpare: false),
            CircuitEntry(spaceNumber: 2, breakerAmps: 15, breakerType: .single, circuitDescription: "Living Room Lights", isSpare: false)
        ]
        let exporter = PanelSchedulePDFExporter(schedule: schedule, options: PanelScheduleExportOptions())

        let url = try exporter.writeToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(url.path.contains("PanelSchedules"), "PDF should be written under the scoped PanelSchedules temp directory.")
        XCTAssertEqual(url.pathExtension, "pdf")

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0, "Exported PDF must not be empty.")
    }

    func testFilenameSanitizesPanelNameAndFallsBackWhenEmpty() throws {
        let unsafeSchedule = PanelSchedule(panelName: "Main / Panel #1 (2026)")
        let unsafeURL = try PanelSchedulePDFExporter(schedule: unsafeSchedule, options: PanelScheduleExportOptions())
            .writeToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: unsafeURL) }
        XCTAssertFalse(unsafeURL.lastPathComponent.contains("/"), "Sanitized filename must not retain path-unsafe characters.")
        XCTAssertFalse(unsafeURL.lastPathComponent.contains("#"), "Sanitized filename must not retain path-unsafe characters.")

        let blankSchedule = PanelSchedule(panelName: "   ")
        let blankURL = try PanelSchedulePDFExporter(schedule: blankSchedule, options: PanelScheduleExportOptions())
            .writeToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: blankURL) }
        XCTAssertTrue(blankURL.lastPathComponent.hasPrefix("Panel_Schedule_"), "Blank panel names should fall back to a default filename stem.")
    }

    func testExportNormalizesMalformedTotalSpacesBeforeRendering() throws {
        // A malformed totalSpaces (mirrors #1239) must not crash rendering.
        // `writeToTemporaryFile()` always renders a `normalizedForPersistence()`
        // copy, so this exercises the *normalization* path — by the time
        // `renderPDF`/`drawScheduleTable` see the schedule, totalSpaces has
        // already been clamped up to a positive supported size (20, the
        // default). It does NOT exercise the negative-totalSpaces guard
        // inside `drawScheduleTable` itself; see
        // `testRenderPDFGuardsAgainstNegativeTotalSpacesWhenCalledDirectly`
        // below for a test that bypasses normalization to cover that guard
        // directly.
        var schedule = PanelSchedule(panelName: "Bad Panel", totalSpaces: -4)
        schedule.circuits = [CircuitEntry(spaceNumber: 1, breakerAmps: 20, circuitDescription: "Test", isSpare: false)]

        let url = try PanelSchedulePDFExporter(schedule: schedule, options: PanelScheduleExportOptions())
            .writeToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0, "Exporting a schedule with a malformed totalSpaces should still normalize and render, not crash or produce an empty file.")
    }

    func testExportRequiresRepairForSafeLoadedLegacyPanelSettings() {
        let schedule = PanelSchedule(
            panelName: "Legacy MDP",
            panelType: .mdp,
            totalSpaces: -2,
            circuits: [
                CircuitEntry(id: "visible", spaceNumber: 1, circuitDescription: "Office", isSpare: false),
                CircuitEntry(id: "retained", spaceNumber: 21, circuitDescription: "Legacy equipment", isSpare: false)
            ]
        )

        XCTAssertThrowsError(
            try PanelSchedulePDFExporter(schedule: schedule, options: PanelScheduleExportOptions())
                .writeToTemporaryFile()
        ) { error in
            guard case PanelScheduleExportError.panelSettingsRequireRepair(let validationError) = error else {
                return XCTFail("Expected a repair-required export error, got \(error)")
            }
            XCTAssertEqual(
                validationError,
                .invalidPanelTypeSpaceCount(panelType: .mdp, spaces: 20, allowedSpaces: [42])
            )
        }
    }

    func testRenderPDFGuardsAgainstNegativeTotalSpacesWhenCalledDirectly() throws {
        // Directly exercises the `max(schedule.totalSpaces / 2, 0)` guard in
        // `drawScheduleTable` by calling the `internal` `renderPDF(schedule:)`
        // entry point with a raw, un-normalized negative `totalSpaces` —
        // bypassing `writeToTemporaryFile()`'s `normalizedForPersistence()`
        // step entirely, since that step would otherwise clamp the value to
        // a positive size (20) before rendering and make this branch
        // unreachable through the normal export/print flow.
        var schedule = PanelSchedule(panelName: "Bad Panel", totalSpaces: -4)
        schedule.circuits = [CircuitEntry(spaceNumber: 1, breakerAmps: 20, circuitDescription: "Test", isSpare: false)]

        let exporter = PanelSchedulePDFExporter(schedule: schedule, options: PanelScheduleExportOptions())
        let data = exporter.renderPDF(schedule: schedule)

        XCTAssertGreaterThan(data.count, 0, "Rendering directly with a negative totalSpaces must not crash and must still produce PDF output.")
    }
}
