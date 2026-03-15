import SwiftUI

/// Database backup settings page.
///
/// Placeholder — backup scheduling and management will be implemented
/// in a future phase. Shows informational UI about the planned feature.
struct BackupsPage: View {
    @State private var autoBackupsEnabled: Bool = false
    @State private var backupInterval: String = "daily"
    @State private var retentionDays: Int = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Backups")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                GroupBox("Backup Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable Automatic Backups", isOn: $autoBackupsEnabled)
                            .disabled(true)

                        if autoBackupsEnabled {
                            Picker("Backup Interval", selection: $backupInterval) {
                                Text("Hourly").tag("hourly")
                                Text("Daily").tag("daily")
                                Text("Weekly").tag("weekly")
                            }
                            .frame(maxWidth: 200)

                            Stepper("Retention: \(retentionDays) days", value: $retentionDays, in: 7...365)
                                .frame(maxWidth: 280)
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Manual Backup") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Create a backup of the current database")
                                .font(.callout)
                            Text("Backups are saved to ~/Library/Application Support/WiredPart/backups/")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Backup Now") {}
                            .buttonStyle(.borderedProminent)
                            .disabled(true)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Backup History") {
                    Text("No backups have been created yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }

                infoCard(
                    "About Backups",
                    text: "Automatic backups create timestamped copies of your SQLite database. You can restore from any backup point. Backups are stored locally on this device."
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
