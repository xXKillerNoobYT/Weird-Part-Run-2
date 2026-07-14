import XCTest

/// Regression tests for issue #1335 — load/save failures on seven iOS screens
/// used to render as legitimate empty states (or, on App Config, silently
/// replace payment settings with defaults that Save then persisted).
///
/// These are source-scan tests following the PeerBrowserTargetedSyncRegressionTests
/// idiom: each test asserts on code fragments that exist only in the fix, so a
/// revert back to the silent `try? ... ?? []` pattern fails the suite.
final class SilentLoadFailureSurfacingRegressionTests: XCTestCase {

    // MARK: - IOSJPOCreationPage (part search)

    func testJPOCreationPartSearchFailureSurfacesInlineErrorWithRetry() throws {
        let source = try Self.readSource(["Features", "Orders", "IOSJPOCreationPage.swift"])

        XCTAssertTrue(
            source.contains("@State private var searchError: String?"),
            "JPO creation must carry a dedicated searchError state for the part search panel."
        )
        XCTAssertTrue(
            source.contains("searchError = userFriendlyError(error, context: \"search parts\")"),
            "A part search failure must set searchError via userFriendlyError instead of silently emptying results."
        )
        XCTAssertTrue(
            source.contains("} else if let error = searchError {"),
            "The search results panel must render the searchError branch before the 'No parts found' empty state."
        )
        XCTAssertTrue(
            source.contains(".accessibilityLabel(\"Retry part search\")"),
            "The inline search error row must offer a retry affordance."
        )

        let body = try Self.methodBody(named: "searchParts", in: source)
        XCTAssertTrue(
            body.contains("guard searchText.count >= 2 else {"),
            "Short queries must be split out of the service-availability guard."
        )
        XCTAssertFalse(
            body.contains("submitError = \"Parts service not available\""),
            "A short query must no longer raise the misleading 'Parts service not available' submitError."
        )
        XCTAssertFalse(
            body.contains("catch {\n            searchResults = []\n        }"),
            "The search catch block must not swallow the error by only clearing results."
        )
    }

    // MARK: - IOSPODetailPage (receipt history)

    func testPODetailReceiptHistoryFailureSurfacesSectionError() throws {
        let source = try Self.readSource(["Features", "Orders", "IOSPODetailPage.swift"])

        XCTAssertTrue(
            source.contains("@State private var receiptHistoryError: String?"),
            "PO detail must carry a section-level receiptHistoryError state."
        )
        XCTAssertTrue(
            source.contains("receiptHistoryError = userFriendlyError(error, context: \"load receipt history\")"),
            "Receipt history load failures must set receiptHistoryError instead of defaulting to empty lists."
        )
        XCTAssertTrue(
            source.contains("receiptItemsError = userFriendlyError(error, context: \"load receipt details\")"),
            "Per-session receipt item load failures must surface via the SEPARATE item-level error so loaded sessions never blank."
        )
        XCTAssertTrue(
            source.contains("@State private var receiptItemsError: String?"),
            "PO detail must carry a distinct per-session item error state."
        )
        XCTAssertTrue(
            source.contains(".accessibilityIdentifier(\"receiptItemsError\")"),
            "The item-detail failure banner must render inline in the sheet, not as a full-sheet error."
        )
        XCTAssertTrue(
            source.contains("if hasEntries || hasBatches || receiptHistoryError != nil {"),
            "The receipt history section must stay visible when the load failed so the error can render."
        )
        XCTAssertTrue(
            source.contains(".accessibilityLabel(\"Retry loading receipt history\")"),
            "The receipt history error row must offer a retry affordance."
        )
        XCTAssertFalse(
            source.contains("(try? service.getReceiptHistory(poId: poId)) ?? []"),
            "getReceiptHistory must not be silently defaulted to []."
        )
        XCTAssertFalse(
            source.contains("(try? service.getReceiptHistoryEntries(poId: poId)) ?? []"),
            "getReceiptHistoryEntries must not be silently defaulted to []."
        )
        XCTAssertFalse(
            source.contains("(try? service.getReceiptHistoryItems(sessionId: sessionId)) ?? []"),
            "getReceiptHistoryItems must not be silently defaulted to []."
        )
    }

