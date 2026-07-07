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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum OnboardingPath {
        case createNew
        case joinExisting
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 28 : 0) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Spacer(minLength: 24)
                        }

                        // Logo & Branding
                        VStack(spacing: 12) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .decorativeIconFont(dynamicTypeSize.isAccessibilitySize ? 56 : 72)
                                .foregroundStyle(Color.accentColor)
                                .symbolRenderingMode(.hierarchical)
                                .accessibilityHidden(true)

                            Text("WiredPart")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                            Text("The all-in-one platform for your trade business")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 24 : 40)
                        }
                        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 24 : 0)

                        if !dynamicTypeSize.isAccessibilitySize {
                            Spacer(minLength: 24)
                        }

                        // Path Selection
                        VStack(spacing: 16) {
                            Text("Get Started")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                            NavigationLink(value: OnboardingPath.createNew) {
                                onboardingPathRow(
                                    icon: "building.2.fill",
                                    title: "Create New Business",
                                    subtitle: "Set up a new company from scratch"
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink(value: OnboardingPath.joinExisting) {
                                onboardingPathRow(
                                    icon: "link.circle.fill",
                                    title: "Join Existing Business",
                                    subtitle: "Connect to a shop computer on your network"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 16 : 24)

                        if !dynamicTypeSize.isAccessibilitySize {
                            Spacer(minLength: 24)
                        }

                        Text("Your data stays on your devices. No cloud account required.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 24 : 32)
                            .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 32 : 24)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationDestination(for: OnboardingPath.self) { path in
                // Prime system permissions first on both paths. On the join path
                // this is essential: the Local Network prompt must be answered
                // before DevicePairingView starts Bonjour discovery, or the first
                // scan silently finds nothing.
                switch path {
                case .createNew:
                    PermissionsPrimingView {
                        BusinessProfileSetupView()
                            .environmentObject(appCore)
                    }
                    .environmentObject(appCore)
                case .joinExisting:
                    PermissionsPrimingView {
                        DevicePairingView()
                            .environmentObject(appCore)
                    }
                    .environmentObject(appCore)
                }
            }
        }
    }

    private func onboardingPathRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.15))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .dsCard()
    }
}

#Preview {
    OnboardingWelcomeView()
        .environmentObject(AppCore())
}
