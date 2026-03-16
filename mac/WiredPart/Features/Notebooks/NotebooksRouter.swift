import SwiftUI

/// Routes a `/notebooks/*` path to the appropriate notebooks page view.
///
/// Extracts the tab ID from the path and switches to the corresponding page.
/// Falls back to AllNotebooksPage when the tab ID is unrecognized.
struct NotebooksRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    /// Extract the tab ID from the path, e.g. "/notebooks/templates" -> "templates"
    private var tabId: String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return "all" }
        return String(components.last ?? "all")
    }

    var body: some View {
        switch tabId {
        case "all", "general":
            AllNotebooksPage()
        case "job-notebooks":
            JobNotebooksPage()
        case "templates":
            NotebookTemplatesPage()
        default:
            AllNotebooksPage()
        }
    }
}
