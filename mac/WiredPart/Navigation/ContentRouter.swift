import SwiftUI

/// Routes a navigation path string to the corresponding SwiftUI view.
///
/// - `/dashboard` routes to the native DashboardView
/// - `/parts/*` routes to the appropriate parts page via PartsRouter
/// - `/settings/*` routes to the appropriate settings page via SettingsRouter
/// - All other paths fall back to a placeholder or WebFallbackView
struct ContentRouter: View {
    @EnvironmentObject private var appCore: AppCore
    let path: String

    var body: some View {
        routedView
    }

    @ViewBuilder
    private var routedView: some View {
        if path == "/dashboard" {
            DashboardView()
        } else if path.hasPrefix("/parts") {
            PartsRouter(path: path)
        } else if path.hasPrefix("/warehouse") {
            WarehouseRouter(path: path)
        } else if path.hasPrefix("/jobs") {
            JobsRouter(path: path)
        } else if path.hasPrefix("/settings") {
            SettingsRouter(path: path)
        } else {
            PlaceholderView(path: path)
        }
    }
}

// MARK: - Placeholder

/// Shown for modules/tabs that don't have a native SwiftUI implementation yet.
/// Displays the path and a message indicating future native implementation.
struct PlaceholderView: View {
    let path: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Coming Soon")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Native view for \(path) is under development.")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("This feature is available in the web interface.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
