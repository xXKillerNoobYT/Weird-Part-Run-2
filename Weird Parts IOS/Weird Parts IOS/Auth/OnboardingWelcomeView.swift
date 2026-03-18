import SwiftUI
import WiredPartCore

/// Two-path onboarding welcome screen.
///
/// Presented on first launch when no business profile exists.
/// Users choose between:
/// - **Create New Business** → BusinessProfileSetupView
/// - **Join Existing Business** → DevicePairingView
struct OnboardingWelcomeView: View {
    @EnvironmentObject private var appCore: AppCore

    enum OnboardingPath {
        case createNew
        case joinExisting
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Logo & Branding
                VStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)

                    Text("WiredPart")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("The all-in-one platform for your trade business")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                // Path Selection
                VStack(spacing: 16) {
                    Text("Get Started")
                        .font(.title2)
                        .fontWeight(.semibold)

                    // Create New Business
                    NavigationLink(value: OnboardingPath.createNew) {
                        HStack(spacing: 16) {
                            Image(systemName: "building.2.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.accentColor.opacity(0.15))
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Create New Business")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Set up a new company from scratch")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .dsCard()
                    }
                    .buttonStyle(.plain)

                    // Join Existing Business
                    NavigationLink(value: OnboardingPath.joinExisting) {
                        HStack(spacing: 16) {
                            Image(systemName: "link.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.accentColor.opacity(0.15))
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Join Existing Business")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Connect to a shop computer on your network")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .dsCard()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Spacer()

                Text("Your data stays on your devices. No cloud account required.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(iOS)
            .background(Color(.systemBackground))
            #elseif os(macOS)
            .background(Color(.windowBackgroundColor))
            #endif
            .navigationDestination(for: OnboardingPath.self) { path in
                switch path {
                case .createNew:
                    BusinessProfileSetupView()
                        .environmentObject(appCore)
                case .joinExisting:
                    DevicePairingView()
                        .environmentObject(appCore)
                }
            }
        }
    }
}

#Preview {
    OnboardingWelcomeView()
        .environmentObject(AppCore())
}
