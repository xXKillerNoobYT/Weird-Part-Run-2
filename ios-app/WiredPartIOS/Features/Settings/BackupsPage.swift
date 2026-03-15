import SwiftUI
import WiredPartCore

/// Database backup and restore settings page.
///
/// Provides options to create manual backups of the local database
/// and view existing backups. This is an informational placeholder
/// that describes the backup functionality.
struct BackupsPage: View {
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        Form {
            Section("Database Info") {
                LabeledContent("Database Path", value: AppCore.databasePath())
                    .font(.caption2)
                LabeledContent("Core Version", value: WiredPartCore.version)
            }

            Section("Manual Backup") {
                Button {
                    // Placeholder: create a database backup
                } label: {
                    Label("Create Backup Now", systemImage: "square.and.arrow.down.fill")
                }

                Text("Creates a timestamped copy of the database file in the app's Documents folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Auto-Backup") {
                Text("Automatic backups run before each sync operation and keep the last 5 copies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Restore") {
                Text("To restore from a backup, replace the current database file with a backup copy. This requires restarting the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
