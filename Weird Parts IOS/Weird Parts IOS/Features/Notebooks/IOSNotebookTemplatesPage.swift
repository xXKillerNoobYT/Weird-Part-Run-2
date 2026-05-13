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
        case help
        var id: String {
            switch self {
            case .createNotebook(let templateId): return "create-\(templateId)"
            case .help: return "help"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var pendingDeleteTemplateId: Int64?

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
                .accessibilityLabel("Refresh default templates")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .confirmationDialog(
            DestructiveConfirmationCopy.deleteTitle("Template"),
            isPresented: Binding(get: { pendingDeleteTemplateId != nil }, set: { if !$0 { pendingDeleteTemplateId = nil } }),
            titleVisibility: .visible
        ) {
            Button(DestructiveConfirmationCopy.deleteButton("Template"), role: .destructive) {
                if let id = pendingDeleteTemplateId { deleteTemplate(id) }
            }
            Button("Cancel", role: .cancel) { pendingDeleteTemplateId = nil }
        } message: {
            Text(DestructiveConfirmationCopy.deleteMessage(itemName: pendingDeleteTemplateName))
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .createNotebook(let templateId):
                CreateNotebookSheet(templateId: templateId, onSave: { loadData() })
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(title: "Notebook Templates Help", sections: [
                    ("What This Page Does", "Displays available notebook templates grouped by category. Templates provide pre-built structures so you can create new notebooks with sections and entries already laid out, saving time on repetitive documentation."),
                    ("How to Use It", "Browse templates by category. Tap any template or swipe right and tap 'Use' to create a new notebook from that template. Use the search bar to filter templates by name, description, or category."),
                    ("Template Types", "Job templates are designed for job-site documentation with sections like scope of work, materials, and punch lists. General templates cover everyday needs like meeting notes or inspections."),
                    ("Refreshing Defaults", "Tap the refresh button in the toolbar to re-seed the default templates. This is useful if defaults were deleted or if new built-in templates have been added in an update."),
                    ("Deleting Templates", "Swipe left on any non-default template to delete it. Default templates cannot be deleted to ensure a baseline set is always available.")
                ])
            }
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Template List

    private var pendingDeleteTemplateName: String {
        guard let id = pendingDeleteTemplateId else { return "this template" }
        return templates.first(where: { $0.id == id })?.name ?? "this template"
    }

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
                    .accessibilityHidden(true)
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
                    pendingDeleteTemplateId = template.id
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
            loadError = userFriendlyError(error, context: "load notebooks")
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
            actionError = userFriendlyError(error, context: "save template")
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
            actionError = userFriendlyError(error, context: "save template")
        }
    }
}
