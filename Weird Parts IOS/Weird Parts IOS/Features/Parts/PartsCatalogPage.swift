import SwiftUI
import GRDB
import WiredPartCore

/// Full parts catalog with cascading hierarchy filters, pagination,
/// low-stock indicator, and a quick-edit sheet.
///
/// Matches the Windows/React catalog feature set adapted for mobile:
///   - Cascading filters: Category → Style → Type → Color → Brand
///   - Sortable list with tap-to-sort headers
///   - Pagination (25 per page)
///   - Low-stock filter toggle
///   - Quick-edit modal (name, code, cost, markup)
///   - Swipe-to-delete
struct PartsCatalogPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data
    @State private var parts: [CatalogPartRow] = []
    @State private var totalCount = 0
    @State private var isLoading = true

    // Lookup tables for hierarchy filters
    @State private var categories: [PartCategory] = []
    @State private var styles: [PartStyle] = []
    @State private var types: [PartType] = []
    @State private var colors: [PartColor] = []
    @State private var brands: [Brand] = []

    // MARK: - Filters
    @State private var searchText = ""
    @State private var selectedCategoryId: Int64?
    @State private var selectedStyleId: Int64?
    @State private var selectedTypeId: Int64?
    @State private var selectedColorId: Int64?
    @State private var selectedBrandId: Int64?
    @State private var lowStockOnly = false
    @State private var showFilters = false

    // MARK: - Sorting
    @State private var sortField: SortField = .name
    @State private var sortAscending = true

    // MARK: - Pagination
    @State private var currentPage = 1
    private let pageSize = 25

    // MARK: - Sheets
    @State private var showAddPart = false
    @State private var selectedPart: CatalogPartRow?
    @State private var quickEditPart: CatalogPartRow?
    @State private var loadError: String?

    // MARK: - Cascading filter options
    private var filteredStyles: [PartStyle] {
        guard let catId = selectedCategoryId else { return styles }
        return styles.filter { $0.categoryId == catId }
    }
    private var filteredTypes: [PartType] {
        guard let styleId = selectedStyleId else { return types }
        return types.filter { $0.styleId == styleId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips bar
            if showFilters {
                filterBar
            }

            // Sort header
            sortHeader

            if isLoading {
                ProgressView("Loading catalog…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
            } else if parts.isEmpty {
                emptyState
            } else {
                partsList
                paginationBar
            }
        }
        .searchable(text: $searchText, prompt: "Search parts by name, code, or brand…")
        .onChange(of: searchText) { _, _ in resetAndLoad() }
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    withAnimation { showFilters.toggle() }
                } label: {
                    Image(systemName: showFilters
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                Button {
                    showAddPart = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddPart) {
            PartFormSheet(part: nil, categories: categories, brands: brands) { await loadData() }
        }
        .sheet(item: $selectedPart) { partRow in
            PartDetailSheet(partRow: partRow, categories: categories, brands: brands) { await loadData() }
        }
        .sheet(item: $quickEditPart) { partRow in
            QuickEditSheet(part: partRow) { await loadData() }
        }
        .background(DS.Background.page)
        .task { await loadLookups(); await loadData() }
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Category
                filterMenu(
                    label: "Category",
                    icon: "folder.fill",
                    selection: selectedCategoryId,
                    options: categories.compactMap { ($0.id, $0.name) }
                ) { newValue in
                    selectedCategoryId = newValue
                    // Clear dependent filters
                    selectedStyleId = nil
                    selectedTypeId = nil
                    resetAndLoad()
                }

                // Style (cascaded from category)
                filterMenu(
                    label: "Style",
                    icon: "paintpalette.fill",
                    selection: selectedStyleId,
                    options: filteredStyles.compactMap { ($0.id, $0.name) }
                ) { newValue in
                    selectedStyleId = newValue
                    selectedTypeId = nil
                    resetAndLoad()
                }

                // Type (cascaded from style)
                filterMenu(
                    label: "Type",
                    icon: "square.grid.2x2.fill",
                    selection: selectedTypeId,
                    options: filteredTypes.compactMap { ($0.id, $0.name) }
                ) { newValue in
                    selectedTypeId = newValue
                    resetAndLoad()
                }

                // Color
                filterMenu(
                    label: "Color",
                    icon: "drop.fill",
                    selection: selectedColorId,
                    options: colors.compactMap { ($0.id, $0.name) }
                ) { newValue in
                    selectedColorId = newValue
                    resetAndLoad()
                }

                // Brand
                filterMenu(
                    label: "Brand",
                    icon: "tag.fill",
                    selection: selectedBrandId,
                    options: brands.compactMap { ($0.id, $0.name) }
                ) { newValue in
                    selectedBrandId = newValue
                    resetAndLoad()
                }

                // Low stock toggle
                Button {
                    lowStockOnly.toggle()
                    resetAndLoad()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Low Stock")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(lowStockOnly ? Color.orange.opacity(0.15) : Color.clear)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(lowStockOnly ? Color.orange.opacity(0.5) : Color.accentColor.opacity(0.3), lineWidth: 1))
                }

                // Clear all
                if hasActiveFilters {
                    Button {
                        clearAllFilters()
                    } label: {
                        Text("Clear")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var hasActiveFilters: Bool {
        selectedCategoryId != nil || selectedStyleId != nil ||
        selectedTypeId != nil || selectedColorId != nil ||
        selectedBrandId != nil || lowStockOnly
    }

    private func clearAllFilters() {
        selectedCategoryId = nil
        selectedStyleId = nil
        selectedTypeId = nil
        selectedColorId = nil
        selectedBrandId = nil
        lowStockOnly = false
        resetAndLoad()
    }

    @ViewBuilder
    private func filterMenu(
        label: String,
        icon: String,
        selection: Int64?,
        options: [(Int64?, String)],
        onChange: @escaping (Int64?) -> Void
    ) -> some View {
        Menu {
            Button("All \(label)s") { onChange(nil) }
            Divider()
            ForEach(options, id: \.0) { id, name in
                Button(name) { onChange(id) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(selection.flatMap { sel in options.first { $0.0 == sel }?.1 } ?? label)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selection != nil ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
        }
    }

    // MARK: - Sort Header

    private var sortHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                sortButton("Name", field: .name)
                sortButton("Code", field: .code)
                sortButton("Category", field: .category)
                sortButton("Brand", field: .brand)
                sortButton("Stock", field: .stock)
                sortButton("Cost", field: .cost)
                sortButton("Sell", field: .sell)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemGroupedBackground).opacity(0.6))
    }

    @ViewBuilder
    private func sortButton(_ label: String, field: SortField) -> some View {
        Button {
            if sortField == field {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = true
            }
            resetAndLoad()
        } label: {
            HStack(spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(sortField == field ? .bold : .regular)
                if sortField == field {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .foregroundStyle(sortField == field ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Parts List

    @ViewBuilder
    private var partsList: some View {
        List {
            Section {
                Text("\(totalCount) part\(totalCount == 1 ? "" : "s") · Page \(currentPage) of \(totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(parts, id: \.id) { part in
                Button {
                    selectedPart = part
                } label: {
                    partRow(part)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await deletePart(part) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        quickEditPart = part
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func partRow(_ part: CatalogPartRow) -> some View {
        HStack(spacing: 12) {
            // Icon with low-stock indicator
            ZStack(alignment: .topTrailing) {
                VStack {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if part.isLowStock {
                    Circle()
                        .fill(.orange)
                        .frame(width: 10, height: 10)
                        .offset(x: 3, y: -3)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(part.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let code = part.code, !code.isEmpty {
                        Text(code)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    if let catName = part.categoryName {
                        Text(catName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    if let brandName = part.brandName {
                        Text(brandName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if appCore.hasPermission("show_dollar_values") {
                    Text(String(format: "$%.2f", part.companyCostPrice))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text("\(part.totalStock) in stock")
                    .font(.caption)
                    .foregroundStyle(part.totalStock > 0 ? .green : .red)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 56)
    }

    // MARK: - Pagination Bar

    private var totalPages: Int {
        max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
    }

    @ViewBuilder
    private var paginationBar: some View {
        HStack {
            Button {
                if currentPage > 1 {
                    currentPage -= 1
                    Task { await loadData() }
                }
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .font(.subheadline)
            }
            .disabled(currentPage <= 1)

            Spacer()

            Text("Page \(currentPage) of \(totalPages)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                if currentPage < totalPages {
                    currentPage += 1
                    Task { await loadData() }
                }
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .font(.subheadline)
                    .labelStyle(.titleAndIcon)
            }
            .disabled(currentPage >= totalPages)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Parts Found")
                .font(.title3)
                .fontWeight(.semibold)
            Text(hasActiveFilters || !searchText.isEmpty
                 ? "Try adjusting your filters or search."
                 : "Add parts to your catalog to start tracking inventory.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if !hasActiveFilters && searchText.isEmpty {
                Button {
                    showAddPart = true
                } label: {
                    Label("Add Part", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func resetAndLoad() {
        currentPage = 1
        Task { await loadData() }
    }

    // MARK: - Data Loading

    @Sendable
    private func loadLookups() async {
        guard let db = appCore.db else { return }
        do {
            let result = try await db.writer.read { conn -> ([PartCategory], [PartStyle], [PartType], [PartColor], [Brand]) in
                let cats = try PartCategory
                    .filter(Column("deleted_at") == nil)
                    .order(Column("sort_order").asc, Column("name").asc)
                    .fetchAll(conn)
                let stys = try PartStyle
                    .filter(Column("deleted_at") == nil)
                    .order(Column("sort_order").asc, Column("name").asc)
                    .fetchAll(conn)
                let typs = try PartType
                    .filter(Column("deleted_at") == nil)
                    .order(Column("sort_order").asc, Column("name").asc)
                    .fetchAll(conn)
                let cols = try PartColor
                    .filter(Column("deleted_at") == nil)
                    .order(Column("sort_order").asc, Column("name").asc)
                    .fetchAll(conn)
                let brnds = try Brand
                    .filter(Column("deleted_at") == nil)
                    .order(Column("name").asc)
                    .fetchAll(conn)
                return (cats, stys, typs, cols, brnds)
            }
            await MainActor.run {
                categories = result.0
                styles = result.1
                types = result.2
                colors = result.3
                brands = result.4
            }
        } catch {
            print("[PartsCatalogPage] Load lookups error: \(error)")
        }
    }

    @Sendable
    private func loadData() async {
        isLoading = parts.isEmpty
        guard let db = appCore.db else { return }

        do {
            let offset = (currentPage - 1) * pageSize

            // Build WHERE clauses
            var whereClauses = ["p.deleted_at IS NULL"]
            var args: [DatabaseValueConvertible?] = []

            if let catId = selectedCategoryId {
                whereClauses.append("p.category_id = ?")
                args.append(catId)
            }
            if let styleId = selectedStyleId {
                whereClauses.append("p.style_id = ?")
                args.append(styleId)
            }
            if let typeId = selectedTypeId {
                whereClauses.append("p.type_id = ?")
                args.append(typeId)
            }
            if let colorId = selectedColorId {
                whereClauses.append("p.color_id = ?")
                args.append(colorId)
            }
            if let brandId = selectedBrandId {
                whereClauses.append("p.brand_id = ?")
                args.append(brandId)
            }

            let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
            if !trimmedSearch.isEmpty {
                whereClauses.append("(p.name LIKE ? OR p.code LIKE ? OR COALESCE(b.name, '') LIKE ?)")
                let like = "%\(trimmedSearch)%"
                args.append(like)
                args.append(like)
                args.append(like)
            }

            if lowStockOnly {
                whereClauses.append("p.min_stock_level IS NOT NULL AND COALESCE((SELECT SUM(se.quantity) FROM stock_entries se WHERE se.part_id = p.id AND se.deleted_at IS NULL), 0) < p.min_stock_level")
            }

            let whereSQL = whereClauses.joined(separator: " AND ")

            // Sort
            let orderSQL: String = switch sortField {
            case .name: "p.name"
            case .code: "p.code"
            case .category: "category_name"
            case .brand: "brand_name"
            case .stock: "total_stock"
            case .cost: "p.company_cost_price"
            case .sell: "(p.company_cost_price * (1 + p.company_markup_percent / 100))"
            }
            let dir = sortAscending ? "ASC" : "DESC"

            // Convert args to StatementArguments before the Sendable closure
            let countArgs = StatementArguments(args)
            var fetchArgValues = args
            fetchArgValues.append(pageSize)
            fetchArgValues.append(offset)
            let fetchArgs = StatementArguments(fetchArgValues)

            let result = try await db.writer.read { conn -> (Int, [CatalogPartRow]) in
                // Count
                let countSQL = """
                    SELECT COUNT(*) FROM parts p
                    LEFT JOIN brands b ON b.id = p.brand_id
                    WHERE \(whereSQL)
                    """
                let count = try Int.fetchOne(conn, sql: countSQL, arguments: countArgs) ?? 0

                // Fetch page
                let fetchSQL = """
                    SELECT p.*,
                           pc.name AS category_name,
                           b.name AS brand_name,
                           ps.name AS style_name,
                           pcol.name AS color_name,
                           COALESCE((SELECT SUM(se.quantity) FROM stock_entries se WHERE se.part_id = p.id AND se.deleted_at IS NULL), 0) AS total_stock
                    FROM parts p
                    LEFT JOIN part_categories pc ON pc.id = p.category_id
                    LEFT JOIN brands b ON b.id = p.brand_id
                    LEFT JOIN part_styles ps ON ps.id = p.style_id
                    LEFT JOIN part_colors pcol ON pcol.id = p.color_id
                    WHERE \(whereSQL)
                    ORDER BY \(orderSQL) \(dir)
                    LIMIT ? OFFSET ?
                    """

                let rows = try Row.fetchAll(conn, sql: fetchSQL, arguments: fetchArgs)

                let prows = rows.map { row -> CatalogPartRow in
                    let stock: Int = row["total_stock"] ?? 0
                    let minStock: Int? = row["min_stock_level"]
                    return CatalogPartRow(
                        id: row["id"],
                        name: row["name"],
                        code: row["code"],
                        categoryId: row["category_id"],
                        categoryName: row["category_name"],
                        styleId: row["style_id"],
                        styleName: row["style_name"],
                        colorId: row["color_id"],
                        colorName: row["color_name"],
                        brandId: row["brand_id"],
                        brandName: row["brand_name"],
                        companyCostPrice: row["company_cost_price"] ?? 0,
                        companyMarkupPercent: row["company_markup_percent"] ?? 0,
                        totalStock: stock,
                        partType: row["part_type"] ?? "standard",
                        isActive: row["is_active"] ?? 1,
                        isLowStock: minStock.map { stock < $0 } ?? false
                    )
                }
                return (count, prows)
            }

            await MainActor.run {
                totalCount = result.0
                parts = result.1
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Delete

    private func deletePart(_ part: CatalogPartRow) async {
        guard let db = appCore.db else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        do {
            try await db.writer.write { conn in
                try conn.execute(sql: "UPDATE parts SET deleted_at = ? WHERE id = ?", arguments: [now, part.id])
            }
            await loadData()
        } catch {
            print("[PartsCatalogPage] Delete part error: \(error)")
        }
    }
}

// MARK: - Sort Field

private enum SortField: String {
    case name, code, category, brand, stock, cost, sell
}

// MARK: - Catalog Part Row Model

struct CatalogPartRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let code: String?
    let categoryId: Int64
    let categoryName: String?
    let styleId: Int64?
    let styleName: String?
    let colorId: Int64?
    let colorName: String?
    let brandId: Int64?
    let brandName: String?
    let companyCostPrice: Double
    let companyMarkupPercent: Double
    let totalStock: Int
    let partType: String
    let isActive: Int
    let isLowStock: Bool
}

// MARK: - Quick Edit Sheet

private struct QuickEditSheet: View {
    let part: CatalogPartRow
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var code: String = ""
    @State private var costPrice: String = ""
    @State private var markupPercent: String = ""
    @State private var isSaving = false

    private var sellPrice: Double {
        let cost = Double(costPrice) ?? 0
        let markup = Double(markupPercent) ?? 0
        return cost * (1 + markup / 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Part Info") {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Code", text: $code)
                        .frame(minHeight: 44)
                }

                Section("Hierarchy") {
                    if let cat = part.categoryName {
                        LabeledContent("Category", value: cat)
                    }
                    if let style = part.styleName {
                        LabeledContent("Style", value: style)
                    }
                    if let color = part.colorName {
                        LabeledContent("Color", value: color)
                    }
                    if let brand = part.brandName {
                        LabeledContent("Brand", value: brand)
                    }
                }

                Section("Pricing") {
                    HStack {
                        Text("$")
                        TextField("Cost", text: $costPrice)
                            .keyboardType(.decimalPad)
                    }
                    .frame(minHeight: 44)
                    HStack {
                        TextField("Markup %", text: $markupPercent)
                            .keyboardType(.decimalPad)
                        Text("%")
                    }
                    .frame(minHeight: 44)
                    LabeledContent("Sell Price", value: String(format: "$%.2f", sellPrice))
                        .foregroundStyle(.secondary)
                }

                Section("Stock") {
                    LabeledContent("In Stock", value: "\(part.totalStock)")
                    LabeledContent("Status", value: part.isLowStock ? "Low Stock ⚠️" : "OK")
                }
            }
            .navigationTitle("Quick Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                name = part.name
                code = part.code ?? ""
                costPrice = String(format: "%.2f", part.companyCostPrice)
                markupPercent = String(format: "%.1f", part.companyMarkupPercent)
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        guard let db = appCore.db else { return }

        isSaving = true
        let cost = Double(costPrice) ?? 0
        let markup = Double(markupPercent) ?? 0
        let now = ISO8601DateFormatter().string(from: Date())
        let capturedCode = code

        do {
            try await db.writer.write { conn in
                try conn.execute(
                    sql: """
                        UPDATE parts SET name = ?, code = ?,
                        company_cost_price = ?, company_markup_percent = ?,
                        updated_at = ? WHERE id = ?
                        """,
                    arguments: [trimmedName, capturedCode.isEmpty ? nil : capturedCode, cost, markup, now, part.id]
                )
            }
            await onSave()
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run { isSaving = false }
        }
    }
}

// MARK: - Part Form Sheet (Add/Full Edit)

private struct PartFormSheet: View {
    let part: CatalogPartRow?
    let categories: [PartCategory]
    let brands: [Brand]
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var code = ""
    @State private var selectedCategoryId: Int64 = 0
    @State private var selectedBrandId: Int64?
    @State private var partType = "standard"
    @State private var costPrice = ""
    @State private var markupPercent = ""

    private let partTypes = ["standard", "special_order", "custom"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Part Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Part Code (optional)", text: $code)
                        .frame(minHeight: 44)
                    Picker("Type", selection: $partType) {
                        ForEach(partTypes, id: \.self) { t in
                            Text(t.replacingOccurrences(of: "_", with: " ").capitalized).tag(t)
                        }
                    }
                }

                Section("Classification") {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("Select…").tag(Int64(0))
                        ForEach(categories, id: \.id) { cat in
                            Text(cat.name).tag(cat.id ?? Int64(0))
                        }
                    }
                    Picker("Brand", selection: Binding(
                        get: { selectedBrandId ?? -1 },
                        set: { selectedBrandId = $0 == -1 ? nil : $0 }
                    )) {
                        Text("None").tag(Int64(-1))
                        ForEach(brands, id: \.id) { brand in
                            Text(brand.name).tag(brand.id ?? Int64(-1))
                        }
                    }
                }

                Section("Pricing") {
                    HStack {
                        Text("$")
                        TextField("Cost Price", text: $costPrice)
                            .keyboardType(.decimalPad)
                    }
                    .frame(minHeight: 44)
                    HStack {
                        TextField("Markup %", text: $markupPercent)
                            .keyboardType(.decimalPad)
                        Text("%")
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle(part == nil ? "New Part" : "Edit Part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                            await onSave()
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedCategoryId == 0)
                }
            }
            .onAppear {
                if let p = part {
                    name = p.name
                    code = p.code ?? ""
                    selectedCategoryId = p.categoryId
                    selectedBrandId = p.brandId
                    partType = p.partType
                    costPrice = String(format: "%.2f", p.companyCostPrice)
                    markupPercent = String(format: "%.1f", p.companyMarkupPercent)
                }
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, selectedCategoryId > 0 else { return }
        let cost = Double(costPrice) ?? 0
        let markup = Double(markupPercent) ?? 0
        guard let db = appCore.db else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let capturedCode = code
        let capturedCategoryId = selectedCategoryId
        let capturedBrandId = selectedBrandId
        let capturedPartType = partType

        do {
            if let p = part {
                try await db.writer.write { conn in
                    try conn.execute(
                        sql: """
                            UPDATE parts SET name = ?, code = ?, category_id = ?, brand_id = ?,
                            part_type = ?, company_cost_price = ?, company_markup_percent = ?,
                            updated_at = ? WHERE id = ?
                            """,
                        arguments: [trimmedName, capturedCode.isEmpty ? nil : capturedCode, capturedCategoryId,
                                    capturedBrandId, capturedPartType, cost, markup, now, p.id]
                    )
                }
            } else {
                try await db.writer.write { conn in
                    try conn.execute(
                        sql: """
                            INSERT INTO parts (name, code, category_id, brand_id, part_type,
                            company_cost_price, company_markup_percent, created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [trimmedName, capturedCode.isEmpty ? nil : capturedCode, capturedCategoryId,
                                    capturedBrandId, capturedPartType, cost, markup, now, now]
                    )
                }
            }
        } catch {
            print("[PartFormSheet] Save error: \(error)")
        }
    }
}

// MARK: - Part Detail Sheet

private struct PartDetailSheet: View {
    let partRow: CatalogPartRow
    let categories: [PartCategory]
    let brands: [Brand]
    let onUpdate: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var stockEntries: [StockEntry] = []
    @State private var showEditForm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Part Information") {
                    LabeledContent("Name", value: partRow.name)
                    if let code = partRow.code {
                        LabeledContent("Code", value: code)
                    }
                    LabeledContent("Type", value: partRow.partType.replacingOccurrences(of: "_", with: " ").capitalized)
                    if let cat = partRow.categoryName {
                        LabeledContent("Category", value: cat)
                    }
                    if let style = partRow.styleName {
                        LabeledContent("Style", value: style)
                    }
                    if let color = partRow.colorName {
                        LabeledContent("Color", value: color)
                    }
                    if let brand = partRow.brandName {
                        LabeledContent("Brand", value: brand)
                    }
                    LabeledContent("Status", value: partRow.isActive == 1 ? "Active" : "Inactive")
                }

                if appCore.hasPermission("show_dollar_values") {
                    Section("Pricing") {
                        LabeledContent("Cost Price", value: String(format: "$%.2f", partRow.companyCostPrice))
                        LabeledContent("Markup", value: String(format: "%.1f%%", partRow.companyMarkupPercent))
                        let sellPrice = partRow.companyCostPrice * (1 + partRow.companyMarkupPercent / 100)
                        LabeledContent("Sell Price", value: String(format: "$%.2f", sellPrice))
                    }
                }

                Section("Stock (\(partRow.totalStock) total)") {
                    if stockEntries.isEmpty {
                        Text("No stock entries")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(stockEntries, id: \.id) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Warehouse #\(entry.warehouseId)")
                                        .font(.subheadline)
                                    if let bin = entry.binLocation {
                                        Text("Bin: \(bin)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(entry.quantity)")
                                    .font(.headline)
                                    .foregroundStyle(entry.quantity > 0 ? .green : .red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Part Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showEditForm = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            .sheet(isPresented: $showEditForm) {
                PartFormSheet(part: partRow, categories: categories, brands: brands) {
                    await onUpdate()
                    dismiss()
                }
            }
            .task { await loadStock() }
        }
    }

    @Sendable
    private func loadStock() async {
        guard let db = appCore.db else { return }
        do {
            let entries = try await db.writer.read { conn in
                try StockEntry
                    .filter(Column("part_id") == partRow.id)
                    .filter(Column("deleted_at") == nil)
                    .fetchAll(conn)
            }
            await MainActor.run { stockEntries = entries }
        } catch {
            print("[PartDetailSheet] Load stock error: \(error)")
        }
    }
}
