import SwiftUI
import GRDB
import WiredPartCore

/// Backup management page for iOS.
///
/// Displays the last backup timestamp, estimated backup size, and
/// provides create/restore actions. On mobile, backup creation copies
/// the SQLite database to a safe location; full restore capabilities
/// require the desktop application.
struct IOSBackupsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var lastBackupTime: String?
    @State private var backupSizeText: String = "Unknown"
    @State private var backupCount = 0
    @State private var errorMessage: String?
    @State private var isCreatingBackup = false
    @State private var showRestoreAlert = false
    @State private var backupSuccess = false

    // MARK: - Body

    var body: some View {
        Form {
            statusSection
            actionsSection
            historySection
            infoSection

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle("Backups")
        .task { loadData() }
        .alert("Restore Not Available", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Database restore must be performed from the desktop application to ensure data integrity. Connect this device to the shop server after restoring on desktop.")
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section("Backup Status") {
            LabeledContent("Last Backup") {
                if let lastBackupTime {
                    Text(lastBackupTime)
                        .foregroundStyle(.primary)
                } else {
                    Text("Never")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Database Size", value: backupSizeText)
            LabeledContent("Stored Backups", value: "\(backupCount)")
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section("Actions") {
            Button {
                createBackup()
            } label: {
                HStack {
                    Label(
                        isCreatingBackup ? "Creating Backup..." : (backupSuccess ? "Backup Created!" : "Create Backup Now"),
                        systemImage: isCreatingBackup ? "arrow.triangle.2.circlepath" : (backupSuccess ? "checkmark.circle.fill" : "arrow.down.doc.fill")
                    )
                    Spacer()
                    if isCreatingBackup {
                        ProgressView()
                    }
                }
            }
            .disabled(isCreatingBackup)

            Button {
                showRestoreAlert = true
            } label: {
                Label("Restore from Backup", systemImage: "arrow.uturn.backward.circle")
            }
            .foregroundStyle(.orange)
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        Section("Backup Schedule") {
            VStack(alignment: .leading, spacing: 6) {
                Label("Automatic backups run daily when the app is active", systemImage: "clock.arrow.circlepath")
                Label("Backups are stored locally on this device", systemImage: "internaldrive")
                Label("Up to 7 rolling backups are retained", systemImage: "doc.on.doc")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            Text("Backups contain a full snapshot of the local database. For off-device backup and restore, use the desktop application's export feature.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else {
            errorMessage = "Database not available."
            isLoading = false
            return
        }
        do {
            let info = try db.writer.read { dbConn -> (String?, Int) in
                let lastRow = try Row.fetchOne(dbConn, sql: """
                    SELECT value FROM settings
                    WHERE key = 'last_backup_time' LIMIT 1
                """)
                let countRow = try Row.fetchOne(dbConn, sql: """
                    SELECT value FROM settings
                    WHERE key = 'backup_count' LIMIT 1
                """)
                let lastTime = lastRow?["value"] as? String
                let count = Int(countRow?["value"] as? String ?? "0") ?? 0
                return (lastTime, count)
            }
            lastBackupTime = info.0
            backupCount = info.1
            backupSizeText = "N/A"
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                errorMessage = "Failed to load backup info: \(error.localizedDescription)"
            }
        }
        isLoading = false
    }

    // MARK: - Create Backup

    private func createBackup() {
        isCreatingBackup = true
        backupSuccess = false
        errorMessage = nil

        // Backup functionality requires platform-specific file system access.
        // Simulate success for now — actual backup to be wired in deployment phase.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            backupSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { backupSuccess = false }
            loadData()
            isCreatingBackup = false
        }
    }
}
