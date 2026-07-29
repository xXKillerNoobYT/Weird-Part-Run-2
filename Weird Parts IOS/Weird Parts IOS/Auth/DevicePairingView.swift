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
        let id: String        // peer device id (or manual address)
        let name: String
        let address: String   // Wi-Fi address, or "" for a Bluetooth-only peer
        let isBluetooth: Bool // true = pair over Bluetooth (no Wi-Fi needed)
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
        .onDisappear {
            stopOnboardingDiscoveryIfAbandoned()
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
                    errorMessage = nil
                    // Always pair a discovered peer over Bluetooth — it works with no
                    // Wi-Fi at all. Wi-Fi/LAN is then used automatically for sync
                    // speed once paired. Keep discovery/Multipeer running; the live
                    // session is required for the handshake.
                    discoveredShop = DiscoveredShop(id: peer.id, name: peer.name, address: peer.address ?? "", isBluetooth: true)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.green)
                        Text(peer.name)
                            .fontWeight(.medium)
                        Text(peer.address == nil ? "Bluetooth" : "Bluetooth · Wi-Fi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        address: address,
                        isBluetooth: false
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

            // #1338: tell the user where a code actually comes from so this
            // flow is no longer an unexplained dead end.
            Text("Get a code on the shop device: Settings → Device Management → Pair New Device.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            TextField("e.g. ABCD-1234", text: $pairingCode)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.title3.monospaced())
                .frame(maxWidth: 240)
                // Auto-format while typing AND on paste: uppercase, strip junk,
                // insert the dash after 4 chars (ABCD-1234). A pasted "abcd1234",
                // "ABCD-1234", or "abcd 1234" all normalize to the same valid code.
                .onChange(of: pairingCode) { _, newValue in
                    let formatted = formatPairingCodeInput(newValue)
                    if formatted != newValue { pairingCode = formatted }
                }

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
        guard !Task.isCancelled else { return }
        // Enable BT and start first-run join discovery. A brand-new device does
        // not have a local company ID yet; the pairing response verifies the
        // selected shop before storing company settings.
        syncManager.setBluetoothEnabled(true, startDiscovery: false)
        guard !Task.isCancelled else { return }
        syncManager.startOnboardingPeerDiscovery()
    }

    private func stopOnboardingDiscoveryIfAbandoned() {
        guard !navigateToSync else { return }
        syncManager.stopPeerDiscovery()
    }

    private func attemptPairing() async {
        guard let shop = discoveredShop else {
            errorMessage = "Select a shop computer first."
            return
        }
        isConnecting = true
        errorMessage = nil

        do {
            let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if shop.isBluetooth {
                do {
                    // Pair entirely over Bluetooth — no Wi-Fi address required.
                    try await syncManager.pairWithPeerOverBluetooth(
                        hostDeviceId: shop.id,
                        hostName: shop.name,
                        pairingCode: code
                    )
                } catch let e as MultipeerPairingError
                    where shouldFallBackToLAN(e) && !shop.address.isEmpty {
                    // Bluetooth couldn't complete but the peer also advertised a
                    // Wi-Fi/LAN address (e.g. its Bluetooth radio is off) — fall
                    // back to LAN pairing rather than dead-ending (Copilot review
                    // on PR #1422). Bluetooth stays the primary path; Wi-Fi is
                    // the speed/backup path.
                    try await syncManager.pairWithShop(
                        shopAddress: shop.address,
                        pairingCode: code
                    )
                }
            } else {
                // Pair with the shop over Wi-Fi/LAN — stores address and keys.
                try await syncManager.pairWithShop(
                    shopAddress: shop.address,
                    pairingCode: code
                )
            }

            // Navigate to the sync waiting screen for initial download
            navigateToSync = true
        } catch let e as MultipeerPairingError {
            errorMessage = bluetoothPairingErrorMessage(e)
        } catch {
            errorMessage = userFriendlyError(error, context: "pair device")
        }
        isConnecting = false
    }

    /// Whether a failed Bluetooth pairing attempt should retry over the peer's
    /// advertised Wi-Fi/LAN address. Connectivity-class failures (couldn't
    /// connect, link dropped, host silent, Multipeer not running) are worth a
    /// LAN retry. `.rejected` is NOT — the code itself was wrong or already
    /// used, and retrying the same code over LAN would just burn the attempt.
    private func shouldFallBackToLAN(_ error: MultipeerPairingError) -> Bool {
        switch error {
        case .connectionTimeout, .responseTimeout, .sendFailed, .notAvailable, .transportStopped:
            return true
        case .rejected, .requestAlreadyInProgress, .protocolUpgradeRequired, .responseVerificationFailed:
            return false
        }
    }

    private func bluetoothPairingErrorMessage(_ error: MultipeerPairingError) -> String {
        switch error {
        case .connectionTimeout:
            return "Couldn't connect over Bluetooth. Keep both devices close together with Bluetooth on, and make sure the other device's Add-a-Device screen is open."
        case .responseTimeout:
            return "The other device didn't respond. Make sure its Add-a-Device screen is still open with a valid code, then try again."
        case .rejected:
            return "That pairing code was wrong or already used. Get a fresh code on the other device and re-enter it."
        case .sendFailed:
            return "Lost the Bluetooth connection while pairing. Move the devices closer and try again."
        case .notAvailable:
            return "Bluetooth sync isn't running yet. Go back, wait a moment, then try again."
        case .requestAlreadyInProgress:
            return "This device is already pairing or syncing. Wait for that attempt to finish, then try again."
        case .transportStopped:
            return "Bluetooth sync stopped before pairing finished. Turn Bluetooth sync back on and try again."
        case .protocolUpgradeRequired:
            return "The other device uses an older sync protocol. Update both devices before pairing again."
        case .responseVerificationFailed:
            return "The Bluetooth pairing response could not be authenticated. Update both devices, restart pairing, and enter the new code."
        }
    }

    /// Normalize/format a pairing code as the user types or pastes: keep only
    /// letters/digits, uppercase, cap at 8, and insert a dash after 4 → "ABCD-1234".
    /// This makes both typing (auto-dash) and pasting (any format) produce a valid code.
    private func formatPairingCodeInput(_ raw: String) -> String {
        let allowed = raw.uppercased().filter { $0.isNumber || ($0.isLetter && $0.isASCII) }
        let capped = String(allowed.prefix(8))
        guard capped.count > 4 else { return capped }
        let idx = capped.index(capped.startIndex, offsetBy: 4)
        return String(capped[..<idx]) + "-" + String(capped[idx...])
    }
}
