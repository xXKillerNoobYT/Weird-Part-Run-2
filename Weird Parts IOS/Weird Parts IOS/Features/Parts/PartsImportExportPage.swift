import SwiftUI
import WiredPartCore
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Import/Export page for parts data.
///
/// Provides selective CSV export with field group checkboxes,
/// and a CSV importer with preview/conflict resolution before committing.
struct PartsImportExportPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var stats: PartsService.ImportExportStats?
    @State private var isLoading = true
    @State private var loadError: String?

    // Export
    @State private var selectedGroups: Set<PartsService.ExportFieldGroup> = [.hierarchy]
    @State private var exportStatus: ExportStatus = .idle
    @State private var showExportConfirm = false

    // Import
    @State private var showFileImporter = false
    @State private var importPreview: ImportPreview?
    private enum ActiveSheet: String, Identifiable {
        case importPreview
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var importStatus: ImportStatus = .idle

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                OnboardingBanner(pageId: "parts-import-export")

                if isLoading {
                    ProgressView("Loading stats...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let error = loadError {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Failed to Load",
                        message: error,
                        actionLabel: "Retry"
                    ) {
                        Task { await loadStats() }
                    }
                    .frame(minHeight: 320)
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
            Button("Export \(stats?.totalParts ?? 0) Parts (CSV)") {
                Task { await exportParts() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will export \(stats?.totalParts ?? 0) parts to a CSV file with \(selectedGroups.count) field group(s) selected.")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: importAllowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await parseImportFile(url: url) }
                }
            case .failure:
                importStatus = .error("Failed to select file.")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .importPreview:
                ImportPreviewSheet(
                    preview: $importPreview,
                    onConfirm: { Task { await executeImport() } },
                    onApplyMapping: { reapplyImportMapping($0) },
                    onCancel: {
                        importPreview = nil
                        activeSheet = nil
                    }
                )
                .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Import/Export Help",
                    sections: [
                        ("Exporting", "Export your parts catalog to CSV. Select which field groups to include: hierarchy, pricing, stock levels, and more."),
                        ("Importing", "Import parts from a CSV file. Preview changes before committing. Conflicts are highlighted for review."),
                        ("Tips", "Exported files can be edited in Excel or Google Sheets and re-imported. Use the same column headers for a smooth import.")
                    ]
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .background(DS.Background.page)
        .task {
            await loadStats()
            appCore.onboardingManager?.markCompleted("import-view")
        }
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
                statCard(title: "Total Parts", value: "\(stats?.totalParts ?? 0)", icon: "wrench.and.screwdriver.fill", color: .blue)
                statCard(title: "Categories", value: "\(stats?.totalCategories ?? 0)", icon: "folder.fill", color: .orange)
                statCard(title: "Brands", value: "\(stats?.totalBrands ?? 0)", icon: "tag.fill", color: .purple)
                statCard(title: "Suppliers", value: "\(stats?.totalSuppliers ?? 0)", icon: "building.2.fill", color: .green)
            }
        }
    }

    @ViewBuilder
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Export Section

    private var selectAll: Bool {
        get { selectedGroups.count == PartsService.ExportFieldGroup.allCases.count }
        set {
            if newValue {
                selectedGroups = Set(PartsService.ExportFieldGroup.allCases)
            } else {
                selectedGroups.removeAll()
            }
        }
    }

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
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Parts to CSV")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Select which field groups to include in the export.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                VStack(spacing: 4) {
                    Toggle("Select All", isOn: Binding(
                        get: { selectAll },
                        set: { newValue in
                            if newValue {
                                selectedGroups = Set(PartsService.ExportFieldGroup.allCases)
                            } else {
                                selectedGroups.removeAll()
                            }
                        }
                    ))
                    .fontWeight(.medium)

                    Divider()

                    ForEach(PartsService.ExportFieldGroup.allCases, id: \.self) { group in
                        Toggle(group.displayName, isOn: Binding(
                            get: { selectedGroups.contains(group) },
                            set: { isOn in
                                if isOn {
                                    selectedGroups.insert(group)
                                } else {
                                    selectedGroups.remove(group)
                                }
                            }
                        ))
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)

                switch exportStatus {
                case .idle:
                    Button {
                        showExportConfirm = true
                    } label: {
                        Label("Export \(stats?.totalParts ?? 0) Parts to CSV", systemImage: "arrow.down.doc.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
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
                            .accessibilityHidden(true)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)

                case .error(let message):
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
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
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import Parts from CSV or Excel")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Choose CSV/XLSX, review detected mappings, then resolve duplicates before commit.")
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
                        Label("Choose CSV or XLSX File", systemImage: "doc.badge.plus")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)

                    HStack(spacing: 8) {
                        Image(systemName: "doc.richtext")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("PDF import is planned and will unlock after the PDF/OCR backend lands.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                case .importing:
                    ProgressView("Importing...")
                        .frame(maxWidth: .infinity)

                case .success(let message):
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                        Button("Import Another") {
                            importStatus = .idle
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity)

                case .error(let message):
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .accessibilityHidden(true)
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        Button("Try Again") {
                            importStatus = .idle
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Info Section

    @ViewBuilder
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CSV/XLSX Format")
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
                            .accessibilityHidden(true)
                        Text(col)
                            .font(.caption)
                            .monospaced()
                    }
                }

                Text("Optional columns:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, 4)
                ForEach(["code", "brand", "cost_price", "markup_percent", "part_type", "description", "unit_of_measure", "shelf_location", "bin_location"], id: \.self) { col in
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text(col)
                            .font(.caption)
                            .monospaced()
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Import Types

    private var importAllowedContentTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText]
        if let xlsx = UTType(filenameExtension: "xlsx") {
            types.append(xlsx)
        }
        return types
    }

    // MARK: - Data Loading

    @Sendable
    private func loadStats() async {
        isLoading = stats == nil
        loadError = nil
        do {
            guard let service = appCore.partsService else {
                loadError = "Parts service not available"
                isLoading = false
                return
            }
            let newStats = try service.getImportExportStats()
            await MainActor.run {
                stats = newStats
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load import data")
                isLoading = false
            }
        }
    }

    // MARK: - Export

    private func exportParts() async {
        exportStatus = .exporting
        do {
            guard let service = appCore.partsService else {
                loadError = "Parts service not available"
                await MainActor.run { exportStatus = .error("Service not available") }
                return
            }
            let csvString = try service.exportPartsCSV(groups: selectedGroups)

            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                await MainActor.run { exportStatus = .error("Cannot access Documents directory") }
                return
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let filename = "parts_export_\(formatter.string(from: Date())).csv"
            let fileURL = docs.appendingPathComponent(filename)
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)

            await MainActor.run {
                exportStatus = .success("Exported to \(filename)")
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run { exportStatus = .idle }
        } catch {
            await MainActor.run {
                exportStatus = .error(userFriendlyError(error, context: "export parts"))
            }
        }
    }

    // MARK: - Import Parsing

    private func parseImportFile(url: URL) async {
        importStatus = .importing
        do {
            guard let service = appCore.partsService else {
                await MainActor.run { importStatus = .error("Validation error: parts service is not available.") }
                return
            }

            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let filename = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            if ext == "xlsx" {
                let data = try Data(contentsOf: url)
                var servicePreview = try service.previewPartsImportXLSX(data)
                servicePreview.source?.filename = filename
                let preview = ImportPreview(
                    servicePreview: servicePreview,
                    sourceKind: .xlsx,
                    filename: filename,
                    sheetName: servicePreview.source?.sheetName,
                    sourceColumns: canonicalColumns(from: servicePreview),
                    columnMappings: canonicalColumns(from: servicePreview).map { ColumnMapping(sourceColumn: $0, target: ColumnMappingTarget(rawValue: $0) ?? .ignore, confidence: .exact) },
                    sourceRows: [],
                    mappingError: nil
                )
                await MainActor.run {
                    self.importPreview = preview
                    self.activeSheet = .importPreview
                    self.importStatus = .idle
                }
                return
            }

            guard ext == "csv" || ext == "txt" || ext.isEmpty else {
                await MainActor.run { importStatus = .error("Parse error: choose a CSV or XLSX file. PDF import is planned but not available yet.") }
                return
            }

            let content = try String(contentsOf: url, encoding: .utf8)
            let sourceRows = parseCSVRows(content)
            guard sourceRows.count > 1 else {
                await MainActor.run { importStatus = .error("Parse error: CSV file is empty or has no data rows.") }
                return
            }
            let sourceColumns = sourceRows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            var preview = ImportPreview(
                servicePreview: PartsService.PartsImportPreview(totalRows: sourceRows.count - 1),
                sourceKind: .csv,
                filename: filename,
                sheetName: nil,
                sourceColumns: sourceColumns,
                columnMappings: inferColumnMappings(sourceColumns),
                sourceRows: sourceRows,
                mappingError: nil
            )
            try applyMapping(to: &preview, service: service)
            await MainActor.run {
                self.importPreview = preview
                self.activeSheet = .importPreview
                self.importStatus = .idle
            }
        } catch {
            await MainActor.run {
                importStatus = .error("Parse error: \(userFriendlyError(error, context: "read import file"))")
            }
        }
    }

    private func applyMapping(to preview: inout ImportPreview, service: PartsService) throws {
        guard preview.sourceKind == .csv else { return }
        let selectedTargets = preview.columnMappings.filter { $0.target != .ignore }.map(\.target)
        let missingRequired = ColumnMappingTarget.required.filter { !selectedTargets.contains($0) }
        guard missingRequired.isEmpty else {
            preview.mappingError = "Mapping error: map a source column to \(missingRequired.map(\.displayName).joined(separator: " and "))."
            preview.servicePreview = PartsService.PartsImportPreview(totalRows: max(0, preview.sourceRows.count - 1))
            return
        }

        let duplicateTargets = Dictionary(grouping: selectedTargets, by: { $0 }).filter { $0.value.count > 1 }.map(\.key)
        guard duplicateTargets.isEmpty else {
            preview.mappingError = "Mapping error: each canonical field can only be mapped once (duplicate: \(duplicateTargets.map(\.displayName).joined(separator: ", ")))."
            preview.servicePreview = PartsService.PartsImportPreview(totalRows: max(0, preview.sourceRows.count - 1))
            return
        }

        preview.mappingError = nil
        let selectedMappings = preview.columnMappings.filter { $0.target != .ignore }
        let header = selectedMappings.map { $0.target.rawValue }
        let rows = preview.sourceRows.dropFirst().map { row in
            selectedMappings.map { mapping -> String in
                guard let sourceIndex = preview.sourceColumns.firstIndex(of: mapping.sourceColumn), sourceIndex < row.count else { return "" }
                return row[sourceIndex]
            }
        }
        var csv = encodeCSVRow(header)
        for row in rows {
            csv += "\n" + encodeCSVRow(row)
        }
        var servicePreview = try service.previewPartsImportCSV(csv)
        servicePreview.source?.filename = preview.filename
        preview.servicePreview = servicePreview
    }

    private func reapplyImportMapping(_ updatedPreview: ImportPreview) {
        guard let service = appCore.partsService else {
            importPreview?.mappingError = "Validation error: parts service is not available."
            return
        }
        var preview = updatedPreview
        do {
            try applyMapping(to: &preview, service: service)
        } catch {
            preview.mappingError = "Validation error: \(userFriendlyError(error, context: "preview mapped import"))"
        }
        importPreview = preview
    }

    private func canonicalColumns(from preview: PartsService.PartsImportPreview) -> [String] {
        var columns: [String] = ["name", "category"]
        for row in preview.newParts {
            if row.code != nil { columns.append("code") }
            if row.brand != nil { columns.append("brand") }
            columns.append(contentsOf: row.fields.keys)
        }
        for conflict in preview.conflicts {
            let row = conflict.parsedRow
            if row.code != nil { columns.append("code") }
            if row.brand != nil { columns.append("brand") }
            columns.append(contentsOf: row.fields.keys)
        }
        return Array(Set(columns)).sorted()
    }

    private func inferColumnMappings(_ columns: [String]) -> [ColumnMapping] {
        columns.map { column in
            let normalized = normalizeColumn(column)
            if let exact = ColumnMappingTarget.allCases.first(where: { normalizeColumn($0.rawValue) == normalized }) {
                return ColumnMapping(sourceColumn: column, target: exact, confidence: .exact)
            }
            if let alias = ColumnMappingTarget.allCases.first(where: { $0.aliases.map(normalizeColumn).contains(normalized) }) {
                return ColumnMapping(sourceColumn: column, target: alias, confidence: .alias)
            }
            return ColumnMapping(sourceColumn: column, target: .ignore, confidence: .unmapped)
        }
    }

    private func normalizeColumn(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func executeImport() async {
        guard let preview = importPreview,
              let service = appCore.partsService else { return }
        await MainActor.run {
            activeSheet = nil
            importStatus = .importing
        }
        do {
            guard preview.mappingError == nil else {
                await MainActor.run { importStatus = .error(preview.mappingError ?? "Mapping error: review source column mappings.") }
                return
            }
            guard preview.servicePreview.errors.isEmpty else {
                let first = preview.servicePreview.errors[0]
                await MainActor.run { importStatus = .error("Validation error: row \(first.rowNumber): \(first.message)") }
                return
            }
            let result = try service.commitPartsImportCSV(preview.servicePreview)
            await MainActor.run {
                importPreview = nil
                var msg = "Created \(result.created)"
                if result.updated > 0 { msg += ", Updated \(result.updated)" }
                if result.skipped > 0 { msg += ", Skipped \(result.skipped)" }
                importStatus = .success(msg)
            }
            await loadStats()
        } catch {
            await MainActor.run {
                importStatus = .error("Conflict/import error: \(userFriendlyError(error, context: "commit parts import"))")
            }
        }
    }

    // MARK: - CSV Helpers

    private func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        while let char = iterator.next() {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if char == "\n" && !inQuotes {
                row.append(field)
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    rows.append(row)
                }
                row = []
                field = ""
            } else if char != "\r" || inQuotes {
                field.append(char)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.append(row)
        }
        return rows
    }

    private func encodeCSVRow(_ fields: [String]) -> String {
        fields.map { value in
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
                return "\"\(escaped)\""
            }
            return escaped
        }.joined(separator: ",")
    }

}

