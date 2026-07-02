import SwiftUI
import WiredPartCore
import GRDB

enum IOSDatabaseExportSnapshotter {
    nonisolated static func exportSQLiteSnapshot(from source: any DatabaseWriter, sourceURL: URL, to destURL: URL) throws {
        for url in [destURL, URL(fileURLWithPath: destURL.path + "-wal"), URL(fileURLWithPath: destURL.path + "-shm")] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }

        // Keep the exported artifact encrypted by preserving the live database file bytes.
        // First force committed WAL pages into the main database so a single-file copy is
        // complete, then copy only the checkpointed SQLite file into the share-sheet temp path.
        try source.write { db in
            guard let checkpoint = try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(TRUNCATE)") else {
                throw NSError(domain: "IOSDatabaseExportSnapshotter", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Database checkpoint did not return a result."
                ])
            }
            let busy: Int = checkpoint[0]
            let log: Int = checkpoint[1]
            let checkpointed: Int = checkpoint[2]
            guard busy == 0 else {
                throw NSError(domain: "IOSDatabaseExportSnapshotter", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Database is busy. Try again in a moment."
                ])
            }
            guard checkpointed == log else {
                throw NSError(domain: "IOSDatabaseExportSnapshotter", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Database is busy. Try again in a moment."
                ])
            }
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            } catch {
                try? FileManager.default.removeItem(at: destURL)
                throw error
            }
        }
    }

    nonisolated static func userFriendlyExportError(raw: String) -> String {
        let normalized = raw.lowercased()
        if normalized.contains("database is locked") || normalized.contains("database is busy") {
            return "The database is busy. Please try again in a moment."
        }
        if normalized.contains("disk i/o error") || normalized.contains("disk full") {
            return "Storage problem. Check your device has enough space."
        }
        return "Couldn't export data. Pull down to retry."
    }
}

/// Writes selected-table export artifacts (CSV/JSON) into the temporary directory.
///
/// Nonisolated so the row fetch, serialization, and file I/O run off the main
/// actor — large table exports must not freeze the Settings UI (GH #1314).
enum IOSTableExportWriter {
    nonisolated static func writeExports(
        tables: [String],
        format: String,
        settingsService: SettingsService
    ) throws -> [URL] {
        let tmpDir = FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        var urls: [URL] = []

        for table in tables {
            let rows = try settingsService.exportTable(table)
            guard !rows.isEmpty else { continue }

            let ext = format == "json" ? "json" : "csv"
            let fileURL = tmpDir.appendingPathComponent("wiredpart-export-\(table)-\(dateStr).\(ext)")

            if format == "json" {
                let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: fileURL)
            } else {
                // CSV
                guard let firstRow = rows.first as? [String: Any] else { continue }
                let headers = firstRow.keys.sorted()
                var csv = headers.joined(separator: ",") + "\n"
                for row in rows {
                    guard let dict = row as? [String: Any] else { continue }
                    let values = headers.map { key -> String in
                        let val = dict[key] ?? ""
                        let str = "\(val)"
                        if str.contains(",") || str.contains("\"") || str.contains("\n") {
                            return "\"\(str.replacingOccurrences(of: "\"", with: "\"\""))\""
                        }
                        return str
                    }
                    csv += values.joined(separator: ",") + "\n"
                }
                try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            urls.append(fileURL)
        }
        return urls
    }
}

