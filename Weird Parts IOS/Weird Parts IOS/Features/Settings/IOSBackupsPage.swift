import SwiftUI
import WiredPartCore
import GRDB

enum IOSBackupFileCopier {
    nonisolated static let retainedBackupLimit = 7

    struct CleanupFailure: LocalizedError {
        let originalError: Error
        let cleanupError: Error

        var errorDescription: String? {
            "Backup failed and the partial backup could not be cleaned up: \(cleanupError.localizedDescription). Original backup error: \(originalError.localizedDescription)"
        }
    }

    struct InvalidRetentionLimit: LocalizedError {
        let limit: Int

        var errorDescription: String? {
            "Backup retention limit must be zero or greater, got \(limit)."
        }
    }

    nonisolated static func copySQLiteSnapshot(from sourceURL: URL, to destURL: URL) throws {
        var createdURLs: [URL] = []

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            createdURLs.append(destURL)

            for suffix in ["-wal", "-shm"] {
                let sourceSidecar = URL(fileURLWithPath: sourceURL.path + suffix)
                guard FileManager.default.fileExists(atPath: sourceSidecar.path) else { continue }

                let destinationSidecar = URL(fileURLWithPath: destURL.path + suffix)
                try FileManager.default.copyItem(at: sourceSidecar, to: destinationSidecar)
                createdURLs.append(destinationSidecar)
            }
        } catch {
            var cleanupError: Error?
            for createdURL in createdURLs.reversed() {
                do {
                    try FileManager.default.removeItem(at: createdURL)
                } catch let removalError {
                    cleanupError = removalError
                }
            }

            if let cleanupError {
                throw CleanupFailure(originalError: error, cleanupError: cleanupError)
            }
            throw error
        }
    }

    /// Creates a complete SQLite snapshot while holding the application's writer lock.
    /// A raw main-file/WAL copy can observe the files at different points in time, which
    /// produces a restore that is structurally valid but missing recently committed rows.
    nonisolated static func checkpointAndCopySQLiteSnapshot(
        from source: any DatabaseWriter,
        sourceURL: URL,
        to destURL: URL
    ) throws {
        try removeSQLiteSnapshot(at: destURL)
        try source.write { db in
            guard let checkpoint = try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(TRUNCATE)") else {
                throw NSError(domain: "IOSBackupFileCopier", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Database checkpoint did not return a result."
                ])
            }
            let busy: Int = checkpoint[0]
            let log: Int = checkpoint[1]
            let checkpointed: Int = checkpoint[2]
            guard busy == 0, checkpointed == log else {
                throw NSError(domain: "IOSBackupFileCopier", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Database is busy. Try again in a moment."
                ])
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        }
    }

    nonisolated static func removeSQLiteSnapshot(at snapshotURL: URL) throws {
        for url in [snapshotURL, URL(fileURLWithPath: snapshotURL.path + "-wal"), URL(fileURLWithPath: snapshotURL.path + "-shm")] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    nonisolated static func manualBackupSnapshotFiles(in directoryURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { url in
                url.lastPathComponent.hasPrefix("wiredpart-backup-") && url.pathExtension == "sqlite"
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    nonisolated static func pruneBackups(in directoryURL: URL, retaining maxCount: Int = retainedBackupLimit) throws {
        guard maxCount >= 0 else { throw InvalidRetentionLimit(limit: maxCount) }

        let backupsToRemove = try manualBackupSnapshotFiles(in: directoryURL).dropFirst(maxCount)
        for backupURL in backupsToRemove {
            try removeSQLiteSnapshot(at: backupURL)
        }
    }
}

enum IOSManualBackupOperation {
    enum Outcome {
        case completed
        case failed(Error)

        nonisolated var completionAccessibilityValue: String? {
            switch self {
            case .completed:
                return "Backup created"
            case .failed:
                return nil
            }
        }

        nonisolated var failure: Error? {
            guard case let .failed(error) = self else { return nil }
            return error
        }
    }

    nonisolated static func createSnapshot(
        from sourceURL: URL,
        to destinationURL: URL,
        in backupDirectory: URL,
        reloadLedger: () throws -> Void
    ) -> Outcome {
        do {
            try IOSBackupFileCopier.copySQLiteSnapshot(from: sourceURL, to: destinationURL)
            do {
                try IOSBackupFileCopier.pruneBackups(in: backupDirectory)
            } catch {
                do {
                    try IOSBackupFileCopier.removeSQLiteSnapshot(at: destinationURL)
                } catch let cleanupError {
                    return .failed(IOSBackupFileCopier.CleanupFailure(originalError: error, cleanupError: cleanupError))
                }
                return .failed(error)
            }

            try reloadLedger()
            return .completed
        } catch {
            return .failed(error)
        }
    }
}

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
                .accessibilityHint("Opens help for this page.")
                .accessibilityIdentifier("settings-backups-help-button")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Backups Help", sections: [
                ("What This Page Does", "Manages local database backups. Shows the last backup time, database size, and stored backup count. You can create new backups manually."),
                ("How to Use It", "Tap 'Create Backup Now' to snapshot the current database. Automatic backups run daily. Up to 7 rolling backups are retained. Database restore must be done from the desktop application."),
            ])
        }
        .task {
            guard canManageSettings else { return }
            do {
                try loadData()
            } catch {
                errorMessage = userFriendlyError(error, context: "load backup status")
            }
        }
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
            .rowAccessibility(
                label: "Create backup now",
                value: isCreatingBackup ? "Backup in progress" : (backupSuccess ? "Backup created" : nil),
                hint: "Snapshots the current database to this device. Up to 7 backups are kept.",
                id: "settings-backups-create-backup-button"
            )

            Button {
                showRestoreAlert = true
            } label: {
                Label("Restore from Backup", systemImage: "arrow.uturn.backward.circle")
            }
            .foregroundStyle(.orange)
            .rowAccessibility(
                label: "Restore from backup",
                hint: "Shows how to restore. Restore itself must be done from the desktop app.",
                id: "settings-backups-restore-info-button"
            )
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

    private func loadData() throws {
        // DB size
        if let path = dbPath,
           let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64 {
            backupSizeText = formatFileSize(size)
        } else {
            backupSizeText = "Unknown"
        }

        // Scan backups
        guard let dir = backupDir else {
            throw CocoaError(.fileNoSuchFile)
        }
        let backups = try IOSBackupFileCopier.manualBackupSnapshotFiles(in: dir)
        backupCount = backups.count
        if let newest = backups.first {
            lastBackupTime = newest.lastPathComponent
                .replacingOccurrences(of: "wiredpart-backup-", with: "")
                .replacingOccurrences(of: ".sqlite", with: "")
        } else {
            lastBackupTime = nil
        }
    }

    // MARK: - Create Backup

    private func createBackup() {
        isCreatingBackup = true
        backupSuccess = false
        errorMessage = nil

        guard let sourcePath = dbPath, let dir = backupDir, let database = appCore.db else {
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

        switch IOSManualBackupOperation.createSnapshot(
            from: URL(fileURLWithPath: sourcePath),
            to: destURL,
            in: dir,
            reloadLedger: loadData
        ) {
        case .completed:
            backupSuccess = true
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                backupSuccess = false
            }
        case let .failed(error):
            errorMessage = userFriendlyError(error, context: "manage backups")
        }
        isCreatingBackup = false
    }
}
