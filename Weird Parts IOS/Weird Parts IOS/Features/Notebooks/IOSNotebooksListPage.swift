import SwiftUI
import WiredPartCore

/// Notebooks list page for iOS.
///
/// Displays a searchable list of notebooks with title, type badge,
/// associated job name, entries count, and status. Supports pull-to-refresh
/// and type-based filtering.
struct IOSNotebooksListPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var notebooks: [NotebooksService.NotebookListItem] = []
    @State private var allNotebooks: [NotebooksService.NotebookListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var typeFilter = "all"
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var dateRange: ReportDateRange = .thisMonth
    @State private var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    private let typeOptions = ["all", "general", "job", "daily_report", "checklist"]

    // MARK: - ActiveSheet

    private enum ActiveSheet: Identifiable {
        case help
        case createNotebook
        var id: String {
            switch self {
            case .help: return "help"
            case .createNotebook: return "create"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "notebooks-all")
            SkippedModuleHint(moduleId: "notebooks")
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            typePicker
            notebookList
        }
        .task { appCore.onboardingManager?.markCompleted("notebooks-view") }
        .navigationTitle("Notebooks")
        .searchable(text: $searchText, prompt: "Search notebooks...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .createNotebook } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create notebook")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .createNotebook:
                CreateNotebookSheet(onSave: { loadData() })
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(title: "Notebooks Help", sections: [
                ("What This Page Does", "Displays all notebooks in the system. Notebooks are organized documents that hold structured entries such as text blocks, checklists, photos, and part references. They can be general-purpose or linked to specific jobs."),
                ("How to Use It", "Use the type filter chips at the top to narrow by notebook type (General, Job, Daily Report, or Checklist). Use the search bar to find notebooks by title, job name, or author. Tap a notebook to view its full contents. Pull down to refresh the list."),
                ("Creating a Notebook", "Tap the + button in the toolbar to create a new notebook. You can choose a type, assign it to a job, and optionally start from a template."),
                ("Notebook Types", "General notebooks are standalone. Job notebooks are linked to a specific job. Daily Report notebooks track daily progress. Checklist notebooks contain to-do items that can be checked off.")
            ])
            }
        }
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
        .onAppear {
            NotificationCenter.default.post(
                name: .notebooksListPageActive,
                object: nil,
                userInfo: [
                    "context": "Notebooks List: \(notebooks.count) notebooks, type filter: \(typeFilter)."
                ]
            )
            // Register AI filter (prompt 62S)
            appCore.aiFilterRegistry.register(
                pageId: "notebooks",
                filterName: "Notebook Type",
                options: typeOptions,
                activate: { value in
                    typeFilter = value
                    loadData()
                }
            )
            appCore.aiFilterRegistry.applyPendingFilter(pageId: "notebooks")
        }
        .onDisappear {
            NotificationCenter.default.post(name: .notebooksListPageInactive, object: nil)
            appCore.aiFilterRegistry.deregister(pageId: "notebooks")
        }
    }

    // MARK: - Type Picker

    private func countForType(_ type: String) -> Int {
        let notebooks = dateFilteredAllNotebooks
        if type == "all" { return notebooks.count }
        return notebooks.filter { $0.notebookType == type }.count
    }

    private var typePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(typeOptions, id: \.self) { type in
                    SmartFilterCard(
                        title: type == "all" ? "All" : type.replacingOccurrences(of: "_", with: " ").capitalized,
                        count: countForType(type),
                        isSelected: typeFilter == type
                    ) {
                        typeFilter = type
                        loadData()
                    }
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
            ProgressView("Loading notebooks...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredNotebooks.isEmpty {
            ContentUnavailableView {
                Label("No Notebooks", systemImage: "book.closed")
            } description: {
                Text("No notebooks match your criteria.")
            }
        } else {
            List(filteredNotebooks, id: \.id) { notebook in
                NavigationLink(destination: IOSNotebookDetailPage(notebookId: notebook.id).environmentObject(appCore)) {
                    notebookRow(notebook)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredNotebooks: [NotebooksService.NotebookListItem] {
        var result = dateFilteredNotebooks

        guard !searchText.isEmpty else { return result }
        let query = searchText.lowercased()
        result = result.filter {
            $0.title.lowercased().contains(query) ||
            ($0.jobName?.lowercased().contains(query) ?? false) ||
            $0.createdByName.lowercased().contains(query)
        }
        return result
    }

    private var dateFilteredNotebooks: [NotebooksService.NotebookListItem] {
        notebooks.filter(matchesSelectedDateRange)
    }

    private var dateFilteredAllNotebooks: [NotebooksService.NotebookListItem] {
        allNotebooks.filter(matchesSelectedDateRange)
    }

    private func matchesSelectedDateRange(_ notebook: NotebooksService.NotebookListItem) -> Bool {
        StandardFilterBarDateFilter.contains(
            notebook.updatedAt,
            selectedRange: dateRange,
            customStart: customStart,
            customEnd: customEnd
        )
    }

    private func notebookRow(_ notebook: NotebooksService.NotebookListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notebookIcon(notebook.notebookType))
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(notebook.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    typeBadge(notebook.notebookType)
                }
                if let jobName = notebook.jobName {
                    Label(jobName, systemImage: "hammer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text("by \(notebook.createdByName)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let updated = notebook.updatedAt {
                        Text(updated)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(notebook.status)
                Label("\(notebook.entryCount)", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Show green dot for recently updated notebooks
            if isRecentlyUpdated(notebook.updatedAt) {
                ActionDot(isOverdue: false)
            }
        }
        .padding(.vertical, 4)
    }

    /// Check if a date string represents a recent update (within 7 days).
    private func isRecentlyUpdated(_ dateStr: String?) -> Bool {
        guard let dateStr else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: dateStr) ?? basic.date(from: dateStr) else { return false }
        return Date().timeIntervalSince(date) < 7 * 86400
    }

    // MARK: - Helpers

    private func notebookIcon(_ type: String) -> String {
        switch type {
        case "job": return "hammer.circle"
        case "general": return "book"
        case "daily_report": return "sun.and.horizon"
        case "checklist": return "checklist"
        case "template": return "doc.text"
        default: return "book.closed"
        }
    }

    private func typeBadge(_ type: String) -> some View {
        let color: Color = switch type {
        case "job": .blue
        case "general": .green
        case "daily_report": .orange
        case "checklist": .purple
        default: .secondary
        }
        return Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

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
            allNotebooks = try service.listNotebooks(notebookType: nil)
            notebooks = typeFilter == "all"
                ? allNotebooks
                : allNotebooks.filter { $0.notebookType == typeFilter }
        } catch {
            loadError = userFriendlyError(error, context: "load notebooks")
        }
        isLoading = false
    }
}
