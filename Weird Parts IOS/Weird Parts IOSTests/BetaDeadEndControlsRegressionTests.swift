import XCTest

/// Regression coverage for the beta dead-end-controls batch
/// (GH #1338 umbrella, #1188, #1191, #1206, #851).
///
/// These are source-scan checks (same pattern as
/// `DashboardScannerEntityContextRegressionTests`): they pin the removal of
/// controls that only led to coming-soon toasts / guaranteed errors, and the
/// wiring fixes for misrouted quick actions, so refactors cannot quietly
/// reintroduce a dead end.
final class BetaDeadEndControlsRegressionTests: XCTestCase {

    // MARK: - #1206: Shared Reports must not open the public-report stub

    func testSharedReportsDoesNotInstantiatePublicReportStub() throws {
        let source = try Self.readSource("Features/Reports/IOSReportsRouter.swift")
        XCTAssertFalse(
            source.contains("IOSPublicReportView("),
            "Shared Reports must not navigate to the IOSPublicReportView stub (guaranteed error with an empty token) until public sharing ships."
        )
        XCTAssertFalse(
            source.contains("View Public Report"),
            "The 'View Public Report' dead-end row must stay hidden until public report sharing exists."
        )
    }

    // MARK: - #851: Payment Tracking menu item hidden for beta

    func testPaymentTrackingMenuItemIsHiddenForBeta() throws {
        let menuSource = try Self.readSource("Navigation/UserMenuSheet.swift")
        XCTAssertFalse(
            menuSource.contains("settings-payment-tracking"),
            "The Payment Tracking menu item routes to a placeholder and must stay hidden for beta (#851, owner decision in #1348)."
        )

        let routerSource = try Self.readSource("Features/Settings/SettingsRouter.swift")
        XCTAssertFalse(
            routerSource.contains("comingSoonPage"),
            "SettingsRouter must not route any visible menu item to a coming-soon placeholder page."
        )

        let contentRouterSource = try Self.readSource("Navigation/IOSContentRouter.swift")
        XCTAssertFalse(
            contentRouterSource.contains("/settings/payment-tracking"),
            "The /settings/payment-tracking URL route must stay removed while the page is a placeholder."
        )
    }

    // MARK: - #1338: Warehouse Exec quick actions must use real tab ids

    func testWarehouseExecQuickActionsUseFullTabIds() throws {
        let source = try Self.readSource("Features/Office/IOSWarehouseExecPage.swift")

        for tabId in ["warehouse-movements", "warehouse-receiving", "warehouse-audit"] {
            XCTAssertTrue(
                source.contains("\"tabId\": \"\(tabId)\""),
                "Warehouse Exec quick actions must navigate with the full tab id '\(tabId)' — bare suffixes match no tab and silently no-op."
            )
        }
        XCTAssertFalse(
            source.contains("\"moduleId\": \"orders\""),
            "'Start Receiving' must target the warehouse module (receiving lives at /warehouse/receiving), not orders."
        )
        for badTabId in ["\"tabId\": \"movements\"", "\"tabId\": \"receiving\"", "\"tabId\": \"audit\""] {
            XCTAssertFalse(
                source.contains(badTabId),
                "Short tab id \(badTabId) matches no AppTab id/path and must not come back."
            )
        }
    }

    // MARK: - #1338: Inventory grid Transfer swipe must actually navigate

    func testInventoryGridTransferSwipeNavigatesToMovements() throws {
        let source = try Self.readSource("Features/Warehouse/IOSInventoryGridPage.swift")
        XCTAssertFalse(
            source.contains("\"moduleId\": \"warehouse-movements\""),
            "A tab id passed as moduleId matches no module and makes the Transfer swipe a silent no-op."
        )
        XCTAssertTrue(
            source.contains("\"moduleId\": \"warehouse\"") && source.contains("\"tabId\": \"warehouse-movements\""),
            "The Transfer swipe must post moduleId 'warehouse' with tabId 'warehouse-movements'."
        )
    }

    // MARK: - #1188: Orders bulk-action coming-soon bar removed

    func testPartsOrderManagementHasNoComingSoonActions() throws {
        let source = try Self.readSource("Features/Orders/IOSPartsOrderManagementPage.swift")
        XCTAssertFalse(
            source.contains("showComingSoon"),
            "Parts order management must not ship visible bulk actions that only show a coming-soon toast (#1188)."
        )
        for deadAction in ["Move to PO", "Remove + Hold", "Change Qty"] {
            XCTAssertFalse(
                source.contains("Button(\"\(deadAction)\")"),
                "Dead-end bulk action button '\(deadAction)' must stay removed until its service flow exists."
            )
        }
    }

    // MARK: - #1191: chat thread controls must not dead-end

    func testMessageThreadHasNoComingSoonOrSilentActions() throws {
        let source = try Self.readSource("Features/Chat/IOSMessageThreadView.swift")
        XCTAssertFalse(
            source.contains("showComingSoon"),
            "The chat composer must not show coming-soon toasts for the file attach button — it is wired to a document picker now (#1191)."
        )
        XCTAssertTrue(
            source.contains(".fileImporter("),
            "The Attach File button must open a real document picker."
        )
        XCTAssertTrue(
            source.contains("escalateThreadByChannel") && source.contains("pushBackThreadByChannel"),
            "Escalate and Push Back quick actions must call their channel-scoped service methods."
        )
        XCTAssertFalse(
            source.contains("break // Wired in later prompts"),
            "Thread quick actions must not silently fall through — unsupported actions are filtered from rendering and surfaced if triggered."
        )
        XCTAssertTrue(
            source.contains("supportedThreadActions"),
            "Rendered quick actions must be filtered to the set the view can actually perform."
        )
    }

    // MARK: - #1338: sync settings placeholder buttons removed or wired

    func testSyncSettingsPagesHaveNoPermanentlyDisabledButtons() throws {
        for page in [
            "Features/Settings/IOSDeviceManagementPage.swift",
            "Features/Settings/IOSRemoteSyncPage.swift",
            "Features/Settings/IOSSharedChannelsPage.swift",
        ] {
            let source = try Self.readSource(page)
            XCTAssertFalse(
                source.contains(".disabled(true)"),
                "\(page) must not render permanently disabled placeholder buttons — wire the action or remove the control (#1338)."
            )
        }

        let deviceManagement = try Self.readSource("Features/Settings/IOSDeviceManagementPage.swift")
        XCTAssertTrue(
            deviceManagement.contains("issueShopPairingCode"),
            "Pair New Device must issue a real pairing code so the Join Existing Business flow has a host-side code source."
        )
    }

    // MARK: - #1338: supplier bridge load errors must be surfaced

    func testSupplierBridgePageSurfacesLoadErrors() throws {
        let source = try Self.readSource("Features/Settings/IOSSupplierBridgePage.swift")
        XCTAssertTrue(
            source.contains("ErrorStateView"),
            "Supplier Bridge settings must surface load failures with ErrorStateView + retry instead of a misleading empty state."
        )
    }

    // MARK: - Helper

    private static func readSource(_ relativePath: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
