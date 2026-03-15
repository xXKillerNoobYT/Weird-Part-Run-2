import SwiftUI
import WiredPartCore

struct IOSToolsRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "tools-registry": IOSToolRegistryPage()
        case "tools-checkouts": IOSToolCheckoutsPage()
        default: Text("Unknown tools page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
