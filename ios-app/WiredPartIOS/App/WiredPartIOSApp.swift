import SwiftUI
import WiredPartCore

/// Main entry point for the WiredPart iOS application.
///
/// Initializes the shared AppCore (database + services) before
/// presenting any UI. On first launch the database is created
/// in the app's Documents directory; subsequent launches reopen it.
@main
struct WiredPartIOSApp: App {
    @StateObject private var appCore = AppCore()

    var body: some Scene {
        WindowGroup {
            Group {
                if appCore.isReady {
                    if appCore.needsBootstrap {
                        BootstrapView()
                            .environmentObject(appCore)
                    } else if appCore.currentUser == nil {
                        LoginView()
                            .environmentObject(appCore)
                    } else {
                        IOSMainView()
                            .environmentObject(appCore)
                    }
                } else if let error = appCore.loadError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text("Failed to load database")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    LoadingView()
                }
            }
        }
    }
}
