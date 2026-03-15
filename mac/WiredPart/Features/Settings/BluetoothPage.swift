import SwiftUI

/// Bluetooth sync configuration page.
///
/// Placeholder — the Bluetooth sync subsystem (Apple Multipeer Connectivity)
/// is implemented in core but not yet wired to the macOS UI.
struct BluetoothPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Bluetooth")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                GroupBox("Bluetooth Status") {
                    HStack(spacing: 12) {
                        Image(systemName: "wave.3.right")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("Bluetooth Sync")
                                .font(.headline)
                            Text("Configuration coming soon")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Paired Devices") {
                    VStack(spacing: 12) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No paired devices")
                            .foregroundStyle(.secondary)
                        Text("Bluetooth peer-to-peer sync allows devices to exchange data without a network connection using Apple Multipeer Connectivity.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                GroupBox("Scan for Devices") {
                    HStack {
                        Text("Scan for nearby WiredPart devices")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Scan") {}
                            .buttonStyle(.bordered)
                            .disabled(true)
                    }
                    .padding(.vertical, 4)
                }

                infoCard(
                    "About Bluetooth Sync",
                    text: "Bluetooth sync uses Apple Multipeer Connectivity to create a direct peer-to-peer connection between devices. This works even without Wi-Fi or cellular connectivity, making it ideal for field use."
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
