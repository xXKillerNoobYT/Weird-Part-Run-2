import SwiftUI
import WiredPartCore

/// Notebook templates list page for iOS.
///
/// Displays a list of notebook templates (type = "template") with title,
/// created by, entry count, and status. Supports pull-to-refresh and
/// search filtering.
struct IOSNotebookTemplatesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var templates: [NotebooksService.NotebookListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            templateList
                .navigationTitle("Templates")
                .searchable(text: $searchText, prompt: "Search templates...")
                .refreshable { loadData() }
                .task { loadData() }
        }
    }

    // MARK: - Template List

    @ViewBuilder
    private var templateList: some View {
        if isLoading {
            ProgressView("Loading templates...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredTemplates.isEmpty {
            ContentUnavailableView {
                Label("No Templates", systemImage: "doc.text")
            } description: {
                Text("No notebook templates found.")
            }
        } else {
            List(filteredTemplates, id: \.id) { template in
                templateRow(template)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredTemplates: [NotebooksService.NotebookListItem] {
        guard !searchText.isEmpty else { return templates }
        let query = searchText.lowercased()
        return templates.filter {
            $0.title.lowercased().contains(query) ||
            $0.createdByName.lowercased().contains(query)
        }
    }

    private func templateRow(_ template: NotebooksService.NotebookListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(template.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("by \(template.createdByName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let updated = template.updatedAt {
                    Text("Updated \(updated)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(template.status)
                Label("\(template.entryCount) entries", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "archived": .secondary
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.notebooksService else { return }
        isLoading = templates.isEmpty
        do {
            templates = try service.listTemplates()
        } catch {
            print("[IOSNotebookTemplatesPage] Load error: \(error)")
        }
        isLoading = false
    }
}
