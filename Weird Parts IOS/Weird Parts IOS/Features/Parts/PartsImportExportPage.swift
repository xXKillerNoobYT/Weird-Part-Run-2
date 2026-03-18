import SwiftUI
import GRDB
import WiredPartCore
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Import/Export page for parts data.
///
/// Provides CSV export of the parts catalog and a file importer for
/// importing parts from CSV files. Shows summary statistics and
/// recent import/export history.
struct PartsImportExportPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var stats = ImportExportStats()
    @State private var isLoading = true
    @State private var showFileImporter = false
    @State private var exportStatus: ExportStatus = .idle
    @State private var importStatus: ImportStatus = .idle
    @State private var showExportConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading stats...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    statsSection
                    exportSection
                    importSection
                    infoSection
                }
            }
            .padding()
        }
        .refreshable { await loadStats() }
        .confirmationDialog("Export Parts?", isPresented: $showExportConfirm, titleVisibility: .visible) {
            Button("Export All Parts (CSV)") {
                Task { await exportParts() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will export \(stats.totalParts) parts to a CSV file.")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await importFromCSV(url: url) }
                }
            case .failure:
                importStatus = .error("Failed to select file.")
            }
        }
        #if os(iOS)
        .background(DS.Background.page)
        #elseif os(macOS)
        .background(DS.Background.page)
        #endif
        .task { await loadStats() }
    }

    // MARK: - Stats Section

    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Catalog Summary")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                statCard(title: "Total Parts", value: "\(stats.totalParts)", icon: "wrench.and.screwdriver.fill", color: .blue)
                statCard(title: "Categories", value: "\(stats.totalCategories)", icon: "folder.fill", color: .orange)
                statCard(title: "Brands", value: "\(stats.totalBrands)", icon: "tag.fill", color: .purple)
                statCard(title: "Suppliers", value: "\(stats.totalSuppliers)", icon: "building.2.fill", color: .green)
            }
        }
    }

    @ViewBuilder
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.secondarySystemGroupedBackground))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Export Section

    @ViewBuilder
    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export")
                .font(.headline)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Parts to CSV")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Export your entire parts catalog including categories, brands, and pricing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                switch exportStatus {
                case .idle:
                    Button {
                        showExportConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Export CSV", systemImage: "arrow.down.doc.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)

                case .exporting:
                    ProgressView("Exporting...")
                        .frame(maxWidth: .infinity)

                case .success(let message):
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)

                case .error(let message):
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            #if os(iOS)
            .background(Color(.secondarySystemGroupedBackground))
            #elseif os(macOS)
            .background(Color(.secondarySystemGroupedBackground))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Import Section

    @ViewBuilder
    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import")
                .font(.headline)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import Parts from CSV")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Import parts from a CSV file. Expected columns: name, code, category, brand, cost_price, markup_percent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                switch importStatus {
                case .idle:
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Choose CSV File", systemImage: "doc.badge.plus")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)

                case .importing:
                    ProgressView("Importing...")
                        .frame(maxWidth: .infinity)

                case .success(let message):
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)

                case .error(let message):
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            #if os(iOS)
            .background(Color(.secondarySystemGroupedBackground))
            #elseif os(macOS)
            .background(Color(.secondarySystemGroupedBackground))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Info Section

    @ViewBuilder
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CSV Format")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Required columns:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                ForEach(["name", "category"], id: \.self) { col in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(col)
                            .font(.caption)
                            .monospaced()
                    }
                }

                Text("Optional columns:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, 4)
                ForEach(["code", "brand", "cost_price", "markup_percent", "part_type", "description", "unit_of_measure"], id: \.self) { col in
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(col)
                            .font(.caption)
                            .monospaced()
                    }
                }
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.secondarySystemGroupedBackground))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data Loading

    @Sendable
    private func loadStats() async {
        isLoading = true
        do {
            guard let db = appCore.db else { return }
            let newStats = try await db.writer.read { dbConnection -> ImportExportStats in
                let parts = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL") ?? 0
                let cats = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM part_categories WHERE deleted_at IS NULL") ?? 0
                let brands = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM brands WHERE deleted_at IS NULL") ?? 0
                let suppliers = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM suppliers WHERE deleted_at IS NULL") ?? 0
                return ImportExportStats(
                    totalParts: parts,
                    totalCategories: cats,
                    totalBrands: brands,
                    totalSuppliers: suppliers
                )
            }
            await MainActor.run {
                stats = newStats
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    // MARK: - Export

    private func exportParts() async {
        exportStatus = .exporting
        do {
            guard let db = appCore.db else { return }
            let csvString = try await db.writer.read { dbConnection -> String in
                let rows = try Row.fetchAll(dbConnection, sql: """
                    SELECT p.name, p.code, pc.name AS category, b.name AS brand,
                           p.company_cost_price, p.company_markup_percent, p.part_type,
                           p.description, p.unit_of_measure
                    FROM parts p
                    LEFT JOIN part_categories pc ON pc.id = p.category_id
                    LEFT JOIN brands b ON b.id = p.brand_id
                    WHERE p.deleted_at IS NULL
                    ORDER BY p.name ASC
                    """)

                var csv = "name,code,category,brand,cost_price,markup_percent,part_type,description,unit_of_measure\n"
                for row in rows {
                    let name: String = row["name"]
                    let code: String? = row["code"]
                    let category: String? = row["category"]
                    let brand: String? = row["brand"]
                    let cost: Double = row["company_cost_price"]
                    let markup: Double = row["company_markup_percent"]
                    let ptype: String = row["part_type"]
                    let desc: String? = row["description"]
                    let uom: String? = row["unit_of_measure"]

                    csv += "\(csvEscapeValue(name)),\(csvEscapeValue(code ?? "")),\(csvEscapeValue(category ?? "")),\(csvEscapeValue(brand ?? "")),"
                    csv += "\(cost),\(markup),\(csvEscapeValue(ptype)),\(csvEscapeValue(desc ?? "")),\(csvEscapeValue(uom ?? ""))\n"
                }
                return csv
            }

            // Write to documents directory
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                await MainActor.run { exportStatus = .error("Cannot access Documents directory") }
                return
            }
            let filename = "parts_export_\(exportDateString()).csv"
            let fileURL = docs.appendingPathComponent(filename)
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)

            await MainActor.run {
                exportStatus = .success("Exported to \(filename)")
            }
            // Reset status after 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run { exportStatus = .idle }
        } catch {
            await MainActor.run {
                exportStatus = .error("Export failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Import

    private func importFromCSV(url: URL) async {
        importStatus = .importing
        do {
            // Start accessing security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard lines.count > 1 else {
                await MainActor.run { importStatus = .error("CSV file is empty or has no data rows.") }
                return
            }

            let headers = parseCSVLine(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            guard let nameIdx = headers.firstIndex(of: "name"),
                  let catIdx = headers.firstIndex(of: "category") else {
                await MainActor.run { importStatus = .error("CSV must have 'name' and 'category' columns.") }
                return
            }

            let codeIdx = headers.firstIndex(of: "code")
            let brandIdx = headers.firstIndex(of: "brand")
            let costIdx = headers.firstIndex(of: "cost_price")
            let markupIdx = headers.firstIndex(of: "markup_percent")
            let typeIdx = headers.firstIndex(of: "part_type")

            guard let db = appCore.db else { return }
            var imported = 0

            for lineIdx in 1..<lines.count {
                let fields = parseCSVLine(lines[lineIdx])
                guard fields.count > max(nameIdx, catIdx) else { continue }

                let partName = fields[nameIdx].trimmingCharacters(in: .whitespaces)
                let catName = fields[catIdx].trimmingCharacters(in: .whitespaces)
                guard !partName.isEmpty, !catName.isEmpty else { continue }

                let code = codeIdx.flatMap { $0 < fields.count ? fields[$0].trimmingCharacters(in: .whitespaces) : nil }
                let brandName = brandIdx.flatMap { $0 < fields.count ? fields[$0].trimmingCharacters(in: .whitespaces) : nil }
                let cost = costIdx.flatMap { $0 < fields.count ? Double(fields[$0].trimmingCharacters(in: .whitespaces)) : nil } ?? 0
                let markup = markupIdx.flatMap { $0 < fields.count ? Double(fields[$0].trimmingCharacters(in: .whitespaces)) : nil } ?? 0
                let partType = typeIdx.flatMap { $0 < fields.count ? fields[$0].trimmingCharacters(in: .whitespaces) : nil } ?? "standard"

                let now = ISO8601DateFormatter().string(from: Date())

                try await db.writer.write { dbConnection in
                    // Find or create category
                    let catId: Int64
                    if let existingCat = try Row.fetchOne(dbConnection, sql: "SELECT id FROM part_categories WHERE name = ? AND deleted_at IS NULL", arguments: [catName]) {
                        catId = existingCat["id"]
                    } else {
                        try dbConnection.execute(
                            sql: "INSERT INTO part_categories (name, sort_order, created_at, updated_at) VALUES (?, 0, ?, ?)",
                            arguments: [catName, now, now]
                        )
                        catId = dbConnection.lastInsertedRowID
                    }

                    // Find or create brand
                    var brandId: Int64? = nil
                    if let bName = brandName, !bName.isEmpty {
                        if let existingBrand = try Row.fetchOne(dbConnection, sql: "SELECT id FROM brands WHERE name = ? AND deleted_at IS NULL", arguments: [bName]) {
                            brandId = existingBrand["id"]
                        } else {
                            try dbConnection.execute(
                                sql: "INSERT INTO brands (name, created_at, updated_at) VALUES (?, ?, ?)",
                                arguments: [bName, now, now]
                            )
                            brandId = dbConnection.lastInsertedRowID
                        }
                    }

                    // Insert part
                    try dbConnection.execute(
                        sql: """
                            INSERT INTO parts (name, code, category_id, brand_id, part_type,
                            company_cost_price, company_markup_percent, created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [partName, code, catId, brandId, partType, cost, markup, now, now]
                    )
                }
                imported += 1
            }

            await loadStats()
            await MainActor.run {
                importStatus = .success("Imported \(imported) parts successfully.")
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run { importStatus = .idle }
        } catch {
            await MainActor.run {
                importStatus = .error("Import failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - CSV Helpers

    private func parseCSVLine(_ line: String) -> [String] {
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
}

// MARK: - CSV Escape (nonisolated free function for Sendable safety)

nonisolated private func csvEscapeValue(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

// MARK: - Free function for export date

private func exportDateString() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HHmmss"
    return formatter.string(from: Date())
}

// MARK: - Types

private struct ImportExportStats {
    var totalParts = 0
    var totalCategories = 0
    var totalBrands = 0
    var totalSuppliers = 0
}

private enum ExportStatus {
    case idle, exporting, success(String), error(String)
}

private enum ImportStatus {
    case idle, importing, success(String), error(String)
}
