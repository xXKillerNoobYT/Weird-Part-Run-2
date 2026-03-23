import SwiftUI

/// Deprecated — replaced by the JPO creation flow.
///
/// Use Job Orders → Create JPO instead.
struct IOSUnifiedOrderPage: View {
    var body: some View {
        ContentUnavailableView {
            Label("Page Replaced", systemImage: "arrow.right.circle")
        } description: {
            Text("This page has been replaced. Use Job Orders → Create JPO.")
        }
    }
}
