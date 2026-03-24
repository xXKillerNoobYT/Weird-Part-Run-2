# 24A — Import/Export Page Redesign

> **Chain position:** **24A** (standalone — finishes Parts section)
> **Prerequisite:** None
> **Plan:** `docs/plans/ios-import-export-page.md`
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding.

## Context

The Import/Export page has raw SQL (`import GRDB`), platform guards, silent error handling, no duplicate detection on import, no field selection on export, and no import preview. This prompt fixes all of it in one pass since the page is self-contained.

**Files to read first:**
- `docs/plans/ios-import-export-page.md` — full design spec
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsImportExportPage.swift` — current page
- `core/Sources/WiredPartCore/Services/PartsService.swift` — check for existing export/import methods
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift` — Part model fields

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsImportExportPage.swift` — full rewrite
- `core/Sources/WiredPartCore/Services/PartsService.swift` — add service methods

## Task

### Step 1: Add service methods to PartsService

Add a new section for import/export:

```swift
// MARK: - 9. Import / Export

/// Get catalog stats for the import/export page.
public struct CatalogStats: Sendable {
    public let totalParts: Int
    public let totalCategories: Int
    public let totalBrands: Int
    public let totalSuppliers: Int
}

public func getCatalogStats() throws -> CatalogStats {
    try db.writer.read { dbConn in
        let parts = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL") ?? 0
        let cats = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM part_categories WHERE deleted_at IS NULL") ?? 0
        let brands = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM brands WHERE deleted_at IS NULL") ?? 0
        let suppliers = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM suppliers WHERE deleted_at IS NULL") ?? 0
        return CatalogStats(totalParts: parts, totalCategories: cats, totalBrands: brands, totalSuppliers: suppliers)
    }
}

/// Export field groups.
public enum ExportFieldGroup: String, CaseIterable, Sendable {
    case hierarchy, pricing, stockLevels, forecast, details
}

/// Export parts to CSV string with selected field groups.
/// Basic fields (name, code) are always included.
public func exportPartsCSV(groups: Set<ExportFieldGroup>) throws -> String {
    try db.writer.read { dbConn in
        // Build SELECT columns
        var columns = ["p.name", "p.code"]
        var headers = ["name", "code"]

        if groups.contains(.hierarchy) {
            columns += ["pc.name AS category", "ps.name AS style", "pt.name AS part_type_name", "b.name AS brand", "pco.name AS color"]
            headers += ["category", "style", "type", "brand", "color"]
        }
        if groups.contains(.pricing) {
            columns += ["p.company_cost_price", "p.company_markup_percent", "p.company_sell_price"]
            headers += ["cost_price", "markup_percent", "sell_price"]
        }
        if groups.contains(.stockLevels) {
            columns += ["p.min_stock_level", "p.target_stock_level", "p.max_stock_level",
                         "COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) AS current_stock"]
            headers += ["min_stock", "target_stock", "max_stock", "current_stock"]
        }
        if groups.contains(.forecast) {
            columns += ["p.forecast_adu_30", "p.forecast_adu_90", "p.forecast_days_until_low", "p.forecast_suggested_order"]
            headers += ["forecast_adu_30", "forecast_adu_90", "forecast_days_until_low", "forecast_suggested_order"]
        }
        if groups.contains(.details) {
            columns += ["p.description", "p.unit_of_measure", "p.part_type", "p.shelf_location", "p.bin_location"]
            headers += ["description", "unit_of_measure", "part_type", "shelf_location", "bin_location"]
        }

        let sql = """
            SELECT \(columns.joined(separator: ", "))
            FROM parts p
            LEFT JOIN part_categories pc ON pc.id = p.category_id
            LEFT JOIN part_styles ps ON ps.id = p.style_id
            LEFT JOIN part_types pt ON pt.id = p.type_id
            LEFT JOIN brands b ON b.id = p.brand_id
            LEFT JOIN part_colors pco ON pco.id = p.color_id
            WHERE p.deleted_at IS NULL
            ORDER BY p.name ASC
            """

        let rows = try Row.fetchAll(dbConn, sql: sql)
        var csv = headers.joined(separator: ",") + "\n"

        for row in rows {
            var values: [String] = []
            for header in headers {
                let colName = header == "type" ? "part_type_name" : header
                if let strVal: String = row[colName] {
                    values.append(csvEscape(strVal))
                } else if let dblVal: Double = row[colName] {
                    values.append(String(dblVal))
                } else if let intVal: Int = row[colName] {
                    values.append(String(intVal))
                } else {
                    values.append("")
                }
            }
            csv += values.joined(separator: ",") + "\n"
        }
        return csv
    }
}

