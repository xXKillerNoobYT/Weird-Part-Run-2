import Foundation
import GRDB

/// Parts & Inventory Service — full CRUD for the parts hierarchy, catalog,
/// brands, suppliers, pricing, stock, forecasting, companions, and alternatives.
///
/// All queries run against the local SQLite database via GRDB.
/// Tables that may not yet exist are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: Parts & Inventory feature area (Phases 2, 2.5, 3.5, 16)
public final class PartsService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Result Types

    /// Nested hierarchy tree: categories -> styles -> types -> (colors, brands).
    public struct HierarchyTree: Sendable {
        public var categories: [CategoryNode]

        public init(categories: [CategoryNode]) {
            self.categories = categories
        }
    }

    /// A single category node with its child styles.
    public struct CategoryNode: Sendable, Identifiable {
        public var category: PartCategory
        public var styles: [StyleNode]
        public var id: Int64? { category.id }

        public init(category: PartCategory, styles: [StyleNode]) {
            self.category = category
            self.styles = styles
        }
    }

    /// A single style node with its child types.
    public struct StyleNode: Sendable, Identifiable {
        public var style: PartStyle
        public var types: [TypeNode]
        public var id: Int64? { style.id }

        public init(style: PartStyle, types: [TypeNode]) {
            self.style = style
            self.types = types
        }
    }

    /// A single type node with its linked colors and brands.
    public struct TypeNode: Sendable, Identifiable {
        public var type: PartType
        public var colors: [PartColor]
        public var brands: [Brand]
        public var id: Int64? { type.id }

        public init(type: PartType, colors: [PartColor], brands: [Brand]) {
            self.type = type
            self.colors = colors
            self.brands = brands
        }
    }

    /// Aggregate catalog statistics for the parts overview screen.
    public struct CatalogStats: Sendable {
        public var totalParts: Int
        public var activeParts: Int
        public var deprecatedParts: Int
        public var lowStockParts: Int

        public init(totalParts: Int, activeParts: Int, deprecatedParts: Int, lowStockParts: Int) {
            self.totalParts = totalParts
            self.activeParts = activeParts
            self.deprecatedParts = deprecatedParts
            self.lowStockParts = lowStockParts
        }
    }

    /// Summarised stock for a single part across all locations.
    public struct StockSummary: Sendable {
        public var total: Int
        public var byLocationType: [String: Int]

        public init(total: Int, byLocationType: [String: Int]) {
            self.total = total
            self.byLocationType = byLocationType
        }
    }

    /// A part record enriched with joined dimension names and aggregate stock.
    public struct PartWithDetails: Sendable {
        public var part: Part
        public var categoryName: String?
        public var styleName: String?
        public var typeName: String?
        public var colorName: String?
        public var brandName: String?
        public var totalStock: Int

        public init(
            part: Part,
            categoryName: String?,
            styleName: String?,
            typeName: String?,
            colorName: String?,
            brandName: String?,
            totalStock: Int
        ) {
            self.part = part
            self.categoryName = categoryName
            self.styleName = styleName
            self.typeName = typeName
            self.colorName = colorName
            self.brandName = brandName
            self.totalStock = totalStock
        }
    }

    /// Row returned by companion rules list (rule + source/target arrays).
    public struct CompanionRuleWithRelations: Sendable {
        public var id: Int64
        public var name: String
        public var description: String?
        public var styleMatch: String
        public var qtyMode: String
        public var qtyRatio: Double
        public var isActive: Int
        public var createdBy: Int64?
        public var createdAt: String?
        public var updatedAt: String?
        public var sources: [CompanionRuleSource]
        public var targets: [CompanionRuleTarget]

        public init(
            id: Int64, name: String, description: String?,
            styleMatch: String, qtyMode: String, qtyRatio: Double,
            isActive: Int, createdBy: Int64?, createdAt: String?, updatedAt: String?,
            sources: [CompanionRuleSource], targets: [CompanionRuleTarget]
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.styleMatch = styleMatch
            self.qtyMode = qtyMode
            self.qtyRatio = qtyRatio
            self.isActive = isActive
            self.createdBy = createdBy
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.sources = sources
            self.targets = targets
        }
    }

    /// A source entry for a companion rule.
    public struct CompanionRuleSource: Sendable {
        public var id: Int64
        public var ruleId: Int64
        public var categoryId: Int64
        public var styleId: Int64?

        public init(id: Int64, ruleId: Int64, categoryId: Int64, styleId: Int64?) {
            self.id = id
            self.ruleId = ruleId
            self.categoryId = categoryId
            self.styleId = styleId
        }
    }

    /// A target entry for a companion rule.
    public struct CompanionRuleTarget: Sendable {
        public var id: Int64
        public var ruleId: Int64
        public var categoryId: Int64
        public var styleId: Int64?

        public init(id: Int64, ruleId: Int64, categoryId: Int64, styleId: Int64?) {
            self.id = id
            self.ruleId = ruleId
            self.categoryId = categoryId
            self.styleId = styleId
        }
    }

    /// A part alternative with joined part name for display.
    public struct PartAlternativeWithName: Sendable {
        public var id: Int64
        public var partId: Int64
        public var alternativePartId: Int64
        public var relationship: String
        public var preference: Int
        public var notes: String?
        public var createdBy: Int64?
        public var createdAt: String?
        public var alternativePartName: String?
        public var alternativePartCode: String?

        public init(
            id: Int64, partId: Int64, alternativePartId: Int64,
            relationship: String, preference: Int, notes: String?,
            createdBy: Int64?, createdAt: String?,
            alternativePartName: String?, alternativePartCode: String?
        ) {
            self.id = id
            self.partId = partId
            self.alternativePartId = alternativePartId
            self.relationship = relationship
            self.preference = preference
            self.notes = notes
            self.createdBy = createdBy
            self.createdAt = createdAt
            self.alternativePartName = alternativePartName
            self.alternativePartCode = alternativePartCode
        }
    }

    /// A supplier link enriched with the supplier name.
    public struct PartSupplierLinkWithName: Sendable {
        public var id: Int64
        public var partId: Int64
        public var supplierId: Int64
        public var supplierPartNumber: String?
        public var supplierCostPrice: Double?
        public var moq: Int?
        public var discountBrackets: String?
        public var lastPriceDate: String?
        public var isPreferred: Int
        public var deletedAt: String?
        public var createdAt: String?
        public var supplierName: String?

        public init(
            id: Int64, partId: Int64, supplierId: Int64,
            supplierPartNumber: String?, supplierCostPrice: Double?,
            moq: Int?, discountBrackets: String?, lastPriceDate: String?,
            isPreferred: Int, deletedAt: String?, createdAt: String?,
            supplierName: String?
        ) {
            self.id = id
            self.partId = partId
            self.supplierId = supplierId
            self.supplierPartNumber = supplierPartNumber
            self.supplierCostPrice = supplierCostPrice
            self.moq = moq
            self.discountBrackets = discountBrackets
            self.lastPriceDate = lastPriceDate
            self.isPreferred = isPreferred
            self.deletedAt = deletedAt
            self.createdAt = createdAt
            self.supplierName = supplierName
        }
    }

    /// A brand with its associated part count.
    public struct BrandWithCount: Sendable {
        public var brand: Brand
        public var partCount: Int

        public init(brand: Brand, partCount: Int) {
            self.brand = brand
            self.partCount = partCount
        }
    }

    /// A supplier with its associated brand count.
    public struct SupplierWithCount: Sendable {
        public var supplier: Supplier
        public var brandCount: Int

        public init(supplier: Supplier, brandCount: Int) {
            self.supplier = supplier
            self.brandCount = brandCount
        }
    }

    // MARK: - Errors

    public enum PartsError: Error, Sendable {
        case categoryNotFound(Int64)
        case styleNotFound(Int64)
        case typeNotFound(Int64)
        case colorNotFound(Int64)
        case brandNotFound(Int64)
        case supplierNotFound(Int64)
        case partNotFound(Int64)
        case companionRuleNotFound(Int64)
    }

    // =========================================================================
    // MARK: - 1. Hierarchy (Category / Style / Type / Color) CRUD
    // =========================================================================

    /// Build the full nested hierarchy tree: categories -> styles -> types -> (colors, brands).
    public func getHierarchy() throws -> HierarchyTree {
        do {
            return try db.writer.read { dbConn in
                // Fetch all active categories
                let categories = try PartCategory.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM part_categories WHERE deleted_at IS NULL ORDER BY sort_order, name"
                )

                // Fetch all active styles
                let styles = try PartStyle.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM part_styles WHERE deleted_at IS NULL ORDER BY sort_order, name"
                )

                // Fetch all active types
                let types = try PartType.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM part_types WHERE deleted_at IS NULL ORDER BY sort_order, name"
                )

                // Fetch all active colors
                let colors = try PartColor.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM part_colors WHERE deleted_at IS NULL ORDER BY sort_order, name"
                )

                // Fetch all brands
                let brands = try Brand.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM brands WHERE deleted_at IS NULL ORDER BY name"
                )

                // Fetch type-color links
                let colorLinks = try Row.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM type_color_links"
                )

                // Fetch type-brand links
                let brandLinks = try Row.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM type_brand_links"
                )

                // Index colors and brands by ID for quick lookup
                let colorById = Dictionary(uniqueKeysWithValues: colors.compactMap { c in
                    c.id.map { ($0, c) }
                })
                let brandById = Dictionary(uniqueKeysWithValues: brands.compactMap { b in
                    b.id.map { ($0, b) }
                })

                // Build type-color map: typeId -> [PartColor]
                var typeColorMap: [Int64: [PartColor]] = [:]
                for link in colorLinks {
                    let typeId: Int64 = link["type_id"]
                    let colorId: Int64 = link["color_id"]
                    if let color = colorById[colorId] {
                        typeColorMap[typeId, default: []].append(color)
                    }
                }

                // Build type-brand map: typeId -> [Brand]
                var typeBrandMap: [Int64: [Brand]] = [:]
                for link in brandLinks {
                    let typeId: Int64 = link["type_id"]
                    let brandId: Int64 = link["brand_id"]
                    if let brand = brandById[brandId] {
                        typeBrandMap[typeId, default: []].append(brand)
                    }
                }

                // Group types by styleId
                var typesByStyle: [Int64: [TypeNode]] = [:]
                for type in types {
                    let tId = type.id ?? 0
                    let node = TypeNode(
                        type: type,
                        colors: typeColorMap[tId] ?? [],
                        brands: typeBrandMap[tId] ?? []
                    )
                    typesByStyle[type.styleId, default: []].append(node)
                }

                // Group styles by categoryId
                var stylesByCategory: [Int64: [StyleNode]] = [:]
                for style in styles {
                    let sId = style.id ?? 0
                    let node = StyleNode(
                        style: style,
                        types: typesByStyle[sId] ?? []
                    )
                    stylesByCategory[style.categoryId, default: []].append(node)
                }

                // Assemble category nodes
                let categoryNodes = categories.map { cat in
                    CategoryNode(
                        category: cat,
                        styles: stylesByCategory[cat.id ?? 0] ?? []
                    )
                }

                return HierarchyTree(categories: categoryNodes)
            }
        } catch {
            if isTableNotFoundError(error) { return HierarchyTree(categories: []) }
            throw error
        }
    }

    // MARK: Categories

    /// List all active (non-deleted) categories sorted by sort_order.
    public func listCategories() throws -> [PartCategory] {
        do {
            return try db.writer.read { dbConn in
                try PartCategory.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM part_categories WHERE deleted_at IS NULL ORDER BY sort_order, name"
                )
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a new category. Returns the inserted row ID.
    @discardableResult
    public func createCategory(name: String, description: String? = nil) throws -> Int64 {
        var record = PartCategory(
            name: name,
            description: description,
            sortOrder: 0
        )
        try db.writer.write { dbConn in
            try record.insert(dbConn)
        }
        return record.id!
    }

    /// Update an existing category's name, description, and/or sortOrder.
    public func updateCategory(id: Int64, name: String? = nil, description: String? = nil, sortOrder: Int? = nil) throws {
        try db.writer.write { dbConn in
            var setClauses: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let name {
                setClauses.append("name = ?")
                args.append(name)
            }
            if let description {
                setClauses.append("description = ?")
                args.append(description)
            }
            if let sortOrder {
                setClauses.append("sort_order = ?")
                args.append(sortOrder)
            }

            guard !setClauses.isEmpty else { return }
            setClauses.append("updated_at = datetime('now')")
            args.append(id)

            let sql = "UPDATE part_categories SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args)!)
        }
    }

    /// Soft-delete a category.
    public func deleteCategory(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE part_categories SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: Styles

    /// List all active styles for a given category, sorted by sort_order.
    public func listStyles(categoryId: Int64) throws -> [PartStyle] {
        do {
            return try db.writer.read { dbConn in
                try PartStyle.fetchAll(
                    dbConn,
                    sql: """
                        SELECT * FROM part_styles
                        WHERE category_id = ? AND deleted_at IS NULL
                        ORDER BY sort_order, name
                        """,
                    arguments: [categoryId]
                )
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a new style under a category. Returns the inserted row ID.
    @discardableResult
    public func createStyle(categoryId: Int64, name: String, description: String? = nil, sortOrder: Int = 0) throws -> Int64 {
        var record = PartStyle(
            categoryId: categoryId,
            name: name,
            description: description,
            sortOrder: sortOrder
        )
        try db.writer.write { dbConn in
            try record.insert(dbConn)
        }
        return record.id!
    }

    /// Update an existing style.
    public func updateStyle(id: Int64, name: String? = nil, description: String? = nil, sortOrder: Int? = nil) throws {
        try db.writer.write { dbConn in
            var setClauses: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let name {
                setClauses.append("name = ?")
                args.append(name)
            }
            if let description {
                setClauses.append("description = ?")
                args.append(description)
            }
            if let sortOrder {
                setClauses.append("sort_order = ?")
                args.append(sortOrder)
            }

            guard !setClauses.isEmpty else { return }
            setClauses.append("updated_at = datetime('now')")
            args.append(id)

            let sql = "UPDATE part_styles SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args)!)
        }
    }

    /// Soft-delete a style.
    public func deleteStyle(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE part_styles SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: Types

    /// List all active types for a given style, sorted by sort_order.
    public func listTypes(styleId: Int64) throws -> [PartType] {
        do {
            return try db.writer.read { dbConn in
                try PartType.fetchAll(
                    dbConn,
                    sql: """
                        SELECT * FROM part_types
                        WHERE style_id = ? AND deleted_at IS NULL
                        ORDER BY sort_order, name
                        """,
                    arguments: [styleId]
                )
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a single type by ID.
    public func getType(id: Int64) throws -> PartType {
        let record = try db.writer.read { dbConn in
            try PartType.fetchOne(
                dbConn,
                sql: "SELECT * FROM part_types WHERE id = ?",
                arguments: [id]
            )
        }
        guard let record else { throw PartsError.typeNotFound(id) }
        return record
    }

    /// Create a new type under a style. Returns the inserted row ID.
    @discardableResult
    public func createType(styleId: Int64, name: String, description: String? = nil, sortOrder: Int = 0) throws -> Int64 {
        var record = PartType(
            styleId: styleId,
            name: name,
            description: description,
            sortOrder: sortOrder
        )
        try db.writer.write { dbConn in
            try record.insert(dbConn)
        }
        return record.id!
    }

    /// Update an existing type.
    public func updateType(id: Int64, name: String? = nil, description: String? = nil, sortOrder: Int? = nil) throws {
        try db.writer.write { dbConn in
            var setClauses: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let name {
                setClauses.append("name = ?")
                args.append(name)
            }
            if let description {
                setClauses.append("description = ?")
                args.append(description)
            }
            if let sortOrder {
                setClauses.append("sort_order = ?")
                args.append(sortOrder)
            }

            guard !setClauses.isEmpty else { return }
            setClauses.append("updated_at = datetime('now')")
            args.append(id)

            let sql = "UPDATE part_types SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args)!)
        }
    }

    /// Soft-delete a type.
    public func deleteType(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE part_types SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: Colors

    /// List all active colors sorted by sort_order.
    public func listColors() throws -> [PartColor] {
        do {
            return try db.writer.read { dbConn in
                try PartColor.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM part_colors WHERE deleted_at IS NULL ORDER BY sort_order, name"
                )
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a new color. Returns the inserted row ID.
    @discardableResult
    public func createColor(name: String, hexCode: String? = nil, sortOrder: Int = 0) throws -> Int64 {
        var record = PartColor(
            name: name,
            hexCode: hexCode,
            sortOrder: sortOrder
        )
        try db.writer.write { dbConn in
            try record.insert(dbConn)
        }
        return record.id!
    }

    /// Update an existing color.
    public func updateColor(id: Int64, name: String? = nil, hexCode: String? = nil, sortOrder: Int? = nil) throws {
        try db.writer.write { dbConn in
            var setClauses: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let name {
                setClauses.append("name = ?")
                args.append(name)
            }
            if let hexCode {
                setClauses.append("hex_code = ?")
                args.append(hexCode)
            }
            if let sortOrder {
                setClauses.append("sort_order = ?")
                args.append(sortOrder)
            }

            guard !setClauses.isEmpty else { return }
            args.append(id)

            let sql = "UPDATE part_colors SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args)!)
        }
    }

    /// Soft-delete a color.
    public func deleteColor(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE part_colors SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: Type-Color / Type-Brand Links

    /// Link a type to a color. Returns the inserted link row ID.
    @discardableResult
    public func linkTypeToColor(typeId: Int64, colorId: Int64, imageUrl: String? = nil) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO type_color_links (type_id, color_id, image_url, created_at)
                    VALUES (?, ?, ?, datetime('now'))
                    """,
                arguments: [typeId, colorId, imageUrl]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Remove a type-color link by link ID.
    public func unlinkTypeColor(linkId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "DELETE FROM type_color_links WHERE id = ?",
                arguments: [linkId]
            )
        }
    }

    /// Link a type to a brand. Returns the inserted link row ID.
    @discardableResult
    public func linkTypeToBrand(typeId: Int64, brandId: Int64) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO type_brand_links (type_id, brand_id, created_at)
                    VALUES (?, ?, datetime('now'))
                    """,
                arguments: [typeId, brandId]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Remove a type-brand link by link ID.
    public func unlinkTypeBrand(linkId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "DELETE FROM type_brand_links WHERE id = ?",
                arguments: [linkId]
            )
        }
    }

    // =========================================================================
    // MARK: - 2. Catalog (Part CRUD)
    // =========================================================================

    /// List parts with pagination and optional filters.
    /// Joins category and brand names for display. Includes aggregate stock count.
    public func listParts(
        search: String? = nil,
        categoryId: Int64? = nil,
        brandId: Int64? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) throws -> [PartWithDetails] {
        do {
            return try db.writer.read { dbConn in
                var whereClauses = ["p.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(p.name LIKE ? OR p.code LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                }
                if let categoryId {
                    whereClauses.append("p.category_id = ?")
                    args.append(categoryId)
                }
                if let brandId {
                    whereClauses.append("p.brand_id = ?")
                    args.append(brandId)
                }

                args.append(limit)
                args.append(offset)

                let sql = """
                    SELECT p.*,
                           pc.name AS category_name,
                           ps.name AS style_name,
                           pt.name AS type_name,
                           pcol.name AS color_name,
                           b.name AS brand_name,
                           COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) AS total_stock
                    FROM parts p
                    LEFT JOIN part_categories pc ON pc.id = p.category_id
                    LEFT JOIN part_styles ps ON ps.id = p.style_id
                    LEFT JOIN part_types pt ON pt.id = p.type_id
                    LEFT JOIN part_colors pcol ON pcol.id = p.color_id
                    LEFT JOIN brands b ON b.id = p.brand_id
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY p.name ASC
                    LIMIT ? OFFSET ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args)!)
                return rows.map { row in
                    let part = try! Part(row: row)
                    return PartWithDetails(
                        part: part,
                        categoryName: row["category_name"] as String?,
                        styleName: row["style_name"] as String?,
                        typeName: row["type_name"] as String?,
                        colorName: row["color_name"] as String?,
                        brandName: row["brand_name"] as String?,
                        totalStock: row["total_stock"] as Int
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a single part by ID with joined dimension names and stock total.
    public func getPart(id: Int64) throws -> PartWithDetails {
        let result: PartWithDetails? = try db.writer.read { dbConn in
            let sql = """
                SELECT p.*,
                       pc.name AS category_name,
                       ps.name AS style_name,
                       pt.name AS type_name,
                       pcol.name AS color_name,
                       b.name AS brand_name,
                       COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) AS total_stock
                FROM parts p
                LEFT JOIN part_categories pc ON pc.id = p.category_id
                LEFT JOIN part_styles ps ON ps.id = p.style_id
                LEFT JOIN part_types pt ON pt.id = p.type_id
                LEFT JOIN part_colors pcol ON pcol.id = p.color_id
                LEFT JOIN brands b ON b.id = p.brand_id
                WHERE p.id = ?
                """
            guard let row = try Row.fetchOne(dbConn, sql: sql, arguments: [id]) else {
                return nil
            }
            let part = try Part(row: row)
            return PartWithDetails(
                part: part,
                categoryName: row["category_name"] as String?,
                styleName: row["style_name"] as String?,
                typeName: row["type_name"] as String?,
                colorName: row["color_name"] as String?,
                brandName: row["brand_name"] as String?,
                totalStock: row["total_stock"] as Int
            )
        }
        guard let result else { throw PartsError.partNotFound(id) }
        return result
    }

    /// Quick search parts by name or code. Lightweight (no joins).
    public func searchParts(query: String, limit: Int = 20) throws -> [Part] {
        do {
            return try db.writer.read { dbConn in
                let pattern = "%\(query)%"
                return try Part.fetchAll(
                    dbConn,
                    sql: """
                        SELECT * FROM parts
                        WHERE deleted_at IS NULL
                          AND (name LIKE ? OR code LIKE ?)
                        ORDER BY name ASC
                        LIMIT ?
                        """,
                    arguments: [pattern, pattern, limit]
                )
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a new part. Returns the inserted row ID.
    @discardableResult
    public func createPart(
        categoryId: Int64,
        name: String,
        partType: String = "general",
        styleId: Int64? = nil,
        typeId: Int64? = nil,
        colorId: Int64? = nil,
        code: String? = nil,
        description: String? = nil,
        brandId: Int64? = nil,
        manufacturerPartNumber: String? = nil,
        unitOfMeasure: String? = nil,
        weightLbs: Double? = nil,
        companyCostPrice: Double = 0.0,
        companyMarkupPercent: Double = 0.0,
        minStockLevel: Int? = nil,
        maxStockLevel: Int? = nil,
        targetStockLevel: Int? = nil,
        reorderPoint: Int? = nil,
        notes: String? = nil,
        imageUrl: String? = nil,
        shelfLocation: String? = nil,
        binLocation: String? = nil
    ) throws -> Int64 {
        var record = Part(
            categoryId: categoryId,
            styleId: styleId,
            typeId: typeId,
            colorId: colorId,
            partType: partType,
            code: code,
            name: name,
            description: description,
            brandId: brandId,
            manufacturerPartNumber: manufacturerPartNumber,
            unitOfMeasure: unitOfMeasure,
            weightLbs: weightLbs,
            companyCostPrice: companyCostPrice,
            companyMarkupPercent: companyMarkupPercent,
            minStockLevel: minStockLevel,
            maxStockLevel: maxStockLevel,
            targetStockLevel: targetStockLevel,
            reorderPoint: reorderPoint,
            notes: notes,
            imageUrl: imageUrl,
            shelfLocation: shelfLocation,
            binLocation: binLocation
        )
        try db.writer.write { dbConn in
            try record.insert(dbConn)
        }
        return record.id!
    }

    /// Update an existing part. Only non-nil fields are updated.
    public func updatePart(
        id: Int64,
        name: String? = nil,
        code: String? = nil,
        description: String? = nil,
        categoryId: Int64? = nil,
        styleId: Int64? = nil,
        typeId: Int64? = nil,
        colorId: Int64? = nil,
        brandId: Int64? = nil,
        partType: String? = nil,
        manufacturerPartNumber: String? = nil,
        unitOfMeasure: String? = nil,
        weightLbs: Double? = nil,
        companyCostPrice: Double? = nil,
        companyMarkupPercent: Double? = nil,
        minStockLevel: Int? = nil,
        maxStockLevel: Int? = nil,
        targetStockLevel: Int? = nil,
        reorderPoint: Int? = nil,
        isDeprecated: Int? = nil,
        deprecationReason: String? = nil,
        notes: String? = nil,
        imageUrl: String? = nil,
        shelfLocation: String? = nil,
        binLocation: String? = nil
    ) throws {
        try db.writer.write { dbConn in
            var setClauses: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let name { setClauses.append("name = ?"); args.append(name) }
            if let code { setClauses.append("code = ?"); args.append(code) }
            if let description { setClauses.append("description = ?"); args.append(description) }
            if let categoryId { setClauses.append("category_id = ?"); args.append(categoryId) }
            if let styleId { setClauses.append("style_id = ?"); args.append(styleId) }
            if let typeId { setClauses.append("type_id = ?"); args.append(typeId) }
            if let colorId { setClauses.append("color_id = ?"); args.append(colorId) }
            if let brandId { setClauses.append("brand_id = ?"); args.append(brandId) }
            if let partType { setClauses.append("part_type = ?"); args.append(partType) }
            if let manufacturerPartNumber { setClauses.append("manufacturer_part_number = ?"); args.append(manufacturerPartNumber) }
            if let unitOfMeasure { setClauses.append("unit_of_measure = ?"); args.append(unitOfMeasure) }
            if let weightLbs { setClauses.append("weight_lbs = ?"); args.append(weightLbs) }
            if let companyCostPrice { setClauses.append("company_cost_price = ?"); args.append(companyCostPrice) }
            if let companyMarkupPercent { setClauses.append("company_markup_percent = ?"); args.append(companyMarkupPercent) }
            if let minStockLevel { setClauses.append("min_stock_level = ?"); args.append(minStockLevel) }
            if let maxStockLevel { setClauses.append("max_stock_level = ?"); args.append(maxStockLevel) }
            if let targetStockLevel { setClauses.append("target_stock_level = ?"); args.append(targetStockLevel) }
            if let reorderPoint { setClauses.append("reorder_point = ?"); args.append(reorderPoint) }
            if let isDeprecated { setClauses.append("is_deprecated = ?"); args.append(isDeprecated) }
            if let deprecationReason { setClauses.append("deprecation_reason = ?"); args.append(deprecationReason) }
            if let notes { setClauses.append("notes = ?"); args.append(notes) }
            if let imageUrl { setClauses.append("image_url = ?"); args.append(imageUrl) }
            if let shelfLocation { setClauses.append("shelf_location = ?"); args.append(shelfLocation) }
            if let binLocation { setClauses.append("bin_location = ?"); args.append(binLocation) }

            guard !setClauses.isEmpty else { return }
            setClauses.append("updated_at = datetime('now')")
            args.append(id)

            let sql = "UPDATE parts SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args)!)
        }
    }

    /// Soft-delete a part.
    public func deletePart(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Get aggregate catalog statistics.
    public func getCatalogStats() throws -> CatalogStats {
        let totalParts = try safeCount(
            sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL"
        )
        let activeParts = try safeCount(
            sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL AND (is_deprecated = 0 OR is_deprecated IS NULL)"
        )
        let deprecatedParts = try safeCount(
            sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL AND is_deprecated = 1"
        )
        let lowStockParts = try safeCount(
            sql: """
                SELECT COUNT(*) FROM parts p
                WHERE p.deleted_at IS NULL
                  AND p.min_stock_level > 0
                  AND (
                    SELECT COALESCE(SUM(s.qty), 0)
                    FROM stock s
                    WHERE s.part_id = p.id AND s.deleted_at IS NULL
                  ) < p.min_stock_level
                """
        )
        return CatalogStats(
            totalParts: totalParts,
            activeParts: activeParts,
            deprecatedParts: deprecatedParts,
            lowStockParts: lowStockParts
        )
    }

    // =========================================================================
    // MARK: - 3. Brands
    // =========================================================================

    /// List all active brands with their part counts. Optionally filter by search text.
    public func listBrands(search: String? = nil) throws -> [BrandWithCount] {
        do {
            return try db.writer.read { dbConn in
                var whereClauses = ["b.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("b.name LIKE ?")
                    args.append("%\(search)%")
                }

                let sql = """
                    SELECT b.*,
                           COALESCE((SELECT COUNT(*) FROM parts p WHERE p.brand_id = b.id AND p.deleted_at IS NULL), 0) AS part_count
                    FROM brands b
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY b.name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args)!)
                return rows.map { row in
                    let brand = try! Brand(row: row)
                    return BrandWithCount(brand: brand, partCount: row["part_count"] as Int)
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a single brand by ID.
    public func getBrand(id: Int64) throws -> Brand {
        let record = try db.writer.read { dbConn in
            try Brand.fetchOne(
                dbConn,
                sql: "SELECT * FROM brands WHERE id = ?",
                arguments: [id]
            )
        }
        guard let record else { throw PartsError.brandNotFound(id) }
        return record
    }

    /// Create a new brand. Returns the inserted row ID.
    @discardableResult
    public func createBrand(name: String, website: String? = nil, notes: String? = nil) throws -> Int64 {
        var record = Brand(name: name, website: website, notes: notes)
        try db.writer.write { dbConn in
            try record.insert(dbConn)
        }
        return record.id!
    }

    /// Update an existing brand.
    public func updateBrand(id: Int64, name: String? = nil, website: String? = nil, notes: String? = nil) throws {
        try db.writer.write { dbConn in
            var setClauses: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let name { setClauses.append("name = ?"); args.append(name) }
            if let website { setClauses.append("website = ?"); args.append(website) }
            if let notes { setClauses.append("notes = ?"); args.append(notes) }

            guard !setClauses.isEmpty else { return }
            setClauses.append("updated_at = datetime('now')")
            args.append(id)

            let sql = "UPDATE brands SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args)!)
        }
    }

    /// Soft-delete a brand.
    public func deleteBrand(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE brands SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - 4. Suppliers
    // =========================================================================

    /// List all active suppliers with associated brand count. Optionally filter by search text.
    public func listSuppliers(search: String? = nil) throws -> [SupplierWithCount] {
        do {
            return try db.writer.read { dbConn in
                var whereClauses = ["s.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("s.name LIKE ?")
                    args.append("%\(search)%")
                }

                let sql = """
                    SELECT s.*,
                           COALESCE((SELECT COUNT(*) FROM brand_supplier_links bsl WHERE bsl.supplier_id = s.id AND bsl.deleted_at IS NULL), 0) AS brand_count
                    FROM suppliers s
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY s.name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args)!)
                return rows.map { row in
                    let supplier = try! Supplier(row: row)
                    return SupplierWithCount(supplier: supplier, brandCount: row["brand_count"] as Int)
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a single supplier by ID.
    public func getSupplier(id: Int64) throws -> Supplier {
        let record = try db.writer.read { dbConn in
            try Supplier.fetchOne(
                dbConn,
                sql: "SELECT * FROM suppliers WHERE id = ?",
                arguments: [id]
            )
        }
        guard let record else { throw PartsError.supplierNotFound(id) }
        return record
    }

    /// Create a new supplier. Returns the inserted row ID.
    @discardableResult
    public func createSupplier(
        name: String,
        contactName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        address: String? = nil,
        website: String? = nil,
        notes: String? = nil
    ) throws -> Int64 {
        var record = Supplier(
            name: name,
            contactName: contactName,
            email: email,
            phone: phone,
            address: address,
            website: website,
            notes: notes
        )
        try db.writer.write { dbConn in
            try record.insert(dbConn)
        }
        return record.id!
    }

    /// Update an existing supplier.
    public func updateSupplier(
        id: Int64,
        name: String? = nil,
        contactName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        address: String? = nil,
        website: String? = nil,
        notes: String? = nil
    ) throws {
        try db.writer.write { dbConn in
            var setClauses: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let name { setClauses.append("name = ?"); args.append(name) }
            if let contactName { setClauses.append("contact_name = ?"); args.append(contactName) }
            if let email { setClauses.append("email = ?"); args.append(email) }
            if let phone { setClauses.append("phone = ?"); args.append(phone) }
            if let address { setClauses.append("address = ?"); args.append(address) }
            if let website { setClauses.append("website = ?"); args.append(website) }
            if let notes { setClauses.append("notes = ?"); args.append(notes) }

            guard !setClauses.isEmpty else { return }
            setClauses.append("updated_at = datetime('now')")
            args.append(id)

            let sql = "UPDATE suppliers SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args)!)
        }
    }

    /// Soft-delete a supplier.
    public func deleteSupplier(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Get all suppliers carrying a specific part (via part_supplier_links).
    public func getPartSuppliers(partId: Int64) throws -> [PartSupplierLinkWithName] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT psl.*, s.name AS supplier_name
                        FROM part_supplier_links psl
                        JOIN suppliers s ON s.id = psl.supplier_id
                        WHERE psl.part_id = ? AND psl.deleted_at IS NULL
                        ORDER BY psl.is_preferred DESC, s.name ASC
                        """,
                    arguments: [partId]
                )
                return rows.map { row in
                    PartSupplierLinkWithName(
                        id: row["id"] as Int64,
                        partId: row["part_id"] as Int64,
                        supplierId: row["supplier_id"] as Int64,
                        supplierPartNumber: row["supplier_part_number"] as String?,
                        supplierCostPrice: row["supplier_cost_price"] as Double?,
                        moq: row["moq"] as Int?,
                        discountBrackets: row["discount_brackets"] as String?,
                        lastPriceDate: row["last_price_date"] as String?,
                        isPreferred: row["is_preferred"] as Int,
                        deletedAt: row["deleted_at"] as String?,
                        createdAt: row["created_at"] as String?,
                        supplierName: row["supplier_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Add a part-supplier link. Returns the inserted row ID.
    @discardableResult
    public func addPartSupplierLink(
        partId: Int64,
        supplierId: Int64,
        supplierPartNumber: String? = nil,
        costPrice: Double? = nil,
        moq: Int? = nil,
        isPreferred: Bool = false
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO part_supplier_links
                    (part_id, supplier_id, supplier_part_number, supplier_cost_price, moq, is_preferred, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [partId, supplierId, supplierPartNumber, costPrice, moq, isPreferred ? 1 : 0]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Soft-delete a part-supplier link.
    public func removePartSupplierLink(linkId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE part_supplier_links SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [linkId]
            )
        }
    }

    /// Get all suppliers for a brand (via brand_supplier_links).
    public func getBrandSuppliers(brandId: Int64) throws -> [Supplier] {
        do {
            return try db.writer.read { dbConn in
                try Supplier.fetchAll(
                    dbConn,
                    sql: """
                        SELECT s.* FROM suppliers s
                        JOIN brand_supplier_links bsl ON bsl.supplier_id = s.id
                        WHERE bsl.brand_id = ? AND bsl.deleted_at IS NULL AND s.deleted_at IS NULL
                        ORDER BY s.name ASC
                        """,
                    arguments: [brandId]
                )
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get all brands for a supplier (via brand_supplier_links).
    public func getSupplierBrands(supplierId: Int64) throws -> [Brand] {
        do {
            return try db.writer.read { dbConn in
                try Brand.fetchAll(
                    dbConn,
                    sql: """
                        SELECT b.* FROM brands b
                        JOIN brand_supplier_links bsl ON bsl.brand_id = b.id
                        WHERE bsl.supplier_id = ? AND bsl.deleted_at IS NULL AND b.deleted_at IS NULL
                        ORDER BY b.name ASC
                        """,
                    arguments: [supplierId]
                )
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 5. Pricing
    // =========================================================================

    /// Update a part's company cost price and markup percent. Returns the updated part.
    @discardableResult
    public func updatePartPricing(
        partId: Int64,
        companyCostPrice: Double,
        companyMarkupPercent: Double
    ) throws -> Part {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE parts
                    SET company_cost_price = ?,
                        company_markup_percent = ?,
                        cost_last_updated = datetime('now'),
                        updated_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [companyCostPrice, companyMarkupPercent, partId]
            )
        }
        let record = try db.writer.read { dbConn in
            try Part.fetchOne(
                dbConn,
                sql: "SELECT * FROM parts WHERE id = ?",
                arguments: [partId]
            )
        }
        guard let record else { throw PartsError.partNotFound(partId) }
        return record
    }

    // =========================================================================
    // MARK: - 6. Stock
    // =========================================================================

    /// Get all stock rows for a part across all locations.
    public func getPartStock(partId: Int64) throws -> [Row] {
        do {
            return try db.writer.read { dbConn in
                try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT * FROM stock
                        WHERE part_id = ? AND deleted_at IS NULL
                        ORDER BY location_type, location_id
                        """,
                    arguments: [partId]
                )
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a stock summary for a part: total quantity and breakdown by location type.
    public func getPartStockSummary(partId: Int64) throws -> StockSummary {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT location_type, SUM(qty) AS type_total
                        FROM stock
                        WHERE part_id = ? AND deleted_at IS NULL
                        GROUP BY location_type
                        """,
                    arguments: [partId]
                )

                var total = 0
                var byType: [String: Int] = [:]
                for row in rows {
                    let locType: String = row["location_type"]
                    let typeTotal: Int = row["type_total"]
                    byType[locType] = typeTotal
                    total += typeTotal
                }

                return StockSummary(total: total, byLocationType: byType)
            }
        } catch {
            if isTableNotFoundError(error) {
                return StockSummary(total: 0, byLocationType: [:])
            }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 7. Forecasting
    // =========================================================================

    /// List parts with their forecast fields for the forecasting dashboard.
    public func listForecastData(search: String? = nil, limit: Int = 50, offset: Int = 0) throws -> [Part] {
        do {
            return try db.writer.read { dbConn in
                var whereClauses = ["deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(name LIKE ? OR code LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                }

                args.append(limit)
                args.append(offset)

                let sql = """
                    SELECT * FROM parts
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY forecast_days_until_low ASC, name ASC
                    LIMIT ? OFFSET ?
                    """

                return try Part.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args)!)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Recalculate Average Daily Usage (ADU) for the last 30 and 90 days
    /// from stock_movements. Updates each part's forecast fields.
    ///
    /// This is a batch operation that runs across all non-deleted parts.
    public func recalculateForecasts() throws {
        do {
            try db.writer.write { dbConn in
                // Get all active parts
                let partIds = try Int64.fetchAll(
                    dbConn,
                    sql: "SELECT id FROM parts WHERE deleted_at IS NULL"
                )

                for partId in partIds {
                    // ADU 30: total outbound movements in last 30 days / 30
                    let consumed30 = try Int.fetchOne(
                        dbConn,
                        sql: """
                            SELECT COALESCE(SUM(ABS(qty)), 0)
                            FROM stock_movements
                            WHERE part_id = ?
                              AND movement_type IN ('consume', 'transfer', 'return_to_supplier')
                              AND created_at >= datetime('now', '-30 days')
                              AND deleted_at IS NULL
                            """,
                        arguments: [partId]
                    ) ?? 0
                    let adu30 = Double(consumed30) / 30.0

                    // ADU 90: total outbound movements in last 90 days / 90
                    let consumed90 = try Int.fetchOne(
                        dbConn,
                        sql: """
                            SELECT COALESCE(SUM(ABS(qty)), 0)
                            FROM stock_movements
                            WHERE part_id = ?
                              AND movement_type IN ('consume', 'transfer', 'return_to_supplier')
                              AND created_at >= datetime('now', '-90 days')
                              AND deleted_at IS NULL
                            """,
                        arguments: [partId]
                    ) ?? 0
                    let adu90 = Double(consumed90) / 90.0

                    // Current stock
                    let currentStock = try Int.fetchOne(
                        dbConn,
                        sql: """
                            SELECT COALESCE(SUM(qty), 0) FROM stock
                            WHERE part_id = ? AND deleted_at IS NULL
                            """,
                        arguments: [partId]
                    ) ?? 0

                    // Days until low (using ADU-30 as primary indicator)
                    let minStock = try Int.fetchOne(
                        dbConn,
                        sql: "SELECT COALESCE(min_stock_level, 0) FROM parts WHERE id = ?",
                        arguments: [partId]
                    ) ?? 0

                    let daysUntilLow: Int
                    if adu30 > 0 {
                        let surplus = Double(currentStock - minStock)
                        daysUntilLow = max(0, Int(surplus / adu30))
                    } else {
                        daysUntilLow = 999
                    }

                    // Suggested reorder point = ADU-30 * 7 (one week lead buffer)
                    let forecastReorderPoint = Int(adu30 * 7)

                    // Target qty = reorder point * 2
                    let forecastTargetQty = forecastReorderPoint * 2

                    // Suggested order = target - current stock (clamped to 0)
                    let forecastSuggestedOrder = max(0, forecastTargetQty - currentStock)

                    try dbConn.execute(
                        sql: """
                            UPDATE parts SET
                                forecast_adu_30 = ?,
                                forecast_adu_90 = ?,
                                forecast_reorder_point = ?,
                                forecast_target_qty = ?,
                                forecast_suggested_order = ?,
                                forecast_days_until_low = ?,
                                forecast_last_run = datetime('now'),
                                updated_at = datetime('now')
                            WHERE id = ?
                            """,
                        arguments: [adu30, adu90, forecastReorderPoint, forecastTargetQty, forecastSuggestedOrder, daysUntilLow, partId]
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 8. Companions
    // =========================================================================

    /// List all companion rules with their source and target entries.
    public func listCompanionRules() throws -> [CompanionRuleWithRelations] {
        do {
            return try db.writer.read { dbConn in
                let rules = try Row.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM companion_rules ORDER BY name ASC"
                )

                return try rules.map { ruleRow in
                    let ruleId: Int64 = ruleRow["id"]

                    let sourceRows = try Row.fetchAll(
                        dbConn,
                        sql: "SELECT * FROM companion_rule_sources WHERE rule_id = ?",
                        arguments: [ruleId]
                    )

                    let targetRows = try Row.fetchAll(
                        dbConn,
                        sql: "SELECT * FROM companion_rule_targets WHERE rule_id = ?",
                        arguments: [ruleId]
                    )

                    let sources = sourceRows.map { row in
                        CompanionRuleSource(
                            id: row["id"] as Int64,
                            ruleId: row["rule_id"] as Int64,
                            categoryId: row["category_id"] as Int64,
                            styleId: row["style_id"] as Int64?
                        )
                    }

                    let targets = targetRows.map { row in
                        CompanionRuleTarget(
                            id: row["id"] as Int64,
                            ruleId: row["rule_id"] as Int64,
                            categoryId: row["category_id"] as Int64,
                            styleId: row["style_id"] as Int64?
                        )
                    }

                    return CompanionRuleWithRelations(
                        id: ruleId,
                        name: ruleRow["name"] as String,
                        description: ruleRow["description"] as String?,
                        styleMatch: ruleRow["style_match"] as String,
                        qtyMode: ruleRow["qty_mode"] as String,
                        qtyRatio: ruleRow["qty_ratio"] as Double,
                        isActive: ruleRow["is_active"] as Int,
                        createdBy: ruleRow["created_by"] as Int64?,
                        createdAt: ruleRow["created_at"] as String?,
                        updatedAt: ruleRow["updated_at"] as String?,
                        sources: sources,
                        targets: targets
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a new companion rule. Returns the inserted rule ID.
    @discardableResult
    public func createCompanionRule(
        name: String,
        description: String? = nil,
        styleMatch: String = "auto",
        qtyMode: String = "sum",
        qtyRatio: Double = 1.0
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO companion_rules (name, description, style_match, qty_mode, qty_ratio, is_active, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
                    """,
                arguments: [name, description, styleMatch, qtyMode, qtyRatio]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Update an existing companion rule.
    public func updateCompanionRule(
        id: Int64,
        name: String? = nil,
        description: String? = nil,
        styleMatch: String? = nil,
        qtyMode: String? = nil,
        qtyRatio: Double? = nil,
        isActive: Int? = nil
    ) throws {
        try db.writer.write { dbConn in
            var setClauses: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let name { setClauses.append("name = ?"); args.append(name) }
            if let description { setClauses.append("description = ?"); args.append(description) }
            if let styleMatch { setClauses.append("style_match = ?"); args.append(styleMatch) }
            if let qtyMode { setClauses.append("qty_mode = ?"); args.append(qtyMode) }
            if let qtyRatio { setClauses.append("qty_ratio = ?"); args.append(qtyRatio) }
            if let isActive { setClauses.append("is_active = ?"); args.append(isActive) }

            guard !setClauses.isEmpty else { return }
            setClauses.append("updated_at = datetime('now')")
            args.append(id)

            let sql = "UPDATE companion_rules SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args)!)
        }
    }

    /// Soft-delete a companion rule by deactivating it.
    /// (companion_rules does not have a deleted_at column, so we set is_active = 0.)
    public func deleteCompanionRule(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE companion_rules SET is_active = 0, updated_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - 9. Alternatives
    // =========================================================================

    /// List all alternatives for a part (bidirectional).
    /// Returns rows where either part_id or alternative_part_id matches the given partId.
    public func listPartAlternatives(partId: Int64) throws -> [PartAlternativeWithName] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT pa.*,
                               CASE WHEN pa.part_id = ? THEN p2.name ELSE p1.name END AS alt_part_name,
                               CASE WHEN pa.part_id = ? THEN p2.code ELSE p1.code END AS alt_part_code
                        FROM part_alternatives pa
                        JOIN parts p1 ON p1.id = pa.part_id
                        JOIN parts p2 ON p2.id = pa.alternative_part_id
                        WHERE pa.part_id = ? OR pa.alternative_part_id = ?
                        ORDER BY pa.preference ASC, pa.id ASC
                        """,
                    arguments: [partId, partId, partId, partId]
                )
                return rows.map { row in
                    PartAlternativeWithName(
                        id: row["id"] as Int64,
                        partId: row["part_id"] as Int64,
                        alternativePartId: row["alternative_part_id"] as Int64,
                        relationship: row["relationship"] as String,
                        preference: row["preference"] as Int,
                        notes: row["notes"] as String?,
                        createdBy: row["created_by"] as Int64?,
                        createdAt: row["created_at"] as String?,
                        alternativePartName: row["alt_part_name"] as String?,
                        alternativePartCode: row["alt_part_code"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Link two parts as alternatives. Returns the inserted row ID.
    @discardableResult
    public func linkPartAlternative(
        partId: Int64,
        alternativePartId: Int64,
        relationship: String = "substitute",
        preference: Int = 0,
        notes: String? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO part_alternatives
                    (part_id, alternative_part_id, relationship, preference, notes, created_at)
                    VALUES (?, ?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [partId, alternativePartId, relationship, preference, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Delete a part alternative link by link ID.
    public func unlinkPartAlternative(linkId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "DELETE FROM part_alternatives WHERE id = ?",
                arguments: [linkId]
            )
        }
    }

    // =========================================================================
    // MARK: - 10. Import / Export (Stubs)
    // =========================================================================

    /// Export all active parts as a CSV string.
    /// Includes basic fields: id, code, name, category_id, brand_id, cost, markup.
    public func exportPartsCSV() throws -> String {
        do {
            let parts = try db.writer.read { dbConn in
                try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT p.id, p.code, p.name, p.category_id,
                               pc.name AS category_name, p.brand_id,
                               b.name AS brand_name,
                               p.company_cost_price, p.company_markup_percent,
                               p.min_stock_level, p.unit_of_measure
                        FROM parts p
                        LEFT JOIN part_categories pc ON pc.id = p.category_id
                        LEFT JOIN brands b ON b.id = p.brand_id
                        WHERE p.deleted_at IS NULL
                        ORDER BY p.name ASC
                        """
                )
            }

            var csv = "id,code,name,category_id,category_name,brand_id,brand_name,company_cost_price,company_markup_percent,min_stock_level,unit_of_measure\n"
            for row in parts {
                let id: Int64 = row["id"]
                let code: String = row["code"] ?? ""
                let name: String = row["name"]
                let categoryId: Int64 = row["category_id"]
                let categoryName: String = row["category_name"] ?? ""
                let brandId: Int64? = row["brand_id"]
                let brandName: String = row["brand_name"] ?? ""
                let cost: Double = row["company_cost_price"]
                let markup: Double = row["company_markup_percent"]
                let minStock: Int = row["min_stock_level"] ?? 0
                let uom: String = row["unit_of_measure"] ?? "each"

                // Escape CSV fields that may contain commas or quotes
                let escapedName = csvEscape(name)
                let escapedCategoryName = csvEscape(categoryName)
                let escapedBrandName = csvEscape(brandName)

                csv += "\(id),\(csvEscape(code)),\(escapedName),\(categoryId),\(escapedCategoryName),\(brandId.map(String.init) ?? ""),\(escapedBrandName),\(cost),\(markup),\(minStock),\(uom)\n"
            }

            return csv
        } catch {
            if isTableNotFoundError(error) { return "" }
            throw error
        }
    }

    /// Import parts from a CSV string.
    /// **Stub implementation** -- parses the header but does not insert yet.
    /// Returns the number of rows that would be imported.
    public func importPartsCSV(csvString: String) throws -> Int {
        let lines = csvString.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return 0 }
        // First line is header; remaining lines are data rows
        return lines.count - 1
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Execute a `SELECT COUNT(*)` query and return the integer result.
    /// If the table does not exist (e.g., migration hasn't run), returns 0.
    private func safeCount(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Int {
        do {
            return try db.writer.read { dbConn in
                try Int.fetchOne(dbConn, sql: sql, arguments: arguments) ?? 0
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    ///
    /// SQLite returns `SQLITE_ERROR` (code 1) with a message like
    /// "no such table: <name>" when a query references a table that
    /// doesn't exist. We treat this as a non-fatal condition so the
    /// service can still return partial data on freshly created databases.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table")
    }

    /// Escape a string for CSV output. Wraps in quotes if it contains commas,
    /// double-quotes, or newlines. Doubles any existing double-quotes.
    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
