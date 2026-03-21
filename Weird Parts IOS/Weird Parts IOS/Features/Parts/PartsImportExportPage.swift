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
    @State private var showImportPreview = false
    @State private var importStatus: ImportStatus = .idle

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading stats...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let error = loadError {
                    ContentUnavailableView {
                        Label("Failed to Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await loadStats() } }
                            .buttonStyle(.bordered)
                    }
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
            allowedContentTypes: [.commaSeparatedText, .plainText],
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
        .sheet(isPresented: $showImportPreview) {
            ImportPreviewSheet(
                preview: $importPreview,
                onConfirm: { Task { await executeImport() } },
                onCancel: {
                    importPreview = nil
                    showImportPreview = false
                }
            )
            .environmentObject(appCore)
        }
        .background(DS.Background.page)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import Parts from CSV")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Import parts with duplicate detection and conflict resolution.")
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
                        Label("Choose CSV File", systemImage: "doc.badge.plus")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)

                case .importing:
                    ProgressView("Importing...")
                        .frame(maxWidth: .infinity)

                case .success(let message):
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
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
                ForEach(["code", "brand", "cost_price", "markup_percent", "part_type", "description", "unit_of_measure", "shelf_location", "bin_location"], id: \.self) { col in
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Export

    private func exportParts() async {
        exportStatus = .exporting
        do {
            guard let service = appCore.partsService else { return }
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
                exportStatus = .error("Export failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Import Parsing

    private func parseImportFile(url: URL) async {
        importStatus = .importing
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard lines.count > 1 else {
                await MainActor.run { importStatus = .error("CSV file is empty or has no data rows.") }
                return
            }

            let headers = parseCSVLine(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            guard let nameIdx = headers.firstIndex(of: "name") else {
                await MainActor.run { importStatus = .error("CSV must have a 'name' column.") }
                return
            }

            let codeIdx = headers.firstIndex(of: "code")
            let catIdx = headers.firstIndex(of: "category")
            let brandIdx = headers.firstIndex(of: "brand")

            guard let service = appCore.partsService else {
                await MainActor.run { importStatus = .error("Parts service not available") }
                return
            }

            var preview = ImportPreview(totalRows: lines.count - 1)

            for lineIdx in 1..<lines.count {
                let fields = parseCSVLine(lines[lineIdx])
                guard fields.count > nameIdx else {
                    preview.errors.append(ImportError(rowNumber: lineIdx + 1, message: "Not enough columns"))
                    continue
                }

                let partName = fields[nameIdx].trimmingCharacters(in: .whitespaces)
                guard !partName.isEmpty else {
                    preview.errors.append(ImportError(rowNumber: lineIdx + 1, message: "Empty name"))
                    continue
                }

                let code = codeIdx.flatMap { $0 < fields.count ? fields[$0].trimmingCharacters(in: .whitespaces) : nil }
                let category = catIdx.flatMap { $0 < fields.count ? fields[$0].trimmingCharacters(in: .whitespaces) : nil }
                let brand = brandIdx.flatMap { $0 < fields.count ? fields[$0].trimmingCharacters(in: .whitespaces) : nil }

                // Build fields map for all other columns
                var fieldsMap: [String: String] = [:]
                for (i, header) in headers.enumerated() {
                    guard i < fields.count else { break }
                    if header != "name" && header != "code" && header != "category" && header != "brand" {
                        let val = fields[i].trimmingCharacters(in: .whitespaces)
                        if !val.isEmpty { fieldsMap[header] = val }
                    }
                }

                let parsed = ParsedRow(name: partName, code: code, category: category, brand: brand, fields: fieldsMap)

                // Duplicate detection: by code first, then by name
                var existingPart: Part?
                if let c = code, !c.isEmpty {
                    existingPart = try? service.findPartByCode(c)
                }
                if existingPart == nil {
                    existingPart = try? service.findPartByName(partName)
                }

                if let existing = existingPart {
                    preview.conflicts.append(ConflictRow(parsedRow: parsed, existingPart: existing))
                } else {
                    preview.newParts.append(parsed)
                }
            }

            await MainActor.run {
                self.importPreview = preview
                self.showImportPreview = true
                self.importStatus = .idle
            }
        } catch {
            await MainActor.run {
                importStatus = .error("Failed to read file: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Import Execution

    private func executeImport() async {
        guard let preview = importPreview,
              let service = appCore.partsService else { return }
        await MainActor.run {
            showImportPreview = false
            importStatus = .importing
        }
        var created = 0, updated = 0, skipped = 0, errors = 0

        // Create new parts
        for row in preview.newParts {
            do {
                let catId = try service.findOrCreateCategory(name: row.category ?? "Uncategorized")
                var brandId: Int64? = nil
                if let bName = row.brand, !bName.isEmpty {
                    brandId = try service.findOrCreateBrand(name: bName)
                }

                let cost = row.fields["cost_price"].flatMap(Double.init) ?? 0
                let markup = row.fields["markup_percent"].flatMap(Double.init) ?? 0
                let partType = row.fields["part_type"] ?? "general"
                let desc = row.fields["description"]
                let uom = row.fields["unit_of_measure"]
                let shelf = row.fields["shelf_location"]
                let bin = row.fields["bin_location"]

                _ = try service.createPart(
                    categoryId: catId,
                    name: row.name,
                    partType: partType,
                    code: row.code,
                    description: desc,
                    brandId: brandId,
                    unitOfMeasure: uom,
                    companyCostPrice: cost,
                    companyMarkupPercent: markup,
                    shelfLocation: shelf,
                    binLocation: bin
                )
                created += 1
            } catch {
                errors += 1
            }
        }

        // Update conflicts marked as "update"
        for conflict in preview.conflicts where conflict.resolution == .update {
            do {
                guard let existingId = conflict.existingPart.id else { continue }
                let row = conflict.parsedRow

                var catId: Int64? = nil
                if let catName = row.category, !catName.isEmpty {
                    catId = try service.findOrCreateCategory(name: catName)
                }
                var brandId: Int64? = nil
                if let bName = row.brand, !bName.isEmpty {
                    brandId = try service.findOrCreateBrand(name: bName)
                }

                try service.updatePart(
                    id: existingId,
                    name: row.name,
                    code: row.code,
                    categoryId: catId,
                    brandId: brandId,
                    unitOfMeasure: row.fields["unit_of_measure"],
                    companyCostPrice: row.fields["cost_price"].flatMap(Double.init),
                    companyMarkupPercent: row.fields["markup_percent"].flatMap(Double.init),
                    shelfLocation: row.fields["shelf_location"],
                    binLocation: row.fields["bin_location"]
                )
                updated += 1
            } catch {
                errors += 1
            }
        }

        skipped = preview.conflicts.filter { $0.resolution == .skip || $0.resolution == .ask }.count

        await MainActor.run {
            importPreview = nil
            var msg = "Created \(created)"
            if updated > 0 { msg += ", Updated \(updated)" }
            if skipped > 0 { msg += ", Skipped \(skipped)" }
            if errors > 0 { msg += ", \(errors) error(s)" }
            importStatus = .success(msg)
        }
        await loadStats()
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

private struct ParsedRow {
    let name: String
    let code: String?
    let category: String?
    let brand: String?
    let fields: [String: String]
}

private struct ImportPreview {
    var newParts: [ParsedRow] = []
    var conflicts: [ConflictRow] = []
    var errors: [ImportError] = []
    var totalRows: Int = 0
}

private struct ConflictRow: Identifiable {
    let id = UUID()
    let parsedRow: ParsedRow
    let existingPart: Part
    var resolution: ConflictResolution = .ask
}

private enum ConflictResolution {
    case ask, update, skip
}

private struct ImportError: Identifiable {
    let id = UUID()
    let rowNumber: Int
    let message: String
}

// MARK: - Import Preview Sheet

private struct ImportPreviewSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Binding var preview: ImportPreview?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var previewBinding: Binding<ImportPreview> {
        Binding(
            get: { preview ?? ImportPreview() },
            set: { preview = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if preview != nil {
                    ImportPreviewContent(preview: previewBinding, onConfirm: onConfirm)
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

    private var updateCount: Int {
        preview.conflicts.filter { $0.resolution == .update }.count
    }

    private var confirmLabel: String {
        let newCount = preview.newParts.count
        let updCount = updateCount
        if updCount > 0 {
            return "Import \(newCount) New + \(updCount) Updates"
        }
        return "Import \(newCount) New Parts"
    }

    var body: some View {
        List {
            // Summary
            Section {
                HStack {
                    Label("\(preview.newParts.count) new", systemImage: "plus.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Label("\(preview.conflicts.count) conflicts", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Label("\(preview.errors.count) errors", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .font(.subheadline)
            } header: {
                Text("Summary — \(preview.totalRows) rows")
            }

            // New parts
            if !preview.newParts.isEmpty {
                Section {
                    ForEach(Array(preview.newParts.prefix(20).enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            HStack(spacing: 8) {
                                if let code = row.code, !code.isEmpty {
                                    Text(code).font(.caption).foregroundStyle(.secondary)
                                }
                                if let cat = row.category {
                                    Text(cat).font(.caption).foregroundStyle(.blue)
                                }
                                if let brand = row.brand {
                                    Text(brand).font(.caption).foregroundStyle(.purple)
                                }
                            }
                        }
                    }
                    if preview.newParts.count > 20 {
                        Text("+ \(preview.newParts.count - 20) more...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("New Parts")
                }
            }

            // Conflicts
            if !preview.conflicts.isEmpty {
                Section {
                    // Bulk actions
                    HStack {
                        Button("Update All") {
                            for i in preview.conflicts.indices {
                                preview.conflicts[i].resolution = .update
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)

                        Button("Skip All") {
                            for i in preview.conflicts.indices {
                                preview.conflicts[i].resolution = .skip
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    ForEach($preview.conflicts) { $conflict in
                        conflictRow(conflict: $conflict)
                    }
                } header: {
                    Text("Conflicts — Duplicates Found")
                }
            }

            // Errors
            if !preview.errors.isEmpty {
                Section {
                    ForEach(preview.errors) { err in
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
                    Text("Errors (will be skipped)")
                }
            }

            // Confirm button
            Section {
                Button(action: onConfirm) {
                    Text(confirmLabel)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .disabled(preview.newParts.isEmpty && updateCount == 0)
            }
        }
    }

    @ViewBuilder
    private func conflictRow(conflict: Binding<ConflictRow>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Part name + code
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

            // Side-by-side comparison
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(conflict.wrappedValue.existingPart.name)
                        .font(.caption)
                    Text(conflict.wrappedValue.existingPart.code ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CSV")
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

            // Action buttons
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
    private func resolutionBadge(_ resolution: ConflictResolution) -> some View {
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
