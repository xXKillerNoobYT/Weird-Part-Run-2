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

    func testGeofenceAlertHasManualDismissPathThatDoesNotCallJobServices() throws {
        let source = try Self.readGeofenceAlertSource()
        let clockPageSource = try Self.readClockPageSource()

        XCTAssertTrue(source.contains("Button(\"Not Now\")"))
        XCTAssertTrue(source.contains("Button(\"Dismiss Alert\", role: .destructive)"))
        XCTAssertTrue(source.contains("private func dismissWithoutServiceCall()"))
        XCTAssertTrue(source.contains("geofenceManager.acknowledgeExit()"))
        XCTAssertTrue(source.contains("onResolved()"))
        XCTAssertTrue(source.contains(".interactiveDismissDisabled(isProcessing)"))
        XCTAssertFalse(
            clockPageSource.contains(".interactiveDismissDisabled(true)"),
            "The full-screen geofence alert must not be hard-locked by the presenting Clock page."
        )

        let dismissFunction = try XCTUnwrap(source.range(of: "private func dismissWithoutServiceCall()"))
        let dismissBody = source[dismissFunction.lowerBound..<source.endIndex]
        let dismissEnd = try XCTUnwrap(dismissBody.range(of: "// MARK: - Load Jobs"))
        let manualDismissSource = String(dismissBody[..<dismissEnd.lowerBound])

        XCTAssertFalse(manualDismissSource.contains("appCore.jobsService"))
        XCTAssertFalse(manualDismissSource.contains("getActiveClockEntry"))
        XCTAssertFalse(manualDismissSource.contains("clockOut"))
        XCTAssertFalse(manualDismissSource.contains("switchClockedInJob"))
        XCTAssertFalse(manualDismissSource.contains("toggleSupplyRun"))
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

    private static func readClockPageSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Jobs")
            .appendingPathComponent("IOSClockPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
