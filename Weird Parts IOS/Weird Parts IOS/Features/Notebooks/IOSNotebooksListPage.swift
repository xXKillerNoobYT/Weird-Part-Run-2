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
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var typeFilter = "all"

    private let typeOptions = ["all", "general", "job", "daily_report", "checklist"]

    var body: some View {
        VStack(spacing: 0) {
            typePicker
            notebookList
        }
        .navigationTitle("Notebooks")
        .searchable(text: $searchText, prompt: "Search notebooks...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Type Picker

    private var typePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(typeOptions, id: \.self) { type in
                    Button {
                        typeFilter = type
                        loadData()
                    } label: {
                        Text(type == "all" ? "All" : type.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .fontWeight(typeFilter == type ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(typeFilter == type ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(typeFilter == type ? .white : .primary)
                    }
                    .buttonStyle(.plain)
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
        } else if filteredNotebooks.isEmpty {
            ContentUnavailableView {
                Label("No Notebooks", systemImage: "book.closed")
            } description: {
                Text("No notebooks match your criteria.")
            }
        } else {
            List(filteredNotebooks, id: \.id) { notebook in
                notebookRow(notebook)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredNotebooks: [NotebooksService.NotebookListItem] {
        guard !searchText.isEmpty else { return notebooks }
        let query = searchText.lowercased()
        return notebooks.filter {
            $0.title.lowercased().contains(query) ||
            ($0.jobName?.lowercased().contains(query) ?? false) ||
            $0.createdByName.lowercased().contains(query)
        }
    }

    private func notebookRow(_ notebook: NotebooksService.NotebookListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notebookIcon(notebook.notebookType))
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

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
        }
        .padding(.vertical, 4)
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
        guard let service = appCore.notebooksService else { return }
        isLoading = notebooks.isEmpty
        do {
            notebooks = try service.listNotebooks(
                notebookType: typeFilter == "all" ? nil : typeFilter
            )
        } catch {
            print("[IOSNotebooksListPage] Load error: \(error)")
        }
        isLoading = false
    }
}
