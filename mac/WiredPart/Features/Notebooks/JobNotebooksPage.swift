import SwiftUI
import WiredPartCore

/// Job notebooks page showing only notebooks linked to jobs.
///
/// Displays a table of job-specific notebooks with title, job name, creator,
/// entry count, status, and last updated date columns. Filters by notebook_type = "job".
struct JobNotebooksPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var notebooks: [NotebooksService.NotebookListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

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
                Text("Job Notebooks")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(notebooks.count) notebook\(notebooks.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search job notebooks...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { loadData() }

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
            ProgressView("Loading job notebooks...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredNotebooks.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "hammer")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No job notebooks")
                    .font(.headline)
                Text(searchText.isEmpty
                     ? "Job notebooks are created from within job details."
                     : "No job notebooks match your search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedNotebooks, sortOrder: $sortOrder) {
                TableColumn("Title", value: \.title) { notebook in
                    Text(notebook.title)
                        .fontWeight(.medium)
                }
                .width(min: 150, ideal: 220)

                TableColumn("Job") { (notebook: NotebooksService.NotebookListItem) in
                    Text(notebook.jobName ?? "-")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 180)

                TableColumn("Created By", value: \.createdByName) { notebook in
                    Text(notebook.createdByName)
                        .font(.callout)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Entries", value: \.entryCount) { notebook in
                    Text("\(notebook.entryCount)")
                        .font(.callout)
                }
                .width(min: 50, ideal: 60)

                TableColumn("Status", value: \.status) { notebook in
                    statusBadge(notebook.status)
                }
                .width(min: 70, ideal: 90)

                TableColumn("Updated") { (notebook: NotebooksService.NotebookListItem) in
                    Text(formatDate(notebook.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 120)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var filteredNotebooks: [NotebooksService.NotebookListItem] {
        guard !searchText.isEmpty else { return notebooks }
        let term = searchText.lowercased()
        return notebooks.filter { nb in
            nb.title.lowercased().contains(term) ||
            (nb.jobName ?? "").lowercased().contains(term) ||
            nb.createdByName.lowercased().contains(term)
        }
    }

    private var sortedNotebooks: [NotebooksService.NotebookListItem] {
        filteredNotebooks.sorted(using: sortOrder)
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
            notebooks = try service.listNotebooks(notebookType: "job")
        } catch {
            print("[JobNotebooksPage] Load error: \(error)")
        }

        isLoading = false
    }
}
