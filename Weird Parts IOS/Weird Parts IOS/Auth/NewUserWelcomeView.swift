import SwiftUI
import WiredPartCore

/// Overlay shown to non-admin users on their first login.
/// Provides quick tips about the app's core features.
struct NewUserWelcomeView: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some View {
        if !hasSeenWelcome && !shouldSuppressForWarehouseLocationsUITest {
            welcomeOverlay
        }
    }

    private var shouldSuppressForWarehouseLocationsUITest: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UITesting") && args.contains("-UITestingWarehouseLocations")
    }

    private var welcomeOverlay: some View {
        ScrollView {
            VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 20 : 24) {
                Image(systemName: "hand.wave.fill")
                    .decorativeIconFont(dynamicTypeSize.isAccessibilitySize ? 44 : 64)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text("Welcome to WiredPart!")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let user = appCore.currentUser {
                    Text("Hi \(user.displayName), you're all set up.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 22 : 16) {
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
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 12 : 24)

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
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(dynamicTypeSize.isAccessibilitySize ? 24 : 32)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func tipRow(icon: String, color: Color, title: String, detail: String) -> some View {
        let alignment: VerticalAlignment = dynamicTypeSize.isAccessibilitySize ? .top : .center
        return HStack(alignment: alignment, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
