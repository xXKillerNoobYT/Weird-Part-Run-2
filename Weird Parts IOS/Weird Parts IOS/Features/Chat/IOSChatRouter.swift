import SwiftUI
import WiredPartCore

struct IOSChatRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "chat-channels": IOSChannelsPage()
        case "chat-questions": IOSQuestionsPage()
        case "chat-rfis": IOSRFIListPage()
        default: Text("Unknown chat page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
