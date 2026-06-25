import SwiftUI
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

    @State private var activeSheet: ActiveSheet?
    @State private var isLoading = true
    @State private var lastBackupTime: String?
    @State private var backupSizeText: String = "Unknown"
    @State private var backupCount = 0
    @State private var errorMessage: String?
    @State private var isCreatingBackup = false
    @State private var showRestoreAlert = false
    @State private var backupSuccess = false

    private var canManageSettings: Bool {
        appCore.hasPermission("manage_settings")
    }

    // MARK: - Body

    var body: some View {
        Group {
            if canManageSettings {
                backupsForm
            } else {
                EmptyStateView(
                    icon: "lock.shield",
                    title: "Access Restricted",
                    message: "You don't have permission to manage backups."
                )
            }
        }
        .navigationTitle("Backups")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Backups Help", sections: [
                ("What This Page Does", "Manages local database backups. Shows the last backup time, database size, and stored backup count. You can create new backups manually."),
                ("How to Use It", "Tap 'Create Backup Now' to snapshot the current database. Automatic backups run daily. Up to 7 rolling backups are retained. Database restore must be done from the desktop application."),
            ])
        }
        .task { if canManageSettings { loadData() } }
        .alert("Restore Not Available", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Database restore must be performed from the desktop application to ensure data integrity. Connect this device to the shop server after restoring on desktop.")
        }
    }

    private var backupsForm: some View {
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
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
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

    // MARK: - Helpers

    private var backupDir: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("WiredPart/Backups")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var dbPath: String? {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
        return try? AppCore.databasePath(isUITesting: isUITesting)
    }

    private func formatFileSize(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    // MARK: - Data Loading

    private func loadData() {
        // DB size
        if let path = dbPath,
           let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64 {
            backupSizeText = formatFileSize(size)
        } else {
            backupSizeText = "Unknown"
        }

        // Scan backups
        if let dir = backupDir,
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]) {
            let backups = files.filter { $0.pathExtension == "sqlite" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            backupCount = backups.count
            if let newest = backups.first {
                lastBackupTime = newest.lastPathComponent
                    .replacingOccurrences(of: "wiredpart-backup-", with: "")
                    .replacingOccurrences(of: ".sqlite", with: "")
            } else {
                lastBackupTime = nil
            }
        }

        isLoading = false
    }

    // MARK: - Create Backup

    private func createBackup() {
        isCreatingBackup = true
        backupSuccess = false
        errorMessage = nil

        guard let sourcePath = dbPath, let dir = backupDir else {
            errorMessage = "Cannot locate database or backup directory."
            isCreatingBackup = false
            return
        }

        // Check free disk space
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: dir.path),
           let freeSpace = attrs[.systemFreeSize] as? UInt64,
           freeSpace < 100_000_000 {
            errorMessage = "Low disk space (\(formatFileSize(freeSpace)) free). Free up space before backing up."
            isCreatingBackup = false
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupName = "wiredpart-backup-\(timestamp).sqlite"
        let destURL = dir.appendingPathComponent(backupName)

        do {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            try FileManager.default.copyItem(at: sourceURL, to: destURL)

            // Copy WAL/SHM if they exist
            let walPath = sourcePath + "-wal"
            if FileManager.default.fileExists(atPath: walPath) {
                try? FileManager.default.copyItem(
                    at: URL(fileURLWithPath: walPath),
                    to: dir.appendingPathComponent(backupName + "-wal")
                )
            }
            let shmPath = sourcePath + "-shm"
            if FileManager.default.fileExists(atPath: shmPath) {
                try? FileManager.default.copyItem(
                    at: URL(fileURLWithPath: shmPath),
                    to: dir.appendingPathComponent(backupName + "-shm")
                )
            }

            backupSuccess = true
            loadData()

            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                backupSuccess = false
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "manage backups")
        }
        isCreatingBackup = false
    }
}
