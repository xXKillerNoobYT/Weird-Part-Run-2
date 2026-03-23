import SwiftUI
import WiredPartCore

/// Sheet for adding a new entry or task to a notebook.
struct AddNotebookEntrySheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let notebookId: Int64
    let entryType: String
    var onSave: () -> Void

    @State private var title = ""
    @State private var content = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private var isTask: Bool { entryType == "task" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField(isTask ? "Task description" : "Entry title", text: $title)
                }

                Section("Content (Optional)") {
                    TextEditor(text: $content)
                        .frame(minHeight: 80)
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isTask ? "New Task" : "New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { saveEntry() }
                        .disabled(title.isEmpty || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func saveEntry() {
        guard let service = appCore.notebooksService,
              let userId = appCore.currentUser?.id else { return }
        isSaving = true
        saveError = nil
        do {
            _ = try service.addNotebookEntry(
                notebookId: notebookId,
                title: title,
                content: content.isEmpty ? nil : content,
                entryType: entryType,
                createdBy: userId
            )
            onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
