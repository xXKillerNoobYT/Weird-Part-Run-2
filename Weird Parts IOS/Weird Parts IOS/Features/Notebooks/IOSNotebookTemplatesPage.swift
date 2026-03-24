import SwiftUI
import WiredPartCore

/// Notebook templates page showing available templates grouped by category.
struct IOSNotebookTemplatesPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var templates: [NotebooksService.NotebookTemplateItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var actionError: String?

    private enum ActiveSheet: Identifiable {
        case createNotebook(templateId: Int64)
        var id: String { "create-\(templateId)" }
        var templateId: Int64 {
            switch self { case .createNotebook(let id): return id }
        }
    }
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading templates...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if filteredTemplates.isEmpty {
                ContentUnavailableView {
                    Label("No Templates", systemImage: "doc.text")
                } description: {
                    Text("No notebook templates found.")
                }
            } else {
                templateList
            }
        }
        .navigationTitle("Templates")
        .searchable(text: $searchText, prompt: "Search templates...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    seedTemplates()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            CreateNotebookSheet(templateId: sheet.templateId, onSave: { loadData() })
                .environmentObject(appCore)
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Template List

    private var templateList: some View {
        List {
            if let error = actionError {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }

            ForEach(groupedCategories, id: \.self) { category in
                Section {
                    ForEach(templatesForCategory(category)) { template in
                        templateRow(template)
                    }
                } header: {
                    Text(category.capitalized)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var filteredTemplates: [NotebooksService.NotebookTemplateItem] {
        guard !searchText.isEmpty else { return templates }
        let query = searchText.lowercased()
        return templates.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) == true) ||
            ($0.category?.lowercased().contains(query) == true)
        }
    }

    private var groupedCategories: [String] {
        let cats = Set(filteredTemplates.map { $0.category ?? "general" })
        return cats.sorted()
    }

    private func templatesForCategory(_ category: String) -> [NotebooksService.NotebookTemplateItem] {
        filteredTemplates.filter { ($0.category ?? "general") == category }
    }

    private func templateRow(_ template: NotebooksService.NotebookTemplateItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: template.templateType == "job" ? "doc.richtext.fill" : "doc.text.fill")
                    .foregroundStyle(.orange)
                Text(template.name).font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Text(template.templateType.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1))
                        .clipShape(Capsule())
                    if template.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green)
                            .clipShape(Capsule())
                    }
                }
            }
            if let desc = template.description {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button {
                activeSheet = .createNotebook(templateId: template.id)
            } label: {
                Label("Use", systemImage: "plus.circle")
            }
            .tint(.blue)
            if !template.isDefault {
                Button(role: .destructive) {
                    deleteTemplate(template.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activeSheet = .createNotebook(templateId: template.id)
        }
    }

    // MARK: - Actions

    private func loadData() {
        guard let service = appCore.notebooksService else {
            loadError = "Notebooks service unavailable"
            isLoading = false
            return
        }
        isLoading = templates.isEmpty
        loadError = nil
        do {
            templates = try service.getTemplates()
            // Auto-seed defaults if none exist
            if templates.isEmpty, let userId = appCore.currentUser?.id {
                try service.seedDefaultTemplates(createdBy: userId)
                templates = try service.getTemplates()
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteTemplate(_ templateId: Int64) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.deleteTemplate(templateId: templateId)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func seedTemplates() {
        guard let service = appCore.notebooksService,
              let userId = appCore.currentUser?.id else {
            actionError = "Service unavailable"
            return
        }
        do {
            try service.seedDefaultTemplates(createdBy: userId)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
