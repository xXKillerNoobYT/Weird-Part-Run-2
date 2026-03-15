import SwiftUI
import GRDB
import WiredPartCore
import UniformTypeIdentifiers

/// Import/Export page for bulk parts operations.
///
/// Provides CSV export of the parts catalog and CSV import with
/// a file picker. Shows operation results and progress feedback.
struct ImportExportPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportResult: String?
    @State private var importResult: String?
    @State private var partCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Import / Export")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // MARK: - Export Section

                GroupBox("Export Parts Catalog") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export all active parts as a CSV file. Includes code, name, category, brand, cost, markup, stock levels, and location data.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Text("\(partCount) parts available for export")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button {
                                exportCSV()
                            } label: {
                                if isExporting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Export CSV", systemImage: "square.and.arrow.up")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isExporting || partCount == 0)

                            if let result = exportResult {
                                Label(result, systemImage: result.contains("Error") ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(result.contains("Error") ? .red : .green)
                                    .font(.caption)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Import Section

                GroupBox("Import Parts from CSV") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Import parts from a CSV file. The file must have headers matching: code, name, category, brand, cost_price, markup_percent.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Text("Expected CSV columns:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("code, name, category, brand, cost_price, markup_percent, unit_of_measure, shelf_location, bin_location, notes")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(.controlBackgroundColor)))

                        HStack {
                            Button {
                                pickAndImportCSV()
                            } label: {
                                if isImporting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Import CSV", systemImage: "square.and.arrow.down")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isImporting)

                            if let result = importResult {
                                Label(result, systemImage: result.contains("Error") ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(result.contains("Error") ? .red : .green)
                                    .font(.caption)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Tips

                GroupBox("Tips") {
                    VStack(alignment: .leading, spacing: 8) {
                        tipRow(icon: "lightbulb", text: "Export first to get a template CSV with the correct column headers.")
                        tipRow(icon: "exclamationmark.triangle", text: "Imported parts are matched by code. Existing parts with the same code will be updated.")
                        tipRow(icon: "arrow.uturn.backward", text: "Imports are not reversible. Consider exporting a backup before importing.")
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadCount() }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .font(.caption)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    private func loadCount() {
        guard let db = appCore.db else { return }
        do {
            partCount = try db.writer.read { conn in
                try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL") ?? 0
            }
        } catch {
            print("[ImportExportPage] Count error: \(error)")
        }
    }

    // MARK: - Export

    private func exportCSV() {
        guard let db = appCore.db else { return }
        isExporting = true
        exportResult = nil

        let writer = db.writer
        Task.detached {
            do {
                let csvString = try await writer.read { conn -> String in
                    let rows = try Row.fetchAll(
                        conn,
                        sql: """
                            SELECT
                                COALESCE(p.code, '') AS code,
                                p.name,
                                COALESCE(pc.name, '') AS category,
                                COALESCE(b.name, '') AS brand,
                                p.company_cost_price AS cost_price,
                                p.company_markup_percent AS markup_percent,
                                COALESCE(p.unit_of_measure, '') AS unit_of_measure,
                                COALESCE(p.shelf_location, '') AS shelf_location,
                                COALESCE(p.bin_location, '') AS bin_location,
                                COALESCE(p.notes, '') AS notes
                            FROM parts p
                            LEFT JOIN part_categories pc ON pc.id = p.category_id
                            LEFT JOIN brands b ON b.id = p.brand_id
                            WHERE p.deleted_at IS NULL
                            ORDER BY p.name ASC
                            """
                    )

                    var csv = "code,name,category,brand,cost_price,markup_percent,unit_of_measure,shelf_location,bin_location,notes\n"
                    for row in rows {
                        let fields: [String] = [
                            csvEscape(row["code"] as String? ?? ""),
                            csvEscape(row["name"] as String? ?? ""),
                            csvEscape(row["category"] as String? ?? ""),
                            csvEscape(row["brand"] as String? ?? ""),
                            String(format: "%.2f", (row["cost_price"] as Double?) ?? 0),
                            String(format: "%.0f", (row["markup_percent"] as Double?) ?? 0),
                            csvEscape(row["unit_of_measure"] as String? ?? ""),
                            csvEscape(row["shelf_location"] as String? ?? ""),
                            csvEscape(row["bin_location"] as String? ?? ""),
                            csvEscape(row["notes"] as String? ?? ""),
                        ]
                        csv += fields.joined(separator: ",") + "\n"
                    }
                    return csv
                }

                // Show save panel on main thread
                await MainActor.run {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.commaSeparatedText]
                    panel.nameFieldStringValue = "parts-export-\(dateStamp()).csv"

                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            try csvString.write(to: url, atomically: true, encoding: .utf8)
                            exportResult = "Exported successfully"
                        } catch {
                            exportResult = "Error: \(error.localizedDescription)"
                        }
                    }

                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportResult = "Error: \(error.localizedDescription)"
                    isExporting = false
                }
            }
        }
    }

    // MARK: - Import

    private func pickAndImportCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isImporting = true
        importResult = nil

        let writer = appCore.db!.writer
        Task.detached {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard lines.count > 1 else {
                    await MainActor.run {
                        importResult = "Error: CSV file is empty or has no data rows"
                        isImporting = false
                    }
                    return
                }

                // Parse header
                let headers = parseCSVLine(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                let nameIdx = headers.firstIndex(of: "name")
                let codeIdx = headers.firstIndex(of: "code")
                let costIdx = headers.firstIndex(of: "cost_price")
                let markupIdx = headers.firstIndex(of: "markup_percent")

                guard let nameIdx else {
                    await MainActor.run {
                        importResult = "Error: CSV must have a 'name' column"
                        isImporting = false
                    }
                    return
                }

                var imported = 0
                var updated = 0
                var errors = 0

                for lineIndex in 1..<lines.count {
                    let fields = parseCSVLine(lines[lineIndex])
                    guard fields.count > nameIdx else { errors += 1; continue }

                    let name = fields[nameIdx].trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { errors += 1; continue }

                    let code = codeIdx.flatMap { $0 < fields.count ? fields[$0].trimmingCharacters(in: .whitespaces) : nil }
                    let costPrice = costIdx.flatMap { $0 < fields.count ? Double(fields[$0].trimmingCharacters(in: .whitespaces)) : nil } ?? 0
                    let markupPercent = markupIdx.flatMap { $0 < fields.count ? Double(fields[$0].trimmingCharacters(in: .whitespaces)) : nil } ?? 0

                    do {
                        // Check if part exists by code
                        let existing: Int64? = try await writer.read { conn in
                            if let code, !code.isEmpty {
                                return try Int64.fetchOne(conn, sql: "SELECT id FROM parts WHERE code = ? AND deleted_at IS NULL", arguments: [code])
                            }
                            return nil
                        }

                        if let existingId = existing {
                            // Update existing
                            try await writer.write { conn in
                                try conn.execute(
                                    sql: "UPDATE parts SET name = ?, company_cost_price = ?, company_markup_percent = ?, updated_at = datetime('now') WHERE id = ?",
                                    arguments: [name, costPrice, markupPercent, existingId]
                                )
                            }
                            updated += 1
                        } else {
                            // Insert new (category_id = 1 as default placeholder)
                            try await writer.write { conn in
                                try conn.execute(
                                    sql: """
                                        INSERT INTO parts (code, name, category_id, part_type, company_cost_price, company_markup_percent, created_at, updated_at)
                                        VALUES (?, ?, 1, 'stock', ?, ?, datetime('now'), datetime('now'))
                                        """,
                                    arguments: [code, name, costPrice, markupPercent]
                                )
                            }
                            imported += 1
                        }
                    } catch {
                        errors += 1
                    }
                }

                await MainActor.run {
                    importResult = "Imported \(imported), updated \(updated), errors \(errors)"
                    isImporting = false
                    loadCount()
                }
            } catch {
                await MainActor.run {
                    importResult = "Error: \(error.localizedDescription)"
                    isImporting = false
                }
            }
        }
    }

    // MARK: - CSV Helpers

    private nonisolated func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private nonisolated func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
