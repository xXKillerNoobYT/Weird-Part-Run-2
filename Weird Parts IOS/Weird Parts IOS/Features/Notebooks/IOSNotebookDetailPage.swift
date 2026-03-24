import SwiftUI
import WiredPartCore

/// Notebook detail page with hierarchical structure: Groups → Sections → Block Entries.
struct IOSNotebookDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let notebookId: Int64

    // MARK: - State

    @State private var notebook: NotebooksService.NotebookDetail?
    @State private var hierarchy: NotebooksService.NotebookHierarchy?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var expandedGroups: Set<Int64> = []
    @State private var expandedSections: Set<Int64> = []

    // MARK: - ActiveSheet

    private enum ActiveSheet: Identifiable {
        case addEntry(sectionId: Int64)
        case editEntry(NotebooksService.NotebookEntryRow)
        case addSection(groupId: Int64?)
        case addGroup
        case editSection(sectionId: Int64, name: String)
        case editGroup(groupId: Int64, name: String)

        var id: String {
            switch self {
            case .addEntry(let id): return "addEntry-\(id)"
            case .editEntry(let entry): return "editEntry-\(entry.id)"
            case .addSection(let id): return "addSection-\(id ?? 0)"
            case .addGroup: return "addGroup"
            case .editSection(let id, _): return "editSection-\(id)"
            case .editGroup(let id, _): return "editGroup-\(id)"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading notebook...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                contentList
            }
        }
        .navigationTitle(notebook?.title ?? "Notebook")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        activeSheet = .addGroup
                    } label: {
                        Label("Add Section Group", systemImage: "folder.badge.plus")
                    }
                    Button {
                        activeSheet = .addSection(groupId: nil)
                    } label: {
                        Label("Add Section", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
                .environmentObject(appCore)
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Content List

    private var contentList: some View {
        List {
            if let error = actionError {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }

            // Section Groups (collapsible)
            if let groups = hierarchy?.groups, !groups.isEmpty {
                ForEach(groups) { groupItem in
                    Section {
                        DisclosureGroup(
                            isExpanded: groupBinding(groupItem.id)
                        ) {
                            ForEach(groupItem.sections) { sectionItem in
                                sectionRow(sectionItem)
                            }
                            Button {
                                activeSheet = .addSection(groupId: groupItem.id)
                            } label: {
                                Label("Add Section", systemImage: "plus")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.orange)
                                Text(groupItem.name).font(.headline)
                                Spacer()
                                Text("\(groupItem.sections.count) sections")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .contextMenu {
                                Button {
                                    activeSheet = .editGroup(groupId: groupItem.id, name: groupItem.name)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button {
                                    activeSheet = .addSection(groupId: groupItem.id)
                                } label: {
                                    Label("Add Section", systemImage: "plus")
                                }
                                Button(role: .destructive) {
                                    deleteSectionGroup(groupItem.id)
                                } label: {
                                    Label("Delete Group", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            // Ungrouped sections
            if let ungrouped = hierarchy?.ungroupedSections, !ungrouped.isEmpty {
                Section {
                    ForEach(ungrouped) { sectionItem in
                        sectionRow(sectionItem)
                    }
                } header: {
                    Text("Pages")
                }
            }

            // Empty state
            if hierarchy?.groups.isEmpty == true && hierarchy?.ungroupedSections.isEmpty == true {
                Section {
                    EmptyStateView(
                        icon: "note.text",
                        title: "No Content",
                        message: "Add section groups and sections to organize this notebook."
                    )
                }
            }

            // Legacy entries (entries without sections from before the hierarchy)
            let legacyEntries = notebook?.entries ?? []
            if !legacyEntries.isEmpty && hierarchy?.groups.isEmpty == true && hierarchy?.ungroupedSections.isEmpty == true {
                Section {
                    ForEach(legacyEntries) { entry in
                        entryRow(entry)
                    }
                } header: {
                    Text("Entries")
                }
            }

            // Info section
            Section {
                if let nb = notebook {
                    detailRow("Type", nb.notebookType)
                    if let created = nb.createdAt {
                        detailRow("Created", String(created.prefix(10)))
                    }
                    if let jobName = nb.jobName {
                        detailRow("Job", jobName)
                    }
                }
            } header: {
                Text("Notebook Info")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Section Row

    private func sectionRow(_ sectionItem: NotebooksService.SectionWithEntries) -> some View {
        DisclosureGroup(
            isExpanded: sectionBinding(sectionItem.id)
        ) {
            ForEach(sectionItem.entries) { entry in
                entryRow(entry)
            }
            Button {
                activeSheet = .addEntry(sectionId: sectionItem.id)
            } label: {
                Label("Add Block", systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        } label: {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.blue)
                Text(sectionItem.name).font(.subheadline)
                Spacer()
                Text("\(sectionItem.entries.count)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .contextMenu {
                Button {
                    activeSheet = .editSection(sectionId: sectionItem.id, name: sectionItem.name)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    activeSheet = .addEntry(sectionId: sectionItem.id)
                } label: {
                    Label("Add Block", systemImage: "plus.circle")
                }
                Button(role: .destructive) {
                    deleteSection(sectionItem.id)
                } label: {
                    Label("Delete Section", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Block Entry Display

    @ViewBuilder
    private func entryRow(_ entry: NotebooksService.NotebookEntryRow) -> some View {
        Group {
            switch entry.blockType {
            case "heading":
                Text(entry.title ?? entry.content)
                    .font(headingFont(level: entry.headingLevel ?? 1))
                    .bold()

            case "checklist":
                if let items = decodeChecklistItems(entry.checklistItems) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = entry.title, !title.isEmpty {
                            Text(title).font(.subheadline).bold()
                        }
                        ForEach(items.indices, id: \.self) { idx in
                            HStack(spacing: 8) {
                                Image(systemName: items[idx].checked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(items[idx].checked ? .green : .secondary)
                                Text(items[idx].text)
                                    .strikethrough(items[idx].checked)
                                    .font(.subheadline)
                            }
                        }
                    }
                } else {
                    Text(entry.content).font(.subheadline)
                }

            case "photo":
                if let path = entry.photoPath, let url = URL(string: path) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } placeholder: {
                        HStack {
                            Image(systemName: "photo")
                            Text("Loading photo...")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                        Text(entry.title ?? "Photo").font(.subheadline)
                    }
                }

            case "part_reference":
                HStack {
                    Image(systemName: "shippingbox.fill").foregroundStyle(.blue)
                    Text(entry.title ?? "Part Reference")
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                }
                .padding(8)
                .background(.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            case "divider":
                Divider()

            case "callout":
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(.yellow)
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = entry.title, !title.isEmpty {
                            Text(title).font(.subheadline).bold()
                        }
                        Text(entry.content)
                            .font(.callout)
                            .italic()
                    }
                }
                .padding(.vertical, 4)

            case "table":
                HStack {
                    Image(systemName: "tablecells").foregroundStyle(.purple)
                    Text(entry.title ?? "Table").font(.subheadline)
                }
                .padding(8)
                .background(.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            case "todo":
                HStack(spacing: 8) {
                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(entry.isCompleted ? .green : .secondary)
                    Text(entry.title ?? entry.content)
                        .font(.subheadline)
                        .strikethrough(entry.isCompleted)
                }

            default: // "text" and any other type
                VStack(alignment: .leading, spacing: 2) {
                    if let title = entry.title, !title.isEmpty {
                        Text(title).font(.subheadline).bold()
                    }
                    if !entry.content.isEmpty {
                        Text(entry.content)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    HStack {
                        Text(entry.createdByName)
                            .font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        if let date = entry.createdAt {
                            Text(String(date.prefix(10)))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .contextMenu {
            Button {
                activeSheet = .editEntry(entry)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteEntry(entry.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .headline
        }
    }

    private struct ChecklistItemData: Codable {
        let text: String
        let checked: Bool
    }

    private func decodeChecklistItems(_ json: String?) -> [ChecklistItemData]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([ChecklistItemData].self, from: data)
    }

    private func groupBinding(_ id: Int64) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(id) },
            set: { expanded in
                if expanded { expandedGroups.insert(id) }
                else { expandedGroups.remove(id) }
            }
        )
    }

    private func sectionBinding(_ id: Int64) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(id) },
            set: { expanded in
                if expanded { expandedSections.insert(id) }
                else { expandedSections.remove(id) }
            }
        )
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .addEntry(let sectionId):
            AddNotebookEntrySheet(
                notebookId: notebookId,
                sectionId: sectionId,
                onSave: { loadData() }
            )

        case .editEntry(let entry):
            AddNotebookEntrySheet(
                notebookId: notebookId,
                sectionId: nil,
                editingEntry: entry,
                onSave: { loadData() }
            )

        case .addSection(let groupId):
            NameInputSheet(title: "New Section", placeholder: "Section name") { name in
                createSection(groupId: groupId, name: name)
            }

        case .addGroup:
            NameInputSheet(title: "New Section Group", placeholder: "Group name") { name in
                createSectionGroup(name: name)
            }

        case .editSection(let sectionId, let currentName):
            NameInputSheet(title: "Rename Section", placeholder: "Section name", initialValue: currentName) { name in
                renameSection(sectionId: sectionId, name: name)
            }

        case .editGroup(let groupId, let currentName):
            NameInputSheet(title: "Rename Group", placeholder: "Group name", initialValue: currentName) { name in
                renameSectionGroup(groupId: groupId, name: name)
            }
        }
    }

    // MARK: - Data Operations

    private func loadData() {
        guard let service = appCore.notebooksService else {
            loadError = "Notebooks service unavailable"
            isLoading = false
            return
        }
        isLoading = notebook == nil
        loadError = nil
        actionError = nil
        do {
            notebook = try service.getNotebookDetail(id: notebookId)
            hierarchy = try service.getNotebookHierarchy(notebookId: notebookId)
            // Auto-expand all groups and sections on first load
            if expandedGroups.isEmpty, let groups = hierarchy?.groups {
                expandedGroups = Set(groups.map(\.id))
            }
            if expandedSections.isEmpty {
                var ids: [Int64] = []
                hierarchy?.groups.forEach { g in ids.append(contentsOf: g.sections.map(\.id)) }
                hierarchy?.ungroupedSections.forEach { s in ids.append(s.id) }
                expandedSections = Set(ids)
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func createSectionGroup(name: String) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            _ = try service.createSectionGroup(notebookId: notebookId, name: name)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func createSection(groupId: Int64?, name: String) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            _ = try service.createSection(notebookId: notebookId, groupId: groupId, name: name)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func renameSectionGroup(groupId: Int64, name: String) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.updateSectionGroup(groupId: groupId, name: name)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func renameSection(sectionId: Int64, name: String) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.updateSection(sectionId: sectionId, name: name)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteSectionGroup(_ groupId: Int64) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.deleteSectionGroup(groupId: groupId)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteSection(_ sectionId: Int64) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.deleteSection(sectionId: sectionId)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteEntry(_ entryId: Int64) {
        guard let service = appCore.notebooksService else {
            actionError = "Notebooks service unavailable"
            return
        }
        do {
            try service.deleteBlockEntry(entryId: entryId)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - NameInputSheet

/// Simple sheet for entering a name (group or section).
private struct NameInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let placeholder: String
    var initialValue: String = ""
    let onSave: (String) -> Void

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $name)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = initialValue
            }
        }
    }
}
