import SwiftUI
import WiredPartCore

/// Notebook detail page showing info fields, entries, and tasks.
struct IOSNotebookDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let notebookId: Int64

    @State private var notebook: NotebooksService.NotebookDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedTab = "entries"

    private let tabs = ["entries", "tasks", "info"]

    var body: some View {
        VStack(spacing: 0) {
            tabPicker

            if isLoading {
                ProgressView("Loading notebook...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                tabContent
            }
        }
        .navigationTitle(notebook?.title ?? "Notebook")
        .refreshable { loadData() }
        .task { loadData() }
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.capitalized)
                            .font(.caption)
                            .fontWeight(selectedTab == tab ? .bold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selectedTab == tab ? Color.accentColor : Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case "entries":
            entriesTab
        case "tasks":
            tasksTab
        case "info":
            infoTab
        default:
            Text("Unknown tab")
        }
    }

    private var entriesTab: some View {
        List {
            let entries = notebook?.entries ?? []
            if entries.isEmpty {
                Section {
                    EmptyStateView(
                        icon: "note.text",
                        title: "No Entries",
                        message: "This notebook has no entries yet."
                    )
                }
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.content)
                            .font(.subheadline)
                        HStack {
                            Text(entry.createdByName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let date = entry.createdAt {
                                Text(String(date.prefix(10)))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private var tasksTab: some View {
        List {
            Section {
                Text("Tasks will be loaded from NotebooksService")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private var infoTab: some View {
        List {
            if let nb = notebook {
                Section("Notebook Info") {
                    detailRow("Title", nb.title)
                    detailRow("Type", nb.notebookType)
                    if let created = nb.createdAt {
                        detailRow("Created", String(created.prefix(10)))
                    }
                    if let jobName = nb.jobName {
                        detailRow("Job", jobName)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func loadData() {
        guard let service = appCore.notebooksService else { return }
        isLoading = notebook == nil
        loadError = nil
        do {
            notebook = try service.getNotebookDetail(id: notebookId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
