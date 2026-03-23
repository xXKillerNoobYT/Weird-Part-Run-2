import SwiftUI

/// Generic form sheet wrapper with save/cancel toolbar buttons.
///
/// Provides consistent sheet presentation for create/edit forms.
///
/// Usage:
///   .sheet(isPresented: $showCreate) {
///       FormSheet(title: "New Part", isSaving: $isSaving, isValid: isValid) {
///           savePart()
///       } content: {
///           TextField("Name", text: $name)
///       }
///   }
struct FormSheet<Content: View>: View {
    let title: String
    @Binding var isSaving: Bool
    var isValid: Bool = true
    var saveLabel: String = "Save"
    var onSave: () -> Void
    var onCancel: (() -> Void)?
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                content
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let onCancel {
                            onCancel()
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) {
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }
}