// MARK: - Export Field Group Display Names

extension PartsService.ExportFieldGroup {
    var displayName: String {
        switch self {
        case .hierarchy: return "Hierarchy (category, style, type, brand, color)"
        case .pricing: return "Pricing (cost, markup, sell price)"
        case .stockLevels: return "Stock Levels (min, target, max, current)"
        case .forecast: return "Forecast (ADU, days until low, suggested order)"
        case .details: return "Details (description, UOM, shelf/bin location)"
        }
    }
}

// MARK: - Types

private enum ExportStatus {
    case idle, exporting, success(String), error(String)
}

private enum ImportStatus {
    case idle, importing, success(String), error(String)
}

private enum ImportSourceKind: String {
    case csv
    case xlsx

    var displayName: String { rawValue.uppercased() }
}

private enum ColumnMappingTarget: String, CaseIterable, Identifiable {
    case ignore
    case name
    case category
    case code
    case brand
    case costPrice = "cost_price"
    case markupPercent = "markup_percent"
    case partType = "part_type"
    case description
    case unitOfMeasure = "unit_of_measure"
    case shelfLocation = "shelf_location"
    case binLocation = "bin_location"

    var id: String { rawValue }

    static let required: [ColumnMappingTarget] = [.name, .category]

    var displayName: String {
        switch self {
        case .ignore: return "Ignore"
        case .name: return "Part name"
        case .category: return "Category"
        case .code: return "Code"
        case .brand: return "Brand"
        case .costPrice: return "Cost price"
        case .markupPercent: return "Markup percent"
        case .partType: return "Part type"
        case .description: return "Description"
        case .unitOfMeasure: return "Unit of measure"
        case .shelfLocation: return "Shelf location"
        case .binLocation: return "Bin location"
        }
    }

