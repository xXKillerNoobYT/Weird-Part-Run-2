import SwiftUI
import WiredPartCore

/// Post-onboarding "Add a Device" sheet.
///
/// Closes the gap where the pairing handshake only existed during first-run
/// onboarding (`DevicePairingView`). From any existing device, this shows a
/// short-lived pairing code and makes this device discoverable on the network /
/// Bluetooth (via `IOSSyncManager.issueShopPairingCode()`, which starts peer
/// sync if it isn't already running). A new device then chooses "Join Existing
/// Business", finds this one, and enters the code to join the same company.
struct IOSAddDeviceSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var pairingCode: String?
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var syncManager: IOSSyncManager { appCore.syncManager }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                        .padding(.top, 8)

                    Text("Add a Device to This Company")
                        .font(.title3).fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    content

                    liveStatus

                    steps

                    // Always-visible controls: regenerate a fresh code without
                    // relaunching, and a Close that works even where the toolbar
                    // Done is unreliable (Mac Catalyst dismiss quirk — see #1415).
                    HStack(spacing: 12) {
                        Button {
                            Task { await loadCode() }
                        } label: {
                            Label("New Code", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)

                        Button {
                            dismiss()
                        } label: {
                            Text("Close")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("Add a Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadCode() }
            .onDisappear {
                // Closing the sheet ends the pairing offer: invalidate the code
                // and close the cross-company connection window on the host.
                Task { await appCore.syncManager.endPairingOffer() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Preparing this device…")
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if let code = pairingCode {
            VStack(spacing: 8) {
                Text("Pairing Code")
                    .font(.caption).foregroundStyle(.secondary)
                Text(code)
                    .font(.system(.largeTitle, design: .monospaced))
                    .fontWeight(.bold)
                    .textSelection(.enabled)
                    .accessibilityLabel("Pairing code \(code.map(String.init).joined(separator: " "))")
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Label("Copy Code", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .dsCard()
        } else if let errorMessage {
            VStack(spacing: 10) {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await loadCode() } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    /// Live host-side feedback: which devices are connected right now, whether a
    /// transfer is running, and the result of the last completed transfer — so the
    /// host actually SEES the pairing + data transfer happen instead of a silent wait.
    @ViewBuilder
    private var liveStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !syncManager.discoveredPeers.isEmpty {
                Text("Nearby devices")
                    .font(.headline)
                ForEach(syncManager.discoveredPeers) { peer in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(peer.state == "connected" ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(peer.name)
                            .font(.subheadline)
                        Text(peer.state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }

            if let syncingName = syncManager.activeSyncPeerName {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Sending company data to \(syncingName)…")
                        .font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            } else if let summary = syncManager.lastHostSyncSummary {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On the new device:")
                .font(.headline)
            stepRow(1, "Install and open WiredPart.")
            stepRow(2, "Tap \u{201C}Join Existing Business.\u{201D}")
            stepRow(3, "Pick this device when it appears in the list.")
            stepRow(4, "Enter the pairing code above.")
            Text("Keep this screen open until the new device finishes. The code expires shortly for security.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadCode() async {
        isLoading = true
        errorMessage = nil
        // Clear any previous code first: on regenerate-failure the old (already
        // burned or stale) code must not keep rendering while the error hides
        // behind it (Copilot review on PR #1422).
        pairingCode = nil
        do {
            pairingCode = try await syncManager.issueShopPairingCode()
        } catch {
            errorMessage = userFriendlyError(error, context: "generate a pairing code")
        }
        isLoading = false
    }
}