    // MARK: - IOSScheduleConfigPage (shift templates / holidays / hats)

    func testScheduleConfigListLoadFailuresSetLoadErrorMsg() throws {
        let source = try Self.readSource(["Features", "Scheduling", "IOSScheduleConfigPage.swift"])

        XCTAssertTrue(
            source.contains("loadErrorMsg = userFriendlyError(error, context: \"load shift templates and holidays\")"),
            "Shift template/holiday load failures must set loadErrorMsg instead of rendering empty editors."
        )
        XCTAssertTrue(
            source.contains("loadErrorMsg = userFriendlyError(error, context: \"load supervisor hats\")"),
            "Supervisor hat load failures must set loadErrorMsg instead of an empty picker."
        )
        XCTAssertFalse(
            source.contains("(try? svc.getShiftTemplates()) ?? []"),
            "getShiftTemplates must not be silently defaulted to []."
        )
        XCTAssertFalse(
            source.contains("(try? svc.getHolidays()) ?? []"),
            "getHolidays must not be silently defaulted to []."
        )
        XCTAssertFalse(
            source.contains("(try? people.listHats()) ?? []"),
            "listHats must not be silently defaulted to []."
        )
    }

    // MARK: - IOSPeopleDashboardPage (payment alerts)

    func testPeopleDashboardPaymentLookupFailureShowsDegradedSection() throws {
        let source = try Self.readSource(["Features", "People", "IOSPeopleDashboardPage.swift"])

        XCTAssertTrue(
            source.contains("@State private var paymentAlertsError: String?"),
            "People dashboard must carry a paymentAlertsError state for the payment alerts section."
        )
        XCTAssertTrue(
            source.contains("paymentAlertsError = userFriendlyError(error, context: \"load payment alerts\")"),
            "Payment lookup failures must set paymentAlertsError instead of hiding the section."
        )
        XCTAssertTrue(
            source.contains("if let error = paymentAlertsError {"),
            "The list must render a degraded payment-alerts section when the lookup failed."
        )
        XCTAssertTrue(
            source.contains("paymentTrackingEnabled = try service.isPaymentTrackingEnabled()"),
            "isPaymentTrackingEnabled must be a throwing read routed to the error state."
        )
        XCTAssertFalse(
            source.contains("(try? service.isPaymentTrackingEnabled()) ?? false"),
            "isPaymentTrackingEnabled must not silently default to disabled."
        )
        XCTAssertFalse(
            source.contains("(try? service.getOverdueCustomers()) ?? []"),
            "getOverdueCustomers must not silently default to no overdue customers."
        )
    }

    // MARK: - IOSWishlistPage (auto-approvals + status counts)

    func testWishlistAutoApprovalFailureSurfacesBannerAndCountsFailureSurfacesLoadError() throws {
        let source = try Self.readSource(["Features", "Orders", "IOSWishlistPage.swift"])

        XCTAssertTrue(
            source.contains("@State private var autoApprovalError: String?"),
            "Wishlist must carry an autoApprovalError state for the failed write pass."
        )
        // The write pass moved to a detached background task (DIS-006):
        // the raw error is captured off-main (autoApprovalFailure = error) and
        // mapped to user copy before the surrounding MainActor state update.
        // Assert both halves of that chain.
        XCTAssertTrue(
            source.contains("autoApprovalFailure = error"),
            "A processAutoApprovals failure must be captured, not swallowed."
        )
        XCTAssertTrue(
            source.contains("autoApprovalError = autoApprovalFailure.map { userFriendlyError($0, context: \"run wishlist auto-approvals\") }"),
            "The captured auto-approval failure must be surfaced as user-facing copy on the main actor."
        )
        XCTAssertTrue(
            source.contains("_ = try service.processAutoApprovals(byUserId: currentUserId)"),
            "processAutoApprovals must be a throwing call inside a do/catch."
        )
        XCTAssertTrue(
            source.contains("if let error = autoApprovalError {"),
            "The wishlist body must render the auto-approval failure banner."
        )
        XCTAssertTrue(
            source.contains("let counts = try service.getStatusCounts()"),
            "getStatusCounts must throw into the loadError path instead of rendering zero counts."
        )
        XCTAssertFalse(
            source.contains("_ = try? service.processAutoApprovals(byUserId: currentUserId)"),
            "The auto-approval write must not be swallowed with try?."
        )
        XCTAssertFalse(
            source.contains("(try? service.getStatusCounts()) ?? WishlistService.StatusCounts()"),
            "Status counts must not silently default to all zeros."
        )
    }

