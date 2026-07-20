import XCTest

final class WEI3900ClockFlowQATests: XCTestCase {
    private static let uiTestingPIN = "8396"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["WEIRD_PARTS_UI_TEST_PIN"] = Self.uiTestingPIN
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launchArguments += [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
            "-UITestingOpenDashboardClock"
        ]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// WEI-3900 / WEI-3914 clock QA entry point.
    ///
    /// Keep this source file present because the UI test target's synchronized
    /// source list expects it. The test uses the real app shell and clock page
    /// controls rather than a static fixture: it deep-links to Dashboard > Clock,
    /// verifies the phone/tablet-relevant break/lunch/supply-run controls, and
    /// exercises whichever clock state the seeded UI-test database exposes.
    @MainActor
    func testClockBreakLunchAndTodayEntriesUserFlow() throws {
        app.launch()
        // Give the clock page's async service/location refresh a short window to settle
        // before starting XCTest snapshot polling; querying during that launch window
        // can make XCTest report the app main run loop as busy.
        RunLoop.current.run(until: Date().addingTimeInterval(8))

        XCTAssertTrue(
            waitForClockPage(),
            "Clock page should open through the user-facing Dashboard > Clock route"
        )

        if isNotClockedInState() {
            allowLocationIfPrompted()
            clockIntoShopIfPossible()
        }

        XCTAssertTrue(
            waitForClockContent(timeout: 20),
            "Clock page should render current status, today's hours, or clock-in options after launch"
        )

        verifyBreakLunchAndSupplyRunControlsAreReachable()
    }

    /// GitHub #1450 / WEI-4956 regression: the canonical active Supply Run
    /// card must cross a real minute boundary while the foreground Clock page
    /// remains untouched. This intentionally waits instead of navigating away
    /// and back, which previously hid the invalidated timer bug.
    @MainActor
    func testActiveSupplyRunDurationAdvancesWithoutLeavingClockPage() throws {
        app.launchArguments.append("-UITestingActiveSupplyRunNearMinute")
        app.launch()
        allowLocationIfPrompted()

        XCTAssertTrue(waitForClockPage())
        // SwiftUI exports the combined card identifier on a container whose
        // XCUI element type varies by OS/runtime; keep this stable-identifier
        // query type-agnostic and assert singularity below.
        let cards = app.descendants(matching: .any).matching(identifier: "clock-active-supply-run-card")
        let card = cards.firstMatch
        for _ in 0..<6 where !card.exists {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "The deterministic active Supply Run should show one canonical card.")
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(card.label, "Supply Run Active")

        let initialValue = try XCTUnwrap(card.value as? String)
        let initialMinutes = try XCTUnwrap(durationMinutes(in: initialValue))

        XCTAssertTrue(
            waitUntil(timeout: 70) {
                guard let value = card.value as? String,
                      let minutes = durationMinutes(in: value) else { return false }
                return value != initialValue && minutes > initialMinutes
            },
            "The foreground card accessibility value must advance from its observed duration without leaving or re-entering the Clock page. Initial: \(initialValue). Last: \(String(describing: card.value))"
        )
    }

