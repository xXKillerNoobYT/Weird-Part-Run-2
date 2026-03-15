import SwiftUI

/// Cryptographic key management page.
///
/// Placeholder — shows informational cards about company keys,
/// certificates, and the key audit log. The full key management
/// system uses Ed25519 via CryptoKit in the core package.
struct KeyManagementPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Key Management")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                GroupBox("Company Keys") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text("Ed25519 Signing Keys")
                                    .font(.headline)
                                Text("Used to sign sync messages and verify data integrity")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Key generation and management will be available when the security subsystem is fully configured.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Device Certificates") {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("Device certificates verify that each device in the network is authorized to participate in sync.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                GroupBox("Key Audit Log") {
                    Text("All key operations (creation, rotation, revocation) are logged here for security auditing.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }

                infoCard(
                    "About Key Management",
                    text: "WiredPart uses Ed25519 digital signatures to ensure data authenticity during sync. Each device has its own signing key, and the company has a root key that signs device certificates."
                )
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
