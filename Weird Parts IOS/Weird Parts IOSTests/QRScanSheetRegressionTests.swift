import XCTest
import WiredPartCore
@testable import Weird_Parts

@MainActor
final class QRScanSheetRegressionTests: XCTestCase {
    func testScanResultCallbackRunsAfterDismissOnMainActor() throws {
        var events: [String] = []
        QRScanCompletionDispatcher.deliver(
            dismiss: { events.append("dismiss") },
            onResult: { events.append("result") }
        )

        XCTAssertEqual(events, ["dismiss", "result"])

        // Keep one source-shape check for the actor-isolation regression: the
        // production call site, not only the helper, must enter MainActor.run.
        let source = try Self.qrScanSheetSource()
        let normalized = normalizedSource(source)
        XCTAssertTrue(
            normalized.contains("awaitMainActor.run{letshouldComplete=deliveryGate.finish(")
                && normalized.contains("ifshouldComplete{QRScanCompletionDispatcher.deliver("),
            "QRScanSheet must dispatch completion from its MainActor result transaction."
        )
    }

    func testDuplicateScanGuardPreventsOverlappingProcessing() {
        var gate = QRScanDeliveryGate()

        XCTAssertTrue(gate.claim("PO-42"))
        XCTAssertFalse(gate.claim("PO-42"))
        XCTAssertFalse(gate.claim("PO-43"))
        XCTAssertTrue(gate.isProcessing)
    }

    func testDeliveryGateInvokesCompletionOnceForDuplicatePayload() {
        var gate = QRScanDeliveryGate()
        var callbackCount = 0
        let payload = #"{"app":"wiredpart","version":2,"type":"po","id":42,"code":"PO-42"}"#

        for _ in 0..<2 {
            guard gate.claim(payload) else { continue }
            if gate.finish(payload, isFound: true, shouldComplete: true) {
                callbackCount += 1
            }
        }

        let isProcessing = gate.isProcessing
        let completedPayload = gate.completedPayload
        XCTAssertEqual(callbackCount, 1)
        XCTAssertFalse(isProcessing)
        XCTAssertEqual(completedPayload, payload)
    }

    func testDeliveryGateSuppressesConsecutiveFoundMismatchButRetriesAfterAnotherResult() {
        var gate = QRScanDeliveryGate()

        XCTAssertTrue(gate.claim("JOB-1"))
        XCTAssertFalse(gate.finish("JOB-1", isFound: true, shouldComplete: false))
        XCTAssertFalse(gate.claim("JOB-1"), "A consecutive found mismatch must be suppressed.")

        XCTAssertTrue(gate.claim("MISSING-1"))
        XCTAssertFalse(gate.finish("MISSING-1", isFound: false, shouldComplete: false))
        XCTAssertTrue(gate.claim("MISSING-1"), "A not-found result must remain retryable.")
        XCTAssertFalse(gate.finish("MISSING-1", isFound: false, shouldComplete: false))
        XCTAssertTrue(gate.claim("JOB-1"), "A different accepted payload must release found suppression.")
        gate.fail("JOB-1")
        XCTAssertTrue(gate.claim("JOB-1"), "A failed lookup must release the processing slot.")
    }

    func testManualSubmissionGatePreservesInputWhileProcessing() {
        XCTAssertNil(
            QRScanManualSubmissionGate.code(from: "PO-42", isProcessing: true),
            "Return-key submission must no-op while a lookup is active."
        )
        XCTAssertEqual(
            QRScanManualSubmissionGate.code(from: "  PO-42  ", isProcessing: false),
            "PO-42"
        )
        XCTAssertNil(QRScanManualSubmissionGate.code(from: "   ", isProcessing: false))
    }

    func testManualFallbackAndCameraBottomReuseOneStatusView() throws {
        let source = try Self.qrScanSheetSource()
        let bottom = try Self.braceBalancedBody(after: "private var bottomSection", in: source)
        let manual = try Self.braceBalancedBody(after: "private var manualOnlyView", in: source)

        XCTAssertTrue(
            source.contains("private var feedbackStatusView: some View"),
            "QRScanSheet should keep scan feedback in one reusable status view."
        )
        XCTAssertTrue(bottom.contains("feedbackStatusView"))
        XCTAssertTrue(manual.contains("feedbackStatusView"))
    }

    func testProcessingStateShowsAccessibleLookingUpAndDisablesLookup() throws {
        let source = try Self.qrScanSheetSource()
        let feedback = try Self.braceBalancedBody(after: "private var feedbackStatusView", in: source)
        let processingClaim = try Self.braceBalancedBody(after: "let shouldSkip = await MainActor.run", in: source)

        XCTAssertTrue(
            feedback.contains("ProgressView()") && feedback.contains("Text(\"Looking up…\")"),
            "Processing feedback must include both a spinner and visible Looking up text."
        )
        XCTAssertTrue(
            source.contains(".disabled(manualCode.isBlankRequiredText || isProcessing)"),
            "Look Up must remain disabled while processing."
        )
        XCTAssertTrue(
            feedback.contains(".accessibilityIdentifier(\"qrScanStatus\")")
                && feedback.contains(".accessibilityLabel(statusAccessibilityLabel)")
                && feedback.contains(".accessibilityAddTraits(.updatesFrequently)"),
            "The status view needs a stable accessibility identifier and update semantics for VoiceOver."
        )
        XCTAssertTrue(
            source.contains("UIAccessibility.post(notification: .announcement, argument: status)"),
            "Status changes should be announced to VoiceOver."
        )
        XCTAssertTrue(
            processingClaim.contains("resultTitle = nil")
                && processingClaim.contains("resultCode = nil")
                && processingClaim.contains("resultEntityType = nil"),
            "Starting a new lookup must clear stale prior results while Looking up is shown."
        )
        XCTAssertTrue(
            source.contains("await Task.yield()"),
            "QRScanSheet should yield once so SwiftUI can render and announce loading before synchronous lookup work."
        )
    }

