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

                    steps
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
        do {
            pairingCode = try await syncManager.issueShopPairingCode()
        } catch {
            errorMessage = userFriendlyError(error, context: "generate a pairing code")
        }
        isLoading = false
    }
}
