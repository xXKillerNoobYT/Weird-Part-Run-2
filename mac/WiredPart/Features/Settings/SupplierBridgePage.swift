import SwiftUI

/// Supplier portal bridge / token management page.
///
/// Placeholder — will manage supplier portal access tokens,
/// API keys, and data exchange settings for each supplier.
struct SupplierBridgePage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Supplier Bridge")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Manage connections to supplier portals and ordering systems.")
                    .foregroundStyle(.secondary)

                GroupBox("Connected Suppliers") {
                    VStack(spacing: 12) {
                        Image(systemName: "link.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No supplier portals connected")
                            .foregroundStyle(.secondary)
                        Text("Add supplier API tokens to enable direct ordering and price updates.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                GroupBox("Add Supplier Connection") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("To connect a supplier portal, you will need:")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            bulletPoint("Supplier API key or access token")
                            bulletPoint("Portal URL or endpoint")
                            bulletPoint("Account credentials (if required)")
                        }

                        Button("Add Supplier") {}
                            .buttonStyle(.borderedProminent)
                            .disabled(true)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Token Management") {
                    Text("Active tokens will be listed here with their expiry dates and refresh status. Tokens are stored securely in the local keychain.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                infoCard(
                    "About Supplier Bridge",
                    text: "The Supplier Bridge connects WiredPart to supplier ordering systems, enabling direct purchase order submission, real-time pricing, and delivery tracking without manual portal access."
                )
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
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
