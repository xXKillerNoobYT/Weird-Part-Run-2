import Foundation
import SwiftUI

/// Deterministic command inputs for UI verification of the assistant's existing
/// authorization boundary. This fixture is compiled only in Debug and requires the
/// regular UI-testing launch flag, so it cannot run in a production app session.
#if DEBUG
@MainActor
enum AIFilterCommandUITestFixture {
    static let launchFlag = "-UITestingAIFilterCommandFixture"
    private static let uiTestingFlag = "-UITesting"

    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(uiTestingFlag) && arguments.contains(launchFlag)
    }

    static let purchaseOrdersPageId = "purchase-orders"
    static let jposPageId = "jpos"
    static let options = ["all", "draft", "submitted", "clear", "clear-all"]

    static func response(pageId: String, value: String) -> String {
        "{\"activateFilter\":{\"pageId\":\"\(pageId)\",\"value\":\"\(value)\"}}"
    }
}

/// A narrow host used only by UI tests. Its controls remain inside
/// `IOSAIAssistantPanel`, ensuring tests exercise the same authorization and
/// confirmation paths as assistant responses without Foundation Models.
struct AIFilterCommandUITestFixtureHost: View {
    @State private var displayMode: AIDisplayMode = .sheet
    @State private var isVisible = true
    @State private var pendingHelpRequest: [AnyHashable: Any]?

    var body: some View {
        IOSAIAssistantPanel(
            displayMode: $displayMode,
            isVisible: $isVisible,
            pendingHelpRequest: $pendingHelpRequest
        )
    }
}
#endif