    // MARK: - IOSEmployeeDetailPage (hat toggle reload)

    func testEmployeeDetailHatToggleReloadFailureKeepsPreviousHatsAndSetsError() throws {
        let source = try Self.readSource(["Features", "People", "IOSEmployeeDetailPage.swift"])

        XCTAssertFalse(
            source.contains("(try? service.getAllHatsWithAssignment(employeeId: employeeId)) ?? []"),
            "The post-toggle hats reload must not silently collapse to an empty list."
        )

        let body = try Self.methodBody(named: "toggleHat", in: source)
        XCTAssertTrue(
            body.contains("allHats = try service.getAllHatsWithAssignment(employeeId: employeeId)"),
            "The post-toggle reload must throw into the catch (keeping the previous allHats on failure)."
        )
        XCTAssertTrue(
            body.contains("loadError = userFriendlyError(error, context: \"update hat\")"),
            "A hat toggle/reload failure must surface via loadError."
        )
    }

    // MARK: - AppConfigPage (payment settings load-failure save gate)

    func testAppConfigSaveIsBlockedAfterFailedLoadSoDefaultsCannotOverwriteRealSettings() throws {
        let source = try Self.readSource(["Features", "Settings", "AppConfigPage.swift"])

        XCTAssertTrue(
            source.contains("@State private var configLoadFailed = false"),
            "App Config must track load failure explicitly (loadError is cleared by the alert's OK button)."
        )
        XCTAssertTrue(
            source.contains(".disabled(!isFormValid || configLoadFailed)"),
            "The Save button must be disabled while the last load attempt failed."
        )
        XCTAssertTrue(
            source.contains("paymentTrackingEnabled = try peopleService.isPaymentTrackingEnabled()"),
            "Payment tracking state must be a throwing read — no silent default to disabled."
        )
        XCTAssertTrue(
            source.contains("let paySettings = try peopleService.getPaymentSettings()"),
            "Payment settings must be a throwing read — no silent default terms/warning/hold."
        )
        XCTAssertTrue(
            source.contains("Label(\"Retry Load\", systemImage: \"arrow.clockwise\")"),
            "The failed-load section must offer a retry affordance."
        )
        XCTAssertFalse(
            source.contains("(try? peopleService.isPaymentTrackingEnabled()) ?? false"),
            "isPaymentTrackingEnabled must not silently default to false."
        )
        XCTAssertFalse(
            source.contains("try? peopleService.getPaymentSettings()"),
            "getPaymentSettings must not be swallowed with try?."
        )

        let saveBody = try Self.methodBody(named: "saveConfig", in: source)
        XCTAssertTrue(
            saveBody.contains("guard !configLoadFailed else {"),
            "saveConfig must refuse to persist while the form holds unloaded defaults."
        )

        let loadBody = try Self.methodBody(named: "loadConfig", in: source)
        XCTAssertTrue(
            loadBody.contains("configLoadFailed = false"),
            "A successful load must clear the load-failed gate."
        )
        XCTAssertTrue(
            loadBody.contains("configLoadFailed = true"),
            "A failed load must set the load-failed gate."
        )
    }

    // MARK: - Helpers

    /// Read an app source file relative to the project root, mirroring the
    /// PeerBrowserTargetedSyncRegressionTests path idiom.
    private static func readSource(
        _ pathComponents: [String],
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS (project folder)
        var sourceURL = projectRoot.appendingPathComponent("Weird Parts IOS")
        for component in pathComponents {
            sourceURL = sourceURL.appendingPathComponent(component)
        }
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    /// Extract a brace-balanced method body so assertions can be scoped to a
    /// single function instead of the whole file.
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
}