/// Data export page for iOS.
///
/// Provides options to export the local database or specific tables
/// as CSV/JSON files. Export artifacts are written to the app's temporary
/// directory and handed straight to the iOS share sheet; nothing is kept
/// in the app's Documents folder.
struct IOSDataExportPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var activeSheet: ActiveSheet?
    @State private var isLoading = true
    @State private var availableTables: [String] = []
    @State private var selectedFormat = "csv"
    @State private var selectedTables: Set<String> = []
    @State private var isExporting = false
    @State private var exportSuccess = false
    @State private var errorMessage: String?
    @State private var dbSizeText = "Unknown"

    private let formats = ["csv", "json"]

    private var canExport: Bool {
        appCore.hasPermission("manage_settings")
    }

    // MARK: - Body

    var body: some View {
        Group {
            if canExport {
                exportForm
            } else {
                EmptyStateView(
                    icon: "lock.shield",
                    title: "Access Restricted",
                    message: "You don't have permission to export data."
                )
            }
        }
        .navigationTitle("Data Export")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .disabled(isExporting)
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(title: "Data Export Help", sections: [
                    ("What This Page Does", "Exports the local database or specific tables as CSV or JSON files. You can also export the full SQLite database file."),
                    ("How to Use It", "Select a format (CSV or JSON), check the tables you want to export, then tap Export. Use 'Export Full Database' for a complete SQLite backup. The share sheet opens as soon as the export is ready — save the files to the Files app, AirDrop them, or send them to another app from there."),
                ])
            case .share(let urls):
                ReportShareSheet(items: urls)
            }
        }
        .task { if canExport { loadData() } }
    }

    private var exportForm: some View {
        Form {
            databaseInfoSection
            formatSection
            tablesSection
            exportActionsSection
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
        case share([URL])

        // Stable IDs only — never embed file paths in SwiftUI view identity (GH #1314).
        var id: String {
            switch self {
            case .help:
                return "help"
            case .share:
                return "share"
            }
        }
    }

    // MARK: - Database Info

    private var databaseInfoSection: some View {
        Section("Database") {
            LabeledContent("Database Size", value: dbSizeText)
            LabeledContent("Tables", value: "\(availableTables.count)")
            LabeledContent("Selected", value: "\(selectedTables.count)")
        }
    }

    // MARK: - Format Section

    private var formatSection: some View {
        Section("Export Format") {
            Picker("Format", selection: $selectedFormat) {
                ForEach(formats, id: \.self) { format in
                    Text(format.uppercased()).tag(format)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Tables Section

    private var tablesSection: some View {
        Section("Select Tables") {
            if isLoading {
                ProgressView("Loading tables...")
            } else {
                Button(selectedTables.count == availableTables.count ? "Deselect All" : "Select All") {
                    if selectedTables.count == availableTables.count {
                        selectedTables.removeAll()
                    } else {
                        selectedTables = Set(availableTables)
                    }
                }
                .font(.subheadline)

                ForEach(availableTables, id: \.self) { table in
                    Button {
                        if selectedTables.contains(table) {
                            selectedTables.remove(table)
                        } else {
                            selectedTables.insert(table)
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedTables.contains(table) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedTables.contains(table) ? .blue : .secondary)
                                .accessibilityHidden(true)
                            Text(table)
                                .foregroundStyle(.primary)
                                .font(.subheadline.monospaced())
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTables.contains(table) ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Export Actions

    private var exportActionsSection: some View {
        Section {
            Button {
                performExport()
            } label: {
                HStack {
                    Spacer()
                    if isExporting {
                        ProgressView()
                            .padding(.trailing, 8)
                    }
                    Text(exportSuccess ? "Export Complete!" : "Export Selected Tables")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTables.isEmpty || isExporting)

            Button {
                exportFullDatabase()
            } label: {
                HStack {
                    Spacer()
                    Text("Export Full Database (.sqlite)")
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .disabled(isExporting)
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            Text("Exports are created as temporary files and offered through the share sheet right away. Save them to the Files app or another location from the share sheet — they are not stored inside the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let settingsService = appCore.settingsService else {
            errorMessage = "Settings service not available."
            isLoading = false
            return
        }
        do {
            availableTables = try settingsService.listDatabaseTables()
            dbSizeText = "N/A"
        } catch {
            errorMessage = userFriendlyError(error, context: "load tables")
        }
        isLoading = false
    }

    // MARK: - Export Actions

    private func performExport() {
        isExporting = true
        exportSuccess = false
        errorMessage = nil
        activeSheet = nil

        guard let settingsService = appCore.settingsService else {
            errorMessage = "Settings service not available."
            isExporting = false
            return
        }

        // Capture value-type inputs on the main actor, then run the heavy row
        // fetch, serialization, and file I/O off-main (GH #1314). UI state
        // updates hop back to the MainActor, mirroring exportFullDatabase().
        let tables = selectedTables.sorted()
        let format = selectedFormat

        Task.detached(priority: .userInitiated) {
            do {
                let urls = try IOSTableExportWriter.writeExports(
                    tables: tables,
                    format: format,
                    settingsService: settingsService
                )
                await MainActor.run {
                    if urls.isEmpty {
                        exportSuccess = false
                        errorMessage = "No rows were exported from the selected tables. Choose tables with data or export the full database."
                    } else {
                        exportSuccess = true
                        activeSheet = .share(urls)
                    }
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = userFriendlyError(error, context: "export data")
                    isExporting = false
                }
            }
        }
    }

    private func exportFullDatabase() {
        isExporting = true
        errorMessage = nil

        guard let database = appCore.db else {
            errorMessage = "Database is not available."
            isExporting = false
            return
        }
        let uiTestingMode = ProcessInfo.processInfo.arguments.contains("-UITesting")
        guard let dbPath = try? AppCore.databasePath(isUITesting: uiTestingMode) else {
            errorMessage = "Cannot locate database."
            isExporting = false
            return
        }

        let sourceURL = URL(fileURLWithPath: dbPath)
        let tmpDir = FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        let destURL = tmpDir.appendingPathComponent("wiredpart-full-\(dateStr).sqlite")

        Task.detached(priority: .userInitiated) {
            do {
                try IOSDatabaseExportSnapshotter.exportSQLiteSnapshot(
                    from: database.writer,
                    sourceURL: sourceURL,
                    to: destURL
                )
                await MainActor.run {
                    exportSuccess = true
                    activeSheet = .share([destURL])
                    isExporting = false
                }
            } catch {
                let message = IOSDatabaseExportSnapshotter.userFriendlyExportError(raw: error.localizedDescription)
                await MainActor.run {
                    errorMessage = message
                    isExporting = false
                }
            }
        }
    }
}
