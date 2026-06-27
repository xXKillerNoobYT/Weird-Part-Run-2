import XCTest

final class OrdersSessionUnavailableRegressionTests: XCTestCase {
    func testOrdersMutationsSurfaceVisibleErrorWhenCurrentUserIsUnavailable() throws {
        let createReturnSource = try Self.readOrdersSource(named: "CreateReturnSheet.swift")
        XCTAssertFalse(
            createReturnSource.contains("guard let userId = appCore.currentUser?.id else { return }"),
            "Create Return should not silently no-op when current user is unavailable."
        )
        XCTAssertTrue(
            createReturnSource.contains("saveError = \"User session unavailable. Sign in again.\""),
            "Create Return should show a visible saveError for missing user session."
        )

        let purchaseOrdersSource = try Self.readOrdersSource(named: "IOSPurchaseOrdersPage.swift")
        XCTAssertFalse(
            purchaseOrdersSource.contains("guard let userId = appCore.currentUser?.id else { return }"),
            "PO cancel/delete should not silently no-op when current user is unavailable."
        )
        XCTAssertTrue(
            purchaseOrdersSource.contains("actionMessage = \"User session unavailable. Sign in again.\""),
            "PO cancel/delete should set actionMessage when user session is unavailable."
        )

        let poDetailSource = try Self.readOrdersSource(named: "IOSPODetailPage.swift")
        XCTAssertFalse(
            poDetailSource.contains("guard let userId = appCore.currentUser?.id else { return }"),
            "PO detail status transitions should not silently no-op when current user is unavailable."
        )
        XCTAssertTrue(
            poDetailSource.contains("actionMessage = \"User session unavailable. Sign in again.\""),
            "PO detail status transitions should set actionMessage when user session is unavailable."
        )
    }

    func testPONoteWritesRequireRealCurrentUserAuthor() throws {
        let poDetailSource = try Self.readOrdersSource(named: "IOSPODetailPage.swift")

        XCTAssertFalse(
            poDetailSource.contains("appCore.currentUser?.displayName ?? \"System\""),
            "PO note audit records must not fall back to a synthetic System author."
        )
        XCTAssertFalse(
            poDetailSource.contains("appCore.currentUser?.displayName ?? \"Unknown\""),
            "Manual PO notes must not fall back to a synthetic Unknown author."
        )
        XCTAssertTrue(
            poDetailSource.contains("guard let author = currentPONoteAuthor() else"),
            "PO note writes should fail closed until a real current user author is available."
        )
        XCTAssertTrue(
            poDetailSource.contains("guard appCore.currentUser?.id != nil else { return nil }"),
            "The PO note author helper should require an authenticated current user id before audit writes."
        )
        XCTAssertTrue(
            poDetailSource.contains("displayName.trimmingCharacters(in: .whitespacesAndNewlines)"),
            "The PO note author helper should reject blank display names instead of writing unattributed notes."
        )
    }

    func testSubmittedPODetailDoesNotExposeDirectMarkOrderedAction() throws {
        let poDetailSource = try Self.readOrdersSource(named: "IOSPODetailPage.swift")
        let directOrderedLabel = "Mark " + "Ordered"
        let directOrderedTransition = "transitionPO(to: " + "\"ordered\")"

        XCTAssertFalse(
            poDetailSource.contains(directOrderedLabel),
            "Submitted POs should only advance to ordered through Send to Supplier / markPOSentToSupplier."
        )
        XCTAssertFalse(
            poDetailSource.contains(directOrderedTransition),
            "PO detail UI must not call updatePOStatus(status: \"ordered\") through transitionPO."
        )
        XCTAssertTrue(
            poDetailSource.contains("activeSheet = .sendToSupplier"),
            "Submitted PO detail should retain the Send to Supplier path."
        )
    }

    func testGroupedPOSendDoesNotSilentlyDropSiblingAttachments() throws {
        let sendSheetSource = try Self.readOrdersSource(named: "POSendToSupplierSheet.swift")

        XCTAssertFalse(
            sendSheetSource.contains("(try? svc.listSendablePOs"),
            "Grouped PO sibling lookup failures must be surfaced instead of falling back to an empty sibling list."
        )
        XCTAssertFalse(
            sendSheetSource.contains("try? appCore.ordersService?.getPODetail"),
            "Selected sibling detail failures must block send/share instead of silently omitting that PO attachment."
        )
        XCTAssertFalse(
            sendSheetSource.contains("try? data.write(to: url)"),
            "Share-sheet temp writes must append URLs only after a successful write."
        )
        XCTAssertTrue(
            sendSheetSource.contains("selected sibling purchase orders could not be prepared"),
            "Grouped send failures should tell the user that selected sibling POs were not prepared."
        )
        XCTAssertTrue(
            sendSheetSource.contains("Share sheet could not prepare every selected PO attachment"),
            "Share fallback failures should distinguish partial/blocked share preparation from complete success."
        )
        XCTAssertTrue(
            sendSheetSource.contains("groupEnabled && siblingPOsError != nil"),
            "Grouped send should keep the prep/send action disabled while sibling lookup is in a failed state."
        )
        XCTAssertTrue(
            sendSheetSource.contains("if groupEnabled, let siblingPOsError"),
            "Grouped send should defensively block prep if sibling lookup failed before the button state updates."
        )
    }

    func testPOSendConfirmationDismissesBeforeParentRefresh() throws {
        let sendSheetSource = try Self.readOrdersSource(named: "POSendToSupplierSheet.swift")

        XCTAssertFalse(
            sendSheetSource.contains("isSaving = false\n                    onConfirmedSent()\n                    dismiss()"),
            "PO sent confirmation must not refresh the parent before dismissing the sheet."
        )
        XCTAssertTrue(
            sendSheetSource.contains("isSaving = false\n                    dismiss()\n                    onConfirmedSent()"),
            "Successful PO sent confirmation should dismiss the sheet before refreshing the parent presenter."
        )
    }

    func testGroupedPOSendToggleOffCannotConfirmSiblingPOs() throws {
        let sendSheetSource = try Self.readOrdersSource(named: "POSendToSupplierSheet.swift")

        XCTAssertTrue(
            sendSheetSource.contains("guard groupEnabled else { return [po.id] }"),
            "When grouped sending is off, confirmSent must only mark the primary PO sent even if stale sibling selections exist."
        )
        XCTAssertTrue(
            sendSheetSource.contains("includedSiblingIds = []") && sendSheetSource.contains("siblingPDFs = [:]"),
            "Turning grouped sending off should clear stale sibling selections and generated sibling PDFs."
        )
        XCTAssertTrue(
            sendSheetSource.contains("private var includedSiblingPOs: [OrdersService.POListItem]") &&
            sendSheetSource.contains("guard groupEnabled else { return [] }"),
            "Email body, attachment, and share-sheet paths should use group-aware sibling inclusion instead of raw stale selected ids."
        )
        XCTAssertFalse(
            sendSheetSource.contains("primary always included\n        [po.id] + Array(includedSiblingIds)"),
            "includedPOs must not blindly append stale sibling ids after grouped sending has been disabled."
        )
        XCTAssertFalse(
            sendSheetSource.contains("siblingPOs where includedSiblingIds.contains"),
            "Attachment/PDF generation should use the group-aware includedSiblingPOs helper."
        )
    }

    private static func readOrdersSource(named filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Orders")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
