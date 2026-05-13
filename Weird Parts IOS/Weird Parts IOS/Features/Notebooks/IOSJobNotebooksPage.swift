import SwiftUI
import WiredPartCore

/// Job-linked notebooks list page for iOS.
///
/// Displays notebooks that are associated with jobs, showing the notebook name,
/// linked job name, entry count, and last-updated date. Supports search filtering
/// and pull-to-refresh.
struct IOSJobNotebooksPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var notebooks: [NotebooksService.NotebookListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var statusCounts: [String: Int] = [:]
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private let statusOptions = ["all", "active", "archived", "locked"]

    // MARK: - ActiveSheet

    private enum ActiveSheet: Identifiable {
        case help
        var id: String {
            switch self {
            case .help: return "help"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "notebooks-job-notebooks")
            statusPicker
            notebookList
        }
        .task { appCore.onboardingManager?.markCompleted("job-notebooks-view") }
        .navigationTitle("Job Notebooks")
        .searchable(text: $searchText, prompt: "Search job notebooks...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Job Notebooks Help", sections: [
                ("What This Page Does", "Shows all notebooks that are linked to jobs. Each notebook tracks structured documentation for a specific job, including notes, checklists, photos, and task items."),
                ("How to Use It", "Use the status filter chips at the top to show only Active, Archived, or Locked notebooks. Use the search bar to find notebooks by title, job name, or author. Tap a notebook to open it and view or edit its entries. Pull down to refresh."),
                ("Notebook Statuses", "Active notebooks are in use and can be edited. Archived notebooks are read-only records of completed work. Locked notebooks are frozen and cannot be modified, typically for compliance or approval purposes."),
                ("Job Context", "Every notebook on this page is tied to a job. The linked job name appears below the notebook title. This makes it easy to find all documentation for a particular job site or project.")
            ])
        }
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let total = statusCounts.values.reduce(0, +)
                SmartFilterCard(
                    title: "All",
                    count: total,
                    isSelected: statusFilter == "all",
                    action: { statusFilter = "all"; loadData() }
                )
                ForEach(statusOptions.dropFirst(), id: \.self) { status in
                    SmartFilterCard(
                        title: status.capitalized,
                        count: statusCounts[status] ?? 0,
                        isSelected: statusFilter == status,
                        action: { statusFilter = status; loadData() }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Notebook List

    @ViewBuilder
    private var notebookList: some View {
        if isLoading {
            ProgressView("Loading job notebooks...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredNotebooks.isEmpty {
            EmptyStateView(
                icon: "hammer.circle",
                title: "No Job Notebooks",
                message: "No job-linked notebooks match your criteria.",
                helpLabel: "Learn how job notebooks work",
                helpAction: { activeSheet = .help }
            )
        } else {
            List(filteredNotebooks, id: \.id) { notebook in
                notebookRow(notebook)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredNotebooks: [NotebooksService.NotebookListItem] {
        var result = notebooks
        if statusFilter != "all" {
            result = result.filter { $0.status == statusFilter }
        }
        guard !searchText.isEmpty else { return result }
        let query = searchText.lowercased()
        return result.filter {
            $0.title.lowercased().contains(query) ||
            ($0.jobName?.lowercased().contains(query) ?? false) ||
            $0.createdByName.lowercased().contains(query)
        }
    }

    private func notebookRow(_ notebook: NotebooksService.NotebookListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(notebook.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let jobName = notebook.jobName {
                    Label(jobName, systemImage: "hammer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("by \(notebook.createdByName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(notebook.status)
                Label("\(notebook.entryCount)", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let updated = notebook.updatedAt {
                    Text(formatDate(updated))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "archived": .secondary
        case "locked": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    private func formatDate(_ dateStr: String) -> String {
        if dateStr.count >= 10 { return String(dateStr.prefix(10)) }
        return dateStr
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.notebooksService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = notebooks.isEmpty
        loadError = nil
        do {
            notebooks = try service.listNotebooks(notebookType: "job")
            // Load status counts for SmartFilterCard
            if statusCounts.isEmpty {
                var counts: [String: Int] = [:]
                for nb in notebooks {
                    counts[nb.status, default: 0] += 1
                }
                statusCounts = counts
            }
        } catch {
            loadError = userFriendlyError(error, context: "load notebooks")
        }
        isLoading = false
    }
}
