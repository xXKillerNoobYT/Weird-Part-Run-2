import SwiftUI
import WiredPartCore

/// Encryption key management page for iOS.
///
/// Shows the status of the device's Ed25519 signing key used for
/// sync verification, along with key creation and rotation dates.
/// Key rotation and advanced management are desktop-only operations.
struct IOSKeyManagementPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var activeSheet: ActiveSheet?
    @State private var keyFingerprint: String?
    @State private var keyCreatedAt: String?
    @State private var keyRotatedAt: String?
    @State private var keyAlgorithm = "Ed25519"
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        Form {
            keyStatusSection
            keyDetailsSection
            rotationSection
            infoSection

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle("Encryption Keys")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
                .accessibilityHint("Opens help for this page.")
                .accessibilityIdentifier("settings-key-management-help-button")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Encryption Keys Help", sections: [
                ("What This Page Does", "Displays the status and details of this device's Ed25519 signing key used for sync verification. Each device has a unique key pair for signing data."),
                ("How to Use It", "Review your key status and fingerprint here. Key rotation and advanced management must be performed from the desktop application. All paired devices re-verify after a rotation."),
            ])
        }
        .task { loadData() }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    // MARK: - Key Status

    private var keyStatusSection: some View {
        Section("Key Status") {
            HStack {
                Label(
                    keyFingerprint != nil ? "Active" : "Not Configured",
                    systemImage: keyFingerprint != nil ? "lock.shield.fill" : "lock.open.fill"
                )
                .foregroundStyle(keyFingerprint != nil ? .green : .orange)
                .font(.body.weight(.medium))
                Spacer()
            }

            if let fingerprint = keyFingerprint {
                LabeledContent("Fingerprint") {
                    Text(fingerprint)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    // MARK: - Key Details

    private var keyDetailsSection: some View {
        Section("Key Details") {
            LabeledContent("Algorithm", value: keyAlgorithm)
            LabeledContent("Created") {
                Text(keyCreatedAt ?? "Unknown")
                    .foregroundStyle(keyCreatedAt != nil ? .primary : .secondary)
            }
            LabeledContent("Last Rotated") {
                Text(keyRotatedAt ?? "Never")
                    .foregroundStyle(keyRotatedAt != nil ? .primary : .secondary)
            }
        }
    }

    // MARK: - Rotation Section

    private var rotationSection: some View {
        Section("Key Rotation") {
            VStack(alignment: .leading, spacing: 6) {
                Label("Key rotation must be performed from the desktop application", systemImage: "desktopcomputer")
                Label("All paired devices will re-verify after rotation", systemImage: "arrow.triangle.2.circlepath")
                Label("Rotate keys periodically for best security", systemImage: "shield.checkered")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            Text("Encryption keys are used to sign and verify all sync payloads between devices. Each device has a unique key pair. The public key is shared during device pairing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let settingsService = appCore.settingsService else {
            errorMessage = "Settings service not available."
            return
        }
        do {
            let keyInfo = try settingsService.getActiveDeviceKey()
            keyFingerprint = keyInfo.fingerprint
            keyCreatedAt = keyInfo.createdAt
            keyRotatedAt = keyInfo.rotatedAt
        } catch {
            errorMessage = userFriendlyError(error, context: "load key info")
        }
    }
}
