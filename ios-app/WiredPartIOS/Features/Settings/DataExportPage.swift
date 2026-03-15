import SwiftUI
import WiredPartCore

/// Data export settings page.
///
/// Provides options to export data from the local database in
/// various formats (CSV, JSON). Uses the database directly for
/// table listing and row counts.
struct DataExportPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var exportFormat = "CSV"
    @State private var tableCounts: [(String, Int)] = []

    private let formats = ["CSV", "JSON"]

    private let exportableTables = [
        "users", "jobs", "parts", "purchase_orders", "labor_entries",
        "vehicles", "certifications", "settings", "company_profiles",
    ]

    var body: some View {
        Form {
            Section("Export Format") {
                Picker("Format", selection: $exportFormat) {
                    ForEach(formats, id: \.self) { format in
                        Text(format).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Available Tables") {
                ForEach(tableCounts, id: \.0) { name, count in
                    HStack {
                        Text(name)
                            .font(.body)
                        Spacer()
                        Text("\(count) rows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    // Placeholder: trigger export
                } label: {
                    Label("Export All Tables", systemImage: "square.and.arrow.up.fill")
                }
                .buttonStyle(.borderedProminent)

                Text("Exports are saved to the app's Documents folder and can be accessed via the Files app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadTableCounts() }
    }

    private func loadTableCounts() {
        tableCounts = exportableTables.compactMap { table in
            let count = (try? appCore.db.writer.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE deleted_at IS NULL")
            }) ?? 0
            return (table, count ?? 0)
        }
    }
}
