import XCTest

final class GeofenceAlertViewRegressionTests: XCTestCase {
    func testSupplyRunExitReasonStartsSupplyRunBeforeAcknowledgingAlert() throws {
        let source = try Self.readGeofenceAlertSource()
        XCTAssertTrue(source.contains("case .supplyRun:"))
        XCTAssertTrue(source.contains("guard let entryId = activeEntryId else"))
        XCTAssertTrue(source.contains("await showMissingActiveClockEntryError()"))
        XCTAssertTrue(source.contains("let notes = try service.getLaborEntryNotes(laborEntryId: entryId)"))
        XCTAssertTrue(source.contains("if !JobsService.isOnSupplyRun(notes: notes)"))
        XCTAssertTrue(source.contains("let newStatus = try service.toggleSupplyRun(laborEntryId: entryId)"))
        XCTAssertTrue(source.contains("guard newStatus == \"supply_run\" else"))
        XCTAssertTrue(
            source.contains("Supply run could not be started. Please refresh the Clock page and try again."),
            "Geofence Supply Run must surface an error if the active labor entry fails to enter supply-run state."
        )

        XCTAssertFalse(
            source.contains("// Stay clocked in, acknowledge and continue"),
            "The Supply Run branch must not remain a no-op."
        )

        let supplyRunCase = try XCTUnwrap(source.range(of: "case .supplyRun:"))
        let supplyRunToggle = try XCTUnwrap(source.range(
            of: "let newStatus = try service.toggleSupplyRun(laborEntryId: entryId)",
            range: supplyRunCase.upperBound..<source.endIndex
        ))
        let acknowledgeExit = try XCTUnwrap(source.range(of: "geofenceManager.acknowledgeExit()"))
        XCTAssertTrue(
            supplyRunToggle.lowerBound < acknowledgeExit.lowerBound,
            "Geofence Supply Run must start supply-run state before acknowledging and resolving the alert."
        )
    }

    func testClockEntryRequiredGeofenceReasonsDoNotResolveWithoutActiveEntry() throws {
        let source = try Self.readGeofenceAlertSource()

        XCTAssertTrue(source.contains("if reason.requiresActiveClockEntry && activeEntryId == nil"))
        XCTAssertTrue(source.contains("await showMissingActiveClockEntryError()"))
        XCTAssertTrue(source.contains("No active clock entry was found. Please refresh the Clock page and try again."))
        XCTAssertTrue(source.contains("showError = true"))
        XCTAssertTrue(
            source.contains("case .supplyRun, .lunch, .breakTime, .doneForDay:"),
            "Clock-mutating geofence responses should require an active clock entry."
        )
        XCTAssertTrue(
            source.contains("case .anotherJob, .other:"),
            "Non-clock-entry responses should not require an active clock entry."
        )
    }

    private static func readGeofenceAlertSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("App")
            .appendingPathComponent("GeofenceAlertView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
