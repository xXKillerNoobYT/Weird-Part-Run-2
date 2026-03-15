import SwiftUI
import WiredPartCore

/// Third-party integrations settings page.
///
/// Lists available integrations and their connection status.
/// Currently an informational placeholder describing planned
/// integration capabilities.
struct IntegrationsPage: View {
    @EnvironmentObject private var appCore: AppCore

    private let integrations: [(name: String, icon: String, description: String, status: String)] = [
        ("LM Studio", "brain", "Local LLM for natural language queries and anomaly detection", "Planned"),
        ("QuickBooks", "dollarsign.circle", "Accounting sync for invoices and expenses", "Planned"),
        ("Google Calendar", "calendar", "Calendar sync for scheduling", "Planned"),
        ("Slack", "bubble.left.and.bubble.right", "Notifications and alerts delivery", "Planned"),
        ("Apple Maps", "map", "Job location and routing", "Available"),
    ]

    var body: some View {
        Form {
            Section("Available Integrations") {
                ForEach(integrations, id: \.name) { integration in
                    HStack(spacing: 12) {
                        Image(systemName: integration.icon)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(integration.name)
                                .font(.body)
                                .fontWeight(.medium)
                            Text(integration.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(integration.status)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(integration.status == "Available" ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                            )
                            .foregroundStyle(integration.status == "Available" ? .green : .secondary)
                    }
                }
            }

            Section {
                Text("Integrations connect WiredPart with external services. Each integration can be configured independently and requires appropriate credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
