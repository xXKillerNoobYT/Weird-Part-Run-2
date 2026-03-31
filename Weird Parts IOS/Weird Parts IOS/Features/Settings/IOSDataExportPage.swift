import SwiftUI
import WiredPartCore

/// Data export page for iOS.
///
/// Provides options to export the local database or specific tables
/// as CSV files. Exports are saved to the device's documents directory
/// and can be shared via the iOS share sheet.
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
                ContentUnavailableView(
                    "Access Restricted",
                    systemImage: "lock.shield",
                    description: Text("You don't have permission to export data.")
                )
            }
        }
        .navigationTitle("Data Export")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Data Export Help", sections: [
                ("What This Page Does", "Exports the local database or specific tables as CSV or JSON files. You can also export the full SQLite database file."),
                ("How to Use It", "Select a format (CSV or JSON), check the tables you want to export, then tap Export. Use 'Export Full Database' for a complete SQLite backup. Exported files are saved to the app's Documents folder."),
            ])
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
        var id: String { "help" }
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
            Text("Exported files are saved to this app's Documents folder. Use the Files app or share sheet to transfer them to another location.")
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

    @State private var exportURLs: [URL] = []
    @State private var showShareSheet = false

    private func performExport() {
        isExporting = true
        exportSuccess = false
        errorMessage = nil
        exportURLs = []

        guard let settingsService = appCore.settingsService else {
            errorMessage = "Settings service not available."
            isExporting = false
            return
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        var urls: [URL] = []

        do {
            for table in selectedTables.sorted() {
                let rows = try settingsService.exportTable(table)
                guard !rows.isEmpty else { continue }

                let ext = selectedFormat == "json" ? "json" : "csv"
                let fileURL = tmpDir.appendingPathComponent("wiredpart-export-\(table)-\(dateStr).\(ext)")

                if selectedFormat == "json" {
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

            exportURLs = urls
            exportSuccess = true
            isExporting = false

            if !urls.isEmpty {
                showShareSheet = true
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "export data")
            isExporting = false
        }
    }

    private func exportFullDatabase() {
        isExporting = true
        errorMessage = nil

        guard let dbPath = try? AppCore.databasePath() else {
            errorMessage = "Cannot locate database."
            isExporting = false
            return
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        let destURL = tmpDir.appendingPathComponent("wiredpart-full-\(dateStr).sqlite")

        do {
            // Remove previous temp if exists
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: dbPath), to: destURL)
            exportURLs = [destURL]
            exportSuccess = true
            showShareSheet = true
        } catch {
            errorMessage = userFriendlyError(error, context: "export data")
        }
        isExporting = false
    }
}
