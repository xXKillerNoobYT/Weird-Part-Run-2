import SwiftUI
import AppKit
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

    init() {
        // Ensure the app appears in the Dock and can become the frontmost app.
        // Required for SPM-based executables which may lack a full app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(ThemeManager.colorScheme(for: appCore.theme.themeMode))
            .task {
                NSApplication.shared.activate()
                await appCore.initialize()
            }
        }
        .defaultSize(width: 1200, height: 800)
    }
}