    var aliases: [String] {
        switch self {
        case .ignore: return []
        case .name: return ["part name", "item", "item name", "description name"]
        case .category: return ["category name", "group", "class"]
        case .code: return ["part code", "sku", "item code", "part number", "part_no"]
        case .brand: return ["manufacturer", "make", "vendor brand"]
        case .costPrice: return ["cost", "unit cost", "company cost", "price"]
        case .markupPercent: return ["markup", "markup %", "margin"]
        case .partType: return ["type", "kind"]
        case .description: return ["notes", "details"]
        case .unitOfMeasure: return ["uom", "unit", "units"]
        case .shelfLocation: return ["shelf", "shelf loc"]
        case .binLocation: return ["bin", "bin loc"]
        }
    }
}

private enum ColumnMappingConfidence: String {
    case exact
    case alias
    case unmapped

    var label: String {
        switch self {
        case .exact: return "exact"
        case .alias: return "suggested"
        case .unmapped: return "unmapped"
        }
    }
}

private struct ColumnMapping: Identifiable {
    let id = UUID()
    let sourceColumn: String
    var target: ColumnMappingTarget
    var confidence: ColumnMappingConfidence
}

private struct ImportPreview {
    var servicePreview: PartsService.PartsImportPreview
    var sourceKind: ImportSourceKind
    var filename: String
    var sheetName: String?
    var sourceColumns: [String]
    var columnMappings: [ColumnMapping]
    var sourceRows: [[String]]
    var mappingError: String?

