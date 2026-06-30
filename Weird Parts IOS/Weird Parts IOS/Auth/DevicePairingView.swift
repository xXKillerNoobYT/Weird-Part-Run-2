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
        SyncCrypto.normalizedPairingCode(pairingCode) != nil
    }

    private var normalizedManualAddress: String? {
        IOSSyncManager.normalizedShopServerAddress(manualAddress)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .decorativeIconFont(56)
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
                    syncManager.setBluetoothEnabled(true, startDiscovery: false)
                    syncManager.startOnboardingPeerDiscovery()
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
                    guard let address = IOSSyncManager.normalizedShopServerAddress(peer.address) else {
                        errorMessage = "This device was found over Bluetooth only. Keep both devices on the same Wi-Fi network or enter the shop address manually."
                        return
                    }
                    errorMessage = nil
                    syncManager.stopPeerDiscovery()
                    discoveredShop = DiscoveredShop(id: peer.id, name: peer.name, address: address)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.green)
                        Text(peer.name)
                            .fontWeight(.medium)
                        if peer.address == nil {
                            Text("Needs Wi-Fi address")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                    guard let address = normalizedManualAddress else { return }
                    discoveredShop = DiscoveredShop(
                        id: address,
                        name: address,
                        address: address
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(normalizedManualAddress == nil)
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Shop Found

    private func shopFoundSection(_ shop: DiscoveredShop) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
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
        // Enable BT and start first-run join discovery. A brand-new device does
        // not have a local company ID yet; the pairing response verifies the
        // selected shop before storing company settings.
        syncManager.setBluetoothEnabled(true, startDiscovery: false)
        syncManager.startOnboardingPeerDiscovery()
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

            // Navigate to the sync waiting screen for initial download
            navigateToSync = true
        } catch {
            errorMessage = userFriendlyError(error, context: "pair device")
        }
        isConnecting = false
    }
}
