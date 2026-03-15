import SwiftUI

/// Third-party integrations management page.
///
/// Placeholder — will provide configuration for connecting
/// to external services (accounting, fleet GPS, supply chain, etc.).
struct IntegrationsPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Integrations")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Connect WiredPart with external services and tools.")
                    .foregroundStyle(.secondary)

                GroupBox("Available Integrations") {
                    VStack(alignment: .leading, spacing: 16) {
                        integrationRow(
                            icon: "building.columns",
                            title: "Accounting Software",
                            description: "QuickBooks, Xero, FreshBooks — sync invoices and expenses.",
                            status: "Coming Soon"
                        )
                        Divider()
                        integrationRow(
                            icon: "location.circle",
                            title: "Fleet GPS",
                            description: "Samsara, Verizon Connect — real-time vehicle tracking.",
                            status: "Coming Soon"
                        )
                        Divider()
                        integrationRow(
                            icon: "shippingbox",
                            title: "Supply Chain",
                            description: "Supplier EDI, catalog feeds, automated reordering.",
                            status: "Coming Soon"
                        )
                        Divider()
                        integrationRow(
                            icon: "calendar",
                            title: "Calendar",
                            description: "Apple Calendar, Google Calendar — schedule synchronization.",
                            status: "Coming Soon"
                        )
                    }
                    .padding(.vertical, 4)
                }

                infoCard(
                    "About Integrations",
                    text: "Third-party integrations will allow WiredPart to exchange data with external services. Each integration can be configured independently with its own credentials and sync settings."
                )
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func integrationRow(icon: String, title: String, description: String, status: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(status)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.secondary.opacity(0.15)))
                .foregroundStyle(.secondary)
        }
    }

    private func infoCard(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "info.circle")
                .font(.headline)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.05)))
    }
}
