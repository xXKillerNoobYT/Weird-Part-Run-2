import SwiftUI
import WiredPartCore

struct IOSNotebooksRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        switch tabId {
        case "notebooks-all": IOSNotebooksListPage()
        case "notebooks-templates": IOSNotebookTemplatesPage()
        default: Text("Unknown notebooks page: \(tabId)").foregroundStyle(.secondary)
        }
    }
}
