import SwiftUI

// MARK: - Environment key for sheet-level dismiss

/// Custom environment key that carries a sheet-level dismiss action.
///
/// SwiftUI's `@Environment(\.dismiss)` inside a `NavigationStack` can bind to the
/// nav stack instead of the enclosing sheet — especially on macOS/iPad. This key
/// captures dismiss at the SHEET level (outside the NavigationStack) so child views
/// can reliably dismiss the sheet.
private struct SheetDismissKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var sheetDismiss: (() -> Void)? {
        get { self[SheetDismissKey.self] }
        set { self[SheetDismissKey.self] = newValue }
    }
}

/// Wraps sheet content in a NavigationStack with a reliable "Done" dismiss button.
///
/// Captures `@Environment(\.dismiss)` OUTSIDE the NavigationStack and:
/// 1. Adds a "Done" toolbar button that uses the outer dismiss
/// 2. Injects `.environment(\.sheetDismiss)` so children can also dismiss the sheet
///
/// Usage:
/// ```swift
/// .sheet(item: $activeSheet) { item in
///     SheetDismissWrapper(title: "My Sheet") {
///         MyContentView()
///     }
/// }
/// ```
struct SheetDismissWrapper<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let content: Content
    var showDoneButton: Bool

    init(title: String, showDoneButton: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.showDoneButton = showDoneButton
        self.content = content()
    }

    var body: some View {
        let dismissAction = { dismiss() }
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showDoneButton {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismissAction() }
                        }
                    }
                }
                .environment(\.sheetDismiss, dismissAction)
        }
        .presentationDragIndicator(.visible)
    }
}