private func csvEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

/// Find a part by code (exact match) for duplicate detection during import.
public func findPartByCode(_ code: String) throws -> Part? {
    try db.writer.read { dbConn in
        try Part.fetchOne(dbConn, sql: """
            SELECT * FROM parts WHERE code = ? AND deleted_at IS NULL
            """, arguments: [code])
    }
}

/// Find a part by name (case-insensitive) for duplicate detection during import.
public func findPartByName(_ name: String) throws -> Part? {
    try db.writer.read { dbConn in
        try Part.fetchOne(dbConn, sql: """
            SELECT * FROM parts WHERE LOWER(name) = LOWER(?) AND deleted_at IS NULL
            """, arguments: [name])
    }
}

/// Find or create a category by name. Returns the category ID.
public func findOrCreateCategory(name: String) throws -> Int64 {
    try db.writer.write { dbConn in
        if let existing = try Row.fetchOne(dbConn, sql:
            "SELECT id FROM part_categories WHERE name = ? AND deleted_at IS NULL",
            arguments: [name]) {
            return existing["id"]
        }
        try dbConn.execute(sql: """
            INSERT INTO part_categories (name, sort_order, created_at, updated_at)
            VALUES (?, 0, datetime('now'), datetime('now'))
            """, arguments: [name])
        return dbConn.lastInsertedRowID
    }
}

/// Find or create a brand by name. Returns the brand ID.
public func findOrCreateBrand(name: String) throws -> Int64 {
    try db.writer.write { dbConn in
        if let existing = try Row.fetchOne(dbConn, sql:
            "SELECT id FROM brands WHERE name = ? AND deleted_at IS NULL",
            arguments: [name]) {
            return existing["id"]
        }
        try dbConn.execute(sql: """
            INSERT INTO brands (name, created_at, updated_at)
            VALUES (?, datetime('now'), datetime('now'))
            """, arguments: [name])
        return dbConn.lastInsertedRowID
    }
}
```

### Step 2: Rewrite PartsImportExportPage

Completely replace the page. Key changes:

1. **Remove `import GRDB`** — all data through PartsService
2. **Remove all `#if os()` platform guards**
3. **Add `loadError` display** with `ErrorStateView`
4. **Export field selection** — checkboxes for each field group + "All" toggle
5. **Import preview sheet** — shows new/duplicate/error counts before committing
6. **Per-conflict resolution** — for each duplicate: Update / Skip / Update All / Skip All

**State variables:**

```swift
@EnvironmentObject private var appCore: AppCore
@State private var stats: PartsService.CatalogStats?
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
```

**Export section** — replace single button with field group checkboxes:

```swift
// Toggle for each group
ForEach(PartsService.ExportFieldGroup.allCases, id: \.self) { group in
    Toggle(group.displayName, isOn: binding(for: group))
}
// "All" toggle
Toggle("Select All", isOn: $selectAll)
    .fontWeight(.medium)

Button { showExportConfirm = true } label: {
    Label("Export \(stats?.totalParts ?? 0) Parts to CSV", systemImage: "arrow.down.doc.fill")
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity)
}
.buttonStyle(.borderedProminent)
.frame(minHeight: 44)
```

**Import preview** — after file is picked, parse and show preview before committing:

```swift
// After CSV is parsed:
struct ImportPreview {
    var newParts: [ParsedRow] = []
    var conflicts: [ConflictRow] = []
    var errors: [ImportError] = []
    var totalRows: Int = 0
}

struct ConflictRow: Identifiable {
    let id = UUID()
    let parsedRow: ParsedRow
    let existingPart: Part
    var resolution: ConflictResolution = .ask
}

enum ConflictResolution {
    case ask, update, skip
}

struct ParsedRow {
    let name: String
    let code: String?
    let category: String?
    let brand: String?
    let fields: [String: String]  // all other columns
}

struct ImportError: Identifiable {
    let id = UUID()
    let rowNumber: Int
    let message: String
}
```

