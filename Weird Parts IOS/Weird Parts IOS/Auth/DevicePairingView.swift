import SwiftUI
import WiredPartCore

/// Device pairing screen for the "Join Existing Business" path.
///
/// The user either scans a QR code displayed on the shop computer
/// or manually enters a pairing code. Once paired, the device begins
/// an initial sync to download the company database.
struct DevicePairingView: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var pairingCode = ""
    @State private var errorMessage: String?
    @State private var isConnecting = false
    @State private var navigateToSync = false

    private var isValid: Bool {
        pairingCode.trimmingCharacters(in: .whitespaces).count >= 4
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                Text("Join a Business")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Connect to a shop computer on your local network to sync the company database.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // QR Scan Option
            VStack(spacing: 12) {
                Button {
                    // QR scanning will be implemented in Phase 16 (Sync Infrastructure)
                    errorMessage = "QR scanning will be available once sync is configured."
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title3)
                        Text("Scan QR Code")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: 300)
                }
                .buttonStyle(.bordered)

                // Divider
                HStack {
                    Rectangle()
                        .fill(.tertiary)
                        .frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Rectangle()
                        .fill(.tertiary)
                        .frame(height: 1)
                }
                .padding(.horizontal, 60)
            }

            // Manual Code Entry
            VStack(spacing: 12) {
                Text("Enter Pairing Code")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                TextField("e.g. ABCD-1234", text: $pairingCode)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .frame(maxWidth: 240)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    attemptPairing()
                } label: {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Connect")
                            .fontWeight(.semibold)
                            .frame(maxWidth: 300)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isConnecting)
            }

            Spacer()

            Text("Make sure both devices are on the same Wi-Fi network.")
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
        .navigationTitle("Pair Device")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(isPresented: $navigateToSync) {
            SyncWaitingView()
                .environmentObject(appCore)
        }
    }

    // MARK: - Actions

    private func attemptPairing() {
        isConnecting = true
        errorMessage = nil

        // Pairing logic will be fully implemented in Phase 16 (Sync Infrastructure).
        // For now, show a placeholder message.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isConnecting = false
            errorMessage = "Sync infrastructure is not yet configured. Please use \"Create New Business\" for now, or check back after sync is set up."
        }
    }
}

#Preview {
    NavigationStack {
        DevicePairingView()
            .environmentObject(AppCore())
    }
}
