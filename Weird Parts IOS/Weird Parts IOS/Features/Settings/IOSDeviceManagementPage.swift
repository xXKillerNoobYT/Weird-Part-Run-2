import SwiftUI
import WiredPartCore

/// Device management page showing this device's identity and the host-side
/// pairing entry point.
///
/// "Pair New Device" issues a one-time pairing code from this device's sync
/// server (#1338). The field device enters that code on the
/// "Join Existing Business" screen (`DevicePairingView`) to pair and download
/// the company database.
struct IOSDeviceManagementPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var activeSheet: ActiveSheet?
    @State private var isIssuingCode = false
    @State private var pairingError: String?

    var body: some View {
        List {
            Section("This Device") {
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UIDevice.current.name)
                            .fontWeight(.medium)
                        Text("iOS \(UIDevice.current.systemVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(.green).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                }
                .rowAccessibility(
                    label: "\(UIDevice.current.name), this device",
                    value: "iOS \(UIDevice.current.systemVersion), active",
                    id: "settings-device-mgmt-this-device-row"
                )
            }

            Section("Paired Devices") {
                EmptyStateView(
                    icon: "desktopcomputer",
                    title: "No Paired Devices",
                    message: "Devices that pair with this one sync over the local network. Tap Pair New Device below to issue a pairing code."
                )
            }

            if Self.isRunningOnMac {
                AgentLinkSection()
            }

            Section("Actions") {
                Button {
                    issuePairingCode()
                } label: {
                    if isIssuingCode {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating Code...")
                        }
                        .frame(minHeight: 44)
                    } else {
                        Label("Pair New Device", systemImage: "plus.circle.fill")
                            .frame(minHeight: 44)
                    }
                }
                .disabled(isIssuingCode)
                .rowAccessibility(
                    label: "Pair new device",
                    value: isIssuingCode ? "Generating code" : nil,
                    hint: "Issues a one-time pairing code for a new device to join this business.",
                    id: "settings-device-mgmt-pair-button"
                )

                if let error = pairingError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Device Management")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
                .accessibilityHint("Opens help for this page.")
                .accessibilityIdentifier("settings-device-mgmt-help-button")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(title: "Device Management Help", sections: [
                    ("What This Page Does", "Shows this device's identity and lets you pair new devices into your shop network. Paired devices sync data with each other over the local network."),
                    ("Pairing a New Device", "Tap Pair New Device to generate a one-time pairing code. On the new device, choose Join Existing Business during setup and enter the code when prompted. Keep both devices on the same Wi-Fi network."),
                ])
            case .pairingCode(let code):
                PairingCodeSheet(code: code)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Macs only (owner decision 2026-08-01) — TRUE for BOTH the Catalyst
    /// build and the iPad binary on Apple Silicon (how TestFlight delivers
    /// to Macs; a compile-time Catalyst gate would hide this from the
    /// owner's actual Mac — the #1622 lesson).
    static var isRunningOnMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    private enum ActiveSheet: Identifiable {
        case help
        case pairingCode(String)

        var id: String {
            switch self {
            case .help: return "help"
            case .pairingCode: return "pairingCode"
            }
        }
    }

    private func issuePairingCode() {
        isIssuingCode = true
        pairingError = nil
        Task {
            do {
                let code = try await appCore.syncManager.issueShopPairingCode()
                activeSheet = .pairingCode(code)
            } catch {
                pairingError = userFriendlyError(error, context: "issue pairing code")
            }
            isIssuingCode = false
        }
    }
}

// MARK: - Pairing Code Sheet

/// Displays a freshly issued one-time pairing code with join instructions.
private struct PairingCodeSheet: View {
    let code: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)

                Text("Pairing Code")
                    .font(.headline)

                Text(code)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .kerning(2)
                    .textSelection(.enabled)
                    .accessibilityLabel("Pairing code")
                    .accessibilityValue(code.map(String.init).joined(separator: " "))
                    .accessibilityIdentifier("settings-pairing-code-text")

                Text("On the new device, choose \"Join Existing Business\" during setup, connect to this device, and enter this code. The code is one-time use.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Keep both devices on the same Wi-Fi network.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .navigationTitle("Pair New Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
