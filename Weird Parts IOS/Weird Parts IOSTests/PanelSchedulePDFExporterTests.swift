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

    func testExportRendersAgainstNormalizedScheduleNotRawInput() throws {
        // A malformed totalSpaces (mirrors #1239) must not crash rendering; the
        // exporter should normalize before drawing the table, same as the
        // builder's Save action does.
        var schedule = PanelSchedule(panelName: "Bad Panel", totalSpaces: -4)
        schedule.circuits = [CircuitEntry(spaceNumber: 1, breakerAmps: 20, circuitDescription: "Test", isSpare: false)]

        let url = try PanelSchedulePDFExporter(schedule: schedule, options: PanelScheduleExportOptions())
            .writeToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0, "Exporting a schedule with a malformed totalSpaces should still normalize and render, not crash or produce an empty file.")
    }
}
