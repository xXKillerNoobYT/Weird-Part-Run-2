import SwiftUI
import WiredPartCore

/// Overlay shown to non-admin users on their first login.
/// Provides quick tips about the app's core features.
struct NewUserWelcomeView: View {
    @EnvironmentObject private var appCore: AppCore
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some View {
        if !hasSeenWelcome && !shouldSuppressForUITestFixture {
            welcomeOverlay
        }
    }

    private var shouldSuppressForUITestFixture: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITesting") &&
            (args.contains("-UITestingWarehouseLocations") ||
             args.contains("-UITestingWEI936AutoLogin"))
    }

    private var welcomeOverlay: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.wave.fill")
                .decorativeIconFont(64)
                .foregroundStyle(.blue)

            Text("Welcome to WiredPart!")
                .font(.title)
                .fontWeight(.bold)

            if let user = appCore.currentUser {
                Text("Hi \(user.displayName), you're all set up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                tipRow(icon: "clock.fill", color: .green,
                       title: "Clock In",
                       detail: "Start each day by clocking in from the Dashboard.")

                tipRow(icon: "doc.text.fill", color: .blue,
                       title: "Parts Orders",
                       detail: "Need parts on a job? Create a Job Parts Order (JPO).")

                tipRow(icon: "questionmark.circle.fill", color: .orange,
                       title: "Need Help?",
                       detail: "Tap the ? button on any page for guidance. Tap the AI button (bottom right) to ask questions.")

                tipRow(icon: "qrcode.viewfinder", color: .purple,
                       title: "QR Scanning",
                       detail: "Scan QR codes to quickly find parts, tools, and POs.")
            }
            .padding(.horizontal, 24)

            Button {
                withAnimation {
                    hasSeenWelcome = true
                    // Auto-start the guided onboarding tour for new users
                    if let manager = appCore.onboardingManager {
                        manager.isOnboardingActive = true
                    }
                }
            } label: {
                Text("Got It — Let's Go!")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func tipRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
