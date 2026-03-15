import SwiftUI
import WiredPartCore

/// Cryptographic key management page.
///
/// Shows the device's Ed25519 signing key status and allows
/// regenerating or exporting the public key. The actual key
/// management is handled by the core package's SyncCrypto module.
struct KeyManagementPage: View {
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        Form {
            Section("Device Signing Key") {
                LabeledContent("Algorithm", value: "Ed25519")
                LabeledContent("Status", value: "Active")
                LabeledContent("Created", value: "On first launch")
            }

            Section("Key Operations") {
                Button {
                    // Placeholder: export public key
                } label: {
                    Label("Export Public Key", systemImage: "square.and.arrow.up")
                }

                Button {
                    // Placeholder: view key fingerprint
                } label: {
                    Label("View Key Fingerprint", systemImage: "textformat.abc.dottedunderline")
                }
            }

            Section("Trusted Keys") {
                Text("No trusted peer keys imported yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Section("How It Works") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Each device has a unique Ed25519 signing key pair generated on first launch.")
                    Text("All sync messages are signed with the private key and verified by peers using the public key.")
                    Text("Keys are stored in the device keychain and never leave the device.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
