import SwiftUI

/// Shared dismiss-safety helpers for form/action sheets.
///
/// Sheets with unsaved user input should use this modifier so swipe-down
/// dismissal is disabled while there is dirty input or an in-flight save. Pair
/// explicit Cancel buttons with `DismissSafety.cancelOrConfirm` so taps either
/// dismiss clean sheets immediately or ask before discarding user work.
struct DismissSafety {
    static func cancelOrConfirm(isDirty: Bool, isSaving: Bool, dismiss: DismissAction, showDiscardConfirmation: Binding<Bool>) {
        guard !isSaving else { return }
        if isDirty {
            showDiscardConfirmation.wrappedValue = true
        } else {
            dismiss()
        }
    }
}

struct DismissSafetyModifier: ViewModifier {
    let isDirty: Bool
    let isSaving: Bool
    let title: String
    let message: String
    let onDiscard: () -> Void

    @Binding var showDiscardConfirmation: Bool

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(isDirty || isSaving)
            .confirmationDialog(
                title,
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    onDiscard()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}

extension View {
    func dismissSafety(
        isDirty: Bool,
        isSaving: Bool = false,
        showDiscardConfirmation: Binding<Bool>,
        title: String = "Discard Changes?",
        message: String = "You have unsaved changes. Discard them and close this sheet?",
        onDiscard: @escaping () -> Void
    ) -> some View {
        modifier(DismissSafetyModifier(
            isDirty: isDirty,
            isSaving: isSaving,
            title: title,
            message: message,
            onDiscard: onDiscard,
            showDiscardConfirmation: showDiscardConfirmation
        ))
    }
}