    /// GitHub #1450 / #1456: AX5 must preserve the active Supply Run state,
    /// complete accessibility semantics, and 44pt primary controls.
    @MainActor
    func testActiveSupplyRunAX5LayoutAndAccessibilityState() throws {
        app.launchArguments += [
            "-UITestingActiveSupplyRunNearMinute",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        allowLocationIfPrompted()

        XCTAssertTrue(waitForClockPage())
        let cards = app.descendants(matching: .any).matching(identifier: "clock-active-supply-run-card")
        let card = cards.firstMatch
        for _ in 0..<8 where !card.exists {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(card.label, "Supply Run Active")
        let value = try XCTUnwrap(card.value as? String)
        XCTAssertTrue(value.contains("Started "))
        XCTAssertNotNil(durationMinutes(in: value))
        XCTAssertTrue(value.contains("Billable while active"))
        XCTAssertFalse(app.staticTexts["Location Required"].exists)
        XCTAssertFalse(app.staticTexts["Location Access Denied"].exists)

        for identifier in ["clockPage_clockOut", "clockPage_switchJob", "clockPage_statePicker"] {
            let button = app.buttons[identifier]
            for _ in 0..<10 where !button.isHittable || button.frame.maxY > app.frame.maxY - 120 {
                app.swipeUp()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
            XCTAssertTrue(button.exists, "\(identifier) should remain reachable at AX5")
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, "\(identifier) width")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(identifier) height")
            XCTAssertLessThanOrEqual(
                button.frame.maxY,
                app.frame.maxY - 100,
                "\(identifier) must scroll fully above persistent bottom navigation"
            )
        }

        let statePicker = app.buttons["clockPage_statePicker"]
        XCTAssertEqual(statePicker.label, "Open break, lunch, and end supply run options")
        XCTAssertEqual(statePicker.value as? String, "Supply run active")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Supply Run AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForClockPage(timeout: TimeInterval = 25) -> Bool {
        waitUntil(timeout: timeout) {
            app.navigationBars["Clock In / Out"].exists
                || app.staticTexts["Clock In / Out"].exists
                || app.staticTexts["Today's Hours"].exists
                || app.staticTexts["Current Status"].exists
                || app.buttons["Shop / Warehouse"].exists
        }
    }

    private func waitForClockContent(timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            app.staticTexts["Today's Hours"].exists
                || app.staticTexts["Current Status"].exists
                || app.staticTexts["Clocked In"].exists
                || app.buttons["Shop / Warehouse"].exists
                || app.staticTexts["Location Required"].exists
                || app.staticTexts["Location Access Denied"].exists
                || app.buttons["Paid Lunch"].exists
                || app.buttons["Paid Break"].exists
        }
    }

    private func isNotClockedInState() -> Bool {
        app.buttons["Shop / Warehouse"].exists || app.staticTexts["Shop / Warehouse"].exists
    }

    private func clockIntoShopIfPossible() {
        let shopButton = firstExistingElement([
            app.buttons["Shop / Warehouse"],
            app.staticTexts["Shop / Warehouse"]
        ], timeout: 3)
        guard let shopButton else { return }
        makeVisibleAndTap(shopButton)

        if app.buttons["Assign & Clock In"].waitForExistence(timeout: 3) {
            app.buttons["Assign & Clock In"].tap()
        }

        _ = waitUntil(timeout: 15) {
            app.staticTexts["Clocked In"].exists
                || app.staticTexts["Current Status"].exists
                || app.buttons["Paid Lunch"].exists
                || app.buttons["Paid Break"].exists
        }
    }

    private func allowLocationIfPrompted() {
        if app.buttons["Allow Location Access"].waitForExistence(timeout: 2) {
            app.buttons["Allow Location Access"].tap()
        }

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButtons = [
            springboard.buttons["Allow While Using App"],
            springboard.buttons["Allow Once"],
            springboard.buttons["Allow"],
        ]
        if let allow = firstExistingElement(allowButtons, timeout: 3) {
            allow.tap()
        }
    }

    private func verifyBreakLunchAndSupplyRunControlsAreReachable() {
        if scrollUntilClockedInControlExists(maxSwipes: 4) {
            XCTAssertTrue(
                waitUntil(timeout: 5) {
                    app.buttons["Paid Lunch"].exists
                        || app.buttons["Paid Break"].exists
                        || app.buttons["Unpaid Lunch"].exists
                        || app.buttons["Supply Run"].exists
                        || app.buttons["End Run"].exists
                        || app.buttons["End Lunch"].exists
                        || app.buttons["End Break"].exists
                        || app.buttons["Resume Work"].exists
                        || app.staticTexts["Today's Hours"].exists
                },
                "Clocked-in page should expose break/lunch/supply-run controls or today's hours"
            )
        } else {
            XCTAssertTrue(
                waitUntil(timeout: 5) {
                    app.buttons["Shop / Warehouse"].exists
                        || app.staticTexts["Today's Hours"].exists
                        || app.staticTexts["Location Required"].exists
                        || app.staticTexts["Location Access Denied"].exists
                },
                "Not-clocked-in page should expose clock-in options, today's hours, or a location-permission blocker"
            )
        }
    }

    private func scrollUntilClockedInControlExists(maxSwipes: Int) -> Bool {
        for attempt in 0...maxSwipes {
            if app.buttons["Paid Lunch"].exists
                || app.buttons["Paid Break"].exists
                || app.buttons["Unpaid Lunch"].exists
                || app.buttons["Supply Run"].exists
                || app.buttons["End Run"].exists
                || app.buttons["End Lunch"].exists
                || app.buttons["End Break"].exists
                || app.buttons["Resume Work"].exists {
                return true
            }
            if attempt < maxSwipes {
                app.swipeUp()
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
        }
        return false
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return false
    }

    private func durationMinutes(in accessibilityValue: String) -> Int? {
        let expression = try? NSRegularExpression(pattern: #"Duration (\d+)h (\d+)m"#)
        let range = NSRange(accessibilityValue.startIndex..., in: accessibilityValue)
        guard let match = expression?.firstMatch(in: accessibilityValue, range: range),
              let hoursRange = Range(match.range(at: 1), in: accessibilityValue),
              let minutesRange = Range(match.range(at: 2), in: accessibilityValue),
              let hours = Int(accessibilityValue[hoursRange]),
              let minutes = Int(accessibilityValue[minutesRange]) else { return nil }
        return hours * 60 + minutes
    }

    private func makeVisibleAndTap(_ element: XCUIElement) {
        let deadline = Date().addingTimeInterval(6)
        while element.exists && !element.isHittable && Date() < deadline {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func firstExistingElement(_ elements: [XCUIElement], timeout: TimeInterval = 0) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = elements.first(where: { $0.exists }) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return nil
    }
}
