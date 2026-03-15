import SwiftUI
import GRDB
import WiredPartCore

/// Main parts catalog list with search, category filtering, and detail sheets.
///
/// Shows all active parts in a macOS-native Table layout with sortable columns.
/// Search filters by name, code, or brand. Category dropdown narrows results.
/// Click a row to view full part details in a sheet.
struct CatalogPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var parts: [CatalogRow] = []
    @State private var categories: [PartCategory] = []
    @State private var isLoading = true

    // MARK: - Filters

    @State private var searchText = ""
    @State private var selectedCategoryId: Int64? = nil

    // MARK: - Detail Sheet

    @State private var selectedPart: CatalogRow?
    @State private var showDetail = false

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\CatalogRow.name)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadData() }
        .sheet(isPresented: $showDetail) {
            if let part = selectedPart {
                partDetailSheet(part)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Catalog")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            // Category filter
            Picker("Category", selection: $selectedCategoryId) {
                Text("All Categories").tag(nil as Int64?)
                ForEach(categories, id: \.id) { cat in
                    Text(cat.name).tag(cat.id as Int64?)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
            .onChange(of: selectedCategoryId) { _, _ in loadData() }

            // Search
            TextField("Search parts...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)
                .onChange(of: searchText) { _, _ in loadData() }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table Content

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading catalog...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if parts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No parts found")
                    .font(.headline)
                Text(searchText.isEmpty && selectedCategoryId == nil
                     ? "Add parts to get started."
                     : "Try adjusting your search or filter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedParts, sortOrder: $sortOrder) {
                TableColumn("Code", value: \.code) { row in
                    Text(row.code)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Name", value: \.name) { row in
                    Text(row.name)
                        .fontWeight(.medium)
                }
                .width(min: 150, ideal: 250)

                TableColumn("Category", value: \.categoryName) { row in
                    Text(row.categoryName)
                        .font(.callout)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Brand", value: \.brandName) { row in
                    Text(row.brandName)
                        .font(.callout)
                }
                .width(min: 80, ideal: 120)

                TableColumn("Stock", value: \.stock) { row in
                    HStack(spacing: 4) {
                        Text("\(row.stock)")
                        if row.isLowStock {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption2)
                        }
                    }
                }
                .width(min: 60, ideal: 70)

                TableColumn("Cost", value: \.costPrice) { row in
                    Text(row.costPrice > 0 ? String(format: "$%.2f", row.costPrice) : "-")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 80)

                TableColumn("Sell", value: \.sellPrice) { row in
                    Text(row.sellPrice > 0 ? String(format: "$%.2f", row.sellPrice) : "-")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .width(min: 70, ideal: 80)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .onChange(of: sortOrder) { _, _ in }
            .onTapGesture(count: 2) {
                // Double-click opens detail — handled per-row below
            }
            .contextMenu(forSelectionType: CatalogRow.ID.self) { ids in
                if let id = ids.first, let part = parts.first(where: { $0.id == id }) {
                    Button("View Details") {
                        selectedPart = part
                        showDetail = true
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let part = parts.first(where: { $0.id == id }) {
                    selectedPart = part
                    showDetail = true
                }
            }
        }
    }

    private var sortedParts: [CatalogRow] {
        parts.sorted(using: sortOrder)
    }

    // MARK: - Detail Sheet

    private func partDetailSheet(_ part: CatalogRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(part.name)
                        .font(.title)
                        .fontWeight(.bold)
                    Spacer()
                    Button("Done") { showDetail = false }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.cancelAction)
                }

                Divider()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    detailField("Code", value: part.code)
                    detailField("Category", value: part.categoryName)
                    detailField("Brand", value: part.brandName)
                    detailField("Stock", value: "\(part.stock)")
                    detailField("Cost Price", value: String(format: "$%.2f", part.costPrice))
                    detailField("Sell Price", value: String(format: "$%.2f", part.sellPrice))
                    detailField("Markup", value: String(format: "%.0f%%", part.markupPercent))
                    detailField("Unit", value: part.unitOfMeasure)
                }

                if !part.shelfLocation.isEmpty {
                    detailField("Shelf Location", value: part.shelfLocation)
                }
                if !part.binLocation.isEmpty {
                    detailField("Bin Location", value: part.binLocation)
                }
                if !part.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(part.notes)
                            .font(.body)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func detailField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.body)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { conn in
                // Load categories for filter picker
                categories = try PartCategory.fetchAll(
                    conn,
                    sql: "SELECT * FROM part_categories WHERE deleted_at IS NULL ORDER BY name ASC"
                )

                // Build parts query with optional filters
                var sql = """
                    SELECT
                        p.id, p.code, p.name, p.company_cost_price, p.company_markup_percent,
                        p.unit_of_measure, p.shelf_location, p.bin_location, p.notes,
                        p.min_stock_level,
                        COALESCE(pc.name, '') AS category_name,
                        COALESCE(b.name, '') AS brand_name,
                        COALESCE((SELECT SUM(se.quantity) FROM stock_entries se WHERE se.part_id = p.id AND se.deleted_at IS NULL), 0) AS total_stock
                    FROM parts p
                    LEFT JOIN part_categories pc ON pc.id = p.category_id
                    LEFT JOIN brands b ON b.id = p.brand_id
                    WHERE p.deleted_at IS NULL
                    """
                var args: [DatabaseValueConvertible?] = []

                if let catId = selectedCategoryId {
                    sql += " AND p.category_id = ?"
                    args.append(catId)
                }

                let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
                if !trimmedSearch.isEmpty {
                    sql += " AND (p.name LIKE ? OR p.code LIKE ? OR COALESCE(b.name, '') LIKE ?)"
                    let like = "%\(trimmedSearch)%"
                    args.append(like)
                    args.append(like)
                    args.append(like)
                }

                sql += " ORDER BY p.name ASC LIMIT 500"

                let rows = try Row.fetchAll(conn, sql: sql, arguments: StatementArguments(args) ?? StatementArguments())

                parts = rows.map { row in
                    let cost: Double = row["company_cost_price"] ?? 0
                    let markup: Double = row["company_markup_percent"] ?? 0
                    let sell = cost * (1 + markup / 100)
                    let stock: Int = row["total_stock"] ?? 0
                    let minStock: Int? = row["min_stock_level"]

                    return CatalogRow(
                        id: row["id"] ?? 0,
                        code: row["code"] as String? ?? "-",
                        name: row["name"] ?? "",
                        categoryName: row["category_name"] ?? "",
                        brandName: row["brand_name"] ?? "",
                        stock: stock,
                        costPrice: cost,
                        sellPrice: sell,
                        markupPercent: markup,
                        unitOfMeasure: row["unit_of_measure"] as String? ?? "",
                        shelfLocation: row["shelf_location"] as String? ?? "",
                        binLocation: row["bin_location"] as String? ?? "",
                        notes: row["notes"] as String? ?? "",
                        isLowStock: minStock.map { stock < $0 } ?? false
                    )
                }
            }
        } catch {
            print("[CatalogPage] Load error: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Catalog Row Model

/// View-model for a single row in the catalog table.
/// Identifiable for Table selection, Comparable fields for sorting.
struct CatalogRow: Identifiable {
    let id: Int64
    let code: String
    let name: String
    let categoryName: String
    let brandName: String
    let stock: Int
    let costPrice: Double
    let sellPrice: Double
    let markupPercent: Double
    let unitOfMeasure: String
    let shelfLocation: String
    let binLocation: String
    let notes: String
    let isLowStock: Bool
}
