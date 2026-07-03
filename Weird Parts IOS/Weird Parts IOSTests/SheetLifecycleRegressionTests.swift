import XCTest

/// Regression coverage for the sheet-lifecycle batch:
/// - Issue #714: `ToolTradeSheet` let the trade recipient selection be
///   swipe-dismissed silently because tapping an employee never marked the
///   sheet dirty. The fix adopts the signature-vs-baseline dirty idiom from
///   `ShiftTemplateEditSheet` (issue #1248) so every user-entered field —
///   recipient included — is discard-protected.
/// - Issue #735: `SmartDeleteSheet` awaited the parent `onComplete()` refresh
///   before calling `dismiss()`, delaying the close behind parent state
///   transitions. Both delete paths must dismiss first, then refresh.
/// - Issue #736: `PricingBulkEditSheet`'s completion Done button deferred
///   `dismiss()` until after `await onComplete()`. It must dismiss
///   synchronously and run the refresh in a follow-up Task, matching
///   `PricingOverrideFlow`'s completion screen.
final class SheetLifecycleRegressionTests: XCTestCase {

    // MARK: - Issue #714

    func testToolTradeRecipientSelectionIsDirtyProtected() throws {
        let sheet = try Self.toolTradeSheetSource()

        // The recipient leads the dirty signature — this anchored fragment is
        // the exact signature head, so a match elsewhere can't satisfy it.
        XCTAssertTrue(
            sheet.contains("selectedUser.map(String.init) ?? \"\","),
            "ToolTradeSheet's form signature must include the selected trade recipient (issue #714)."
        )
        XCTAssertTrue(
            sheet.contains("private var isDirty: Bool { formSignature != baselineSignature }"),
            "ToolTradeSheet must derive dirtiness from the full-form signature baseline."
        )
        // Dirtiness is derived, never manually flagged — a leftover boolean
        // write would reintroduce the missed-field class of bug.
        XCTAssertFalse(
            sheet.contains("isDirty = "),
            "ToolTradeSheet must not manually assign isDirty; the computed signature covers every field."
        )
        // Swipe-dismiss stays blocked while dirty or saving.
        XCTAssertTrue(
            sheet.contains(".interactiveDismissDisabled(isDirty || isSaving)"),
            "ToolTradeSheet must block interactive dismissal while dirty or saving."
        )
        // Cancel routes through the discard confirmation when dirty.
        XCTAssertTrue(
            sheet.contains("if isDirty { showDiscardConfirm = true } else { dismiss() }"),
            "Cancel on ToolTradeSheet must ask before discarding a dirty form."
        )
        XCTAssertTrue(
            sheet.contains(".confirmationDialog(\"Discard changes?\", isPresented: $showDiscardConfirm, titleVisibility: .visible)"),
            "ToolTradeSheet needs the campaign's discard confirmation dialog."
        )
        // Untouched sheets never count as dirty.
        XCTAssertTrue(
            sheet.contains(".onAppear { baselineSignature = formSignature }"),
            "ToolTradeSheet must snapshot the baseline from the untouched defaults on appear."
        )
        // A successful send re-baselines (clears dirty) before notifying the
        // parent, so teardown never trips the discard guard.
        let sendBody = try Self.methodBody(named: "sendTradeRequest", in: sheet)
        guard let rebaseline = sendBody.range(of: "baselineSignature = formSignature"),
              let notify = sendBody.range(of: "onComplete()") else {
            XCTFail("sendTradeRequest() must re-baseline the signature and notify the parent (issue #714).")
            return
        }
        XCTAssertLessThan(
            rebaseline.lowerBound, notify.lowerBound,
            "sendTradeRequest() must clear dirtiness before completing (issue #714)."
        )
    }

    // MARK: - Issue #735

    func testSmartDeleteSheetDismissesBeforeParentRefresh() throws {
        let source = try Self.readFeatureSource(["Parts", "SmartDeleteSheet.swift"])

        for method in ["startEmptyShelfMode", "deleteImmediately"] {
            let body = try Self.methodBody(named: method, in: source)
            guard let dismissRange = body.range(of: "dismiss()"),
                  let completeRange = body.range(of: "await onComplete()") else {
                XCTFail("\(method)() must both dismiss the sheet and run the parent refresh (issue #735).")
                continue
            }
            XCTAssertLessThan(
                dismissRange.lowerBound, completeRange.lowerBound,
                "\(method)() must dismiss the sheet before awaiting the parent onComplete refresh (issue #735)."
            )
        }
    }

