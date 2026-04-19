import SwiftUI
import WiredPartCore

/// A banner showing AI availability status for iOS.
///
/// Uses iOS-native styling with system background colors.
struct IOSAIAvailabilityBanner: View {
    @State private var availability: AIAvailability = .notSupported

    private let aiService = FoundationModelsService()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            availability = aiService.checkAvailability()
        }
    }

    private var statusIcon: String {
        switch availability {
        case .available: return "brain"
        case .appleIntelligenceNotEnabled: return "brain.fill"
        case .modelNotReady: return "arrow.down.circle"
        case .deviceNotEligible, .unavailable, .notSupported: return "brain"
        }
    }

    private var statusColor: Color {
        switch availability {
        case .available: return .green
        case .modelNotReady: return .orange
        case .appleIntelligenceNotEnabled: return .yellow
        case .deviceNotEligible, .unavailable, .notSupported: return .secondary
        }
    }

    private var statusTitle: String {
        switch availability {
        case .available: return "AI Available"
        case .appleIntelligenceNotEnabled: return "Apple Intelligence Disabled"
        case .modelNotReady: return "AI Model Downloading"
        case .deviceNotEligible: return "Device Not Eligible"
        case .unavailable: return "AI Unavailable"
        case .notSupported: return "AI Not Supported"
        }
    }

    private var statusDescription: String {
        switch availability {
        case .available:
            return "On-device AI is ready for text completion and enhancement."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to enable AI features."
        case .modelNotReady:
            return "The AI model is downloading. Features will be available once complete."
        case .deviceNotEligible:
            return "This device does not support Apple Intelligence."
        case .unavailable:
            return "AI features are currently unavailable."
        case .notSupported:
            return "AI features require iOS 26 or later."
        }
    }
}
