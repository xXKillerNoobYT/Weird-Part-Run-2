import SwiftUI
import WiredPartCore

/// Device pairing screen for the "Join Existing Business" path.
///
/// Discovers nearby shop computers via Bluetooth/LAN or allows manual address
/// entry. Once a shop is found, the user enters a pairing code to authenticate,
/// then an initial full sync downloads the company database.
struct DevicePairingView: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var pairingCode = ""
    @State private var manualAddress = ""
    @State private var errorMessage: String?
    @State private var isConnecting = false
    @State private var navigateToSync = false
    @State private var discoveredShop: DiscoveredShop?

    private var syncManager: IOSSyncManager { appCore.syncManager }

    struct DiscoveredShop: Identifiable {
        let id: String
        let name: String
        let address: String
    }

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

            // Discovery status
            if let shop = discoveredShop {
                shopFoundSection(shop)
            } else {
                discoverSection
            }

            // Pairing code entry
            pairingSection

            Spacer()

            Text("Make sure both devices are on the same Wi-Fi network.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("Pair Device")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToSync) {
            SyncWaitingView()
                .environmentObject(appCore)
        }
        .task {
            await scanForShop()
        }
    }

    // MARK: - Discovery

    @ViewBuilder
    private var discoverSection: some View {
        VStack(spacing: 8) {
            if syncManager.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning for shop computer...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if syncManager.discoveredPeers.isEmpty {
                Text("No shop computer found nearby.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    syncManager.setBluetoothEnabled(true)
                    syncManager.startPeerDiscovery()
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Show discovered peers as potential shops
            ForEach(syncManager.discoveredPeers) { peer in
                Button {
                    discoveredShop = DiscoveredShop(id: peer.id, name: peer.name, address: peer.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.green)
                        Text(peer.name)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }
        }

        // Manual entry
        VStack(spacing: 8) {
            HStack {
                Rectangle().fill(.tertiary).frame(height: 1)
                Text("or enter manually").font(.caption).foregroundStyle(.tertiary)
                Rectangle().fill(.tertiary).frame(height: 1)
            }
            .padding(.horizontal, 60)

            HStack(spacing: 8) {
                TextField("192.168.1.100:8080", text: $manualAddress)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Connect") {
                    guard !manualAddress.isEmpty else { return }
                    discoveredShop = DiscoveredShop(
                        id: manualAddress,
                        name: manualAddress,
                        address: manualAddress
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manualAddress.isEmpty)
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Shop Found

    private func shopFoundSection(_ shop: DiscoveredShop) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("Shop Computer Found")
                .font(.headline)

            Text(shop.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Choose Different") {
                discoveredShop = nil
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pairing

    @ViewBuilder
    private var pairingSection: some View {
        VStack(spacing: 12) {
            Text("Enter Pairing Code")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            TextField("e.g. ABCD-1234", text: $pairingCode)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .font(.title3.monospaced())
                .frame(maxWidth: 240)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                Task { await attemptPairing() }
            } label: {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Pair This Device")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 300)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid || isConnecting || discoveredShop == nil)
        }
    }

    // MARK: - Actions

    private func scanForShop() async {
        // Enable BT and start peer discovery
        syncManager.setBluetoothEnabled(true)
        syncManager.startPeerDiscovery()
    }

    private func attemptPairing() async {
        guard let shop = discoveredShop else {
            errorMessage = "Select a shop computer first."
            return
        }
        isConnecting = true
        errorMessage = nil

        do {
            // Pair with the shop — stores address and keys
            try await syncManager.pairWithShop(
                shopAddress: shop.address,
                pairingCode: pairingCode.trimmingCharacters(in: .whitespaces)
            )

            // Save pairing state
            if let service = appCore.settingsService {
                try? service.upsertSettingsMap([
                    "shop_server_address": shop.address,
                    "auto_sync": "true",
                    "sync_interval": "60",
                ], category: "sync")
            }
            UserDefaults.standard.set(true, forKey: "bluetooth_sync_enabled")
            UserDefaults.standard.set(true, forKey: "device_paired")

            // Navigate to the sync waiting screen for initial download
            navigateToSync = true
        } catch {
            errorMessage = userFriendlyError(error, context: "pair device")
        }
        isConnecting = false
    }
}
