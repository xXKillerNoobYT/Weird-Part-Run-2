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
                            Text("To-Do").tag("todo")
                            Text("Callout").tag("callout")
                            Text("Divider").tag("divider")
                        }
                        .pickerStyle(.menu)
                    }
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

    // MARK: - Shortcut Commands

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
                    title: title,
                    content: content.isEmpty ? nil : content,
                    blockData: blockType == "checklist" ? nil : blockData,
                    headingLevel: blockType == "heading" ? headingLevel : nil,
                    checklistItems: blockType == "checklist" ? blockData : nil,
                    updatedBy: userId
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
