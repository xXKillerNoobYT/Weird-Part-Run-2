import SwiftUI
import WiredPartCore

/// Feature-flagged onboarding entry for local on-device AI.
struct OnboardAIMVPEntryView: View {
    @EnvironmentObject private var appCore: AppCore
    @AppStorage("hasSeenOnboardAIMVPEntry") private var hasSeenOnboardAIMVPEntry = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .decorativeIconFont(64)
                .foregroundStyle(.blue)

            Text("On-Device AI")
                .font(.title)
                .fontWeight(.bold)

            Text("WiredPart can run AI locally on this device. No cloud dependency on the main onboarding path.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            runtimeStatusCard
                .padding(.horizontal, 20)

            Button("Continue Onboarding") {
                hasSeenOnboardAIMVPEntry = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color(.systemBackground))
    }

    private var runtimeStatusCard: some View {
        let result = appCore.onboardAIRuntimeBootstrap
        return VStack(alignment: .leading, spacing: 8) {
            Text("Runtime Bootstrap")
                .font(.headline)

            switch result?.route {
            case .ready:
                statusRow("Ready", detail: "Local AI runtime is available for onboarding.", color: .green)
            case .modelUnavailable:
                statusRow("Fallback: Model unavailable", detail: "AI onboarding remains optional and the core onboarding flow continues safely.", color: .orange)
            case .timeout:
                statusRow("Fallback: Startup timeout", detail: "Runtime check timed out. AI onboarding is skipped for this session.", color: .orange)
            case .lowResource:
                statusRow("Fallback: Low resources", detail: "Device is in low-resource mode. AI onboarding is deferred.", color: .orange)
            case .none:
                statusRow("Checking", detail: "Evaluating local runtime availability.", color: .secondary)
            }
        }
        .padding(16)
        .dsCard()
    }

    private func statusRow(_ title: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