**Import preview sheet:**

```swift
.sheet(isPresented: $showImportPreview) {
    ImportPreviewSheet(
        preview: $importPreview,
        onConfirm: { Task { await executeImport() } },
        onCancel: { importPreview = nil }
    )
    .environmentObject(appCore)
}
```

The `ImportPreviewSheet` shows:
- Summary: "X new, Y conflicts, Z errors"
- Conflicts section with side-by-side comparison table (current vs CSV values)
- Each conflict has: [Update] [Skip] buttons
- Footer buttons: [Update All] [Skip All]
- Error list (non-blocking — these rows are skipped)
- Confirm button: "Import X + Y updates" (count updates dynamically based on resolutions)

**Import execution** — uses service layer:

```swift
private func executeImport() async {
    guard let preview = importPreview,
          let service = appCore.partsService else { return }
    importStatus = .importing
    var created = 0, updated = 0, skipped = 0

    // Create new parts
    for row in preview.newParts {
        do {
            let catId = try service.findOrCreateCategory(name: row.category ?? "Uncategorized")
            var brandId: Int64? = nil
            if let bName = row.brand, !bName.isEmpty {
                brandId = try service.findOrCreateBrand(name: bName)
            }
            // Build Part and insert via service
            // ... (use createPart or direct insert via service method)
            created += 1
        } catch {
            // Add to error count, continue
        }
    }

    // Update conflicts marked as "update"
    for conflict in preview.conflicts where conflict.resolution == .update {
        do {
            // Update existing part with CSV values via service
            // ... (use updatePart service method)
            updated += 1
        } catch {
            // Add to error count
        }
    }

    skipped = preview.conflicts.filter { $0.resolution == .skip }.count

    await MainActor.run {
        importStatus = .success("Created \(created), Updated \(updated), Skipped \(skipped)")
        importPreview = nil
    }
    // Reload stats
    await loadStats()
}
```

### Step 3: Add display name extension

```swift
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
```

### Step 4: Load stats via service

```swift
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
        let newStats = try service.getCatalogStats()
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
```

## Important Notes

- **Check Part model field names** — the export SQL uses column aliases. Make sure `style_id`, `type_id`, `color_id` exist on the parts table. If they use different names, adjust the JOINs.
- **findOrCreateCategory/Brand** use `write` transactions — they may create new records. This is intentional for import flexibility.
- **Import preview is a separate sheet** — don't try to show it inline. The preview has complex interaction (per-conflict resolution) that needs its own navigation.
- **"Update All" / "Skip All"** buttons set ALL unresolved conflicts at once. The confirm button updates its count label dynamically.
- **Export writes to Documents directory** — no share sheet (user decision).
- **The `exportPartsCSV(groups:)` method** handles all the SQL JOINs. The UI just passes the selected groups.
- **CSV parsing** — reuse the existing `parseCSVLine()` helper (it handles quoted fields correctly). Don't rewrite it.

## Success Criteria

- [ ] `import GRDB` removed
- [ ] All 4 `#if os()` platform guards removed
- [ ] `loadError` displayed via `ErrorStateView` or error banner
- [ ] Stats load via `PartsService.getCatalogStats()`
- [ ] Export field group checkboxes with "Select All" toggle
- [ ] Export via `PartsService.exportPartsCSV(groups:)`
- [ ] Import shows preview sheet before committing
- [ ] Preview shows: new count, conflict count, error count
- [ ] Each conflict shows side-by-side comparison
- [ ] Per-conflict: [Update] [Skip] buttons
- [ ] Bulk: [Update All] [Skip All] buttons
- [ ] Import executes via service layer (not raw SQL)
- [ ] Duplicate matching: by code first, then by name (case-insensitive)
- [ ] New categories/brands auto-created during import
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 24A Results (YYYY-MM-DD)
- Removed import GRDB + 4 platform guards
- Added loadError display
- Export: 5 field group checkboxes + Select All, via service method
- Import: preview sheet with conflict resolution (Update/Skip per row, Update All/Skip All)
- 7 new service methods: getCatalogStats, exportPartsCSV, findPartByCode/Name, findOrCreateCategory/Brand
- Build: [PASS/FAIL]
```

**Parts section complete after this prompt.**
