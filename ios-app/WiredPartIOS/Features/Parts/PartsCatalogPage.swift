import SwiftUI
import GRDB
import WiredPartCore

/// Full parts catalog listing with search, filtering, and CRUD.
///
/// Shows parts in a searchable list with category/brand filters.
/// Each row shows the part name, code, category, brand, cost, and stock level.
/// Tap to view details; swipe to edit or delete.
struct PartsCatalogPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var parts: [CatalogPartRow] = []
    @State private var categories: [PartCategory] = []
    @State private var brands: [Brand] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedCategoryId: Int64? = nil
    @State private var selectedBrandId: Int64? = nil
    @State private var showFilters = false
    @State private var showAddPart = false
    @State private var selectedPart: CatalogPartRow?

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            if showFilters {
                filterBar
            }

            if isLoading {
                ProgressView("Loading catalog...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredParts.isEmpty {
                emptyState
            } else {
                partsList
            }
        }
        .searchable(text: $searchText, prompt: "Search parts by name, code, or brand...")
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    withAnimation { showFilters.toggle() }
                } label: {
                    Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
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
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
        .task { await loadData() }
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Category filter
                Menu {
                    Button("All Categories") { selectedCategoryId = nil }
                    Divider()
                    ForEach(categories, id: \.id) { cat in
                        Button(cat.name) { selectedCategoryId = cat.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                        Text(selectedCategoryId.flatMap { cid in categories.first { $0.id == cid }?.name } ?? "Category")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedCategoryId != nil ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
                }

                // Brand filter
                Menu {
                    Button("All Brands") { selectedBrandId = nil }
                    Divider()
                    ForEach(brands, id: \.id) { brand in
                        Button(brand.name) { selectedBrandId = brand.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.caption)
                        Text(selectedBrandId.flatMap { bid in brands.first { $0.id == bid }?.name } ?? "Brand")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedBrandId != nil ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
                }

                if selectedCategoryId != nil || selectedBrandId != nil {
                    Button {
                        selectedCategoryId = nil
                        selectedBrandId = nil
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
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.controlBackgroundColor))
        #endif
    }

    // MARK: - Filtered Parts

    private var filteredParts: [CatalogPartRow] {
        var result = parts

        if let catId = selectedCategoryId {
            result = result.filter { $0.categoryId == catId }
        }
        if let bId = selectedBrandId {
            result = result.filter { $0.brandId == bId }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                ($0.code?.lowercased().contains(query) ?? false) ||
                ($0.brandName?.lowercased().contains(query) ?? false) ||
                ($0.categoryName?.lowercased().contains(query) ?? false)
            }
        }
        return result
    }

    // MARK: - Parts List

    @ViewBuilder
    private var partsList: some View {
        List {
            Section {
                Text("\(filteredParts.count) part\(filteredParts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(filteredParts, id: \.id) { part in
                Button {
                    selectedPart = part
                } label: {
                    partRow(part)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await deletePart(part) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder
    private func partRow(_ part: CatalogPartRow) -> some View {
        HStack(spacing: 12) {
            // Part icon with category color
            VStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 40, height: 40)
            #if os(iOS)
            .background(Color(.tertiarySystemGroupedBackground))
            #elseif os(macOS)
            .background(Color(.controlBackgroundColor))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(part.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let code = part.code {
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
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "$%.2f", part.companyCostPrice))
                    .font(.subheadline)
                    .fontWeight(.semibold)
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
            Text("Add parts to your catalog to start tracking inventory.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAddPart = true
            } label: {
                Label("Add Part", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        do {
            let db = appCore.db!
            let result = try await db.writer.read { dbConnection -> ([CatalogPartRow], [PartCategory], [Brand]) in
                let cats = try PartCategory
                    .filter(Column("deleted_at") == nil)
                    .order(Column("name").asc)
                    .fetchAll(dbConnection)

                let brnds = try Brand
                    .filter(Column("deleted_at") == nil)
                    .order(Column("name").asc)
                    .fetchAll(dbConnection)

                let rows = try Row.fetchAll(dbConnection, sql: """
                    SELECT p.*,
                           pc.name AS category_name,
                           b.name AS brand_name,
                           COALESCE(SUM(se.quantity), 0) AS total_stock
                    FROM parts p
                    LEFT JOIN part_categories pc ON pc.id = p.category_id
                    LEFT JOIN brands b ON b.id = p.brand_id
                    LEFT JOIN stock_entries se ON se.part_id = p.id AND se.deleted_at IS NULL
                    WHERE p.deleted_at IS NULL
                    GROUP BY p.id
                    ORDER BY p.name ASC
                    """)

                let prows = rows.map { row -> CatalogPartRow in
                    CatalogPartRow(
                        id: row["id"],
                        name: row["name"],
                        code: row["code"],
                        categoryId: row["category_id"],
                        categoryName: row["category_name"],
                        brandId: row["brand_id"],
                        brandName: row["brand_name"],
                        companyCostPrice: row["company_cost_price"],
                        companyMarkupPercent: row["company_markup_percent"],
                        totalStock: row["total_stock"],
                        partType: row["part_type"],
                        isActive: row["is_active"] ?? 1
                    )
                }
                return (prows, cats, brnds)
            }
            await MainActor.run {
                parts = result.0
                categories = result.1
                brands = result.2
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    // MARK: - Delete

    private func deletePart(_ part: CatalogPartRow) async {
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            try await db.writer.write { dbConnection in
                try dbConnection.execute(sql: "UPDATE parts SET deleted_at = ? WHERE id = ?", arguments: [now, part.id])
            }
            await loadData()
        } catch {}
    }
}

// MARK: - Catalog Part Row Model

struct CatalogPartRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let code: String?
    let categoryId: Int64
    let categoryName: String?
    let brandId: Int64?
    let brandName: String?
    let companyCostPrice: Double
    let companyMarkupPercent: Double
    let totalStock: Int
    let partType: String
    let isActive: Int
}

// MARK: - Part Form Sheet

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
                        Text("Select...").tag(Int64(0))
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
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    .frame(minHeight: 44)
                    HStack {
                        TextField("Markup %", text: $markupPercent)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("%")
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle(part == nil ? "New Part" : "Edit Part")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            if let p = part {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: """
                            UPDATE parts SET name = ?, code = ?, category_id = ?, brand_id = ?,
                            part_type = ?, company_cost_price = ?, company_markup_percent = ?,
                            updated_at = ? WHERE id = ?
                            """,
                        arguments: [trimmedName, code.isEmpty ? nil : code, selectedCategoryId,
                                    selectedBrandId, partType, cost, markup, now, p.id]
                    )
                }
            } else {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: """
                            INSERT INTO parts (name, code, category_id, brand_id, part_type,
                            company_cost_price, company_markup_percent, created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [trimmedName, code.isEmpty ? nil : code, selectedCategoryId,
                                    selectedBrandId, partType, cost, markup, now, now]
                    )
                }
            }
        } catch {}
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
                    if let brand = partRow.brandName {
                        LabeledContent("Brand", value: brand)
                    }
                    LabeledContent("Status", value: partRow.isActive == 1 ? "Active" : "Inactive")
                }

                Section("Pricing") {
                    LabeledContent("Cost Price", value: String(format: "$%.2f", partRow.companyCostPrice))
                    LabeledContent("Markup", value: String(format: "%.1f%%", partRow.companyMarkupPercent))
                    let sellPrice = partRow.companyCostPrice * (1 + partRow.companyMarkupPercent / 100)
                    LabeledContent("Sell Price", value: String(format: "$%.2f", sellPrice))
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        do {
            let db = appCore.db!
            let entries = try await db.writer.read { dbConnection in
                try StockEntry
                    .filter(Column("part_id") == partRow.id)
                    .filter(Column("deleted_at") == nil)
                    .fetchAll(dbConnection)
            }
            await MainActor.run { stockEntries = entries }
        } catch {}
    }
}
