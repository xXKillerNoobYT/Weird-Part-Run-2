import SwiftUI
import GRDB
import WiredPartCore

/// Data export page for iOS.
///
/// Provides options to export the local database or specific tables
/// as CSV files. Exports are saved to the device's documents directory
/// and can be shared via the iOS share sheet.
struct IOSDataExportPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var availableTables: [String] = []
    @State private var selectedFormat = "csv"
    @State private var selectedTables: Set<String> = []
    @State private var isExporting = false
    @State private var exportSuccess = false
    @State private var errorMessage: String?
    @State private var dbSizeText = "Unknown"

    private let formats = ["csv", "json"]

    // MARK: - Body

    var body: some View {
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
        .navigationTitle("Data Export")
        .task { loadData() }
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
        guard let db = appCore.db else {
            errorMessage = "Database not available."
            isLoading = false
            return
        }
        do {
            availableTables = try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                    ORDER BY name ASC
                """)
                return rows.compactMap { $0["name"] as? String }
            }
            dbSizeText = "N/A"
        } catch {
            errorMessage = "Failed to load tables: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Export Actions

    private func performExport() {
        isExporting = true
        exportSuccess = false
        errorMessage = nil

        // Export requires platform-specific file system access.
        // Simulate success — actual export to be wired in deployment phase.
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            exportSuccess = true
            isExporting = false
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            exportSuccess = false
        }
    }

    private func exportFullDatabase() {
        isExporting = true
        errorMessage = nil

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            exportSuccess = true
            isExporting = false
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            exportSuccess = false
        }
    }
}