    // MARK: - Issue #736

    func testPricingBulkEditDoneDismissesBeforeParentRefresh() throws {
        let source = try Self.readFeatureSource(["Parts", "PricingBulkEditSheet.swift"])

        let doneBody = try Self.braceBalancedBody(after: "Button(\"Done\")", in: source)
        // Exact fixed shape: synchronous dismiss, then the refresh in a
        // follow-up Task — the same idiom as PricingOverrideFlow's Done.
        XCTAssertTrue(
            doneBody.contains("dismiss()\n                Task { await onComplete() }"),
            "The completion Done button must dismiss synchronously, then run the parent refresh in a Task (issue #736)."
        )
        guard let dismissRange = doneBody.range(of: "dismiss()"),
              let completeRange = doneBody.range(of: "await onComplete()") else {
            XCTFail("The completion Done button must both dismiss and refresh (issue #736).")
            return
        }
        XCTAssertLessThan(
            dismissRange.lowerBound,
            completeRange.lowerBound,
            "The completion Done button must not defer dismissal behind the parent refresh (issue #736)."
        )
    }

    // MARK: - Issues #1391 / #1392

    func testPricingBulkEditReviewStepHasExplicitBackAndCancelControls() throws {
        let source = try Self.readFeatureSource(["Parts", "PricingBulkEditSheet.swift"])
        let review = try Self.methodBody(named: "reviewOneAtATime", in: source)

        XCTAssertTrue(
            review.contains("reviewIndex = nil") && review.contains("Label(\"Back\", systemImage: \"chevron.left\")"),
            "Pricing bulk edit's one-at-a-time review step needs an explicit Back path to the preview step."
        )
        XCTAssertTrue(
            review.contains("Button(\"Cancel\") { dismiss() }"),
            "Pricing bulk edit's one-at-a-time review step needs an explicit Cancel path; swipe-only is unavailable on Mac Catalyst."
        )
    }

    func testPricingOverrideConflictResolutionHasExplicitBackControl() throws {
        let source = try Self.readFeatureSource(["Parts", "PricingOverrideFlow.swift"])
        let resolveConflicts = try Self.braceBalancedBody(after: "private var resolveConflictsView", in: source)

        XCTAssertTrue(
            resolveConflicts.contains("step = .preview") && resolveConflicts.contains("Label(\"Back\", systemImage: \"chevron.left\")"),
            "Pricing override conflict resolution needs an explicit Back path to the preview step."
        )
        XCTAssertTrue(
            source.contains("Button(\"Cancel\") { dismiss() }"),
            "Pricing override flow must retain the explicit global Cancel path."
        )
    }

    // MARK: - Helpers
    /// Slice of `IOSToolDetailPage.swift` covering only `ToolTradeSheet`, so
    /// assertions can't be satisfied by the sibling sheets in the same file.
    private static func toolTradeSheetSource() throws -> String {
        let source = try readFeatureSource(["Tools", "IOSToolDetailPage.swift"])
        guard let start = source.range(of: "struct ToolTradeSheet: View") else {
            throw XCTSkip("Expected ToolTradeSheet in IOSToolDetailPage.swift")
        }
        guard let end = source[start.upperBound...].range(of: "struct TradeResponseSheet") else {
            throw XCTSkip("Expected TradeResponseSheet after ToolTradeSheet")
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private static func braceBalancedBody(after anchor: String, in source: String) throws -> String {
        try TestSourceSlicer.braceBalancedBody(after: anchor, in: source)
    }

    private static func methodBody(named methodName: String, in source: String) throws -> String {
        try braceBalancedBody(after: "func \(methodName)(", in: source)
    }

    private static func readFeatureSource(
        _ pathComponents: [String],
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        var sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
        for component in pathComponents {
            sourceURL = sourceURL.appendingPathComponent(component)
        }
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