    var totalRows: Int { servicePreview.totalRows }
}

// MARK: - Import Preview Sheet

private struct ImportPreviewSheet: View {
    @Binding var preview: ImportPreview?
    let onConfirm: () -> Void
    let onApplyMapping: (ImportPreview) -> Void
    let onCancel: () -> Void

    private var previewBinding: Binding<ImportPreview> {
        Binding(
            get: { preview ?? ImportPreview(servicePreview: PartsService.PartsImportPreview(), sourceKind: .csv, filename: "", sheetName: nil, sourceColumns: [], columnMappings: [], sourceRows: [], mappingError: nil) },
            set: { preview = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if preview != nil {
                    ImportPreviewContent(preview: previewBinding, onConfirm: onConfirm, onApplyMapping: onApplyMapping)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Import Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

private struct ImportPreviewContent: View {
    @Binding var preview: ImportPreview
    let onConfirm: () -> Void
    let onApplyMapping: (ImportPreview) -> Void

    private var updateCount: Int {
        preview.servicePreview.conflicts.filter { $0.resolution == .update }.count
    }

    private var confirmLabel: String {
        let newCount = preview.servicePreview.newParts.count
        let updCount = updateCount
        if updCount > 0 {
            return "Import \(newCount) New + \(updCount) Updates"
        }
        return "Import \(newCount) New Parts"
    }

    var body: some View {
        List {
            sourceMetadataSection
            mappingSection
            summarySection
            newPartsSection
            conflictsSection
            errorsSection
            confirmSection
        }
    }

    private var sourceMetadataSection: some View {
        Section {
            LabeledContent("Source", value: preview.sourceKind.displayName)
            LabeledContent("Filename", value: preview.filename)
            if let sheetName = preview.sheetName, !sheetName.isEmpty {
                LabeledContent("Sheet", value: sheetName)
            }
            LabeledContent("Rows", value: "\(preview.totalRows)")
        } header: {
            Text("Source")
        }
    }

    private var mappingSection: some View {
        Section {
            if preview.columnMappings.isEmpty {
                Text("Using canonical \(preview.sourceKind.displayName) headers from the backend preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($preview.columnMappings) { $mapping in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(mapping.sourceColumn)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text(mapping.confidence.label)
                                .font(.caption2)
                                .foregroundStyle(mapping.confidence == .unmapped ? .orange : .secondary)
                        }
                        Picker("Canonical field", selection: $mapping.target) {
                            ForEach(ColumnMappingTarget.allCases) { target in
                                Text(target.displayName).tag(target)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                Button("Apply Mapping Preview") {
                    onApplyMapping(preview)
                }
                .buttonStyle(.bordered)
            }
            if let mappingError = preview.mappingError {
                Text(mappingError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Column Mapping")
        } footer: {
            Text("Map source columns to canonical parts fields before validation. Ambiguous or unmapped columns can be corrected here; ignored columns are not imported.")
        }
    }

    private var summarySection: some View {
        Section {
            HStack {
                Label("\(preview.servicePreview.newParts.count) new", systemImage: "plus.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Label("\(preview.servicePreview.conflicts.count) conflicts", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Label("\(preview.servicePreview.errors.count) errors", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .font(.subheadline)
        } header: {
            Text("Summary — \(preview.totalRows) rows")
        }
    }

    @ViewBuilder
    private var newPartsSection: some View {
        if !preview.servicePreview.newParts.isEmpty {
            Section {
                ForEach(Array(preview.servicePreview.newParts.prefix(20).enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack(spacing: 8) {
                            if let code = row.code, !code.isEmpty {
                                Text(code).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(row.category).font(.caption).foregroundStyle(.blue)
                            if let brand = row.brand {
                                Text(brand).font(.caption).foregroundStyle(.purple)
                            }
                        }
                    }
                }
                if preview.servicePreview.newParts.count > 20 {
                    Text("+ \(preview.servicePreview.newParts.count - 20) more...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("New Parts")
            }
        }
    }

    @ViewBuilder
    private var conflictsSection: some View {
        if !preview.servicePreview.conflicts.isEmpty {
            Section {
                HStack {
                    Button("Update All") {
                        for i in preview.servicePreview.conflicts.indices {
                            preview.servicePreview.conflicts[i].resolution = .update
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button("Skip All") {
                        for i in preview.servicePreview.conflicts.indices {
                            preview.servicePreview.conflicts[i].resolution = .skip
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
                .frame(maxWidth: .infinity)

                ForEach($preview.servicePreview.conflicts, id: \.existingPartId) { $conflict in
                    conflictRow(conflict: $conflict)
                }
            } header: {
                Text("Conflicts — Duplicates Found")
            } footer: {
                Text("Conflict errors are handled separately from parse, mapping, and validation errors. Choose update or skip before committing.")
            }
        }
    }

    @ViewBuilder
    private var errorsSection: some View {
        if !preview.servicePreview.errors.isEmpty {
            Section {
                ForEach(Array(preview.servicePreview.errors.enumerated()), id: \.offset) { _, err in
                    HStack {
                        Text("Row \(err.rowNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(err.message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Validation Errors (will be skipped)")
            }
        }
    }

    private var confirmSection: some View {
        Section {
            Button(action: onConfirm) {
                Text(confirmLabel)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .disabled(preview.mappingError != nil || !preview.servicePreview.errors.isEmpty || (preview.servicePreview.newParts.isEmpty && updateCount == 0))
        }
    }

    @ViewBuilder
    private func conflictRow(conflict: Binding<PartsService.PartsImportConflict>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.wrappedValue.parsedRow.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let code = conflict.wrappedValue.parsedRow.code, !code.isEmpty {
                        Text("Code: \(code)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                resolutionBadge(conflict.wrappedValue.resolution)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(conflict.wrappedValue.existingPartName)
                        .font(.caption)
                    Text(conflict.wrappedValue.existingPartCode ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.sourceKind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(conflict.wrappedValue.parsedRow.name)
                        .font(.caption)
                    Text(conflict.wrappedValue.parsedRow.code ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("Update") {
                    conflict.wrappedValue.resolution = .update
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .font(.caption)

                Button("Skip") {
                    conflict.wrappedValue.resolution = .skip
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func resolutionBadge(_ resolution: PartsService.PartsImportConflictResolution) -> some View {
        switch resolution {
        case .ask:
            Text("UNRESOLVED")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.2))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        case .update:
            Text("UPDATE")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        case .skip:
            Text("SKIP")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }
}
