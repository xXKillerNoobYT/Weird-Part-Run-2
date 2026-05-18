import SwiftUI
import WiredPartCore

struct IOSNotebooksRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        routedPage
            .onAppear { postActiveContext() }
            .onDisappear { postInactiveContext() }
    }

    @ViewBuilder
    private var routedPage: some View {
        switch tabId {
        case "notebooks-all": IOSNotebooksListPage()
        case "notebooks-templates": IOSNotebookTemplatesPage()
        case "notebooks-job-notebooks": IOSJobNotebooksPage()
        default: Text("Unknown notebooks page: \(tabId)").foregroundStyle(.secondary)
        }
    }

    private func postActiveContext() {
        switch tabId {
        case "notebooks-templates":
            NotificationCenter.default.post(name: .notebookTemplatesPageActive, object: nil, userInfo: ["context": notebooksContext])
        case "notebooks-job-notebooks":
            NotificationCenter.default.post(name: .jobNotebooksPageActive, object: nil, userInfo: ["context": notebooksContext])
        default:
            break
        }
    }

    private func postInactiveContext() {
        switch tabId {
        case "notebooks-templates":
            NotificationCenter.default.post(name: .notebookTemplatesPageInactive, object: nil)
        case "notebooks-job-notebooks":
            NotificationCenter.default.post(name: .jobNotebooksPageInactive, object: nil)
        default:
            break
        }
    }

    private var notebooksContext: String {
        switch tabId {
        case "notebooks-templates":
            return "Current page: Notebook Templates. Visible workflow: read-only template library, template categories, and template reuse guidance. Available read-only actions: explain template purpose, filtering, and navigation entry points."
        case "notebooks-job-notebooks":
            return "Current page: Job Notebooks. Visible workflow: read-only job-linked notebook list and job note organization context. Available read-only actions: summarize visible job notebook state and explain notebook navigation."
        default:
            return "Current page: Notebooks. Visible workflow: read-only notebook navigation context."
        }
    }
}
