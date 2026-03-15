import SwiftUI

/// Sync configuration and status page.
///
/// Placeholder — shows informational UI about the sync system.
/// Full sync management requires SyncEngine and PeerManager services
/// from a future phase.
struct SyncPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Sync")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                GroupBox("Sync Status") {
                    VStack(alignment: .leading, spacing: 12) {
                        statusRow(icon: "checkmark.circle.fill", color: .green, label: "Local Database", detail: "Active")
                        statusRow(icon: "clock", color: .orange, label: "Last Sync", detail: "Not yet synced")
                        statusRow(icon: "desktopcomputer", color: .blue, label: "Sync Mode", detail: "Standalone")
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Connected Devices") {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No devices connected")
                            .foregroundStyle(.secondary)
                        Text("LAN sync will discover nearby devices automatically when enabled.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                GroupBox("Sync History") {
                    Text("Sync history will appear here once devices begin exchanging data.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }

                infoCard(
                    "How Sync Works",
                    text: "WiredPart uses LAN-based sync over your local network. Changes are tracked in a local change log and exchanged with peer devices using last-write-wins conflict resolution at the field level."
                )
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statusRow(icon: String, color: Color, label: String, detail: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(label)
                .frame(width: 140, alignment: .leading)
            Text(detail)
                .foregroundStyle(.secondary)
        }
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
