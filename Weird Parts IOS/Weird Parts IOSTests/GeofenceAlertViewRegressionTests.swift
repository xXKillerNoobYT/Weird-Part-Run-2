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

    func testLunchAndBreakExitReasonsStartBreakRecordsInsteadOfClockingOut() throws {
        let source = try Self.readGeofenceAlertSource()

        XCTAssertFalse(
            source.contains("case .lunch, .breakTime, .doneForDay:"),
            "Lunch/break geofence responses must not share the Done-for-Day clock-out branch."
        )
        XCTAssertTrue(source.contains("case .lunch:"))
        XCTAssertTrue(source.contains("case .breakTime:"))
        XCTAssertTrue(source.contains("case .doneForDay:"))
        XCTAssertTrue(source.contains("guard let breakSvc = appCore.breakService else"))
        XCTAssertTrue(source.contains("Break service is not available. Please restart the app and try again."))
        XCTAssertTrue(source.contains("Start a paid lunch break. Clock stays active."))

        let lunchCase = try XCTUnwrap(source.range(of: "case .lunch:"))
        let breakCase = try XCTUnwrap(source.range(of: "case .breakTime:"))
        let doneCase = try XCTUnwrap(source.range(of: "case .doneForDay:"))
        let otherCase = try XCTUnwrap(source.range(of: "case .other:"))

        let lunchBody = String(source[lunchCase.upperBound..<breakCase.lowerBound])
        let breakBody = String(source[breakCase.upperBound..<doneCase.lowerBound])
        let doneBody = String(source[doneCase.upperBound..<otherCase.lowerBound])

        XCTAssertTrue(lunchBody.contains("try breakSvc.startBreak"))
        XCTAssertTrue(breakBody.contains("try breakSvc.startBreak"))
        XCTAssertTrue(lunchBody.contains("breakType: \"lunch_paid\""))
        XCTAssertTrue(breakBody.contains("breakType: \"break\""))
        XCTAssertFalse(lunchBody.contains("try service.clockOut"))
        XCTAssertFalse(breakBody.contains("try service.clockOut"))
        XCTAssertTrue(doneBody.contains("try service.clockOut"))
    }

    func testGeofenceAlertHasServiceIndependentDismissEscape() throws {
        let source = try Self.readGeofenceAlertSource()
        let clockPageSource = try Self.readClockPageSource()

        XCTAssertTrue(source.contains("Button(\"Not Now\")"))
        XCTAssertTrue(source.contains("dismissAlertWithoutServiceCall()"))
        XCTAssertNotNil(
            source.range(
                of: #"@MainActor\s+private\s+func\s+dismissAlertWithoutServiceCall\s*\(\s*\)"#,
                options: .regularExpression
            )
        )
        XCTAssertTrue(source.contains("geofenceManager.acknowledgeExit()"))
        XCTAssertTrue(source.contains(".interactiveDismissDisabled(isProcessing)"))
        XCTAssertTrue(clockPageSource.contains("onDismiss: {"))
        XCTAssertTrue(clockPageSource.contains("if geofenceManager.exitTime != nil || geofenceManager.exitLocation != nil"))
        XCTAssertTrue(clockPageSource.contains("geofenceManager.acknowledgeExit()"))
        XCTAssertFalse(
            source.contains(".interactiveDismissDisabled(true)"),
            "The geofence alert must not hard-disable every dismissal path while idle."
        )
        XCTAssertFalse(
            clockPageSource.contains(".interactiveDismissDisabled(true)"),
            "IOSClockPage must not re-disable the geofence full-screen cover after the alert view enables an idle escape path."
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