    func testWrongTypeWarningIsOrangeAndPrecedesSuccessRendering() throws {
        let source = try Self.qrScanSheetSource()
        let feedbackView = try Self.braceBalancedBody(after: "private var feedbackStatusView", in: source)
        let feedback = QRScanFeedback(
            isFound: true,
            entityType: .job,
            expectedType: .po,
            title: "JOB-42",
            code: "JOB-42"
        )

        guard let mismatchRange = feedbackView.range(
            of: "else if let feedback = resultFeedback, feedback.typeMismatch"
        ), let resultRange = feedbackView.range(of: "else if let feedback = resultFeedback {") else {
            XCTFail("Expected type mismatch to branch before generic result rendering.")
            return
        }

        XCTAssertLessThan(mismatchRange.lowerBound, resultRange.lowerBound)
        XCTAssertTrue(feedback.typeMismatch)
        XCTAssertEqual(feedback.message, "Expected po, got job")
        let externalFeedback = QRScanFeedback(
            isFound: true,
            entityType: nil,
            expectedType: .po,
            title: "External catalog match",
            code: "EXT-42"
        )
        XCTAssertTrue(externalFeedback.typeMismatch)
        XCTAssertEqual(externalFeedback.message, "Expected po, got external")
        XCTAssertFalse(
            source.contains("@State private var typeMismatch"),
            "Mismatch classification must be derived from the current result rather than stored independently."
        )
        XCTAssertTrue(
            feedbackView.contains("Text(feedback.message)")
                && feedbackView.contains(".foregroundStyle(.orange)"),
            "Wrong-type results must show an orange Expected/got warning."
        )
        XCTAssertTrue(
            source.contains("return resultFeedback.message"),
            "Visible and accessibility result copy must consume the same derived feedback message."
        )
    }

    func testNotFoundWithExpectedTypeKeepsNotFoundMessageAndIsNotMismatch() throws {
        let source = try Self.qrScanSheetSource()
        let normalized = normalizedSource(source)
        let code = "MANUAL-404"
        let feedback = QRScanFeedback(
            isFound: false,
            entityType: nil,
            expectedType: .po,
            title: code,
            code: code
        )

        XCTAssertFalse(feedback.typeMismatch)
        XCTAssertEqual(feedback.message, "Not found: MANUAL-404")
        XCTAssertTrue(
            normalized.contains("letshouldAutoComplete=result.isFound&&(expectedType==nil||result.entityType==expectedType)"),
            "Only found matching results may auto-complete."
        )
        XCTAssertTrue(
            normalized.contains("??result.fields[\"code\"]??result.code"),
            "A code-only not-found result must always produce a non-nil display title."
        )
    }

    func testMatchingSuccessUsesSingleCompletionPath() {
        var gate = QRScanDeliveryGate()
        var completionCount = 0

        XCTAssertTrue(gate.claim("PO-42"))
        if gate.finish("PO-42", isFound: true, shouldComplete: true) {
            completionCount += 1
        }
        XCTAssertFalse(gate.claim("PO-42"))
        XCTAssertEqual(completionCount, 1)
    }

    func testCancelDoesNotInvokeCallbackAndManualFieldsAreNamedQRCode() throws {
        var gate = QRScanDeliveryGate()
        var callbackCount = 0
        XCTAssertTrue(gate.claim("PO-42"))
        gate.cancel()
        if gate.finish("PO-42", isFound: true, shouldComplete: true) {
            callbackCount += 1
        }
        XCTAssertEqual(callbackCount, 0, "A result already in flight must not complete after dismissal.")
        XCTAssertFalse(gate.claim("PO-43"), "Dismissed sheets must reject later scanner deliveries.")

        let source = try Self.qrScanSheetSource()
        let toolbar = try Self.braceBalancedBody(after: ".toolbar", in: source)

        XCTAssertTrue(toolbar.contains("Button(\"Cancel\") { cancelAndDismiss() }"))
        XCTAssertFalse(toolbar.contains("onResult"))
        XCTAssertEqual(
            source.components(separatedBy: ".accessibilityLabel(\"QR code\")").count - 1,
            2,
            "Both manual QR entry fields must expose the explicit accessible name QR code."
        )
    }

    private func normalizedSource(_ source: String) -> String {
        source.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    private static func qrScanSheetSource() throws -> String {
        guard let sourceURL = Bundle(for: QRScanSheetRegressionTests.self)
            .url(forResource: "QRScanSheetSource", withExtension: "txt") else {
            throw NSError(
                domain: "QRScanSheetRegressionTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "QRScanSheetSource.txt is missing from the test bundle."]
            )
        }
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func braceBalancedBody(after anchor: String, in source: String) throws -> String {
        try TestSourceSlicer.braceBalancedBody(after: anchor, in: source)
    }

    private static func methodBody(named methodName: String, in source: String) throws -> String {
        try braceBalancedBody(after: "func \(methodName)(", in: source)
    }
}
