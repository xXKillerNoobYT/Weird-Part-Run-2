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
        .onAppear {
            NotificationCenter.default.post(
                name: .unifiedOrderPageActive,
                object: nil,
                userInfo: [
                    "context": "Retired Unified Order page is open. This page is read-only and replaced by Job Orders -> Create JPO for new parts requests. Explain the replacement path without creating orders."
                ]
            )
        }
        .onDisappear {
            NotificationCenter.default.post(name: .unifiedOrderPageInactive, object: nil)
        }
    }
}
