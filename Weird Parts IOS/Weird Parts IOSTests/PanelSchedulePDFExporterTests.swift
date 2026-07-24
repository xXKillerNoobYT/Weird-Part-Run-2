import XCTest
import PDFKit
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

    func testWriteToTemporaryFileRendersSecondaryCircuitDescription() throws {
        var schedule = PanelSchedule(panelName: "Tandem Panel")
        schedule.circuits = [
            CircuitEntry(
                spaceNumber: 1,
                breakerAmps: 20,
                breakerType: .tandem,
                circuitDescription: "Kitchen",
                isSpare: false,
                secondaryCircuitDescription: "Pantry"
            )
        ]

        let url = try PanelSchedulePDFExporter(schedule: schedule, options: PanelScheduleExportOptions())
            .writeToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let renderedText = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0)?.string)
        XCTAssertTrue(renderedText.contains("Kitchen / Pantry"), "The PDF circuit row must render both tandem circuit descriptions.")
    }

    func testWriteToTemporaryFileRejectsInvalidCircuitPositionsWithoutWritingPDF() throws {
        let panelName = "InvalidPanel\(UUID().uuidString)"
        var schedule = PanelSchedule(panelName: panelName, totalSpaces: 4)
        schedule.circuits = [
            CircuitEntry(
                spaceNumber: 3,
                breakerAmps: 30,
                breakerType: .double,
                circuitDescription: "Out of Range",
                isSpare: false
            )
        ]
        let exporter = PanelSchedulePDFExporter(schedule: schedule, options: PanelScheduleExportOptions())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PanelSchedules", isDirectory: true)
        let date = DateFormatter.panelScheduleFilenameDate.string(from: Date())
        let expectedURL = directory.appendingPathComponent("\(panelName)_\(date).pdf")
        try? FileManager.default.removeItem(at: expectedURL)
        defer { try? FileManager.default.removeItem(at: expectedURL) }

        XCTAssertThrowsError(try exporter.writeToTemporaryFile()) { error in
            XCTAssertEqual(error as? PanelScheduleValidationError, .doubleBreakerOutOfRange(space: 3))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedURL.path), "An invalid panel schedule must not write a PDF for export or print.")
    }

    func testWriteToTemporaryFileRejectsOverlappingCircuitPositionsWithoutWritingPDF() throws {
        let panelName = "OverlappingPanel\(UUID().uuidString)"
        var schedule = PanelSchedule(panelName: panelName, totalSpaces: 20)
        schedule.circuits = [
            CircuitEntry(id: "double-breaker", spaceNumber: 1, breakerAmps: 30, breakerType: .double, circuitDescription: "Range", isSpare: false),
            CircuitEntry(id: "overlapping-single", spaceNumber: 3, breakerAmps: 20, breakerType: .single, circuitDescription: "Kitchen", isSpare: false)
        ]
        let exporter = PanelSchedulePDFExporter(schedule: schedule, options: PanelScheduleExportOptions())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PanelSchedules", isDirectory: true)
        let date = DateFormatter.panelScheduleFilenameDate.string(from: Date())
        let expectedURL = directory.appendingPathComponent("\(panelName)_\(date).pdf")
        try? FileManager.default.removeItem(at: expectedURL)
        defer { try? FileManager.default.removeItem(at: expectedURL) }

        XCTAssertThrowsError(try exporter.writeToTemporaryFile()) { error in
            XCTAssertEqual(error as? PanelScheduleValidationError, .spaceConflict(space: 3, first: 1, second: 3))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedURL.path), "An overlapping schedule must not write a PDF for export or print.")
    }
}

private extension DateFormatter {
    static let panelScheduleFilenameDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
