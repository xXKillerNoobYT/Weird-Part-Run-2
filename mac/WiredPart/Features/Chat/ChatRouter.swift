import SwiftUI

/// Routes a `/chat/*` path to the appropriate chat page view.
///
/// Extracts the tab ID from the path and switches to the corresponding page.
/// Falls back to ChannelsPage when the tab ID is unrecognized.
struct ChatRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/chat/questions" -> "questions"
    private var tabId: String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return "channels" }
        return String(components.last ?? "channels")
    }

    var body: some View {
        switch tabId {
        case "inbox", "channels":
            ChannelsPage()
        case "qa-board", "questions":
            QuestionsPage()
        default:
            ChannelsPage()
        }
    }
}
