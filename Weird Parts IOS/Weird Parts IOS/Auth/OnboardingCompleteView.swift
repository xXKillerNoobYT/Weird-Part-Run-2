import SwiftUI
import WiredPartCore

/// Success screen shown after completing the "Create New Business" onboarding.
///
/// Displays a confirmation and a button to enter the main app.
/// When tapped, sets `appCore.needsOnboarding = false` which triggers
/// the app root to show IOSMainView.
struct OnboardingCompleteView: View {
    @EnvironmentObject private var appCore: AppCore
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var showCheckmark = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated checkmark
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .scaleEffect(showCheckmark ? 1.0 : 0.5)
                    .opacity(showCheckmark ? 1.0 : 0.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showCheckmark)

                Text("You're All Set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if let user = appCore.currentUser {
                    Text("Welcome, \(user.displayName)")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            // Summary
            VStack(spacing: 12) {
                SummaryRow(icon: "building.2.fill", text: "Business profile created")
                SummaryRow(icon: "person.badge.key.fill", text: "Admin account ready")
                SummaryRow(icon: "internaldrive.fill", text: "Local database initialized")
            }
            .padding(.horizontal, 32)

            Spacer()

            // Enter App
            Button {
                hasSeenWelcome = true  // Admin already onboarded — skip the new-user welcome
                hasCompletedOnboarding = true  // Skip the guided walkthrough too — admin just set up the company
                appCore.completeOnboarding()
            } label: {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 300)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
        .onAppear {
            showCheckmark = true
        }
    }
}

// MARK: - Summary Row

private struct SummaryRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Text(text)
                .font(.body)
            Spacer()
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        OnboardingCompleteView()
            .environmentObject(AppCore())
    }
}
