import SwiftUI

/// Reusable confirmation dialog for destructive or important actions.
///
/// Usage:
///   .confirmationSheet(
///       isPresented: $showDeleteConfirm,
///       title: "Delete Job?",
///       message: "This cannot be undone.",
///       confirmLabel: "Delete",
///       confirmRole: .destructive
///   ) {
///       deleteJob()
///   }
struct ConfirmationSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    var message: String?
    var confirmLabel: String = "Confirm"
    var confirmRole: ButtonRole? = nil
    var cancelLabel: String = "Cancel"
    var onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                Button(cancelLabel, role: .cancel) { }
                Button(confirmLabel, role: confirmRole, action: onConfirm)
            } message: {
                if let message {
                    Text(message)
                }
            }
    }
}

extension View {
    /// Presents a confirmation alert with confirm and cancel actions.
    func confirmationSheet(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        confirmLabel: String = "Confirm",
        confirmRole: ButtonRole? = nil,
        cancelLabel: String = "Cancel",
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(ConfirmationSheetModifier(
            isPresented: isPresented,
            title: title,
            message: message,
            confirmLabel: confirmLabel,
            confirmRole: confirmRole,
            cancelLabel: cancelLabel,
            onConfirm: onConfirm
        ))
    }
}
