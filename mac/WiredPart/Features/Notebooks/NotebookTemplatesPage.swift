import SwiftUI
import WiredPartCore

/// Notebook templates page showing reusable notebook templates.
///
/// Displays a table of notebook templates with title, creator, entry count,
/// status, and last updated date columns. Templates are filtered via
/// the NotebooksService.listTemplates() convenience method.
struct NotebookTemplatesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var templates: [NotebooksService.NotebookListItem] = []
    @State private var isLoading = true

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\NotebooksService.NotebookListItem.title)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadData() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notebook Templates")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(templates.count) template\(templates.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                loadData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading templates...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if templates.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No notebook templates")
                    .font(.headline)
                Text("Create templates to quickly set up new notebooks.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedTemplates, sortOrder: $sortOrder) {
                TableColumn("Title", value: \.title) { template in
                    Text(template.title)
                        .fontWeight(.medium)
                }
                .width(min: 150, ideal: 250)

                TableColumn("Created By", value: \.createdByName) { template in
                    Text(template.createdByName)
                        .font(.callout)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Entries", value: \.entryCount) { template in
                    Text("\(template.entryCount)")
                        .font(.callout)
                }
                .width(min: 50, ideal: 60)

                TableColumn("Status", value: \.status) { template in
                    statusBadge(template.status)
                }
                .width(min: 70, ideal: 90)

                TableColumn("Updated") { (template: NotebooksService.NotebookListItem) in
                    Text(formatDate(template.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 120)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedTemplates: [NotebooksService.NotebookListItem] {
        templates.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "archived": .gray
        case "draft": .orange
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    nonisolated private func formatDate(_ dateStr: String?) -> String {
        guard let dateStr else { return "-" }
        if dateStr.count >= 16 {
            return String(dateStr.prefix(16))
        }
        return dateStr
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            let service = NotebooksService(db: db)
            templates = try service.listTemplates()
        } catch {
            print("[NotebookTemplatesPage] Load error: \(error)")
        }

        isLoading = false
    }
}
