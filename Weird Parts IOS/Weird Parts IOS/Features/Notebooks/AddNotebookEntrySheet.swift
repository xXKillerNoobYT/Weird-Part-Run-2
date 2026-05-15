import SwiftUI
import WiredPartCore

/// Sheet for adding or editing a block entry in a notebook section.
struct AddNotebookEntrySheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let notebookId: Int64
    let sectionId: Int64?
    var editingEntry: NotebooksService.NotebookEntryRow?
    var onSave: () -> Void

    @State private var title = ""
    @State private var content = ""
    @State private var blockType = "text"
    @State private var headingLevel = 1
    @State private var checklistItems: [ChecklistItemInput] = []
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showShortcutHints = false
    @State private var showDeleteChecklistConfirm = false
    @State private var deleteChecklistOffsets: IndexSet?

    private var isEditing: Bool { editingEntry != nil }
    private var hasUnsavedContent: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty ||
        !content.trimmingCharacters(in: .whitespaces).isEmpty ||
        !checklistItems.isEmpty
    }

    private struct ChecklistItemInput: Identifiable {
        let id = UUID()
        var text: String
        var checked: Bool
    }

    private struct SlashCommand: Identifiable {
        let id: String
        let command: String
        let title: String
        let subtitle: String
        let systemImage: String
        let blockType: String
        let headingLevel: Int?
    }

    private let slashCommands: [SlashCommand] = [
        SlashCommand(id: "h1", command: "/h1", title: "Heading 1", subtitle: "Large section header", systemImage: "textformat.size.larger", blockType: "heading", headingLevel: 1),
        SlashCommand(id: "h2", command: "/h2", title: "Heading 2", subtitle: "Medium sub-header", systemImage: "textformat.size", blockType: "heading", headingLevel: 2),
        SlashCommand(id: "h3", command: "/h3", title: "Heading 3", subtitle: "Small sub-header", systemImage: "textformat", blockType: "heading", headingLevel: 3),
        SlashCommand(id: "checklist", command: "/checklist", title: "Checklist", subtitle: "Checkbox list items", systemImage: "checklist", blockType: "checklist", headingLevel: nil),
        SlashCommand(id: "photo", command: "/photo", title: "Photo", subtitle: "Camera or library placeholder", systemImage: "photo", blockType: "photo", headingLevel: nil),
        SlashCommand(id: "part", command: "/part", title: "Part Reference", subtitle: "Tappable part reference placeholder", systemImage: "shippingbox", blockType: "part_reference", headingLevel: nil),
        SlashCommand(id: "panel", command: "/panel", title: "Panel Schedule", subtitle: "Embedded panel schedule block", systemImage: "bolt", blockType: "panel_schedule", headingLevel: nil),
        SlashCommand(id: "divider", command: "/divider", title: "Divider", subtitle: "Horizontal separator", systemImage: "minus", blockType: "divider", headingLevel: nil),
        SlashCommand(id: "quote", command: "/quote", title: "Quote", subtitle: "Indented quote block", systemImage: "quote.opening", blockType: "quote", headingLevel: nil),
        SlashCommand(id: "callout", command: "/callout", title: "Callout", subtitle: "Highlighted note", systemImage: "exclamationmark.bubble", blockType: "callout", headingLevel: nil),
        SlashCommand(id: "table", command: "/table", title: "Table", subtitle: "Simple grid placeholder", systemImage: "tablecells", blockType: "table", headingLevel: nil),
        SlashCommand(id: "code", command: "/code", title: "Code", subtitle: "Monospace code block", systemImage: "chevron.left.forwardslash.chevron.right", blockType: "code", headingLevel: nil),
        SlashCommand(id: "todo", command: "/todo", title: "To-Do", subtitle: "Work item with status tracking", systemImage: "circle", blockType: "todo", headingLevel: nil)
    ]

    private var slashQuery: String? {
        guard !isEditing, content.hasPrefix("/") else { return nil }
        return String(content.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredSlashCommands: [SlashCommand] {
        guard let query = slashQuery, !query.isEmpty else { return slashCommands }
        return slashCommands.filter { command in
            command.command.dropFirst().lowercased().contains(query) ||
            command.title.lowercased().contains(query) ||
            command.subtitle.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Block type picker
                if !isEditing {
                    Section("Block Type") {
                        Picker("Type", selection: $blockType) {
                            Text("Text").tag("text")
                            Text("Heading").tag("heading")
                            Text("Checklist").tag("checklist")
                            Text("Photo").tag("photo")
                            Text("Part Reference").tag("part_reference")
                            Text("Panel Schedule").tag("panel_schedule")
                            Text("To-Do").tag("todo")
                            Text("Quote").tag("quote")
                            Text("Callout").tag("callout")
                            Text("Table").tag("table")
                            Text("Code").tag("code")
                            Text("Divider").tag("divider")
                        }
                        .pickerStyle(.menu)
                        Text("Type / in the content field to open the command palette.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if slashQuery != nil {
                    commandPaletteSection
                }

                // Type-specific fields
                switch blockType {
                case "heading":
                    headingFields

                case "checklist":
                    checklistFields

                case "todo":
                    todoFields

                case "callout":
                    calloutFields

                case "quote":
                    quoteFields

                case "code":
                    codeFields

                case "photo":
                    photoFields

                case "part_reference":
                    partReferenceFields

                case "panel_schedule":
                    panelScheduleFields

                case "table":
                    tableFields

                case "divider":
                    Section {
                        Text("A horizontal divider will be inserted.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                default: // "text"
                    textFields
                }

                // Shortcut command hints
                if !isEditing {
                    Section {
                        DisclosureGroup("Shortcut Commands", isExpanded: $showShortcutHints) {
                            VStack(alignment: .leading, spacing: 6) {
                                shortcutRow("/h1 Title", "Heading level 1")
                                shortcutRow("/h2 Title", "Heading level 2")
                                shortcutRow("/h3 Title", "Heading level 3")
                                shortcutRow("/checklist", "New checklist")
                                shortcutRow("/todo Task", "New to-do item")
                                shortcutRow("/callout Text", "Callout block")
                                shortcutRow("/divider", "Horizontal divider")
                            }
                        }
                    }
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Block" : "New Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Add") { saveEntry() }
                        .disabled(isSaveDisabled || isSaving)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let entry = editingEntry {
                    title = entry.title ?? ""
                    content = entry.content
                    blockType = entry.blockType
                    headingLevel = entry.headingLevel ?? 1
                    if let json = entry.checklistItems {
                        loadChecklistItems(from: json)
                    }
                }
            }
            .onChange(of: content) { _, newValue in
                processShortcutCommand(newValue)
            }
            .scrollDismissesKeyboard(.immediately)
            .interactiveDismissDisabled(hasUnsavedContent && !isSaving)
            .alert("Remove Item?", isPresented: $showDeleteChecklistConfirm) {
                Button("Cancel", role: .cancel) { deleteChecklistOffsets = nil }
                Button("Remove", role: .destructive) {
                    if let offsets = deleteChecklistOffsets {
                        checklistItems.remove(atOffsets: offsets)
                    }
                    deleteChecklistOffsets = nil
                }
            } message: {
                Text("This checklist item will be removed.")
            }
        }
    }

    // MARK: - Type-Specific Field Groups

    private var commandPaletteSection: some View {
        Section("Command Palette") {
            if filteredSlashCommands.isEmpty {
                Text("No matching commands")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredSlashCommands) { command in
                    Button {
                        applySlashCommand(command)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: command.systemImage)
                                .frame(width: 28, height: 28)
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(command.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text("\(command.command) - \(command.subtitle)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(command.title), \(command.command)")
                }
            }
        }
    }

    private var textFields: some View {
        Group {
            Section("Title (Optional)") {
                TextField("Entry title", text: $title)
            }
            Section("Content") {
                TextEditor(text: $content)
                    .frame(minHeight: 100)
            }
        }
    }

    private var headingFields: some View {
        Group {
            Section("Heading") {
                TextField("Heading text", text: $title)
                Picker("Level", selection: $headingLevel) {
                    Text("H1 — Large").tag(1)
                    Text("H2 — Medium").tag(2)
                    Text("H3 — Small").tag(3)
                }
            }
        }
    }

    private var checklistFields: some View {
        Group {
            Section("Checklist Title (Optional)") {
                TextField("Checklist name", text: $title)
            }
            Section("Items") {
                ForEach($checklistItems) { $item in
                    HStack {
                        Button {
                            item.checked.toggle()
                        } label: {
                            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.checked ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.checked ? "Mark as unchecked" : "Mark as checked")
                        TextField("Item", text: $item.text)
                    }
                }
                .onDelete { indices in
                    deleteChecklistOffsets = indices
                    showDeleteChecklistConfirm = true
                }
                Button {
                    checklistItems.append(ChecklistItemInput(text: "", checked: false))
                } label: {
                    Label("Add Item", systemImage: "plus.circle")
                        .font(.caption)
                }
            }
        }
    }

    private var todoFields: some View {
        Section("To-Do") {
            TextField("Task description", text: $title)
        }
    }

    private var calloutFields: some View {
        Group {
            Section("Callout Title (Optional)") {
                TextField("Callout title", text: $title)
            }
            Section("Content") {
                TextEditor(text: $content)
                    .frame(minHeight: 60)
            }
        }
    }

    private var quoteFields: some View {
        Section("Quote") {
            TextEditor(text: $content)
                .frame(minHeight: 80)
        }
    }

    private var codeFields: some View {
        Section("Code") {
            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
        }
    }

    private var photoFields: some View {
        Group {
            Section("Photo Caption") {
                TextField("Photo caption", text: $title)
            }
            Section {
                Text("Photo capture and library selection will attach to this block in the next media pass.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private var partReferenceFields: some View {
        Section("Part Reference") {
            TextField("Part name, SKU, or note", text: $title)
        }
    }

    private var panelScheduleFields: some View {
        Section("Panel Schedule") {
            TextField("Panel name", text: $title)
            Text("Open the notebook panel builder after adding this block to edit breaker assignments.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var tableFields: some View {
        Group {
            Section("Table Title (Optional)") {
                TextField("Table title", text: $title)
            }
            Section("Table Notes") {
                TextEditor(text: $content)
                    .frame(minHeight: 80)
            }
        }
    }

    // MARK: - Shortcut Commands

    private func applySlashCommand(_ command: SlashCommand) {
        let trailingText = trailingTextAfterCommand(command.command)
        blockType = command.blockType
        if let level = command.headingLevel {
            headingLevel = level
        }

        switch command.blockType {
        case "heading", "todo", "photo", "part_reference", "panel_schedule":
            title = trailingText
            content = ""
        case "checklist":
            title = trailingText
            content = ""
            if checklistItems.isEmpty {
                checklistItems.append(ChecklistItemInput(text: "", checked: false))
            }
        case "divider":
            title = ""
            content = ""
        default:
            content = trailingText
        }
    }

    private func trailingTextAfterCommand(_ command: String) -> String {
        let raw = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.lowercased().hasPrefix(command.lowercased()) else { return "" }
        return String(raw.dropFirst(command.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func processShortcutCommand(_ text: String) {
        guard !isEditing else { return }
        if text.hasPrefix("/h1 ") {
            blockType = "heading"
            headingLevel = 1
            title = String(text.dropFirst(4))
            content = ""
        } else if text.hasPrefix("/h2 ") {
            blockType = "heading"
            headingLevel = 2
            title = String(text.dropFirst(4))
            content = ""
        } else if text.hasPrefix("/h3 ") {
            blockType = "heading"
            headingLevel = 3
            title = String(text.dropFirst(4))
            content = ""
        } else if text == "/checklist" {
            blockType = "checklist"
            content = ""
            if checklistItems.isEmpty {
                checklistItems.append(ChecklistItemInput(text: "", checked: false))
            }
        } else if text.hasPrefix("/todo ") {
            blockType = "todo"
            title = String(text.dropFirst(6))
            content = ""
        } else if text.hasPrefix("/callout ") {
            blockType = "callout"
            content = String(text.dropFirst(9))
        } else if text == "/divider" {
            blockType = "divider"
            content = ""
        } else if text.hasPrefix("/quote ") {
            blockType = "quote"
            content = String(text.dropFirst(7))
        } else if text.hasPrefix("/code ") {
            blockType = "code"
            content = String(text.dropFirst(6))
        } else if text.hasPrefix("/table ") {
            blockType = "table"
            content = String(text.dropFirst(7))
        } else if text.hasPrefix("/photo ") {
            blockType = "photo"
            title = String(text.dropFirst(7))
            content = ""
        } else if text.hasPrefix("/part ") {
            blockType = "part_reference"
            title = String(text.dropFirst(6))
            content = ""
        } else if text.hasPrefix("/panel ") {
            blockType = "panel_schedule"
            title = String(text.dropFirst(7))
            content = ""
        }
    }

    private func shortcutRow(_ command: String, _ description: String) -> some View {
        HStack {
            Text(command)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.blue)
            Spacer()
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Validation

    private var isSaveDisabled: Bool {
        switch blockType {
        case "heading": return title.trimmingCharacters(in: .whitespaces).isEmpty
        case "todo": return title.trimmingCharacters(in: .whitespaces).isEmpty
        case "photo": return title.trimmingCharacters(in: .whitespaces).isEmpty
        case "part_reference": return title.trimmingCharacters(in: .whitespaces).isEmpty
        case "panel_schedule": return title.trimmingCharacters(in: .whitespaces).isEmpty
        case "divider": return false
        case "checklist": return checklistItems.filter({ !$0.text.isEmpty }).isEmpty
        default: return title.trimmingCharacters(in: .whitespaces).isEmpty && content.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    // MARK: - Save

    private func saveEntry() {
        guard let service = appCore.notebooksService,
              let userId = appCore.currentUser?.id else {
            saveError = "Service or user unavailable"
            return
        }
        isSaving = true
        saveError = nil

        do {
            if let entry = editingEntry {
                // Update existing entry
                let blockData = blockType == "checklist" ? encodeChecklistItems() : nil
                try service.updateBlockEntry(
                    entryId: entry.id,
                    content: content.isEmpty ? nil : content,
                    blockData: blockData,
                    headingLevel: blockType == "heading" ? headingLevel : nil,
                    checklistItems: blockType == "checklist" ? blockData : nil
                )
            } else {
                // Create new entry
                guard let sid = sectionId else {
                    saveError = "No section specified"
                    isSaving = false
                    return
                }
                let blockData = blockType == "checklist" ? encodeChecklistItems() : nil
                _ = try service.createBlockEntry(
                    sectionId: sid,
                    blockType: blockType,
                    title: title.isEmpty ? nil : title,
                    content: content.isEmpty ? nil : content,
                    blockData: blockData,
                    headingLevel: blockType == "heading" ? headingLevel : nil,
                    checklistItems: blockType == "checklist" ? blockData : nil,
                    createdBy: userId
                )
            }
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save notebook")
        }
        isSaving = false
    }

    // MARK: - Checklist Encoding/Decoding

    private func encodeChecklistItems() -> String? {
        let items = checklistItems.filter { !$0.text.isEmpty }.map {
            ["text": $0.text, "checked": $0.checked ? "true" : "false"]
        }
        guard !items.isEmpty, let data = try? JSONSerialization.data(withJSONObject: items) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func loadChecklistItems(from json: String) {
        guard let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([[String: String]].self, from: data) else { return }
        checklistItems = array.map {
            ChecklistItemInput(
                text: $0["text"] ?? "",
                checked: $0["checked"] == "true"
            )
        }
    }
}
