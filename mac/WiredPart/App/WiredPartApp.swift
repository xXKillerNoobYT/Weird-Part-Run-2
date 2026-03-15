import SwiftUI
import WiredPartCore

/// Main entry point for the WiredPart macOS application.
///
/// Determines which root view to show based on the application state:
/// - Loading spinner while the database initializes
/// - Bootstrap view for first-run setup
/// - Login view for PIN authentication
/// - Main view (sidebar + content) once authenticated
@main
struct WiredPartApp: App {
    @StateObject private var appCore = AppCore()

    var body: some Scene {
        WindowGroup {
            Group {
                if appCore.isLoading {
                    LoadingView()
                } else if appCore.needsBootstrap {
                    BootstrapView()
                        .environmentObject(appCore)
                } else if appCore.currentUser == nil {
                    LoginView()
                        .environmentObject(appCore)
                } else {
                    MainView()
                        .environmentObject(appCore)
                }
            }
            .preferredColorScheme(ThemeManager.colorScheme(for: appCore.theme.themeMode))
            .task {
                await appCore.initialize()
            }
        }
        .defaultSize(width: 1200, height: 800)
    }
}
