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

    /// A brand node within a type, containing the colors that have catalog parts for this brand+type combination.
    public struct BrandNode: Sendable, Identifiable {
        public let brand: Brand?          // nil = "General" (no specific brand)
        public let colors: [PartColor]    // colors with catalog parts for this brand+type
        public let allColors: [PartColor] // all available colors for the color picker
        public var id: Int64 { brand?.id ?? -1 }
        public var name: String { brand?.name ?? "General" }
        public var isGeneral: Bool { brand == nil }

        public init(brand: Brand?, colors: [PartColor], allColors: [PartColor]) {
            self.brand = brand
            self.colors = colors
            self.allColors = allColors
        }
    }

    /// A single type node with its nested brand nodes (each brand has its own colors).
    public struct TypeNode: Sendable, Identifiable {
        public var type: PartType
        public var brandNodes: [BrandNode]  // brands with their per-brand colors
        public var id: Int64? { type.id }

        /// Backward-compatible: flat list of all linked brands (excluding General).
        public var brands: [Brand] {
            brandNodes.compactMap { $0.brand }
        }

        /// Backward-compatible: flat list of all colors across all brands.
        public var colors: [PartColor] {
            var seen = Set<Int64>()
            var result: [PartColor] = []
            for node in brandNodes {
                for color in node.colors {
                    if let cid = color.id, seen.insert(cid).inserted {
                        result.append(color)
                    }
                }
            }
            return result
        }

        /// Convenience: all linked brand IDs (excluding General).
        public var linkedBrandIds: Set<Int64> {
            Set(brandNodes.compactMap { $0.brand?.id })
        }

        /// Convenience: total color count across all brands.
        public var totalColorCount: Int {
            brandNodes.reduce(0) { $0 + $1.colors.count }
        }

        public init(type: PartType, brandNodes: [BrandNode]) {
            self.type = type
            self.brandNodes = brandNodes
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
        public var typeId: Int64?

        public init(id: Int64, ruleId: Int64, categoryId: Int64, styleId: Int64?, typeId: Int64? = nil) {
            self.id = id
            self.ruleId = ruleId
            self.categoryId = categoryId
            self.styleId = styleId
            self.typeId = typeId
        }
    }

    /// A target entry for a companion rule.
    public struct CompanionRuleTarget: Sendable {
        public var id: Int64
        public var ruleId: Int64
        public var categoryId: Int64
        public var styleId: Int64?
        public var typeId: Int64?

        public init(id: Int64, ruleId: Int64, categoryId: Int64, styleId: Int64?, typeId: Int64? = nil) {
            self.id = id
            self.ruleId = ruleId
            self.categoryId = categoryId
            self.styleId = styleId
            self.typeId = typeId
        }
    }

    /// A part alternative with joined part name for display.
    public struct PartAlternativeWithName: Sendable, Identifiable {
        public var id: Int64
        public var partId: Int64
        public var alternativePartId: Int64
        public var relationship: String
        public var preference: Int
        public var notes: String?
        public var createdBy: Int64?
        public var createdAt: String?
        public var partName: String?
        public var partCode: String?
        public var alternativePartName: String?
        public var alternativePartCode: String?

        public init(
            id: Int64, partId: Int64, alternativePartId: Int64,
            relationship: String, preference: Int, notes: String?,
            createdBy: Int64?, createdAt: String?,
            partName: String? = nil, partCode: String? = nil,
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
            self.partName = partName
            self.partCode = partCode
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
        public var supplierCount: Int

        public init(brand: Brand, partCount: Int, supplierCount: Int = 0) {
            self.brand = brand
            self.partCount = partCount
            self.supplierCount = supplierCount
        }
    }

    /// A supplier with its associated brand count.
    public struct SupplierWithCount: Sendable {
        public var supplier: Supplier
        public var brandCount: Int
        public var partCount: Int

        public init(supplier: Supplier, brandCount: Int, partCount: Int = 0) {
            self.supplier = supplier
            self.brandCount = brandCount
            self.partCount = partCount
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
        case invalidQuantity
        case insufficientStock(available: Int, requested: Int)
        case insufficientReturns(available: Int, requested: Int)
        case invalidInput(String)
    }

    // =========================================================================
    // MARK: - 1. Hierarchy (Category / Style / Type / Color) CRUD
    // =========================================================================

    /// Build the full nested hierarchy tree: categories -> styles -> types -> (colors, brands).
    public func getHierarchy() throws -> HierarchyTree {
        do {
            return try db.writer.read { dbConn in
                // Fetch all active categories (alphabetical)
                let categories = try PartCategory.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM part_categories WHERE deleted_at IS NULL ORDER BY name ASC"
                )

                // Fetch all active styles (alphabetical)
                let styles = try PartStyle.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM part_styles WHERE deleted_at IS NULL ORDER BY name ASC"
                )

                // Fetch all active types (alphabetical)
                let types = try PartType.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM part_types WHERE deleted_at IS NULL ORDER BY name ASC"
                )

                // Fetch all active colors (alphabetical)
                let colors = try PartColor.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM part_colors WHERE deleted_at IS NULL ORDER BY name ASC"
                )

                // Fetch all brands
                let brands = try Brand.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM brands WHERE deleted_at IS NULL ORDER BY name"
                )

                // Fetch type-brand links
                let brandLinks = try Row.fetchAll(
                    dbConn,
                    sql: "SELECT * FROM type_brand_links"
                )

                // Index brands by ID for quick lookup
                let brandById = Dictionary(uniqueKeysWithValues: brands.compactMap { b in
                    b.id.map { ($0, b) }
                })

                // Build type-brand map: typeId -> [Brand]
                var typeBrandMap: [Int64: [Brand]] = [:]
                for link in brandLinks {
                    let typeId: Int64 = link["type_id"]
                    let brandId: Int64 = link["brand_id"]
                    if let brand = brandById[brandId] {
                        typeBrandMap[typeId, default: []].append(brand)
                    }
                }

                // Fetch all catalog parts to determine which colors belong to which brand+type
                let catalogParts = try Row.fetchAll(
                    dbConn,
                    sql: "SELECT type_id, brand_id, color_id FROM parts WHERE deleted_at IS NULL"
                )

                // Build brand+type -> color IDs map
                var brandTypeColorMap: [String: Set<Int64>] = [:] // "typeId-brandId" -> color IDs (brandId = -1 for General)
                for row in catalogParts {
                    guard let typeId: Int64 = row["type_id"] else { continue }
                    let brandId: Int64 = row["brand_id"] ?? -1
                    guard let colorId: Int64 = row["color_id"] else { continue }
                    let key = "\(typeId)-\(brandId)"
                    brandTypeColorMap[key, default: []].insert(colorId)
                }

                // Index colors by ID for quick lookup
                let colorById = Dictionary(uniqueKeysWithValues: colors.compactMap { c in
                    c.id.map { ($0, c) }
                })

                // Group types by styleId, building BrandNode arrays
                var typesByStyle: [Int64: [TypeNode]] = [:]
                for type in types {
                    let tId = type.id ?? 0
                    var brandNodes: [BrandNode] = []

                    // General (no brand) node — always present
                    let generalKey = "\(tId)--1"
                    let generalColorIds = brandTypeColorMap[generalKey] ?? []
                    let generalColors = generalColorIds.sorted().compactMap { colorById[$0] }
                    brandNodes.append(BrandNode(brand: nil, colors: generalColors, allColors: colors))

                    // Named brands linked to this type
                    let linkedBrands = typeBrandMap[tId] ?? []
                    for brand in linkedBrands {
                        let bId = brand.id ?? 0
                        let brandKey = "\(tId)-\(bId)"
                        let brandColorIds = brandTypeColorMap[brandKey] ?? []
                        let brandColors = brandColorIds.sorted().compactMap { colorById[$0] }
                        brandNodes.append(BrandNode(brand: brand, colors: brandColors, allColors: colors))
                    }

                    let node = TypeNode(type: type, brandNodes: brandNodes)
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
        guard let id = record.id else { throw PartsError.invalidInput("Failed to get ID after insert") }
        return id
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
            try dbConn.execute(sql: sql, arguments: StatementArguments(args))
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

    /// List ALL active styles across all categories, sorted by name.
    public func listStyles() throws -> [PartStyle] {
        do {
            return try db.writer.read { dbConn in
                try PartStyle.fetchAll(
                    dbConn,
                    sql: """
                        SELECT * FROM part_styles
                        WHERE deleted_at IS NULL
                        ORDER BY name
                        """
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
        guard let id = record.id else { throw PartsError.invalidInput("Failed to get ID after insert") }
        return id
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
            try dbConn.execute(sql: sql, arguments: StatementArguments(args))
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

    /// List ALL active types across all styles, sorted by name.
    public func listTypes() throws -> [PartType] {
        do {
            return try db.writer.read { dbConn in
                try PartType.fetchAll(
                    dbConn,
                    sql: """
                        SELECT * FROM part_types
                        WHERE deleted_at IS NULL
                        ORDER BY name
                        """
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
        guard let id = record.id else { throw PartsError.invalidInput("Failed to get ID after insert") }
        return id
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
            try dbConn.execute(sql: sql, arguments: StatementArguments(args))
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
    public func createColor(name: String, hexCode: String? = nil, partNumber: String? = nil, sortOrder: Int = 0) throws -> Int64 {
        var record = PartColor(
            name: name,
            hexCode: hexCode,
            partNumber: partNumber,
            sortOrder: sortOrder,
            isActive: 1
        )
        try db.writer.write { dbConn in
            try record.insert(dbConn)
        }
        guard let id = record.id else { throw PartsError.invalidInput("Failed to get ID after insert") }
        return id
    }

    /// Update an existing color.
    /// For `partNumber`, pass a value to set, pass `""` to clear, or omit to leave unchanged.
    public func updateColor(id: Int64, name: String? = nil, hexCode: String? = nil, partNumber: String? = nil, sortOrder: Int? = nil) throws {
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
            if let partNumber {
                // Non-empty string = set the value; empty string = clear to NULL
                setClauses.append("part_number = ?")
                args.append(partNumber.isEmpty ? nil : partNumber)
            }
            if let sortOrder {
                setClauses.append("sort_order = ?")
                args.append(sortOrder)
            }

            guard !setClauses.isEmpty else { return }
            args.append(id)

            let sql = "UPDATE part_colors SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args))
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

    /// Find the link row ID for a type-brand association.
    public func getTypeBrandLinkId(typeId: Int64, brandId: Int64) throws -> Int64? {
        try db.writer.read { db in
            try Int64.fetchOne(db, sql: """
                SELECT id FROM type_brand_links WHERE type_id = ? AND brand_id = ?
            """, arguments: [typeId, brandId])
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

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return try rows.map { row in
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

    /// Common color abbreviations used in the trade (e.g., "RD" → "red")
    private static let colorAbbreviations: [String: [String]] = [
        "rd": ["red"],
        "wh": ["white"],
        "gr": ["gray", "grey"],
        "bk": ["black"],
        "bl": ["blue"],
        "gn": ["green"],
        "yl": ["yellow"],
        "or": ["orange"],
        "pk": ["pink"],
        "br": ["brown"],
    ]

    /// Quick search parts by name, code, or color part number. Includes color abbreviation expansion.
    public func searchParts(query: String, limit: Int = 20) throws -> [Part] {
        do {
            return try db.writer.read { dbConn in
                let pattern = "%\(query)%"

                // Expand color abbreviations for the query
                let lowerQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
                var colorPatterns: [String] = []
                if let expanded = Self.colorAbbreviations[lowerQuery] {
                    colorPatterns = expanded.map { "%\($0)%" }
                }

                if colorPatterns.isEmpty {
                    // Standard search: name, code, plus join on color part_number
                    return try Part.fetchAll(
                        dbConn,
                        sql: """
                            SELECT DISTINCT p.* FROM parts p
                            LEFT JOIN part_colors pc ON pc.id = p.color_id
                            LEFT JOIN part_supplier_links psl ON psl.part_id = p.id AND psl.deleted_at IS NULL
                            WHERE p.deleted_at IS NULL
                              AND (p.name LIKE ? OR p.code LIKE ?
                                   OR pc.part_number LIKE ?
                                   OR pc.name LIKE ?
                                   OR psl.supplier_part_number LIKE ?)
                            ORDER BY p.name ASC
                            LIMIT ?
                            """,
                        arguments: [pattern, pattern, pattern, pattern, pattern, limit]
                    )
                } else {
                    // Abbreviation match: search color names by expanded abbreviation
                    let colorPattern = colorPatterns[0]  // Primary expansion
                    return try Part.fetchAll(
                        dbConn,
                        sql: """
                            SELECT DISTINCT p.* FROM parts p
                            LEFT JOIN part_colors pc ON pc.id = p.color_id
                            WHERE p.deleted_at IS NULL
                              AND (p.name LIKE ? OR p.code LIKE ? OR pc.name LIKE ?)
                            ORDER BY p.name ASC
                            LIMIT ?
                            """,
                        arguments: [pattern, pattern, colorPattern, limit]
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get all supplier part numbers for a given color.
    /// Returns an array of (supplierId, supplierName, supplierPartNumber) tuples.
    public func getColorSupplierPartNumbers(colorId: Int64) throws -> [(supplierId: Int64, supplierName: String, supplierPartNumber: String?)] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT psl.supplier_id, s.name AS supplier_name, psl.supplier_part_number
                        FROM part_supplier_links psl
                        JOIN suppliers s ON s.id = psl.supplier_id
                        JOIN parts p ON p.id = psl.part_id
                        WHERE p.color_id = ? AND psl.deleted_at IS NULL AND p.deleted_at IS NULL
                        GROUP BY psl.supplier_id
                        ORDER BY s.name ASC
                        """,
                    arguments: [colorId]
                )
                return rows.map { row in
                    (
                        supplierId: row["supplier_id"] as Int64,
                        supplierName: row["supplier_name"] as String,
                        supplierPartNumber: row["supplier_part_number"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Update the supplier part number on a part-supplier link.
    public func updateSupplierPartNumber(linkId: Int64, supplierPartNumber: String?) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE part_supplier_links SET supplier_part_number = ? WHERE id = ?",
                arguments: [supplierPartNumber, linkId]
            )
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
        guard let partId = record.id else { throw PartsError.invalidInput("Failed to get ID after insert") }
        // Log creation in audit trail (non-fatal if migration hasn't run)
        try? logPartChange(partId: partId, userId: nil, userName: nil, action: "created", context: "Catalog")
        return partId
    }

    /// Update an existing part. Only non-nil fields are updated.
    /// Automatically logs field-level changes to the audit trail.
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
        // Read current values for change detection (non-fatal if fails)
        let currentRow = try? db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT * FROM parts WHERE id = ?", arguments: [id])
        }

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
            try dbConn.execute(sql: sql, arguments: StatementArguments(args))
        }

        // Log field-level changes to audit trail (non-fatal)
        if let row = currentRow {
            var changes: [(field: String, oldValue: String?, newValue: String?)] = []
            func track(_ field: String, _ col: String, _ newVal: String?) {
                let dbValue: DatabaseValue = row[col]
                let oldVal: String? = dbValue.isNull ? nil : "\(dbValue)"
                if let nv = newVal, nv != (oldVal ?? "") {
                    changes.append((field: field, oldValue: oldVal, newValue: nv))
                }
            }
            track("name", "name", name)
            track("code", "code", code)
            track("description", "description", description)
            track("category_id", "category_id", categoryId.map { "\($0)" })
            track("style_id", "style_id", styleId.map { "\($0)" })
            track("type_id", "type_id", typeId.map { "\($0)" })
            track("color_id", "color_id", colorId.map { "\($0)" })
            track("brand_id", "brand_id", brandId.map { "\($0)" })
            track("part_type", "part_type", partType)
            track("manufacturer_part_number", "manufacturer_part_number", manufacturerPartNumber)
            track("unit_of_measure", "unit_of_measure", unitOfMeasure)
            track("weight_lbs", "weight_lbs", weightLbs.map { "\($0)" })
            track("cost_price", "company_cost_price", companyCostPrice.map { "\($0)" })
            track("markup_percent", "company_markup_percent", companyMarkupPercent.map { "\($0)" })
            track("min_stock", "min_stock_level", minStockLevel.map { "\($0)" })
            track("max_stock", "max_stock_level", maxStockLevel.map { "\($0)" })
            track("target_stock", "target_stock_level", targetStockLevel.map { "\($0)" })
            track("reorder_point", "reorder_point", reorderPoint.map { "\($0)" })
            track("notes", "notes", notes)
            track("shelf_location", "shelf_location", shelfLocation)
            track("bin_location", "bin_location", binLocation)
            if !changes.isEmpty {
                try? logPartFieldChanges(partId: id, userId: nil, userName: nil, changes: changes, context: "Catalog Edit")
            }
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
                           COALESCE((SELECT COUNT(*) FROM parts p WHERE p.brand_id = b.id AND p.deleted_at IS NULL), 0) AS part_count,
                           COALESCE((SELECT COUNT(*) FROM brand_supplier_links bsl WHERE bsl.brand_id = b.id AND bsl.deleted_at IS NULL), 0) AS supplier_count
                    FROM brands b
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY b.name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return try rows.map { row in
                    let brand = try Brand(row: row)
                    return BrandWithCount(brand: brand, partCount: row["part_count"] as Int, supplierCount: row["supplier_count"] as Int)
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
        guard let id = record.id else { throw PartsError.invalidInput("Failed to get ID after insert") }
        return id
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
            try dbConn.execute(sql: sql, arguments: StatementArguments(args))
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
                           COALESCE((SELECT COUNT(*) FROM brand_supplier_links bsl WHERE bsl.supplier_id = s.id AND bsl.deleted_at IS NULL), 0) AS brand_count,
                           COALESCE((SELECT COUNT(*) FROM part_supplier_links ps WHERE ps.supplier_id = s.id AND ps.deleted_at IS NULL), 0) AS part_count
                    FROM suppliers s
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY s.name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return try rows.map { row in
                    let supplier = try Supplier(row: row)
                    return SupplierWithCount(supplier: supplier, brandCount: row["brand_count"] as Int, partCount: row["part_count"] as Int)
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
        repName: String? = nil,
        repEmail: String? = nil,
        repPhone: String? = nil,
        deliveryMethod: String? = nil,
        deliveryDays: String? = nil,
        accountNumber: String? = nil,
        notes: String? = nil
    ) throws -> Int64 {
        var record = Supplier(
            name: name,
            contactName: contactName,
            email: email,
            phone: phone,
            address: address,
            website: website,
            repName: repName,
            repEmail: repEmail,
            repPhone: repPhone,
            notes: notes,
            deliveryMethod: deliveryMethod,
            deliveryDays: deliveryDays,
            accountNumber: accountNumber
        )
        try db.writer.write { dbConn in
            try record.insert(dbConn)
        }
        guard let id = record.id else { throw PartsError.invalidInput("Failed to get ID after insert") }
        return id
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
        repName: String? = nil,
        repEmail: String? = nil,
        repPhone: String? = nil,
        deliveryMethod: String? = nil,
        deliveryDays: String? = nil,
        accountNumber: String? = nil,
        isActive: Int? = nil,
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
            if let repName { setClauses.append("rep_name = ?"); args.append(repName) }
            if let repEmail { setClauses.append("rep_email = ?"); args.append(repEmail) }
            if let repPhone { setClauses.append("rep_phone = ?"); args.append(repPhone) }
            if let deliveryMethod { setClauses.append("delivery_method = ?"); args.append(deliveryMethod) }
            if let deliveryDays { setClauses.append("delivery_days = ?"); args.append(deliveryDays) }
            if let accountNumber { setClauses.append("account_number = ?"); args.append(accountNumber) }
            if let isActive { setClauses.append("is_active = ?"); args.append(isActive) }
            if let notes { setClauses.append("notes = ?"); args.append(notes) }

            guard !setClauses.isEmpty else { return }
            setClauses.append("updated_at = datetime('now')")
            args.append(id)

            let sql = "UPDATE suppliers SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args))
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

    /// A brand-supplier link with carry status info.
    public struct BrandSupplierRow: Sendable {
        public let linkId: Int64
        public let brandId: Int64
        public let brandName: String
        public let supplierId: Int64
        public let supplierName: String
        public let carryStatus: String  // "carry_on_shelf" | "need_to_order"
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

    /// Get suppliers for a brand with carry status information.
    public func getBrandSuppliersWithStatus(brandId: Int64) throws -> [BrandSupplierRow] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT bsl.id AS link_id, bsl.brand_id, b.name AS brand_name,
                       bsl.supplier_id, s.name AS supplier_name,
                       COALESCE(bsl.carry_status, 'carry_on_shelf') AS carry_status
                FROM brand_supplier_links bsl
                JOIN suppliers s ON s.id = bsl.supplier_id AND s.deleted_at IS NULL
                JOIN brands b ON b.id = bsl.brand_id AND b.deleted_at IS NULL
                WHERE bsl.brand_id = ? AND bsl.deleted_at IS NULL
                ORDER BY s.name ASC
                """, arguments: [brandId])

            return rows.map { row in
                BrandSupplierRow(
                    linkId: row["link_id"] as Int64? ?? 0,
                    brandId: row["brand_id"] as Int64? ?? 0,
                    brandName: row["brand_name"] as String? ?? "",
                    supplierId: row["supplier_id"] as Int64? ?? 0,
                    supplierName: row["supplier_name"] as String? ?? "",
                    carryStatus: row["carry_status"] as String? ?? "carry_on_shelf"
                )
            }
        }
    }

    /// Update the carry status of a brand-supplier link.
    public func updateBrandSupplierCarryStatus(brandId: Int64, supplierId: Int64, carryStatus: String) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE brand_supplier_links
                    SET carry_status = ?
                    WHERE brand_id = ? AND supplier_id = ? AND deleted_at IS NULL
                    """,
                arguments: [carryStatus, brandId, supplierId]
            )
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

    // MARK: - Brand-Supplier Linking

    /// Link a supplier to a brand. If a soft-deleted link exists, reactivate it.
    /// Returns the link row ID.
    @discardableResult
    public func linkBrandToSupplier(brandId: Int64, supplierId: Int64) throws -> Int64 {
        try db.writer.write { dbConn in
            // Check if a soft-deleted link exists — reactivate it
            if let existing = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT id FROM brand_supplier_links
                    WHERE brand_id = ? AND supplier_id = ?
                    """,
                arguments: [brandId, supplierId]
            ) {
                let linkId: Int64 = existing["id"]
                try dbConn.execute(
                    sql: """
                        UPDATE brand_supplier_links
                        SET deleted_at = NULL, is_active = 1
                        WHERE id = ?
                        """,
                    arguments: [linkId]
                )
                return linkId
            }

            // Create new link
            try dbConn.execute(
                sql: """
                    INSERT INTO brand_supplier_links (brand_id, supplier_id, is_active, created_at)
                    VALUES (?, ?, 1, datetime('now'))
                    """,
                arguments: [brandId, supplierId]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Remove a brand-supplier link (soft delete).
    public func unlinkBrandFromSupplier(brandId: Int64, supplierId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE brand_supplier_links
                    SET deleted_at = datetime('now')
                    WHERE brand_id = ? AND supplier_id = ? AND deleted_at IS NULL
                    """,
                arguments: [brandId, supplierId]
            )
        }
    }

    /// Set the complete list of suppliers for a brand.
    /// Links suppliers in `supplierIds`, unlinks any not in the list.
    public func setBrandSuppliers(brandId: Int64, supplierIds: Set<Int64>) throws {
        // Get currently linked supplier IDs
        let currentSuppliers = try getBrandSuppliers(brandId: brandId)
        let currentIds = Set(currentSuppliers.compactMap { $0.id })

        // Add new links
        let toAdd = supplierIds.subtracting(currentIds)
        for supplierId in toAdd {
            try linkBrandToSupplier(brandId: brandId, supplierId: supplierId)
        }

        // Remove old links
        let toRemove = currentIds.subtracting(supplierIds)
        for supplierId in toRemove {
            try unlinkBrandFromSupplier(brandId: brandId, supplierId: supplierId)
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

    // MARK: - 5b. FIFO/LIFO Cost Engine

    /// Record a new cost layer when parts are received from a purchase order.
    /// Each delivery (even partial) creates its own batch with its own unit cost.
    /// After adding, recalculates and updates the part's weighted average cost.
    ///
    /// - Parameters:
    ///   - partId: The part receiving inventory
    ///   - qty: Number of units received
    ///   - unitCost: Cost per unit (up to 5 decimal precision)
    ///   - poLineId: Optional PO line item reference
    ///   - supplierId: Optional supplier reference for return tracking
    /// - Returns: The created CostLayer
    @discardableResult
    public func addCostLayer(
        partId: Int64,
        qty: Int,
        unitCost: Double,
        poLineId: Int64? = nil,
        supplierId: Int64? = nil
    ) throws -> CostLayer {
        guard qty > 0 else { throw PartsError.invalidQuantity }

        let layer = try db.writer.write { dbConn -> CostLayer in
            var layer = CostLayer(
                partId: partId,
                purchaseDate: ISO8601DateFormatter().string(from: Date()),
                poLineId: poLineId,
                originalQty: qty,
                remainingQty: qty,
                unitCost: unitCost
            )
            try layer.insert(dbConn)
            return layer
        }

        // Recalculate weighted average cost
        try recalculateWeightedAvgCost(partId: partId)

        // Log price history
        try logPriceChange(
            partId: partId,
            changeType: "cost_update",
            newValue: unitCost,
            source: poLineId != nil ? "receiving" : "manual",
            sourceId: poLineId
        )

        return layer
    }

    /// Consume parts using FIFO ordering — oldest batches are used first.
    /// Creates consumption records for return tracking.
    ///
    /// - Parameters:
    ///   - partId: The part being consumed
    ///   - qty: Number of units to consume
    ///   - jobId: Optional job the parts are going to
    ///   - sellPrice: Price charged to the customer per unit
    /// - Returns: Array of consumption records created
    @discardableResult
    public func consumeInventoryFIFO(
        partId: Int64,
        qty: Int,
        jobId: Int64? = nil,
        sellPrice: Double? = nil
    ) throws -> [CostLayerConsumption] {
        guard qty > 0 else { throw PartsError.invalidQuantity }

        let consumptions = try db.writer.write { dbConn -> [CostLayerConsumption] in
            // Get all non-empty layers for this part, oldest first (FIFO)
            let layers = try CostLayer.fetchAll(dbConn, sql: """
                SELECT * FROM cost_layers
                WHERE part_id = ? AND remaining_qty > 0
                ORDER BY purchase_date ASC, id ASC
                """, arguments: [partId])

            // Check total available
            let totalAvailable = layers.reduce(0) { $0 + $1.remainingQty }
            guard totalAvailable >= qty else {
                throw PartsError.insufficientStock(available: totalAvailable, requested: qty)
            }

            var remaining = qty
            var records: [CostLayerConsumption] = []

            for var layer in layers {
                guard remaining > 0 else { break }

                let take = min(remaining, layer.remainingQty)

                // Decrement the layer
                layer.remainingQty -= take
                try layer.update(dbConn)

                // Find the supplier from the PO line if available
                var supplierId: Int64? = nil
                if let poLineId = layer.poLineId {
                    let row = try Row.fetchOne(dbConn, sql: """
                        SELECT po.supplier_id FROM po_line_items pli
                        JOIN purchase_orders po ON po.id = pli.po_id
                        WHERE pli.id = ?
                        """, arguments: [poLineId])
                    supplierId = row?["supplier_id"] as? Int64
                }

                // Create consumption record
                var consumption = CostLayerConsumption(
                    costLayerId: layer.id ?? 0,
                    partId: partId,
                    jobId: jobId,
                    qtyConsumed: take,
                    unitCostAtSale: layer.unitCost,
                    sellPriceCharged: sellPrice,
                    supplierId: supplierId,
                    isReturned: 0,
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
                try consumption.insert(dbConn)
                records.append(consumption)

                remaining -= take
            }

            return records
        }

        // Recalculate weighted average after consumption
        try recalculateWeightedAvgCost(partId: partId)

        return consumptions
    }

    /// Return parts using LIFO — most recently consumed batches are restored first.
    /// Marks consumption records as returned and restores batch quantities.
    /// The returned parts go back as if they never left.
    ///
    /// - Parameters:
    ///   - partId: The part being returned
    ///   - qty: Number of units to return
    ///   - jobId: Optional job the parts are coming back from
    /// - Returns: Array of consumption records that were reversed
    @discardableResult
    public func returnInventoryLIFO(
        partId: Int64,
        qty: Int,
        jobId: Int64? = nil
    ) throws -> [CostLayerConsumption] {
        guard qty > 0 else { throw PartsError.invalidQuantity }

        let reversed = try db.writer.write { dbConn -> [CostLayerConsumption] in
            // Find un-returned consumptions for this part, most recent first (LIFO)
            var sql = """
                SELECT * FROM cost_layer_consumptions
                WHERE part_id = ? AND is_returned = 0
                """
            var args: [any DatabaseValueConvertible] = [partId]
            if let jobId {
                sql += " AND job_id = ?"
                args.append(jobId)
            }
            sql += " ORDER BY created_at DESC, id DESC"

            let consumptions = try CostLayerConsumption.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))

            let totalReturnable = consumptions.reduce(0) { $0 + $1.qtyConsumed }
            guard totalReturnable >= qty else {
                throw PartsError.insufficientReturns(available: totalReturnable, requested: qty)
            }

            var remaining = qty
            var records: [CostLayerConsumption] = []
            let now = ISO8601DateFormatter().string(from: Date())

            for var consumption in consumptions {
                guard remaining > 0 else { break }

                let restore = min(remaining, consumption.qtyConsumed)

                // Restore the cost layer
                if var layer = try CostLayer.fetchOne(dbConn, key: consumption.costLayerId) {
                    layer.remainingQty += restore
                    try layer.update(dbConn)
                }

                // Mark consumption as returned
                if restore == consumption.qtyConsumed {
                    // Full return of this consumption
                    consumption.isReturned = 1
                    consumption.returnedAt = now
                    try consumption.update(dbConn)
                } else {
                    // Partial return: split the consumption record
                    // Reduce original consumption qty
                    consumption.qtyConsumed -= restore
                    try consumption.update(dbConn)

                    // Create a new "returned" record for the restored portion
                    var returnedRecord = consumption
                    returnedRecord.id = nil
                    returnedRecord.qtyConsumed = restore
                    returnedRecord.isReturned = 1
                    returnedRecord.returnedAt = now
                    try returnedRecord.insert(dbConn)
                }

                records.append(consumption)
                remaining -= restore
            }

            return records
        }

        // Recalculate weighted average after return
        try recalculateWeightedAvgCost(partId: partId)

        return reversed
    }

    /// Recalculate and store the weighted average cost for a part from its cost layers.
    /// weighted_avg = Σ(remaining_qty × unit_cost) / Σ(remaining_qty)
    /// This is company-wide — location doesn't matter for pricing.
    public func recalculateWeightedAvgCost(partId: Int64) throws {
        try db.writer.write { dbConn in
            let row = try Row.fetchOne(dbConn, sql: """
                SELECT
                    COALESCE(SUM(remaining_qty * unit_cost), 0) AS total_value,
                    COALESCE(SUM(remaining_qty), 0) AS total_qty
                FROM cost_layers
                WHERE part_id = ? AND remaining_qty > 0
                """, arguments: [partId])

            let totalValue: Double = row?["total_value"] ?? 0
            let totalQty: Int = row?["total_qty"] ?? 0
            let weightedAvg = totalQty > 0 ? totalValue / Double(totalQty) : 0

            try dbConn.execute(
                sql: """
                    UPDATE parts SET weighted_avg_cost = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [weightedAvg, partId]
            )
        }
    }

    /// Get all cost layers (batches) for a part, optionally filtering to non-empty only.
    public func getCostLayers(partId: Int64, nonEmptyOnly: Bool = false) throws -> [CostLayer] {
        try db.writer.read { dbConn in
            var sql = "SELECT * FROM cost_layers WHERE part_id = ?"
            if nonEmptyOnly {
                sql += " AND remaining_qty > 0"
            }
            sql += " ORDER BY purchase_date ASC, id ASC"
            return try CostLayer.fetchAll(dbConn, sql: sql, arguments: [partId])
        }
    }

    /// Get consumption history for a part, optionally filtered by job.
    public func getConsumptionHistory(partId: Int64, jobId: Int64? = nil) throws -> [CostLayerConsumption] {
        try db.writer.read { dbConn in
            var sql = "SELECT * FROM cost_layer_consumptions WHERE part_id = ?"
            var args: [any DatabaseValueConvertible] = [partId]
            if let jobId {
                sql += " AND job_id = ?"
                args.append(jobId)
            }
            sql += " ORDER BY created_at DESC"
            return try CostLayerConsumption.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Reset all cost layers for a part to the current (most recent) buy price.
    /// Collapses all batches into one layer at the new price.
    /// Returns (oldAvg, newAvg) so the caller can show the difference.
    public func resetToCurrentBuyPrice(partId: Int64) throws -> (oldAvg: Double, newAvg: Double) {
        try db.writer.write { dbConn in
            // Get current weighted average
            let currentRow = try Row.fetchOne(dbConn, sql: """
                SELECT weighted_avg_cost FROM parts WHERE id = ?
                """, arguments: [partId])
            let oldAvg: Double = currentRow?["weighted_avg_cost"] ?? 0

            // Get most recent cost layer price
            let recentRow = try Row.fetchOne(dbConn, sql: """
                SELECT unit_cost FROM cost_layers
                WHERE part_id = ? AND remaining_qty > 0
                ORDER BY purchase_date DESC, id DESC
                LIMIT 1
                """, arguments: [partId])
            let currentBuyPrice: Double = recentRow?["unit_cost"] ?? oldAvg

            // Get total remaining inventory
            let qtyRow = try Row.fetchOne(dbConn, sql: """
                SELECT COALESCE(SUM(remaining_qty), 0) AS total
                FROM cost_layers WHERE part_id = ? AND remaining_qty > 0
                """, arguments: [partId])
            let totalQty: Int = qtyRow?["total"] ?? 0

            if totalQty > 0 {
                // Soft-delete all existing layers
                try dbConn.execute(sql: """
                    UPDATE cost_layers SET remaining_qty = 0
                    WHERE part_id = ? AND remaining_qty > 0
                    """, arguments: [partId])

                // Create one new layer at current buy price
                try dbConn.execute(sql: """
                    INSERT INTO cost_layers (part_id, purchase_date, original_qty, remaining_qty, unit_cost)
                    VALUES (?, datetime('now'), ?, ?, ?)
                    """, arguments: [partId, totalQty, totalQty, currentBuyPrice])

                // Update weighted average
                try dbConn.execute(sql: """
                    UPDATE parts SET weighted_avg_cost = ?, cost_last_updated = datetime('now'), updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [currentBuyPrice, partId])
            }

            return (oldAvg, currentBuyPrice)
        }
    }

    /// Log a price change to the history table for auditing.
    public func logPriceChange(
        partId: Int64? = nil,
        pricingTierId: Int64? = nil,
        changeType: String,
        oldValue: Double? = nil,
        newValue: Double? = nil,
        oldSellPrice: Double? = nil,
        newSellPrice: Double? = nil,
        source: String? = nil,
        sourceId: Int64? = nil,
        changedBy: Int64? = nil
    ) throws {
        try db.writer.write { dbConn in
            var record = PriceHistory(
                partId: partId,
                pricingTierId: pricingTierId,
                changeType: changeType,
                oldValue: oldValue,
                newValue: newValue,
                oldSellPrice: oldSellPrice,
                newSellPrice: newSellPrice,
                source: source,
                sourceId: sourceId,
                changedBy: changedBy
            )
            try record.insert(dbConn)
        }
    }

    /// Get price change history for a part.
    public func getPriceHistory(partId: Int64, limit: Int = 50) throws -> [PriceHistory] {
        try db.writer.read { dbConn in
            try PriceHistory.fetchAll(dbConn, sql: """
                SELECT * FROM price_history
                WHERE part_id = ?
                ORDER BY created_at DESC
                LIMIT ?
                """, arguments: [partId, limit])
        }
    }

    // =========================================================================
    // MARK: - 5c. Hierarchical Pricing
    // =========================================================================

    /// Resolved pricing info for a part — includes the effective markup/margin,
    /// where it was set (tier level), and whether it's inherited or direct.
    public struct ResolvedPricing: Sendable {
        public let partId: Int64
        public let weightedAvgCost: Double
        public let effectiveMarkup: Double       // the markup % that applies
        public let effectiveMargin: Double       // calculated margin %
        public let sellPrice: Double             // calculated sell price
        public let tierLevel: String             // "Part", "Brand", "Type", "Style", "Category", "Default"
        public let tierId: Int64?               // the pricing_tier.id that set this, nil for default
        public let isInherited: Bool            // true if price comes from a parent level
        public let isDirectOverride: Bool       // true if this part has its own tier
    }

    /// Resolve the effective pricing for a part by walking UP the hierarchy.
    /// Checks: Part → Brand → Type → Style → Category → Company Default
    public func resolvePartPricing(partId: Int64) throws -> ResolvedPricing {
        try db.writer.read { dbConn in
            // Get part details
            guard let part = try Part.fetchOne(dbConn, key: partId) else {
                throw PartsError.partNotFound(partId)
            }

            let weightedAvg: Double = part.weightedAvgCost ?? 0
            let pricingMode = try self.getCompanySetting(dbConn: dbConn, key: "pricing_mode") ?? "markup"
            let defaultMarkup = Double(try self.getCompanySetting(dbConn: dbConn, key: "default_markup_percent") ?? "50") ?? 50

            // Check each level from most specific to least
            // 1. Part-level tier
            if let tier = try PricingTier.fetchOne(dbConn, sql: """
                SELECT * FROM pricing_tiers WHERE part_id = ? AND deleted_at IS NULL
                """, arguments: [partId]) {
                let (markup, margin, sell) = self.calculatePricing(tier: tier, cost: weightedAvg, mode: pricingMode, defaultMarkup: defaultMarkup)
                return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: markup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Part", tierId: tier.id, isInherited: false, isDirectOverride: true)
            }

            // 2. Brand-level tier (if part has a brand)
            if let brandId = part.brandId {
                if let tier = try PricingTier.fetchOne(dbConn, sql: """
                    SELECT * FROM pricing_tiers WHERE brand_id = ? AND deleted_at IS NULL
                    """, arguments: [brandId]) {
                    let (markup, margin, sell) = self.calculatePricing(tier: tier, cost: weightedAvg, mode: pricingMode, defaultMarkup: defaultMarkup)
                    return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: markup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Brand", tierId: tier.id, isInherited: true, isDirectOverride: false)
                }
            }

            // 3. Type-level tier
            if let typeId = part.typeId {
                if let tier = try PricingTier.fetchOne(dbConn, sql: """
                    SELECT * FROM pricing_tiers WHERE type_id = ? AND deleted_at IS NULL
                    """, arguments: [typeId]) {
                    let (markup, margin, sell) = self.calculatePricing(tier: tier, cost: weightedAvg, mode: pricingMode, defaultMarkup: defaultMarkup)
                    return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: markup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Type", tierId: tier.id, isInherited: true, isDirectOverride: false)
                }
            }

            // 4. Style-level tier
            if let styleId = part.styleId {
                if let tier = try PricingTier.fetchOne(dbConn, sql: """
                    SELECT * FROM pricing_tiers WHERE style_id = ? AND deleted_at IS NULL
                    """, arguments: [styleId]) {
                    let (markup, margin, sell) = self.calculatePricing(tier: tier, cost: weightedAvg, mode: pricingMode, defaultMarkup: defaultMarkup)
                    return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: markup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Style", tierId: tier.id, isInherited: true, isDirectOverride: false)
                }
            }

            // 5. Category-level tier
            if let tier = try PricingTier.fetchOne(dbConn, sql: """
                SELECT * FROM pricing_tiers WHERE category_id = ? AND deleted_at IS NULL
                """, arguments: [part.categoryId]) {
                let (markup, margin, sell) = self.calculatePricing(tier: tier, cost: weightedAvg, mode: pricingMode, defaultMarkup: defaultMarkup)
                return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: markup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Category", tierId: tier.id, isInherited: true, isDirectOverride: false)
            }

            // 6. Company default
            let sell = weightedAvg * (1 + defaultMarkup / 100)
            let margin = sell > 0 ? ((sell - weightedAvg) / sell) * 100 : 0
            return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: defaultMarkup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Default", tierId: nil, isInherited: true, isDirectOverride: false)
        }
    }

    /// Calculate markup, margin, and sell price from a tier.
    /// Enforces minimum 0% margin — sell price never goes below cost.
    private func calculatePricing(
        tier: PricingTier,
        cost: Double,
        mode: String,
        defaultMarkup: Double
    ) -> (markup: Double, margin: Double, sellPrice: Double) {
        if let fixedPrice = tier.fixedSellPrice, fixedPrice > 0 {
            let safeSell = max(fixedPrice, cost) // never below cost
            let markup = cost > 0 ? ((safeSell - cost) / cost) * 100 : 0
            let margin = safeSell > 0 ? ((safeSell - cost) / safeSell) * 100 : 0
            return (markup, max(margin, 0), safeSell)
        }

        let markup: Double
        if mode == "margin", let marginPct = tier.marginPercent {
            // Convert margin to markup: markup = margin / (1 - margin/100)
            let clampedMargin = max(marginPct, 0)
            markup = clampedMargin < 100 ? (clampedMargin / (100 - clampedMargin)) * 100 : defaultMarkup
        } else {
            markup = max(tier.markupPercent ?? defaultMarkup, 0)
        }

        let sellPrice = cost * (1 + markup / 100)
        let margin = sellPrice > 0 ? ((sellPrice - cost) / sellPrice) * 100 : 0
        return (markup, max(margin, 0), sellPrice)
    }

    /// Set or update a pricing tier at a specific hierarchy level.
    /// Only ONE of the id parameters should be non-nil.
    @discardableResult
    public func setPricingTier(
        categoryId: Int64? = nil,
        styleId: Int64? = nil,
        typeId: Int64? = nil,
        brandId: Int64? = nil,
        partId: Int64? = nil,
        markupPercent: Double? = nil,
        marginPercent: Double? = nil,
        fixedSellPrice: Double? = nil,
        setBy: Int64? = nil,
        notes: String? = nil
    ) throws -> PricingTier {
        try db.writer.write { dbConn in
            // Find existing tier at this level
            var conditions: [String] = []
            var args: [any DatabaseValueConvertible] = []

            if let id = categoryId { conditions.append("category_id = ?"); args.append(id) }
            else { conditions.append("category_id IS NULL") }

            if let id = styleId { conditions.append("style_id = ?"); args.append(id) }
            else { conditions.append("style_id IS NULL") }

            if let id = typeId { conditions.append("type_id = ?"); args.append(id) }
            else { conditions.append("type_id IS NULL") }

            if let id = brandId { conditions.append("brand_id = ?"); args.append(id) }
            else { conditions.append("brand_id IS NULL") }

            if let id = partId { conditions.append("part_id = ?"); args.append(id) }
            else { conditions.append("part_id IS NULL") }

            let whereClause = conditions.joined(separator: " AND ")

            // Soft-delete existing tier at this level
            try dbConn.execute(
                sql: "UPDATE pricing_tiers SET deleted_at = datetime('now') WHERE \(whereClause) AND deleted_at IS NULL",
                arguments: StatementArguments(args)
            )

            // Insert new tier
            var tier = PricingTier(
                categoryId: categoryId,
                styleId: styleId,
                typeId: typeId,
                brandId: brandId,
                partId: partId,
                markupPercent: markupPercent,
                marginPercent: marginPercent,
                fixedSellPrice: fixedSellPrice,
                setBy: setBy,
                notes: notes
            )
            try tier.insert(dbConn)
            return tier
        }
    }

    /// Remove a pricing tier (soft delete). Parts under this level revert to parent pricing.
    public func removePricingTier(tierId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE pricing_tiers SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [tierId]
            )
        }
    }

    /// When setting a price at a higher level, find all lower-level overrides
    /// that would conflict. Returns the override tiers with their current pricing
    /// so the user can confirm each one.
    public struct OverrideConflict: Sendable {
        public let tier: PricingTier
        public let currentSellPrice: Double
        public let newSellPrice: Double       // what the price would be under the new tier
        public let difference: Double          // newSellPrice - currentSellPrice
        public let affectedPartCount: Int      // how many parts this override covers
    }

    public func findOverrideConflicts(
        categoryId: Int64? = nil,
        styleId: Int64? = nil,
        typeId: Int64? = nil,
        brandId: Int64? = nil,
        newMarkupPercent: Double? = nil,
        newMarginPercent: Double? = nil,
        newFixedPrice: Double? = nil
    ) throws -> [OverrideConflict] {
        try db.writer.read { dbConn in
            let pricingMode = try self.getCompanySetting(dbConn: dbConn, key: "pricing_mode") ?? "markup"
            let defaultMarkup = Double(try self.getCompanySetting(dbConn: dbConn, key: "default_markup_percent") ?? "50") ?? 50

            // Build a temporary tier for calculation
            let proposedTier = PricingTier(
                markupPercent: newMarkupPercent,
                marginPercent: newMarginPercent,
                fixedSellPrice: newFixedPrice
            )

            var conflicts: [OverrideConflict] = []

            // Find all active tiers that are MORE specific than the proposed level
            var sql = "SELECT * FROM pricing_tiers WHERE deleted_at IS NULL AND ("
            var conditions: [String] = []
            let scopeId: Int64

            if let id = categoryId {
                scopeId = id
                // Category-level change: find style, type, brand, part overrides in this category
                conditions.append("style_id IN (SELECT id FROM part_styles WHERE category_id = ?)")
                conditions.append("type_id IN (SELECT id FROM part_types WHERE style_id IN (SELECT id FROM part_styles WHERE category_id = ?))")
                conditions.append("brand_id IS NOT NULL")
                conditions.append("part_id IN (SELECT id FROM parts WHERE category_id = ?)")
            } else if let id = styleId {
                scopeId = id
                conditions.append("type_id IN (SELECT id FROM part_types WHERE style_id = ?)")
                conditions.append("brand_id IS NOT NULL")
                conditions.append("part_id IN (SELECT id FROM parts WHERE style_id = ?)")
            } else if let id = typeId {
                scopeId = id
                conditions.append("brand_id IS NOT NULL")
                conditions.append("part_id IN (SELECT id FROM parts WHERE type_id = ?)")
            } else if let id = brandId {
                scopeId = id
                conditions.append("part_id IN (SELECT id FROM parts WHERE brand_id = ?)")
            } else {
                return []
            }

            guard !conditions.isEmpty else { return [] }

            sql += conditions.joined(separator: " OR ") + ")"

            let tiers = try PricingTier.fetchAll(dbConn, sql: sql, arguments: StatementArguments(
                conditions.map { _ -> any DatabaseValueConvertible in scopeId }
            ))

            for tier in tiers {
                // Get a representative cost for this tier's parts
                let costRow = try Row.fetchOne(dbConn, sql: """
                    SELECT AVG(weighted_avg_cost) AS avg_cost, COUNT(*) AS cnt FROM parts
                    WHERE deleted_at IS NULL AND (
                        (? IS NOT NULL AND category_id = ?) OR
                        (? IS NOT NULL AND style_id = ?) OR
                        (? IS NOT NULL AND type_id = ?) OR
                        (? IS NOT NULL AND brand_id = ?) OR
                        (? IS NOT NULL AND id = ?)
                    )
                    """, arguments: [
                        tier.categoryId, tier.categoryId,
                        tier.styleId, tier.styleId,
                        tier.typeId, tier.typeId,
                        tier.brandId, tier.brandId,
                        tier.partId, tier.partId
                    ])

                let avgCost: Double = costRow?["avg_cost"] ?? 0
                let count: Int = costRow?["cnt"] ?? 0

                let (_, _, currentSell) = self.calculatePricing(tier: tier, cost: avgCost, mode: pricingMode, defaultMarkup: defaultMarkup)
                let (_, _, newSell) = self.calculatePricing(tier: proposedTier, cost: avgCost, mode: pricingMode, defaultMarkup: defaultMarkup)

                conflicts.append(OverrideConflict(
                    tier: tier,
                    currentSellPrice: currentSell,
                    newSellPrice: newSell,
                    difference: newSell - currentSell,
                    affectedPartCount: count
                ))
            }

            return conflicts
        }
    }

    /// Get up to 15 random in-stock parts that would be affected by a pricing change.
    /// These parts are "locked in" for the preview — the caller should hold this array
    /// for the duration of the review session.
    public struct PricingPreviewPart: Sendable {
        public let partId: Int64
        public let partName: String
        public let currentSellPrice: Double
        public let newSellPrice: Double
        public let currentMarkup: Double
        public let newMarkup: Double
        public let weightedAvgCost: Double
        public let difference: Double
    }

    public func getPreviewParts(
        categoryId: Int64? = nil,
        styleId: Int64? = nil,
        typeId: Int64? = nil,
        brandId: Int64? = nil,
        newMarkupPercent: Double? = nil,
        newMarginPercent: Double? = nil,
        newFixedPrice: Double? = nil,
        limit: Int = 15
    ) throws -> [PricingPreviewPart] {
        try db.writer.read { dbConn in
            let pricingMode = try self.getCompanySetting(dbConn: dbConn, key: "pricing_mode") ?? "markup"
            let defaultMarkup = Double(try self.getCompanySetting(dbConn: dbConn, key: "default_markup_percent") ?? "50") ?? 50

            // Find parts in the target scope that have stock
            var conditions: [String] = ["p.deleted_at IS NULL"]
            var args: [any DatabaseValueConvertible] = []

            if let id = categoryId { conditions.append("p.category_id = ?"); args.append(id) }
            if let id = styleId { conditions.append("p.style_id = ?"); args.append(id) }
            if let id = typeId { conditions.append("p.type_id = ?"); args.append(id) }
            if let id = brandId { conditions.append("p.brand_id = ?"); args.append(id) }

            let whereClause = conditions.joined(separator: " AND ")

            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT p.id, p.name, p.weighted_avg_cost, p.company_markup_percent
                FROM parts p
                WHERE \(whereClause)
                ORDER BY RANDOM()
                LIMIT ?
                """, arguments: StatementArguments(args + [limit]))

            let proposedTier = PricingTier(
                markupPercent: newMarkupPercent,
                marginPercent: newMarginPercent,
                fixedSellPrice: newFixedPrice
            )

            return rows.map { row in
                let partId: Int64 = row["id"]
                let name: String = row["name"]
                let cost: Double = row["weighted_avg_cost"] ?? 0
                let currentMarkup: Double = row["company_markup_percent"] ?? defaultMarkup

                let currentSell = cost * (1 + currentMarkup / 100)
                let (newMarkup, _, newSell) = self.calculatePricing(tier: proposedTier, cost: cost, mode: pricingMode, defaultMarkup: defaultMarkup)

                return PricingPreviewPart(
                    partId: partId,
                    partName: name,
                    currentSellPrice: currentSell,
                    newSellPrice: newSell,
                    currentMarkup: currentMarkup,
                    newMarkup: newMarkup,
                    weightedAvgCost: cost,
                    difference: newSell - currentSell
                )
            }
        }
    }

    /// Read a company cost setting value.
    public func getCompanyCostSetting(key: String) throws -> String? {
        try db.writer.read { dbConn in
            try self.getCompanySetting(dbConn: dbConn, key: key)
        }
    }

    /// Internal helper for reading settings within an existing connection.
    private func getCompanySetting(dbConn: Database, key: String) throws -> String? {
        let row = try Row.fetchOne(dbConn, sql: """
            SELECT setting_value FROM company_cost_settings WHERE setting_key = ?
            """, arguments: [key])
        return row?["setting_value"] as? String
    }

    /// Update a company cost setting.
    public func updateCompanyCostSetting(key: String, value: String, updatedBy: Int64? = nil) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO company_cost_settings (setting_key, setting_value, updated_by, updated_at)
                VALUES (?, ?, ?, datetime('now'))
                ON CONFLICT(setting_key) DO UPDATE SET
                    setting_value = excluded.setting_value,
                    updated_by = excluded.updated_by,
                    updated_at = datetime('now')
                """, arguments: [key, value, updatedBy])
        }
    }

    // =========================================================================
    // MARK: - 5c½. Cascade Cost Pricing (Type → Color → Color×Supplier)
    // =========================================================================

    /// Result of resolving the cascade cost for a color.
    public struct ResolvedCascadeCost: Sendable {
        public let effectiveCost: Double?
        public let source: String  // "supplier", "color", "type", or "none"
        public let typeDefaultCost: Double?
        public let colorOverrideCost: Double?
        public let supplierCost: Double?
    }

    /// Supplier-specific cost row for a color (used by PriceEditSheet).
    public struct ColorSupplierCostRow: Sendable {
        public let id: Int64
        public let colorId: Int64
        public let supplierId: Int64
        public let supplierName: String
        public let cost: Double
        public let notes: String?
    }

    /// Set the default unit cost for all colors of a type.
    public func setPriceForType(typeId: Int64, unitCost: Double?) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE part_types SET default_unit_cost = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [unitCost, typeId])
        }
    }

    /// Set or clear a cost override for a specific color.
    public func setPriceForColor(colorId: Int64, unitCost: Double?) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE part_colors SET unit_cost = ?
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [unitCost, colorId])
        }
    }

    /// Set a supplier-specific cost for a color (upsert).
    public func setSupplierCostForColor(colorId: Int64, supplierId: Int64, cost: Double, notes: String? = nil) throws {
        do {
            try db.writer.write { dbConn in
                try dbConn.execute(sql: """
                    INSERT INTO color_supplier_costs (color_id, supplier_id, cost, notes, created_at, updated_at)
                    VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
                    ON CONFLICT(color_id, supplier_id) DO UPDATE SET
                        cost = excluded.cost,
                        notes = excluded.notes,
                        updated_at = datetime('now')
                    """, arguments: [colorId, supplierId, cost, notes])
            }
        } catch {
            if isTableNotFoundError(error) { return }
            throw error
        }
    }

    /// Remove a supplier-specific cost for a color.
    public func removeSupplierCostForColor(colorId: Int64, supplierId: Int64) throws {
        do {
            try db.writer.write { dbConn in
                try dbConn.execute(sql: """
                    DELETE FROM color_supplier_costs WHERE color_id = ? AND supplier_id = ?
                    """, arguments: [colorId, supplierId])
            }
        } catch {
            if isTableNotFoundError(error) { return }
            throw error
        }
    }

    /// Resolve the effective cost for a color using the cascade:
    /// 1. Color × Supplier cost (if supplierId given)
    /// 2. Color override cost
    /// 3. Type default cost (looks up via type_color_links)
    /// 4. nil (no price set)
    public func getEffectivePrice(colorId: Int64, typeId: Int64? = nil, supplierId: Int64? = nil) throws -> ResolvedCascadeCost {
        do {
            return try db.writer.read { dbConn in
                // Fetch the color's own unit cost
                let colorRow = try Row.fetchOne(dbConn, sql: """
                    SELECT unit_cost FROM part_colors WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [colorId])
                let colorCost: Double? = colorRow?["unit_cost"]

                // Fetch the type's default cost (use provided typeId or look up from type_color_links)
                var typeDefaultCost: Double? = nil
                if let tId = typeId {
                    let typeRow = try Row.fetchOne(dbConn, sql: """
                        SELECT default_unit_cost FROM part_types WHERE id = ? AND deleted_at IS NULL
                        """, arguments: [tId])
                    typeDefaultCost = typeRow?["default_unit_cost"]
                } else {
                    // Find first linked type that has a default cost
                    let typeRow = try Row.fetchOne(dbConn, sql: """
                        SELECT pt.default_unit_cost
                        FROM type_color_links tcl
                        JOIN part_types pt ON pt.id = tcl.type_id AND pt.deleted_at IS NULL
                        WHERE tcl.color_id = ? AND pt.default_unit_cost IS NOT NULL
                        LIMIT 1
                        """, arguments: [colorId])
                    typeDefaultCost = typeRow?["default_unit_cost"]
                }

                // Fetch supplier cost if requested
                var supplierCost: Double? = nil
                if let sId = supplierId {
                    let supplierRow = try Row.fetchOne(dbConn, sql: """
                        SELECT cost FROM color_supplier_costs
                        WHERE color_id = ? AND supplier_id = ?
                        """, arguments: [colorId, sId])
                    supplierCost = supplierRow?["cost"]
                }

                // Resolve cascade: supplier → color → type → none
                let effectiveCost: Double?
                let source: String
                if let sc = supplierCost {
                    effectiveCost = sc
                    source = "supplier"
                } else if let cc = colorCost {
                    effectiveCost = cc
                    source = "color"
                } else if let tc = typeDefaultCost {
                    effectiveCost = tc
                    source = "type"
                } else {
                    effectiveCost = nil
                    source = "none"
                }

                return ResolvedCascadeCost(
                    effectiveCost: effectiveCost,
                    source: source,
                    typeDefaultCost: typeDefaultCost,
                    colorOverrideCost: colorCost,
                    supplierCost: supplierCost
                )
            }
        } catch {
            if isTableNotFoundError(error) {
                return ResolvedCascadeCost(effectiveCost: nil, source: "none", typeDefaultCost: nil, colorOverrideCost: nil, supplierCost: nil)
            }
            throw error
        }
    }

    /// Get all supplier costs for a specific color.
    public func getColorSupplierCosts(colorId: Int64) throws -> [ColorSupplierCostRow] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT csc.id, csc.color_id, csc.supplier_id, s.name AS supplier_name,
                           csc.cost, csc.notes
                    FROM color_supplier_costs csc
                    JOIN suppliers s ON s.id = csc.supplier_id AND s.deleted_at IS NULL
                    WHERE csc.color_id = ?
                    ORDER BY s.name ASC
                    """, arguments: [colorId])

                return rows.map { row in
                    ColorSupplierCostRow(
                        id: row["id"],
                        colorId: row["color_id"],
                        supplierId: row["supplier_id"],
                        supplierName: row["supplier_name"] ?? "",
                        cost: row["cost"],
                        notes: row["notes"]
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 5d. Stale Price Detection
    // =========================================================================

    /// Check if a part's price is stale (not updated within the threshold).
    public func isPartPriceStale(partId: Int64) throws -> Bool {
        try db.writer.read { dbConn in
            let thresholdDays = Int(try self.getCompanySetting(dbConn: dbConn, key: "stale_price_threshold_days") ?? "90") ?? 90

            let row = try Row.fetchOne(dbConn, sql: """
                SELECT cost_last_updated FROM parts WHERE id = ? AND deleted_at IS NULL
                """, arguments: [partId])

            guard let lastUpdated: String = row?["cost_last_updated"],
                  let date = ISO8601DateFormatter().date(from: lastUpdated) else {
                return true // never updated = stale
            }

            let daysSinceUpdate = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
            return daysSinceUpdate > thresholdDays
        }
    }

    /// Get all parts with stale pricing. Useful for reports and alerts.
    public func getStalePricedParts(limit: Int = 100) throws -> [(partId: Int64, name: String, daysSinceUpdate: Int)] {
        try db.writer.read { dbConn in
            let thresholdDays = Int(try self.getCompanySetting(dbConn: dbConn, key: "stale_price_threshold_days") ?? "90") ?? 90

            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT id, name, cost_last_updated FROM parts
                WHERE deleted_at IS NULL
                AND (
                    cost_last_updated IS NULL
                    OR julianday('now') - julianday(cost_last_updated) > ?
                )
                ORDER BY cost_last_updated ASC NULLS FIRST
                LIMIT ?
                """, arguments: [thresholdDays, limit])

            return rows.map { row in
                let partId: Int64 = row["id"]
                let name: String = row["name"]
                let lastUpdated: String? = row["cost_last_updated"]
                let days: Int
                if let lu = lastUpdated, let date = ISO8601DateFormatter().date(from: lu) {
                    days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 999
                } else {
                    days = 999
                }
                return (partId: partId, name: name, daysSinceUpdate: days)
            }
        }
    }

    /// Mark a part's cost as verified (update the timestamp without changing the price).
    public func markPriceVerified(partId: Int64) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE parts SET cost_last_updated = ?, updated_at = ?
                WHERE id = ?
                """, arguments: [now, now, partId])
        }
    }

    /// Get all pricing tiers at a specific level.
    public func getPricingTiers(
        categoryId: Int64? = nil,
        styleId: Int64? = nil,
        typeId: Int64? = nil,
        brandId: Int64? = nil
    ) throws -> [PricingTier] {
        try db.writer.read { dbConn in
            var conditions: [String] = ["deleted_at IS NULL"]
            var args: [any DatabaseValueConvertible] = []

            if let id = categoryId { conditions.append("category_id = ?"); args.append(id) }
            if let id = styleId { conditions.append("style_id = ?"); args.append(id) }
            if let id = typeId { conditions.append("type_id = ?"); args.append(id) }
            if let id = brandId { conditions.append("brand_id = ?"); args.append(id) }

            let whereClause = conditions.joined(separator: " AND ")
            return try PricingTier.fetchAll(dbConn, sql: """
                SELECT * FROM pricing_tiers WHERE \(whereClause)
                ORDER BY created_at DESC
                """, arguments: StatementArguments(args))
        }
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

    /// Forecast row with current stock included (requires stock table JOIN).
    public struct ForecastDataRow: Identifiable, Sendable {
        public var id: Int64 { part.id ?? 0 }
        public let part: Part
        public let currentStock: Int
    }

    /// List parts with forecast data and current stock for the forecasting dashboard.
    /// Joins on the stock table to include aggregated current quantity.
    public func listForecastDataWithStock(search: String? = nil, locationType: String? = nil, locationId: Int64? = nil) throws -> [ForecastDataRow] {
        do {
            return try db.writer.read { dbConn in
                var whereClauses = ["p.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []
                var stockJoin = "LEFT JOIN stock s ON s.part_id = p.id AND s.deleted_at IS NULL"

                if let search, !search.isEmpty {
                    whereClauses.append("(p.name LIKE ? OR p.code LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                }

                if let locType = locationType {
                    stockJoin += " AND s.location_type = ?"
                    args.append(locType)
                    if let locId = locationId {
                        stockJoin += " AND s.location_id = ?"
                        args.append(locId)
                    }
                }

                let sql = """
                    SELECT p.*, COALESCE(SUM(s.qty), 0) AS current_stock
                    FROM parts p
                    \(stockJoin)
                    WHERE \(whereClauses.joined(separator: " AND "))
                    GROUP BY p.id
                    ORDER BY COALESCE(p.forecast_days_until_low, 9999) ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.compactMap { row in
                    guard let part = try? Part(row: row) else { return nil }
                    let stock: Int = row["current_stock"]
                    return ForecastDataRow(part: part, currentStock: stock)
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

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

                return try Part.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
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

        // Also update per-location forecasts
        try recalculateForecastsPerLocation()
    }

    // =========================================================================
    // MARK: - 7b. Per-Location Forecasting
    // =========================================================================

    /// Get or create a LocationStockTarget for a part at a specific location.
    /// Falls back to the part's global min/target/max as initial values.
    public func getLocationStockTarget(partId: Int64, locationType: String, locationId: Int64) throws -> LocationStockTarget {
        try db.writer.read { dbConn in
            if let existing = try LocationStockTarget.fetchOne(dbConn, sql: """
                SELECT * FROM location_stock_targets
                WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                """, arguments: [partId, locationType, locationId]) {
                return existing
            }
            let part = try Part.fetchOne(dbConn, key: partId)
            return LocationStockTarget(
                id: nil,
                partId: partId,
                locationType: locationType,
                locationId: locationId,
                minStock: part?.minStockLevel ?? 0,
                targetStock: part?.targetStockLevel ?? 0,
                maxStock: part?.maxStockLevel ?? 0,
                forecastAdu30: nil, forecastAdu90: nil,
                forecastDaysUntilLow: nil, forecastSuggestedOrder: nil,
                forecastLastRun: nil, certaintyRating: nil,
                deletedAt: nil, updatedAt: nil
            )
        }
    }

    /// Update stock targets for a part at a specific location (upsert).
    public func setLocationStockTarget(partId: Int64, locationType: String, locationId: Int64,
                                        minStock: Int, targetStock: Int, maxStock: Int) throws {
        try db.writer.write { dbConn in
            let existing = try LocationStockTarget.fetchOne(dbConn, sql: """
                SELECT * FROM location_stock_targets
                WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                """, arguments: [partId, locationType, locationId])

            if var target = existing {
                target.minStock = minStock
                target.targetStock = targetStock
                target.maxStock = maxStock
                target.updatedAt = ISO8601DateFormatter().string(from: Date())
                try target.update(dbConn)
            } else {
                var target = LocationStockTarget(
                    id: nil, partId: partId,
                    locationType: locationType, locationId: locationId,
                    minStock: minStock, targetStock: targetStock, maxStock: maxStock,
                    forecastAdu30: nil, forecastAdu90: nil,
                    forecastDaysUntilLow: nil, forecastSuggestedOrder: nil,
                    forecastLastRun: nil, certaintyRating: nil,
                    deletedAt: nil, updatedAt: nil
                )
                try target.insert(dbConn)
            }
        }
    }

    /// Per-location stock target with current stock included.
    public struct LocationStockTargetWithStock: Sendable, Identifiable {
        public var id: String { "\(locationType)_\(locationId)" }
        public let locationType: String
        public let locationId: Int64
        public let locationName: String
        public let minStock: Int
        public let targetStock: Int
        public let maxStock: Int
        public let currentStock: Int
        public let forecastAdu30: Double?
        public let forecastDaysUntilLow: Int?
        public let certaintyRating: Double?

        /// Stock health: -1.0 (empty) to 0.0 (at target) to +1.0 (overstocked)
        public var healthScore: Double {
            guard targetStock > 0 else { return 0 }
            if currentStock <= minStock { return -1.0 }
            if currentStock < targetStock {
                guard targetStock != minStock else { return -1.0 }
                return -Double(targetStock - currentStock) / Double(targetStock - minStock)
            }
            if currentStock > maxStock && maxStock > targetStock {
                return 1.0
            }
            if currentStock > targetStock && maxStock > targetStock {
                return Double(currentStock - targetStock) / Double(maxStock - targetStock)
            }
            return 0.0
        }
    }

    /// List all location stock targets for a given part with current stock.
    public func listLocationStockTargets(partId: Int64) throws -> [LocationStockTargetWithStock] {
        try db.writer.read { dbConn in
            // Get all locations where this part has stock or targets
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT
                    lst.location_type,
                    lst.location_id,
                    lst.min_stock,
                    lst.target_stock,
                    lst.max_stock,
                    lst.forecast_adu_30,
                    lst.forecast_days_until_low,
                    lst.certainty_rating,
                    COALESCE((SELECT SUM(s.qty) FROM stock s
                              WHERE s.part_id = lst.part_id
                              AND s.location_type = lst.location_type
                              AND s.location_id = lst.location_id
                              AND s.deleted_at IS NULL), 0) AS current_stock,
                    COALESCE(wl.name, v.name, 'Unknown') AS location_name
                FROM location_stock_targets lst
                LEFT JOIN warehouse_locations wl ON lst.location_type = 'warehouse'
                    AND wl.id = lst.location_id
                LEFT JOIN vehicles v ON lst.location_type = 'truck'
                    AND v.id = lst.location_id
                WHERE lst.part_id = ? AND lst.deleted_at IS NULL
                ORDER BY lst.location_type ASC, location_name ASC
                """, arguments: [partId])

            return rows.map { row in
                LocationStockTargetWithStock(
                    locationType: row["location_type"] ?? "warehouse",
                    locationId: row["location_id"] ?? 1,
                    locationName: row["location_name"] ?? "Unknown",
                    minStock: row["min_stock"] ?? 0,
                    targetStock: row["target_stock"] ?? 0,
                    maxStock: row["max_stock"] ?? 0,
                    currentStock: row["current_stock"] ?? 0,
                    forecastAdu30: row["forecast_adu_30"],
                    forecastDaysUntilLow: row["forecast_days_until_low"],
                    certaintyRating: row["certainty_rating"]
                )
            }
        }
    }

    /// Recalculate forecasts per-location based on stock movements.
    public func recalculateForecastsPerLocation() throws {
        do {
            try db.writer.write { dbConn in
                // Get all active part-location combinations with movements
                let combinations = try Row.fetchAll(dbConn, sql: """
                    SELECT DISTINCT part_id, to_location_type AS lt, to_location_id AS lid
                    FROM stock_movements
                    WHERE deleted_at IS NULL AND to_location_type IS NOT NULL
                    UNION
                    SELECT DISTINCT part_id, from_location_type AS lt, from_location_id AS lid
                    FROM stock_movements
                    WHERE deleted_at IS NULL AND from_location_type IS NOT NULL
                    """)

                for combo in combinations {
                    let partId: Int64 = combo["part_id"]
                    let locType: String = combo["lt"] ?? "warehouse"
                    let locId: Int64 = combo["lid"] ?? 1

                    // ADU-30: outbound movements from this location
                    let consumed30 = try Int.fetchOne(dbConn, sql: """
                        SELECT COALESCE(SUM(ABS(qty)), 0) FROM stock_movements
                        WHERE part_id = ? AND from_location_type = ? AND from_location_id = ?
                          AND movement_type IN ('consume', 'transfer')
                          AND created_at >= datetime('now', '-30 days')
                          AND deleted_at IS NULL
                        """, arguments: [partId, locType, locId]) ?? 0
                    let adu30 = Double(consumed30) / 30.0

                    let consumed90 = try Int.fetchOne(dbConn, sql: """
                        SELECT COALESCE(SUM(ABS(qty)), 0) FROM stock_movements
                        WHERE part_id = ? AND from_location_type = ? AND from_location_id = ?
                          AND movement_type IN ('consume', 'transfer')
                          AND created_at >= datetime('now', '-90 days')
                          AND deleted_at IS NULL
                        """, arguments: [partId, locType, locId]) ?? 0
                    let adu90 = Double(consumed90) / 90.0

                    // Movement count for certainty
                    let movementCount = try Int.fetchOne(dbConn, sql: """
                        SELECT COUNT(*) FROM stock_movements
                        WHERE part_id = ? AND (
                            (from_location_type = ? AND from_location_id = ?) OR
                            (to_location_type = ? AND to_location_id = ?)
                        ) AND deleted_at IS NULL
                        """, arguments: [partId, locType, locId, locType, locId]) ?? 0
                    let certainty = min(1.0, Double(movementCount) / 50.0)

                    // Current stock at this location
                    let currentStock = try Int.fetchOne(dbConn, sql: """
                        SELECT COALESCE(SUM(qty), 0) FROM stock
                        WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                        """, arguments: [partId, locType, locId]) ?? 0

                    // Get min stock target
                    let minStock = try Int.fetchOne(dbConn, sql: """
                        SELECT COALESCE(
                            (SELECT min_stock FROM location_stock_targets
                             WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL),
                            (SELECT min_stock_level FROM parts WHERE id = ?),
                            0
                        )
                        """, arguments: [partId, locType, locId, partId]) ?? 0

                    // Days until low
                    let daysUntilLow: Int
                    if adu30 > 0 {
                        daysUntilLow = max(0, Int(Double(currentStock - minStock) / adu30))
                    } else {
                        daysUntilLow = 999
                    }

                    let targetStock = try Int.fetchOne(dbConn, sql: """
                        SELECT COALESCE(
                            (SELECT target_stock FROM location_stock_targets
                             WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL),
                            (SELECT target_stock_level FROM parts WHERE id = ?),
                            0
                        )
                        """, arguments: [partId, locType, locId, partId]) ?? 0
                    let suggestedOrder = max(0, targetStock - currentStock)

                    // Upsert location_stock_targets
                    let existing = try Row.fetchOne(dbConn, sql: """
                        SELECT id FROM location_stock_targets
                        WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                        """, arguments: [partId, locType, locId])

                    if let existingId: Int64 = existing?["id"] {
                        try dbConn.execute(sql: """
                            UPDATE location_stock_targets SET
                                forecast_adu_30 = ?, forecast_adu_90 = ?,
                                forecast_days_until_low = ?, forecast_suggested_order = ?,
                                forecast_last_run = datetime('now'), certainty_rating = ?,
                                updated_at = datetime('now')
                            WHERE id = ?
                            """, arguments: [adu30, adu90, daysUntilLow, suggestedOrder, certainty, existingId])
                    } else {
                        try dbConn.execute(sql: """
                            INSERT INTO location_stock_targets
                                (part_id, location_type, location_id, min_stock, target_stock, max_stock,
                                 forecast_adu_30, forecast_adu_90, forecast_days_until_low,
                                 forecast_suggested_order, forecast_last_run, certainty_rating)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
                            """, arguments: [partId, locType, locId, minStock, targetStock, 0,
                                           adu30, adu90, daysUntilLow, suggestedOrder, certainty])
                    }
                }
            }
        } catch {
            if isTableNotFoundError(error) { return }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 7c. Forecast Settings
    // =========================================================================

    /// Get forecast settings for a specific location.
    /// Returns location-specific override if exists, otherwise falls back to location-type default.
    public func getForecastSettings(locationType: String, locationId: Int64? = nil) throws -> ForecastSettings? {
        try db.writer.read { dbConn in
            // Try specific location first
            if let locId = locationId {
                if let specific = try ForecastSettings.fetchOne(dbConn, sql: """
                    SELECT * FROM forecast_settings
                    WHERE location_type = ? AND location_id = ?
                    """, arguments: [locationType, locId]) {
                    return specific
                }
            }
            // Fall back to location-type default
            return try ForecastSettings.fetchOne(dbConn, sql: """
                SELECT * FROM forecast_settings
                WHERE location_type = ? AND location_id IS NULL
                """, arguments: [locationType])
        }
    }

    /// Save or update forecast settings.
    /// If locationId is nil, updates the default for that location type.
    /// If locationId is set, creates/updates override for that specific location.
    public func saveForecastSettings(_ settings: ForecastSettings) throws {
        try db.writer.write { dbConn in
            var s = settings
            s.updatedAt = ISO8601DateFormatter().string(from: Date())
            if s.id != nil {
                try s.update(dbConn)
            } else {
                try s.insert(dbConn)
            }
        }
    }

    /// Get free space rating for a location. Returns 5 (middle) if not set.
    public func getFreeSpaceRating(locationType: String, locationId: Int64) throws -> Int {
        try db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: """
                SELECT free_space_rating FROM location_free_space
                WHERE location_type = ? AND location_id = ?
                """, arguments: [locationType, locationId]) ?? 5
        }
    }

    /// Update free space rating for a location (1-10 scale).
    public func setFreeSpaceRating(locationType: String, locationId: Int64, rating: Int, userId: Int64) throws {
        let clamped = max(1, min(10, rating))
        try db.writer.write { dbConn in
            let existing = try LocationFreeSpace.fetchOne(dbConn, sql: """
                SELECT * FROM location_free_space
                WHERE location_type = ? AND location_id = ?
                """, arguments: [locationType, locationId])
            if var fs = existing {
                fs.freeSpaceRating = clamped
                fs.updatedBy = userId
                fs.updatedAt = ISO8601DateFormatter().string(from: Date())
                try fs.update(dbConn)
            } else {
                var fs = LocationFreeSpace(
                    id: nil, locationType: locationType, locationId: locationId,
                    freeSpaceRating: clamped, updatedBy: userId, updatedAt: nil
                )
                try fs.insert(dbConn)
            }
        }
    }

    /// List all forecast settings (defaults + overrides) for the settings UI.
    public func listAllForecastSettings() throws -> [ForecastSettings] {
        try db.writer.read { dbConn in
            try ForecastSettings.fetchAll(dbConn, sql: """
                SELECT * FROM forecast_settings ORDER BY location_type ASC, location_id ASC
                """)
        }
    }

    // =========================================================================
    // MARK: - 7d. Target Recommendations
    // =========================================================================

    /// Generate the daily recommendation. Call from background task.
    /// Picks the single most impactful candidate and creates a recommendation.
    /// Max 1 per day. Respects 60-day cooldown per part+location.
    public func generateDailyRecommendation() throws {
        try db.writer.write { dbConn in
            // Check if we already generated one today
            let todayCount = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM target_recommendations
                WHERE DATE(created_at) = DATE('now') AND deleted_at IS NULL
                """) ?? 0
            guard todayCount == 0 else { return }

            // Get all location-type settings
            let allSettings = try ForecastSettings.fetchAll(dbConn, sql: """
                SELECT * FROM forecast_settings ORDER BY location_id ASC
                """)

            var bestCandidate: (partId: Int64, locType: String, locId: Int64,
                                currentMin: Int, currentTarget: Int, currentMax: Int,
                                recMin: Int, recTarget: Int, recMax: Int,
                                usage: Double, unit: String, dataDays: Int,
                                impact: Double, reason: String, type: String,
                                curCategory: String?, recCategory: String?)?

            // Scan all active part+location combinations
            let combinations = try Row.fetchAll(dbConn, sql: """
                SELECT DISTINCT
                    lst.part_id, lst.location_type, lst.location_id,
                    lst.min_stock, lst.target_stock, lst.max_stock,
                    lst.part_category, lst.forecast_adu_30,
                    COALESCE(SUM(s.qty), 0) AS current_stock
                FROM location_stock_targets lst
                LEFT JOIN stock s ON s.part_id = lst.part_id
                    AND s.location_type = lst.location_type
                    AND s.location_id = lst.location_id
                    AND s.deleted_at IS NULL
                WHERE lst.deleted_at IS NULL AND lst.do_not_restock = 0
                GROUP BY lst.part_id, lst.location_type, lst.location_id
                """)

            for combo in combinations {
                let partId: Int64 = combo["part_id"]
                let locType: String = combo["location_type"] ?? "warehouse"
                let locId: Int64 = combo["location_id"] ?? 1
                let curMin: Int = combo["min_stock"] ?? 0
                let curTarget: Int = combo["target_stock"] ?? 0
                let curMax: Int = combo["max_stock"] ?? 0
                let category: String = combo["part_category"] ?? "common"
                let currentStock: Int = combo["current_stock"] ?? 0

                // Check cooldown — skip if recommended in last 60 days
                let inCooldown = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM target_recommendations
                    WHERE part_id = ? AND location_type = ? AND location_id = ?
                      AND cooldown_until > datetime('now') AND deleted_at IS NULL
                    """, arguments: [partId, locType, locId]) ?? 0
                guard inCooldown == 0 else { continue }

                // Get settings for this location (specific override or type default)
                let settings = allSettings.first(where: {
                    $0.locationType == locType && $0.locationId == locId
                }) ?? allSettings.first(where: {
                    $0.locationType == locType && $0.locationId == nil
                })
                guard let s = settings else { continue }

                // Check minimum data requirement
                let firstMovement = try String.fetchOne(dbConn, sql: """
                    SELECT MIN(created_at) FROM stock_movements
                    WHERE part_id = ? AND deleted_at IS NULL
                      AND ((from_location_type = ? AND from_location_id = ?)
                        OR (to_location_type = ? AND to_location_id = ?))
                    """, arguments: [partId, locType, locId, locType, locId])
                guard let firstDate = firstMovement else { continue }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                guard let first = formatter.date(from: firstDate) else { continue }
                let daysSinceFirst = Int(Date().timeIntervalSince(first) / 86400)
                guard daysSinceFirst >= s.minDataDays else { continue }

                // Calculate usage based on unit
                let usage: Double
                let unit: String
                if s.usageUnit == "weekly" {
                    // APW: parts per X-week window
                    let windowDays = s.windowWeeks * 7
                    let consumed = try Int.fetchOne(dbConn, sql: """
                        SELECT COALESCE(SUM(ABS(qty)), 0) FROM stock_movements
                        WHERE part_id = ? AND from_location_type = ? AND from_location_id = ?
                          AND movement_type IN ('consume', 'transfer')
                          AND created_at >= datetime('now', '-\(windowDays) days')
                          AND deleted_at IS NULL
                        """, arguments: [partId, locType, locId]) ?? 0
                    usage = Double(consumed) // total in window, not per-day
                    unit = "weekly"
                } else {
                    // ADU: parts per day over lookback period
                    let consumed = try Int.fetchOne(dbConn, sql: """
                        SELECT COALESCE(SUM(ABS(qty)), 0) FROM stock_movements
                        WHERE part_id = ? AND from_location_type = ? AND from_location_id = ?
                          AND movement_type IN ('consume', 'transfer')
                          AND created_at >= datetime('now', '-\(s.aduLookbackDays) days')
                          AND deleted_at IS NULL
                        """, arguments: [partId, locType, locId]) ?? 0
                    usage = Double(consumed) / Double(s.aduLookbackDays)
                    unit = "daily"
                }

                // Calculate recommended values using multipliers
                let multipliers = category == "critical"
                    ? (s.criticalMinMultiplier, s.criticalTargetMultiplier, s.criticalMaxMultiplier)
                    : (s.commonMinMultiplier, s.commonTargetMultiplier, s.commonMaxMultiplier)

                var recMin = Int(usage * multipliers.0)
                var recTarget = Int(usage * multipliers.1)
                var recMax = Int(usage * multipliers.2)

                // Enforce validation: MIN < TARGET < MAX
                if recMin >= recTarget { recTarget = recMin + 1 }
                if recTarget >= recMax { recMax = recTarget + 1 }

                // MIN cannot exceed current inventory, MAX cannot be below current inventory
                if recMin > currentStock { recMin = currentStock }
                if recMax < currentStock { recMax = currentStock }
                // Re-validate after clamping
                if recMin >= recTarget { recTarget = recMin + 1 }
                if recTarget >= recMax { recMax = recTarget + 1 }

                // Calculate impact score (bigger gap = more impactful)
                let minDiff = abs(recMin - curMin)
                let targetDiff = abs(recTarget - curTarget)
                let maxDiff = abs(recMax - curMax)
                let impact = Double(minDiff + targetDiff * 2 + maxDiff)

                // Skip if change is trivial
                guard impact > 2 else { continue }

                // Check if this is the best candidate so far
                if bestCandidate == nil || impact > (bestCandidate?.impact ?? 0) {
                    var reason = ""
                    if recTarget > curTarget {
                        reason = "Usage (\(String(format: "%.1f", usage))/\(unit == "daily" ? "day" : "window")) suggests higher stock levels."
                    } else {
                        reason = "Usage (\(String(format: "%.1f", usage))/\(unit == "daily" ? "day" : "window")) suggests lower stock levels."
                    }
                    bestCandidate = (partId, locType, locId,
                                     curMin, curTarget, curMax,
                                     recMin, recTarget, recMax,
                                     usage, unit, daysSinceFirst,
                                     impact, reason, "adjust",
                                     nil, nil)
                }
            }

            // Also check for category change candidates
            // Common → Critical: unused 6 months at a location
            let staleCommon = try Row.fetchAll(dbConn, sql: """
                SELECT lst.part_id, lst.location_type, lst.location_id
                FROM location_stock_targets lst
                WHERE lst.part_category = 'common' AND lst.deleted_at IS NULL
                  AND NOT EXISTS (
                    SELECT 1 FROM stock_movements sm
                    WHERE sm.part_id = lst.part_id
                      AND ((sm.from_location_type = lst.location_type AND sm.from_location_id = lst.location_id)
                        OR (sm.to_location_type = lst.location_type AND sm.to_location_id = lst.location_id))
                      AND sm.created_at >= datetime('now', '-180 days')
                      AND sm.deleted_at IS NULL
                  )
                  AND NOT EXISTS (
                    SELECT 1 FROM target_recommendations tr
                    WHERE tr.part_id = lst.part_id AND tr.location_type = lst.location_type
                      AND tr.location_id = lst.location_id
                      AND tr.cooldown_until > datetime('now') AND tr.deleted_at IS NULL
                  )
                LIMIT 5
                """)

            for row in staleCommon {
                let partId: Int64 = row["part_id"]
                let locType: String = row["location_type"] ?? "warehouse"
                let locId: Int64 = row["location_id"] ?? 1
                let impact = 5.0
                if bestCandidate == nil || impact > (bestCandidate?.impact ?? 0) {
                    bestCandidate = (partId, locType, locId, 0, 0, 0, 0, 0, 0,
                                     0, "daily", 180, impact,
                                     "No usage in 6 months. Consider marking as Critical or removing.",
                                     "category_change", "common", "critical")
                }
            }

            // Critical → Common: used consistently 4 of last 6 months
            let activeCritical = try Row.fetchAll(dbConn, sql: """
                SELECT lst.part_id, lst.location_type, lst.location_id,
                       COUNT(DISTINCT strftime('%Y-%m', sm.created_at)) AS active_months
                FROM location_stock_targets lst
                JOIN stock_movements sm ON sm.part_id = lst.part_id
                    AND ((sm.from_location_type = lst.location_type AND sm.from_location_id = lst.location_id)
                      OR (sm.to_location_type = lst.location_type AND sm.to_location_id = lst.location_id))
                    AND sm.created_at >= datetime('now', '-180 days')
                    AND sm.deleted_at IS NULL
                WHERE lst.part_category = 'critical' AND lst.deleted_at IS NULL
                  AND NOT EXISTS (
                    SELECT 1 FROM target_recommendations tr
                    WHERE tr.part_id = lst.part_id AND tr.location_type = lst.location_type
                      AND tr.location_id = lst.location_id
                      AND tr.cooldown_until > datetime('now') AND tr.deleted_at IS NULL
                  )
                GROUP BY lst.part_id, lst.location_type, lst.location_id
                HAVING active_months >= 4
                LIMIT 5
                """)

            for row in activeCritical {
                let partId: Int64 = row["part_id"]
                let locType: String = row["location_type"] ?? "warehouse"
                let locId: Int64 = row["location_id"] ?? 1
                let impact = 5.0
                if bestCandidate == nil || impact > (bestCandidate?.impact ?? 0) {
                    bestCandidate = (partId, locType, locId, 0, 0, 0, 0, 0, 0,
                                     0, "daily", 180, impact,
                                     "Used consistently (4+ of last 6 months). Consider switching to Common for better restocking.",
                                     "category_change", "critical", "common")
                }
            }

            // Create the recommendation if we found a candidate
            guard let best = bestCandidate else { return }

            try dbConn.execute(sql: """
                INSERT INTO target_recommendations
                    (part_id, location_type, location_id, recommendation_type,
                     current_min, current_target, current_max,
                     recommended_min, recommended_target, recommended_max,
                     current_category, recommended_category,
                     usage_value, usage_unit, data_days, impact_score, reason,
                     cooldown_until, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                        datetime('now', '+60 days'), 'pending')
                """, arguments: [
                    best.partId, best.locType, best.locId, best.type,
                    best.currentMin, best.currentTarget, best.currentMax,
                    best.recMin, best.recTarget, best.recMax,
                    best.curCategory, best.recCategory,
                    best.usage, best.unit, best.dataDays, best.impact, best.reason
                ])
        }
    }

    /// List pending recommendations (up to 14 days).
    public func listPendingRecommendations(limit: Int = 14) throws -> [TargetRecommendation] {
        try db.writer.read { dbConn in
            try TargetRecommendation.fetchAll(dbConn, sql: """
                SELECT * FROM target_recommendations
                WHERE status = 'pending' AND deleted_at IS NULL
                ORDER BY created_at DESC
                LIMIT ?
                """, arguments: [limit])
        }
    }

    /// Approve a recommendation — applies the new values to location_stock_targets.
    public func approveRecommendation(id: Int64, userId: Int64) throws {
        try db.writer.write { dbConn in
            guard let rec = try TargetRecommendation.fetchOne(dbConn, key: id),
                  rec.status == "pending" else { return }

            if rec.recommendationType == "adjust" {
                try dbConn.execute(sql: """
                    UPDATE location_stock_targets SET
                        min_stock = COALESCE(?, min_stock),
                        target_stock = COALESCE(?, target_stock),
                        max_stock = COALESCE(?, max_stock),
                        updated_at = datetime('now')
                    WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                    """, arguments: [rec.recommendedMin, rec.recommendedTarget, rec.recommendedMax,
                                     rec.partId, rec.locationType, rec.locationId])
            } else if rec.recommendationType == "category_change" {
                try dbConn.execute(sql: """
                    UPDATE location_stock_targets SET
                        part_category = ?,
                        updated_at = datetime('now')
                    WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                    """, arguments: [rec.recommendedCategory, rec.partId, rec.locationType, rec.locationId])
            } else if rec.recommendationType == "remove" {
                try dbConn.execute(sql: """
                    UPDATE location_stock_targets SET
                        do_not_restock = 1,
                        updated_at = datetime('now')
                    WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                    """, arguments: [rec.partId, rec.locationType, rec.locationId])
            }

            // Mark recommendation as approved
            try dbConn.execute(sql: """
                UPDATE target_recommendations SET
                    status = 'approved', approved_by = ?, approved_at = datetime('now')
                WHERE id = ?
                """, arguments: [userId, id])
        }
    }

    /// Dismiss a recommendation with required reason.
    public func dismissRecommendation(id: Int64, userId: Int64, reason: String) throws {
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PartsError.invalidInput("Dismiss reason is required")
        }
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE target_recommendations SET
                    status = 'dismissed', dismissed_by = ?, dismissed_reason = ?
                WHERE id = ? AND status = 'pending'
                """, arguments: [userId, reason, id])
        }
    }

    /// Count pending recommendations (for badge display).
    public func pendingRecommendationCount() throws -> Int {
        try db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM target_recommendations
                WHERE status = 'pending' AND deleted_at IS NULL
                """) ?? 0
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
                            styleId: row["style_id"] as Int64?,
                            typeId: row["type_id"] as Int64?
                        )
                    }

                    let targets = targetRows.map { row in
                        CompanionRuleTarget(
                            id: row["id"] as Int64,
                            ruleId: row["rule_id"] as Int64,
                            categoryId: row["category_id"] as Int64,
                            styleId: row["style_id"] as Int64?,
                            typeId: row["type_id"] as Int64?
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
            try dbConn.execute(sql: sql, arguments: StatementArguments(args))
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
    // MARK: - 8b. Companion Rules V2 (Hierarchy + Points)
    // =========================================================================

    /// Row returned by the hierarchical rule listing.
    public struct CompanionRuleHierarchyRow: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let description: String?
        public let matchLevel: String
        public let tryMatchBrand: Int
        public let autoColorMatch: Int
        public let qtyMode: String
        public let qtyRatio: Double
        public let isActive: Int
        public let parentRuleId: Int64?
        public let autoDeleteAt: String?
        public let deletedAt: String?
        public let createdAt: String?
        public let sources: [CompanionRuleSource]
        public let targets: [CompanionRuleTarget]
        public let childCount: Int
        public let isOrphaned: Bool
    }

    /// List all companion rules grouped by hierarchy. Parent rules first, children indented.
    /// Includes orphaned children (parent deleted, auto_delete_at set).
    public func listCompanionRulesHierarchy() throws -> [CompanionRuleHierarchyRow] {
        try db.writer.read { dbConn in
            // Get all rules (excluding expired auto-deletes)
            let ruleRows = try Row.fetchAll(dbConn, sql: """
                SELECT * FROM companion_rules
                WHERE auto_delete_at IS NULL OR auto_delete_at >= datetime('now')
                ORDER BY parent_rule_id IS NOT NULL, parent_rule_id, name ASC
                """)

            return try ruleRows.map { ruleRow in
                let ruleId: Int64 = ruleRow["id"]

                let sourceRows = try Row.fetchAll(dbConn, sql: """
                    SELECT * FROM companion_rule_sources WHERE rule_id = ?
                    """, arguments: [ruleId])

                let targetRows = try Row.fetchAll(dbConn, sql: """
                    SELECT * FROM companion_rule_targets WHERE rule_id = ?
                    """, arguments: [ruleId])

                let sources = sourceRows.map { row in
                    CompanionRuleSource(
                        id: row["id"] as Int64,
                        ruleId: row["rule_id"] as Int64,
                        categoryId: row["category_id"] as Int64,
                        styleId: row["style_id"] as Int64?,
                        typeId: row["type_id"] as Int64?
                    )
                }

                let targets = targetRows.map { row in
                    CompanionRuleTarget(
                        id: row["id"] as Int64,
                        ruleId: row["rule_id"] as Int64,
                        categoryId: row["category_id"] as Int64,
                        styleId: row["style_id"] as Int64?,
                        typeId: row["type_id"] as Int64?
                    )
                }

                let childCount: Int = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM companion_rules WHERE parent_rule_id = ?
                    """, arguments: [ruleId]) ?? 0

                // Determine match level from source entries
                let matchLevel: String
                if sources.first?.typeId != nil { matchLevel = "type" }
                else if sources.first?.styleId != nil { matchLevel = "style" }
                else { matchLevel = "category" }

                // Check if orphaned: has parent and parent is deleted
                let isOrphaned: Bool
                if let parentId: Int64 = ruleRow["parent_rule_id"] {
                    let parentDeletedAt: String? = try Row.fetchOne(dbConn, sql: """
                        SELECT deleted_at FROM companion_rules WHERE id = ?
                        """, arguments: [parentId])?["deleted_at"]
                    isOrphaned = parentDeletedAt != nil
                } else {
                    isOrphaned = false
                }

                return CompanionRuleHierarchyRow(
                    id: ruleId,
                    name: ruleRow["name"] as String,
                    description: ruleRow["description"] as String?,
                    matchLevel: matchLevel,
                    tryMatchBrand: ruleRow["try_match_brand"] as Int,
                    autoColorMatch: ruleRow["auto_color_match"] as Int,
                    qtyMode: (ruleRow["qty_mode"] as String?) ?? "sum",
                    qtyRatio: (ruleRow["qty_ratio"] as Double?) ?? 1.0,
                    isActive: ruleRow["is_active"] as Int,
                    parentRuleId: ruleRow["parent_rule_id"] as Int64?,
                    autoDeleteAt: ruleRow["auto_delete_at"] as String?,
                    deletedAt: ruleRow["deleted_at"] as String?,
                    createdAt: ruleRow["created_at"] as String?,
                    sources: sources,
                    targets: targets,
                    childCount: childCount,
                    isOrphaned: isOrphaned
                )
            }
        }
    }

    /// Create a companion rule at a specific hierarchy level (category/style/type).
    @discardableResult
    public func createCompanionRuleAtLevel(
        name: String,
        description: String? = nil,
        qtyMode: String = "sum",
        qtyRatio: Double = 1.0,
        tryMatchBrand: Bool = false,
        autoColorMatch: Bool = true,
        parentRuleId: Int64? = nil,
        sources: [(categoryId: Int64, styleId: Int64?, typeId: Int64?)],
        targets: [(categoryId: Int64, styleId: Int64?, typeId: Int64?)]
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            let matchLevel: String
            if sources.first?.typeId != nil { matchLevel = "type" }
            else if sources.first?.styleId != nil { matchLevel = "style" }
            else { matchLevel = "category" }

            try dbConn.execute(sql: """
                INSERT INTO companion_rules
                (name, description, style_match, qty_mode, qty_ratio, try_match_brand, auto_color_match,
                 parent_rule_id, is_active, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
                """,
                arguments: [name, description, matchLevel, qtyMode, qtyRatio,
                            tryMatchBrand ? 1 : 0, autoColorMatch ? 1 : 0, parentRuleId])
            let ruleId = dbConn.lastInsertedRowID

            for src in sources {
                try dbConn.execute(sql: """
                    INSERT INTO companion_rule_sources (rule_id, category_id, style_id, type_id)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [ruleId, src.categoryId, src.styleId, src.typeId])
            }

            for tgt in targets {
                try dbConn.execute(sql: """
                    INSERT INTO companion_rule_targets (rule_id, category_id, style_id, type_id)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [ruleId, tgt.categoryId, tgt.styleId, tgt.typeId])
            }

            return ruleId
        }
    }

    /// Soft-delete a companion rule. If it has children, schedule them for auto-deletion in 30 days.
    public func deleteCompanionRuleSoft(id: Int64) throws {
        try db.writer.write { dbConn in
            let now = ISO8601DateFormatter().string(from: Date())
            try dbConn.execute(sql: """
                UPDATE companion_rules SET deleted_at = ?, is_active = 0, updated_at = ?
                WHERE id = ?
                """, arguments: [now, now, id])

            let deleteDate = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date().addingTimeInterval(30 * 86400))
            try dbConn.execute(sql: """
                UPDATE companion_rules SET auto_delete_at = ?, is_active = 0, updated_at = ?
                WHERE parent_rule_id = ? AND deleted_at IS NULL
                """, arguments: [deleteDate, now, id])
        }
    }

    /// Restore a soft-deleted companion rule and cancel auto-deletion of its children.
    public func restoreCompanionRule(id: Int64) throws {
        try db.writer.write { dbConn in
            let now = ISO8601DateFormatter().string(from: Date())
            try dbConn.execute(sql: """
                UPDATE companion_rules SET deleted_at = NULL, is_active = 1, updated_at = ?
                WHERE id = ?
                """, arguments: [now, id])

            try dbConn.execute(sql: """
                UPDATE companion_rules SET auto_delete_at = NULL, is_active = 1, updated_at = ?
                WHERE parent_rule_id = ? AND deleted_at IS NULL
                """, arguments: [now, id])
        }
    }

    /// Hard-delete rules that have passed their auto_delete_at date.
    public func purgeExpiredRules() throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                DELETE FROM companion_rules
                WHERE auto_delete_at IS NOT NULL AND auto_delete_at < datetime('now')
                """)
        }
    }

    /// List ALL part alternatives (not filtered by a specific part). For the alternatives tab.
    public func listAllAlternatives() throws -> [PartAlternativeWithName] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT pa.id, pa.part_id, pa.alternative_part_id,
                       pa.relationship, pa.preference, pa.notes,
                       pa.created_by, pa.created_at,
                       p1.name AS part_name, p1.code AS part_code,
                       p2.name AS alt_name, p2.code AS alt_code
                FROM part_alternatives pa
                JOIN parts p1 ON p1.id = pa.part_id
                JOIN parts p2 ON p2.id = pa.alternative_part_id
                WHERE p1.deleted_at IS NULL AND p2.deleted_at IS NULL
                ORDER BY pa.preference ASC, pa.id ASC
                """)
            return rows.map { row in
                PartAlternativeWithName(
                    id: row["id"], partId: row["part_id"],
                    alternativePartId: row["alternative_part_id"],
                    relationship: row["relationship"], preference: row["preference"],
                    notes: row["notes"], createdBy: row["created_by"],
                    createdAt: row["created_at"],
                    partName: row["part_name"],
                    partCode: row["part_code"],
                    alternativePartName: row["alt_name"],
                    alternativePartCode: row["alt_code"]
                )
            }
        }
    }

    /// Calculate co-occurrence points by scanning job_parts data.
    /// Groups parts by job, counts category-level co-occurrences.
    /// 1 point per part qty co-occurring on the same job.
    public func calculateCoOccurrencePoints(windowMonths: Int = 48) throws {
        try db.writer.write { dbConn in
            let windowMonthsClamped = max(3, min(windowMonths, 48))
            let cutoffDate = Calendar.current.date(byAdding: .month, value: -windowMonthsClamped, to: Date()) ?? Date().addingTimeInterval(-Double(windowMonthsClamped) * 30 * 86400)
            let cutoff = ISO8601DateFormatter().string(from: cutoffDate)

            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT jp.job_id, p.category_id, SUM(jp.qty_consumed) AS total_qty
                FROM job_parts jp
                JOIN parts p ON p.id = jp.part_id
                WHERE jp.deleted_at IS NULL
                  AND p.deleted_at IS NULL
                  AND p.category_id IS NOT NULL
                  AND jp.consumed_at >= ?
                GROUP BY jp.job_id, p.category_id
                """, arguments: [cutoff])

            var jobCategories: [Int64: [(categoryId: Int64, qty: Int)]] = [:]
            for row in rows {
                let jobId: Int64 = row["job_id"]
                let catId: Int64 = row["category_id"]
                let qty: Int = row["total_qty"]
                jobCategories[jobId, default: []].append((categoryId: catId, qty: qty))
            }

            var pairPoints: [String: (catA: Int64, catB: Int64, points: Int, jobCount: Int)] = [:]
            for (_, categories) in jobCategories {
                guard categories.count >= 2 else { continue }
                for i in 0..<categories.count {
                    for j in (i+1)..<categories.count {
                        let a = categories[i]
                        let b = categories[j]
                        let (catA, catB, pts) = a.categoryId < b.categoryId
                            ? (a.categoryId, b.categoryId, min(a.qty, b.qty))
                            : (b.categoryId, a.categoryId, min(a.qty, b.qty))
                        let key = "\(catA)-\(catB)"
                        var existing = pairPoints[key] ?? (catA: catA, catB: catB, points: 0, jobCount: 0)
                        existing.points += pts
                        existing.jobCount += 1
                        pairPoints[key] = existing
                    }
                }
            }

            for (_, pair) in pairPoints {
                let existing = try Row.fetchOne(dbConn, sql: """
                    SELECT id, points FROM co_occurrence_pairs
                    WHERE category_a_id = ? AND category_b_id = ? AND match_level = 'category'
                    """, arguments: [pair.catA, pair.catB])

                if let existing = existing {
                    let existingId: Int64 = existing["id"]
                    try dbConn.execute(sql: """
                        UPDATE co_occurrence_pairs
                        SET points = ?, co_occurrence_count = ?, last_computed = datetime('now')
                        WHERE id = ?
                        """, arguments: [pair.points, pair.jobCount, existingId])
                } else {
                    try dbConn.execute(sql: """
                        INSERT INTO co_occurrence_pairs
                        (category_a_id, category_b_id, co_occurrence_count, points, match_level,
                         confidence, last_computed)
                        VALUES (?, ?, ?, ?, 'category', ?, datetime('now'))
                        """, arguments: [pair.catA, pair.catB, pair.jobCount, pair.points,
                                         Double(pair.jobCount) / Double(max(jobCategories.count, 1))])
                }
            }
        }
    }

    /// Get qualified pairs that meet all thresholds for poll candidacy.
    public func getQualifiedPairs(
        minPoints: Int = 100,
        minConfidence: Double = 0.15,
        minJobs: Int = 15,
        level: String = "category"
    ) throws -> [(pairId: Int64, catAId: Int64, catBId: Int64, catAName: String, catBName: String, points: Int, confidence: Double, jobCount: Int)] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT cop.id, cop.category_a_id, cop.category_b_id,
                       cop.points, cop.confidence, cop.co_occurrence_count,
                       ca.name AS cat_a_name, cb.name AS cat_b_name
                FROM co_occurrence_pairs cop
                JOIN part_categories ca ON ca.id = cop.category_a_id
                JOIN part_categories cb ON cb.id = cop.category_b_id
                WHERE cop.match_level = ?
                  AND cop.points >= ?
                  AND cop.confidence >= ?
                  AND cop.co_occurrence_count >= ?
                  AND cop.is_blocked = 0
                  AND (cop.tied_cooldown_until IS NULL OR cop.tied_cooldown_until < date('now'))
                  AND cop.id NOT IN (
                      SELECT co_occurrence_id FROM companion_polls
                      WHERE status = 'active' AND match_level = ?
                  )
                ORDER BY cop.points DESC
                """, arguments: [level, minPoints, minConfidence, minJobs, level])

            return rows.map { row in
                (pairId: row["id"] as Int64,
                 catAId: row["category_a_id"] as Int64,
                 catBId: row["category_b_id"] as Int64,
                 catAName: row["cat_a_name"] as String,
                 catBName: row["cat_b_name"] as String,
                 points: row["points"] as Int,
                 confidence: row["confidence"] as Double,
                 jobCount: row["co_occurrence_count"] as Int)
            }
        }
    }

    /// Apply a rejection penalty to a co-occurrence pair (-100 points).
    /// If rejection_count reaches 5, mark as permanently blocked.
    public func applyRejectionPenalty(pairId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE co_occurrence_pairs
                SET points = MAX(0, points - 100),
                    rejection_count = rejection_count + 1,
                    is_blocked = CASE WHEN rejection_count + 1 >= 5 THEN 1 ELSE 0 END,
                    last_computed = datetime('now')
                WHERE id = ?
                """, arguments: [pairId])
        }
    }

    /// Apply a skip penalty to a co-occurrence pair (-50 points only, no rejection count increase).
    public func applySkipPenalty(pairId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE co_occurrence_pairs
                SET points = MAX(0, points - 50),
                    last_computed = datetime('now')
                WHERE id = ?
                """, arguments: [pairId])
        }
    }

    /// Admin reset: unblock a permanently blocked pair and reset its rejection count.
    public func resetBlockedPair(pairId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE co_occurrence_pairs
                SET is_blocked = 0, rejection_count = 0, last_computed = datetime('now')
                WHERE id = ?
                """, arguments: [pairId])
        }
    }

    // MARK: - 8b2. Auto-Discovery Drill-Down

    /// After a category-level poll is accepted, calculate style-level co-occurrence
    /// for the styles within those accepted categories.
    /// This is the hierarchical cascade: Category → Style → Type → Brand.
    public func calculateStyleCoOccurrence(
        categoryAId: Int64,
        categoryBId: Int64,
        windowMonths: Int = 48
    ) throws {
        try db.writer.write { dbConn in
            let windowMonthsClamped = max(3, min(windowMonths, 48))
            let cutoffDate = Calendar.current.date(byAdding: .month, value: -windowMonthsClamped, to: Date()) ?? Date().addingTimeInterval(-Double(windowMonthsClamped) * 30 * 86400)
            let cutoff = ISO8601DateFormatter().string(from: cutoffDate)

            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT jp.job_id, p.category_id, p.style_id, SUM(jp.qty_consumed) AS total_qty
                FROM job_parts jp
                JOIN parts p ON p.id = jp.part_id
                WHERE jp.deleted_at IS NULL AND p.deleted_at IS NULL
                  AND p.category_id IN (?, ?)
                  AND p.style_id IS NOT NULL
                  AND jp.consumed_at >= ?
                GROUP BY jp.job_id, p.category_id, p.style_id
                """, arguments: [categoryAId, categoryBId, cutoff])

            var jobStyles: [Int64: [(catId: Int64, styleId: Int64, qty: Int)]] = [:]
            for row in rows {
                let jobId: Int64 = row["job_id"]
                jobStyles[jobId, default: []].append((
                    catId: row["category_id"],
                    styleId: row["style_id"],
                    qty: row["total_qty"]
                ))
            }

            var pairPoints: [String: (styleA: Int64, catA: Int64, styleB: Int64, catB: Int64, points: Int, jobCount: Int)] = [:]
            for (_, styles) in jobStyles {
                let fromA = styles.filter { $0.catId == categoryAId }
                let fromB = styles.filter { $0.catId == categoryBId }
                for a in fromA {
                    for b in fromB {
                        let (sA, sB) = a.styleId < b.styleId ? (a.styleId, b.styleId) : (b.styleId, a.styleId)
                        let key = "\(sA)-\(sB)"
                        var existing = pairPoints[key] ?? (styleA: sA, catA: categoryAId, styleB: sB, catB: categoryBId, points: 0, jobCount: 0)
                        existing.points += min(a.qty, b.qty)
                        existing.jobCount += 1
                        pairPoints[key] = existing
                    }
                }
            }

            for (_, pair) in pairPoints {
                let existing = try Row.fetchOne(dbConn, sql: """
                    SELECT id FROM co_occurrence_pairs
                    WHERE category_a_id = ? AND category_b_id = ?
                      AND style_a_id = ? AND style_b_id = ? AND match_level = 'style'
                    """, arguments: [pair.catA, pair.catB, pair.styleA, pair.styleB])

                if let existing = existing {
                    let existingId: Int64 = existing["id"]
                    try dbConn.execute(sql: """
                        UPDATE co_occurrence_pairs
                        SET points = ?, co_occurrence_count = ?, last_computed = datetime('now')
                        WHERE id = ?
                        """, arguments: [pair.points, pair.jobCount, existingId])
                } else {
                    try dbConn.execute(sql: """
                        INSERT INTO co_occurrence_pairs
                        (category_a_id, category_b_id, style_a_id, style_b_id,
                         co_occurrence_count, points, match_level, confidence, last_computed)
                        VALUES (?, ?, ?, ?, ?, ?, 'style', ?, datetime('now'))
                        """, arguments: [pair.catA, pair.catB, pair.styleA, pair.styleB,
                                         pair.jobCount, pair.points,
                                         Double(pair.jobCount) / Double(max(jobStyles.count, 1))])
                }
            }
        }
    }

    /// After a style-level poll is accepted, calculate type-level co-occurrence.
    public func calculateTypeCoOccurrence(
        styleAId: Int64,
        styleBId: Int64,
        categoryAId: Int64,
        categoryBId: Int64,
        windowMonths: Int = 48
    ) throws {
        try db.writer.write { dbConn in
            let cutoffDate = Calendar.current.date(byAdding: .month, value: -max(3, min(windowMonths, 48)), to: Date()) ?? Date().addingTimeInterval(-Double(max(3, min(windowMonths, 48))) * 30 * 86400)
            let cutoff = ISO8601DateFormatter().string(from: cutoffDate)

            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT jp.job_id, p.style_id, p.type_id, SUM(jp.qty_consumed) AS total_qty
                FROM job_parts jp
                JOIN parts p ON p.id = jp.part_id
                WHERE jp.deleted_at IS NULL AND p.deleted_at IS NULL
                  AND p.style_id IN (?, ?)
                  AND p.type_id IS NOT NULL
                  AND jp.consumed_at >= ?
                GROUP BY jp.job_id, p.style_id, p.type_id
                """, arguments: [styleAId, styleBId, cutoff])

            var jobTypes: [Int64: [(styleId: Int64, typeId: Int64, qty: Int)]] = [:]
            for row in rows {
                let jobId: Int64 = row["job_id"]
                jobTypes[jobId, default: []].append((
                    styleId: row["style_id"],
                    typeId: row["type_id"],
                    qty: row["total_qty"]
                ))
            }

            var pairPoints: [String: (typeA: Int64, typeB: Int64, points: Int, jobCount: Int)] = [:]
            for (_, types) in jobTypes {
                let fromA = types.filter { $0.styleId == styleAId }
                let fromB = types.filter { $0.styleId == styleBId }
                for a in fromA {
                    for b in fromB {
                        let (tA, tB) = a.typeId < b.typeId ? (a.typeId, b.typeId) : (b.typeId, a.typeId)
                        let key = "\(tA)-\(tB)"
                        var existing = pairPoints[key] ?? (typeA: tA, typeB: tB, points: 0, jobCount: 0)
                        existing.points += min(a.qty, b.qty)
                        existing.jobCount += 1
                        pairPoints[key] = existing
                    }
                }
            }

            for (_, pair) in pairPoints {
                let existing = try Row.fetchOne(dbConn, sql: """
                    SELECT id FROM co_occurrence_pairs
                    WHERE category_a_id = ? AND category_b_id = ?
                      AND type_a_id = ? AND type_b_id = ? AND match_level = 'type'
                    """, arguments: [categoryAId, categoryBId, pair.typeA, pair.typeB])

                if let existing = existing {
                    let existingId: Int64 = existing["id"]
                    try dbConn.execute(sql: "UPDATE co_occurrence_pairs SET points = ?, co_occurrence_count = ?, last_computed = datetime('now') WHERE id = ?",
                                       arguments: [pair.points, pair.jobCount, existingId])
                } else {
                    try dbConn.execute(sql: """
                        INSERT INTO co_occurrence_pairs
                        (category_a_id, category_b_id, style_a_id, style_b_id, type_a_id, type_b_id,
                         co_occurrence_count, points, match_level, confidence, last_computed)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'type', ?, datetime('now'))
                        """, arguments: [categoryAId, categoryBId, styleAId, styleBId,
                                         pair.typeA, pair.typeB, pair.jobCount, pair.points,
                                         Double(pair.jobCount) / Double(max(jobTypes.count, 1))])
                }
            }
        }
    }

    /// Run the full auto-discovery cycle: close expired polls, calculate points,
    /// trigger drill-downs for accepted polls, create weekly poll if needed.
    /// Call this on app launch or daily.
    public func runAutoDiscoveryCycle() throws {
        // 1. Close expired polls
        try closeExpiredPolls()

        // 2. Purge expired cascade-deleted rules
        try purgeExpiredRules()

        // 3. Recalculate category-level co-occurrence points
        try calculateCoOccurrencePoints()

        // 4. For any recently accepted polls, trigger next-level drill-down
        let recentlyAccepted = try db.writer.read { dbConn in
            try Row.fetchAll(dbConn, sql: """
                SELECT cp.source_category_id, cp.target_category_id,
                       cp.source_style_id, cp.target_style_id,
                       cp.match_level
                FROM companion_polls cp
                WHERE cp.result = 'accepted'
                  AND cp.completed_at >= datetime('now', '-7 days')
                ORDER BY cp.completed_at DESC
                """)
        }

        for poll in recentlyAccepted {
            let level: String = poll["match_level"] ?? "category"
            switch level {
            case "category":
                if let catA: Int64 = poll["source_category_id"],
                   let catB: Int64 = poll["target_category_id"] {
                    try calculateStyleCoOccurrence(categoryAId: catA, categoryBId: catB)
                }
            case "style":
                if let styleA: Int64 = poll["source_style_id"],
                   let styleB: Int64 = poll["target_style_id"],
                   let catA: Int64 = poll["source_category_id"],
                   let catB: Int64 = poll["target_category_id"] {
                    try calculateTypeCoOccurrence(styleAId: styleA, styleBId: styleB,
                                                  categoryAId: catA, categoryBId: catB)
                }
            default:
                break
            }
        }

        // 5. Create weekly poll if none exists this week
        _ = try createWeeklyPoll()

        // 6. Log the analysis run
        let now = ISO8601DateFormatter().string(from: Date())
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO companion_auto_discovery_log
                (analysis_date, match_level, data_window_months, pairs_analyzed, created_at)
                VALUES (?, 'all', 48, 0, datetime('now'))
                """, arguments: [now])
        }
    }

    // MARK: 8b-2. Companion Suggestions for JPO Creation

    /// A companion suggestion for the JPO creation page.
    public struct CompanionSuggestion: Sendable {
        public let partId: Int64
        public let partName: String
        public let suggestedQty: Int
        public let points: Int
        public let confidence: Double
        public let pattern: String
    }

    /// Get companion suggestions for a part based on its category/style/type.
    /// Matches the part's hierarchy against companion rule sources, returns
    /// target parts sorted by co-occurrence points.
    public func getCompanionSuggestionsForPart(partId: Int64, limit: Int = 5) throws -> [CompanionSuggestion] {
        try db.writer.read { dbConn in
            // First get the part's hierarchy IDs
            guard let partRow = try Row.fetchOne(dbConn, sql: """
                SELECT category_id, style_id, type_id FROM parts WHERE id = ? AND deleted_at IS NULL
                """, arguments: [partId]) else {
                return []
            }
            let categoryId: Int64 = partRow["category_id"]
            let styleId: Int64? = partRow["style_id"]
            let typeId: Int64? = partRow["type_id"]

            // Find companion rules where the source matches this part's hierarchy
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT DISTINCT p.id AS target_part_id, p.name AS part_name,
                       cr.name AS rule_name, cr.qty_ratio,
                       COALESCE(cop.points, 0) AS points,
                       COALESCE(cop.confidence, 0) AS confidence
                FROM companion_rule_sources rs
                JOIN companion_rules cr ON cr.id = rs.rule_id AND cr.is_active = 1
                JOIN companion_rule_targets rt ON rt.rule_id = cr.id
                JOIN parts p ON p.category_id = rt.category_id
                    AND (rt.style_id IS NULL OR p.style_id = rt.style_id)
                    AND (rt.type_id IS NULL OR p.type_id = rt.type_id)
                    AND p.deleted_at IS NULL
                    AND p.id != ?
                LEFT JOIN co_occurrence_pairs cop ON
                    (cop.category_a_id = rs.category_id AND cop.category_b_id = rt.category_id)
                    OR (cop.category_b_id = rs.category_id AND cop.category_a_id = rt.category_id)
                WHERE rs.category_id = ?
                    AND (rs.style_id IS NULL OR rs.style_id = ?)
                    AND (rs.type_id IS NULL OR rs.type_id = ?)
                    AND cr.deleted_at IS NULL
                ORDER BY points DESC, confidence DESC
                LIMIT ?
                """, arguments: [partId, categoryId, styleId, typeId, limit])

            return rows.map { row in
                CompanionSuggestion(
                    partId: row["target_part_id"] as Int64? ?? 0,
                    partName: row["part_name"] as String? ?? "Unknown",
                    suggestedQty: max(1, Int(row["qty_ratio"] as Double? ?? 1.0)),
                    points: row["points"] as Int? ?? 0,
                    confidence: row["confidence"] as Double? ?? 0,
                    pattern: "Companion: \(row["rule_name"] as String? ?? "rule")"
                )
            }
        }
    }

    // MARK: 8b-3. Companion Feedback Recording

    /// Record that a companion/AI suggestion was accepted from the JPO creation page.
    /// Updates co-occurrence points and logs to companion_feedback table.
    /// Non-critical — callers should catch errors silently.
    public func recordCompanionFeedback(
        sourcePartId: Int64,
        targetPartId: Int64,
        suggestedQty: Int,
        acceptedQty: Int,
        source: String,
        userId: Int64?
    ) throws {
        try db.writer.write { dbConn in
            // Get hierarchy IDs for both parts
            guard let sourceRow = try Row.fetchOne(dbConn, sql: """
                SELECT category_id, style_id, type_id FROM parts WHERE id = ? AND deleted_at IS NULL
                """, arguments: [sourcePartId]),
                  let targetRow = try Row.fetchOne(dbConn, sql: """
                SELECT category_id, style_id, type_id FROM parts WHERE id = ? AND deleted_at IS NULL
                """, arguments: [targetPartId]) else {
                return
            }

            let srcCat: Int64 = sourceRow["category_id"]
            let tgtCat: Int64 = targetRow["category_id"]
            let tgtStyle: Int64? = targetRow["style_id"]

            // 1. Update or insert co_occurrence_pairs (category-level)
            try dbConn.execute(sql: """
                UPDATE co_occurrence_pairs SET
                    points = points + 1,
                    co_occurrence_count = co_occurrence_count + 1
                WHERE (category_a_id = ? AND category_b_id = ?)
                   OR (category_b_id = ? AND category_a_id = ?)
                """, arguments: [srcCat, tgtCat, srcCat, tgtCat])

            if dbConn.changesCount == 0 {
                try dbConn.execute(sql: """
                    INSERT INTO co_occurrence_pairs
                        (category_a_id, category_b_id, co_occurrence_count, points, confidence,
                         match_level, last_computed)
                    VALUES (?, ?, 1, 1, 0.5, 'category', datetime('now'))
                    """, arguments: [srcCat, tgtCat])
            }

            // 2. Log to companion_feedback table
            try dbConn.execute(sql: """
                INSERT INTO companion_feedback
                    (suggestion_id, action, suggested_qty, final_qty,
                     source_categories, target_category_id, target_style_id, user_id, created_at)
                VALUES (0, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                """, arguments: [
                    source == "companion" ? "accepted_companion" : "accepted_ai",
                    suggestedQty,
                    acceptedQty,
                    String(srcCat),
                    tgtCat,
                    tgtStyle,
                    userId
                ])
        }
    }

    // =========================================================================
    // MARK: - 8c. Companion Polls & Voting
    // =========================================================================

    /// Row for displaying a poll in the UI.
    public struct CompanionPollDisplayRow: Sendable {
        public let pollId: Int64
        public let proposedRuleName: String
        public let proposedRuleDescription: String?
        public let sourceName: String
        public let targetName: String
        public let matchLevel: String
        public let status: String
        public let startDate: String
        public let endDate: String
        public let daysRemaining: Int
        public let myVote: String?
        public let totalVotes: Int
        public let poweredAcceptCount: Int
        public let poweredRejectCount: Int
        public let isAdminLocked: Bool
        public let adminLockedResult: String?
        public let result: String?
    }

    /// Create a new weekly poll from the highest-scoring qualified pair.
    /// Returns the new poll ID, or nil if no qualifying pairs exist.
    @discardableResult
    public func createWeeklyPoll() throws -> Int64? {
        // Check if a poll was already created this week
        let recentPoll = try db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: """
                SELECT id FROM companion_polls WHERE start_date >= date('now', '-7 days')
                """)
        }
        if recentPoll != nil { return nil }

        // Get qualified pairs
        let pairs = try getQualifiedPairs()
        guard let best = pairs.first else { return nil }

        let pollId = try db.writer.write { dbConn -> Int64 in
            let proposedName = "\(best.catAName) → \(best.catBName)"

            try dbConn.execute(sql: """
                INSERT INTO companion_polls
                (co_occurrence_id, proposed_rule_name, proposed_rule_description,
                 source_category_id, target_category_id,
                 match_level, status, start_date, end_date, created_at)
                VALUES (?, ?, ?, ?, ?, 'category', 'active', date('now'), date('now', '+30 days'), datetime('now'))
                """, arguments: [best.pairId, proposedName,
                                 "Auto-suggested from \(best.points) co-occurrence points across \(best.jobCount) jobs",
                                 best.catAId, best.catBId])
            let pollId = dbConn.lastInsertedRowID

            // Log to auto-discovery
            try dbConn.execute(sql: """
                INSERT INTO companion_auto_discovery_log
                (analysis_date, match_level, data_window_months, pairs_analyzed, new_pairs_found, poll_created_id, created_at)
                VALUES (date('now'), 'category', 48, ?, 1, ?, datetime('now'))
                """, arguments: [pairs.count, pollId])

            // Notify all active users
            let activeUsers = try Int64.fetchAll(dbConn, sql: """
                SELECT id FROM users WHERE is_active = 1
                """)
            for userId in activeUsers {
                try dbConn.execute(sql: """
                    INSERT INTO notifications (user_id, title, body, severity, source, entity_type, entity_id, type, created_at)
                    VALUES (?, 'New Companion Poll', ?, 'info', 'system', 'companion_poll', ?, 'system', datetime('now'))
                    """, arguments: [userId, proposedName, pollId])
            }

            return pollId
        }

        return pollId
    }

    /// Get all currently active polls with the current user's vote status.
    public func getActivePolls(userId: Int64, isAdmin: Bool = false) throws -> [CompanionPollDisplayRow] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT cp.*,
                       cv.vote AS my_vote,
                       (SELECT COUNT(*) FROM companion_votes WHERE poll_id = cp.id) AS total_votes,
                       (SELECT COUNT(*) FROM companion_votes WHERE poll_id = cp.id AND vote = 'accept' AND has_power = 1) AS powered_accept,
                       (SELECT COUNT(*) FROM companion_votes WHERE poll_id = cp.id AND vote = 'reject' AND has_power = 1) AS powered_reject,
                       COALESCE(ca_src.name, '') AS source_cat_name,
                       COALESCE(cs_src.name, '') AS source_style_name,
                       COALESCE(ct_src.name, '') AS source_type_name,
                       COALESCE(ca_tgt.name, '') AS target_cat_name,
                       COALESCE(cs_tgt.name, '') AS target_style_name,
                       COALESCE(ct_tgt.name, '') AS target_type_name
                FROM companion_polls cp
                LEFT JOIN companion_votes cv ON cv.poll_id = cp.id AND cv.user_id = ?
                LEFT JOIN part_categories ca_src ON ca_src.id = cp.source_category_id
                LEFT JOIN part_styles cs_src ON cs_src.id = cp.source_style_id
                LEFT JOIN part_types ct_src ON ct_src.id = cp.source_type_id
                LEFT JOIN part_categories ca_tgt ON ca_tgt.id = cp.target_category_id
                LEFT JOIN part_styles cs_tgt ON cs_tgt.id = cp.target_style_id
                LEFT JOIN part_types ct_tgt ON ct_tgt.id = cp.target_type_id
                WHERE cp.status IN ('active', 'locked')
                ORDER BY cp.start_date DESC
                """, arguments: [userId])

            return rows.map { row in
                let matchLevel: String = row["match_level"]
                let sourceName = buildHierarchyName(
                    category: row["source_cat_name"], style: row["source_style_name"],
                    type: row["source_type_name"], level: matchLevel)
                let targetName = buildHierarchyName(
                    category: row["target_cat_name"], style: row["target_style_name"],
                    type: row["target_type_name"], level: matchLevel)

                let endDateStr: String = row["end_date"]
                // end_date is stored as YYYY-MM-DD format from date()
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let endDate = dateFormatter.date(from: endDateStr) ?? Date()
                let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0

                return CompanionPollDisplayRow(
                    pollId: row["id"],
                    proposedRuleName: row["proposed_rule_name"],
                    proposedRuleDescription: row["proposed_rule_description"],
                    sourceName: sourceName,
                    targetName: targetName,
                    matchLevel: matchLevel,
                    status: row["status"],
                    startDate: row["start_date"],
                    endDate: endDateStr,
                    daysRemaining: max(0, daysLeft),
                    myVote: row["my_vote"],
                    totalVotes: row["total_votes"],
                    poweredAcceptCount: isAdmin ? (row["powered_accept"] ?? 0) : 0,
                    poweredRejectCount: isAdmin ? (row["powered_reject"] ?? 0) : 0,
                    isAdminLocked: (row["admin_locked_result"] as String?) != nil,
                    adminLockedResult: isAdmin ? row["admin_locked_result"] : nil,
                    result: row["result"]
                )
            }
        }
    }

    /// Helper: build a display name like "Category > Style > Type" based on match level.
    private func buildHierarchyName(category: String?, style: String?, type: String?, level: String) -> String {
        switch level {
        case "type":
            return [category, style, type].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " > ")
        case "style":
            return [category, style].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " > ")
        default:
            return category ?? "Unknown"
        }
    }

    /// Cast or update a vote on a poll. Checks companion_vote_power permission and caches it.
    public func castVote(pollId: Int64, userId: Int64, vote: String) throws {
        try db.writer.write { dbConn in
            guard let poll = try Row.fetchOne(dbConn, sql: "SELECT status FROM companion_polls WHERE id = ?", arguments: [pollId]),
                  (poll["status"] as String) == "active" || (poll["status"] as String) == "locked" else {
                return
            }

            let hasPower = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM user_hats uh
                JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
                WHERE uh.user_id = ? AND uh.is_active = 1 AND hp.permission_key = 'companion_vote_power'
                """, arguments: [userId]) ?? 0

            try dbConn.execute(sql: """
                INSERT INTO companion_votes (poll_id, user_id, vote, has_power, voted_at, updated_at)
                VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
                ON CONFLICT(poll_id, user_id)
                DO UPDATE SET vote = excluded.vote, updated_at = datetime('now')
                """, arguments: [pollId, userId, vote, hasPower > 0 ? 1 : 0])
        }
    }

    /// Close an active poll and determine the result.
    public func closePoll(pollId: Int64) throws {
        try db.writer.write { dbConn in
            guard let poll = try Row.fetchOne(dbConn, sql: "SELECT * FROM companion_polls WHERE id = ?", arguments: [pollId]),
                  (poll["status"] as String) == "active" || (poll["status"] as String) == "locked" else {
                return
            }

            let coOccurrenceId: Int64 = poll["co_occurrence_id"]
            let adminLockedResult: String? = poll["admin_locked_result"]

            let poweredAccept = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM companion_votes
                WHERE poll_id = ? AND vote = 'accept' AND has_power = 1
                """, arguments: [pollId]) ?? 0

            let poweredReject = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM companion_votes
                WHERE poll_id = ? AND vote = 'reject' AND has_power = 1
                """, arguments: [pollId]) ?? 0

            let allAccept = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM companion_votes WHERE poll_id = ? AND vote = 'accept'
                """, arguments: [pollId]) ?? 0
            let allReject = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM companion_votes WHERE poll_id = ? AND vote = 'reject'
                """, arguments: [pollId]) ?? 0
            let totalVotes = allAccept + allReject

            let result: String
            let passed: Bool
            let wasLocked = adminLockedResult != nil

            if let locked = adminLockedResult {
                result = locked == "accept" ? "accepted" : "rejected"
                passed = locked == "accept"
            } else if poweredAccept > poweredReject {
                result = "accepted"
                passed = true
            } else if poweredReject > poweredAccept {
                result = "rejected"
                passed = false
            } else {
                result = "tied"
                passed = false
                let cooldownDate = Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date().addingTimeInterval(60 * 86400)
                let cooldownStr = ISO8601DateFormatter().string(from: cooldownDate)
                try dbConn.execute(sql: """
                    UPDATE co_occurrence_pairs SET tied_cooldown_until = ? WHERE id = ?
                    """, arguments: [cooldownStr, coOccurrenceId])
            }

            try dbConn.execute(sql: """
                UPDATE companion_polls SET status = 'closed', result = ?, completed_at = datetime('now')
                WHERE id = ?
                """, arguments: [result, pollId])

            try dbConn.execute(sql: """
                INSERT INTO companion_poll_results
                (poll_id, passed, total_votes, powered_accept, powered_reject,
                 all_accept, all_reject, was_admin_locked, finalized_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                """, arguments: [pollId, passed ? 1 : 0, totalVotes,
                                 poweredAccept, poweredReject, allAccept, allReject,
                                 wasLocked ? 1 : 0])

            if passed && result != "tied" {
                let matchLevel: String = poll["match_level"]
                let sourceCatId: Int64? = poll["source_category_id"]
                let sourceStyleId: Int64? = poll["source_style_id"]
                let sourceTypeId: Int64? = poll["source_type_id"]
                let targetCatId: Int64? = poll["target_category_id"]
                let targetStyleId: Int64? = poll["target_style_id"]
                let targetTypeId: Int64? = poll["target_type_id"]
                let ruleName: String = poll["proposed_rule_name"]

                try dbConn.execute(sql: """
                    INSERT INTO companion_rules
                    (name, description, style_match, qty_mode, qty_ratio, try_match_brand, auto_color_match,
                     is_active, created_at, updated_at)
                    VALUES (?, 'Auto-created from poll', ?, 'sum', 1.0, ?, ?, 1, datetime('now'), datetime('now'))
                    """, arguments: [ruleName, matchLevel,
                                     poll["try_match_brand"] as Int,
                                     poll["auto_color_match"] as Int])
                let ruleId = dbConn.lastInsertedRowID

                if let catId = sourceCatId {
                    try dbConn.execute(sql: """
                        INSERT INTO companion_rule_sources (rule_id, category_id, style_id, type_id)
                        VALUES (?, ?, ?, ?)
                        """, arguments: [ruleId, catId, sourceStyleId, sourceTypeId])
                }

                if let catId = targetCatId {
                    try dbConn.execute(sql: """
                        INSERT INTO companion_rule_targets (rule_id, category_id, style_id, type_id)
                        VALUES (?, ?, ?, ?)
                        """, arguments: [ruleId, catId, targetStyleId, targetTypeId])
                }

                try dbConn.execute(sql: """
                    UPDATE companion_polls SET created_rule_id = ? WHERE id = ?
                    """, arguments: [ruleId, pollId])
            } else if result == "rejected" {
                try dbConn.execute(sql: """
                    UPDATE co_occurrence_pairs
                    SET points = MAX(0, points - 100),
                        rejection_count = rejection_count + 1,
                        is_blocked = CASE WHEN rejection_count + 1 >= 5 THEN 1 ELSE 0 END,
                        last_computed = datetime('now')
                    WHERE id = ?
                    """, arguments: [coOccurrenceId])
            }
        }
    }

    /// Admin "I know the answer" — lock the poll result.
    public func adminLockPoll(pollId: Int64, result: String, lockedBy: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE companion_polls
                SET status = 'locked', admin_locked_result = ?, admin_locked_by = ?,
                    admin_locked_at = datetime('now')
                WHERE id = ? AND status = 'active'
                """, arguments: [result, lockedBy, pollId])
        }
    }

    /// Admin skip — close the current poll and replace with the next-best suggestion.
    @discardableResult
    public func adminSkipPoll(pollId: Int64) throws -> Int64? {
        try db.writer.write { dbConn in
            guard let poll = try Row.fetchOne(dbConn, sql: "SELECT co_occurrence_id FROM companion_polls WHERE id = ?", arguments: [pollId]) else { return }
            let coOccurrenceId: Int64 = poll["co_occurrence_id"]

            try dbConn.execute(sql: """
                UPDATE companion_polls SET status = 'skipped', result = 'skipped', completed_at = datetime('now')
                WHERE id = ?
                """, arguments: [pollId])

            try dbConn.execute(sql: """
                UPDATE co_occurrence_pairs SET points = MAX(0, points - 50), last_computed = datetime('now')
                WHERE id = ?
                """, arguments: [coOccurrenceId])
        }

        return try createWeeklyPoll()
    }

    /// Admin preview: get the next-best pair that would become next week's poll.
    public func getNextPollPreview() throws -> (pairId: Int64, catAName: String, catBName: String, points: Int, confidence: Double)? {
        let pairs = try getQualifiedPairs()
        guard let best = pairs.first else { return nil }
        return (pairId: best.pairId, catAName: best.catAName, catBName: best.catBName,
                points: best.points, confidence: best.confidence)
    }

    /// Get last week's poll results for a user.
    public func getLastWeekResults(userId: Int64) throws -> [(pollName: String, passed: Bool, myVote: String?, matchedWinner: Bool)] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT cp.proposed_rule_name, cpr.passed,
                       cv.vote AS my_vote
                FROM companion_polls cp
                JOIN companion_poll_results cpr ON cpr.poll_id = cp.id
                LEFT JOIN companion_votes cv ON cv.poll_id = cp.id AND cv.user_id = ?
                WHERE cp.completed_at >= datetime('now', '-7 days')
                ORDER BY cp.completed_at DESC
                """, arguments: [userId])

            return rows.map { row in
                let passed = (row["passed"] as Int) == 1
                let myVote: String? = row["my_vote"]
                let matchedWinner: Bool
                if let vote = myVote {
                    matchedWinner = (vote == "accept" && passed) || (vote == "reject" && !passed)
                } else {
                    matchedWinner = false
                }
                return (pollName: row["proposed_rule_name"] as String,
                        passed: passed, myVote: myVote, matchedWinner: matchedWinner)
            }
        }
    }

    /// Get a user's voting accuracy (% of times they voted with the winning side).
    public func getUserVotingAccuracy(userId: Int64) throws -> (totalVotes: Int, correctVotes: Int, accuracy: Double) {
        try db.writer.read { dbConn in
            let row = try Row.fetchOne(dbConn, sql: """
                SELECT COUNT(*) AS total,
                       SUM(CASE
                           WHEN (cv.vote = 'accept' AND cpr.passed = 1)
                             OR (cv.vote = 'reject' AND cpr.passed = 0) THEN 1
                           ELSE 0
                       END) AS correct
                FROM companion_votes cv
                JOIN companion_poll_results cpr ON cpr.poll_id = cv.poll_id
                WHERE cv.user_id = ?
                """, arguments: [userId])

            let total = (row?["total"] as Int?) ?? 0
            let correct = (row?["correct"] as Int?) ?? 0
            let accuracy = total > 0 ? Double(correct) / Double(total) : 0.0
            return (totalVotes: total, correctVotes: correct, accuracy: accuracy)
        }
    }

    /// When no qualifying poll exists this week, generate a training question.
    public func getTrainingQuestion() throws -> (sourceName: String, targetName: String, points: Int, isTraining: Bool)? {
        try db.writer.read { dbConn in
            let row = try Row.fetchOne(dbConn, sql: """
                SELECT cop.points,
                       ca.name AS cat_a_name, cb.name AS cat_b_name
                FROM co_occurrence_pairs cop
                JOIN part_categories ca ON ca.id = cop.category_a_id
                JOIN part_categories cb ON cb.id = cop.category_b_id
                WHERE cop.match_level = 'category'
                  AND cop.is_blocked = 0
                  AND cop.points > 0 AND cop.points < 100
                ORDER BY cop.points DESC
                LIMIT 1
                """)

            guard let row = row else { return nil }
            return (sourceName: row["cat_a_name"] as String,
                    targetName: row["cat_b_name"] as String,
                    points: row["points"] as Int,
                    isTraining: true)
        }
    }

    /// Get active polls that have been running for 7+ days, formatted for clock-out questions.
    public func getActivePollsForClockOut(userId: Int64) throws -> [(pollId: Int64, questionText: String, hasVoted: Bool)] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT cp.id, cp.proposed_rule_name,
                       (cv.id IS NOT NULL) AS has_voted
                FROM companion_polls cp
                LEFT JOIN companion_votes cv ON cv.poll_id = cp.id AND cv.user_id = ?
                WHERE cp.status IN ('active', 'locked')
                  AND cp.start_date <= date('now', '-7 days')
                  AND cp.end_date >= date('now')
                ORDER BY cp.start_date ASC
                """, arguments: [userId])

            return rows.map { row in
                let name: String = row["proposed_rule_name"]
                return (pollId: row["id"] as Int64,
                        questionText: "Should \(name) be a companion rule?",
                        hasVoted: (row["has_voted"] as Int) == 1)
            }
        }
    }

    /// Check and close any expired polls (past end_date).
    public func closeExpiredPolls() throws {
        let expiredIds = try db.writer.read { dbConn in
            try Int64.fetchAll(dbConn, sql: """
                SELECT id FROM companion_polls
                WHERE status IN ('active', 'locked') AND end_date < date('now')
                """)
        }
        for pollId in expiredIds {
            try closePoll(pollId: pollId)
        }
    }

    // =========================================================================
    // MARK: - 10. Import / Export
    // =========================================================================

    /// Summary statistics for the import/export page.
    public struct ImportExportStats: Sendable {
        public let totalParts: Int
        public let totalCategories: Int
        public let totalBrands: Int
        public let totalSuppliers: Int
    }

    /// Get summary stats for the import/export page.
    public func getImportExportStats() throws -> ImportExportStats {
        try db.writer.read { dbConn in
            let parts = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL") ?? 0
            let cats = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM part_categories WHERE deleted_at IS NULL") ?? 0
            let brands = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM brands WHERE deleted_at IS NULL") ?? 0
            let suppliers = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM suppliers WHERE deleted_at IS NULL") ?? 0
            return ImportExportStats(totalParts: parts, totalCategories: cats, totalBrands: brands, totalSuppliers: suppliers)
        }
    }

    /// Export field groups for selective CSV export.
    public enum ExportFieldGroup: String, CaseIterable, Sendable {
        case hierarchy, pricing, stockLevels, forecast, details
    }

    /// Export parts to CSV string with selected field groups.
    /// Basic fields (name, code) are always included.
    public func exportPartsCSV(groups: Set<ExportFieldGroup>) throws -> String {
        try db.writer.read { dbConn in
            var columns = ["p.name", "p.code"]
            var headers = ["name", "code"]

            if groups.contains(.hierarchy) {
                columns += ["pc.name AS category", "ps.name AS style", "pt.name AS part_type_name", "b.name AS brand", "pco.name AS color"]
                headers += ["category", "style", "type", "brand", "color"]
            }
            if groups.contains(.pricing) {
                columns += ["p.company_cost_price AS cost_price", "p.company_markup_percent AS markup_percent",
                             "ROUND(p.company_cost_price * (1.0 + p.company_markup_percent / 100.0), 2) AS sell_price"]
                headers += ["cost_price", "markup_percent", "sell_price"]
            }
            if groups.contains(.stockLevels) {
                columns += ["p.min_stock_level AS min_stock", "p.target_stock_level AS target_stock", "p.max_stock_level AS max_stock",
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
                    let dbValue: DatabaseValue = row[colName]
                    switch dbValue.storage {
                    case .null:
                        values.append("")
                    case .int64(let v):
                        values.append(String(v))
                    case .double(let v):
                        values.append(String(v))
                    case .string(let v):
                        values.append(csvEscape(v))
                    case .blob:
                        values.append("")
                    }
                }
                csv += values.joined(separator: ",") + "\n"
            }
            return csv
        }
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

    // =========================================================================
    // MARK: - 11. Smart Delete
    // =========================================================================

    /// Result of checking inventory before deletion.
    public struct InventoryCheck: Sendable {
        public let totalStock: Int
        public let partsWithStock: [(partId: Int64, partName: String, stock: Int)]
        public let alternativeParts: [(partId: Int64, partName: String, alternativeId: Int64, alternativeName: String)]
        public var hasInventory: Bool { totalStock > 0 }
    }

    /// A scheduled deletion record for the approval workflow.
    public struct ScheduledDeletion: Identifiable, Sendable {
        public let id: Int64
        public let entityType: String
        public let entityId: Int64
        public let entityName: String
        public let reason: String?
        public let status: String
        public let stockAtSchedule: Int
        public let deleteAfter: String?
        public let alternativePartId: Int64?
        public let alternativePartName: String?
        public let createdAt: String
    }

    /// Check total stock for all parts under a hierarchy node.
    public func checkInventoryForDeletion(entityType: String, entityId: Int64) throws -> InventoryCheck {
        try db.writer.read { db in
            let whereClause: String
            switch entityType {
            case "category": whereClause = "p.category_id = ?"
            case "style": whereClause = "p.style_id = ?"
            case "type": whereClause = "p.type_id = ?"
            case "brand": whereClause = "p.brand_id = ?"
            case "color": whereClause = "p.color_id = ?"
            case "part": whereClause = "p.id = ?"
            default: whereClause = "1=0"
            }

            // Sum stock from both stock tables (stock.qty + stock_entries.quantity)
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.id, p.name,
                       COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0)
                       + COALESCE((SELECT SUM(se.quantity) FROM stock_entries se WHERE se.part_id = p.id AND se.deleted_at IS NULL), 0)
                       AS total_stock
                FROM parts p
                WHERE \(whereClause) AND p.deleted_at IS NULL
                HAVING total_stock > 0
            """, arguments: [entityId])

            let partsWithStock = rows.map { row -> (partId: Int64, partName: String, stock: Int) in
                (row["id"], row["name"], row["total_stock"])
            }
            let totalStock = partsWithStock.reduce(0) { $0 + $1.stock }

            // Get alternative parts
            var alternatives: [(partId: Int64, partName: String, alternativeId: Int64, alternativeName: String)] = []
            for part in partsWithStock {
                let altRows = try Row.fetchAll(db, sql: """
                    SELECT pa.alternative_part_id, ap.name AS alt_name
                    FROM part_alternatives pa
                    JOIN parts ap ON ap.id = pa.alternative_part_id
                    WHERE pa.part_id = ? AND ap.deleted_at IS NULL
                    ORDER BY pa.preference ASC
                    LIMIT 1
                """, arguments: [part.partId])
                for altRow in altRows {
                    alternatives.append((
                        partId: part.partId,
                        partName: part.partName,
                        alternativeId: altRow["alternative_part_id"],
                        alternativeName: altRow["alt_name"]
                    ))
                }
            }

            return InventoryCheck(totalStock: totalStock, partsWithStock: partsWithStock, alternativeParts: alternatives)
        }
    }

    /// Put an entity into "Empty Shelf Mode" — sets stock targets to 0 and starts monitoring.
    @discardableResult
    public func scheduleEmptyShelfDeletion(entityType: String, entityId: Int64, entityName: String, reason: String?, scheduledBy: Int64?) throws -> Int64 {
        try db.writer.write { db in
            let updateClause: String
            switch entityType {
            case "category": updateClause = "category_id = ?"
            case "style": updateClause = "style_id = ?"
            case "type": updateClause = "type_id = ?"
            case "brand": updateClause = "brand_id = ?"
            case "color": updateClause = "color_id = ?"
            case "part": updateClause = "id = ?"
            default: updateClause = "1=0"
            }

            // Zero out stock targets, mark deprecated
            try db.execute(sql: """
                UPDATE parts SET
                    min_stock_level = 0, max_stock_level = 0,
                    target_stock_level = 0, reorder_point = 0,
                    is_deprecated = 1, deprecation_reason = 'Empty Shelf Mode — pending deletion',
                    updated_at = datetime('now')
                WHERE \(updateClause) AND deleted_at IS NULL
            """, arguments: [entityId])

            // Check current stock level across both stock tables
            let columnName = updateClause.components(separatedBy: " =").first ?? "id"
            let currentStock = try Int.fetchOne(db, sql: """
                SELECT COALESCE(
                    (SELECT SUM(s.qty) FROM stock s JOIN parts p ON p.id = s.part_id
                     WHERE p.\(columnName) = ? AND p.deleted_at IS NULL AND s.deleted_at IS NULL), 0)
                + COALESCE(
                    (SELECT SUM(se.quantity) FROM stock_entries se JOIN parts p ON p.id = se.part_id
                     WHERE p.\(columnName) = ? AND p.deleted_at IS NULL AND se.deleted_at IS NULL), 0)
            """, arguments: [entityId, entityId]) ?? 0

            // Find best alternative part
            let altRow = try Row.fetchOne(db, sql: """
                SELECT pa.alternative_part_id, ap.name FROM part_alternatives pa
                JOIN parts ap ON ap.id = pa.alternative_part_id
                JOIN parts p ON p.id = pa.part_id
                WHERE p.\(columnName) = ? AND ap.deleted_at IS NULL
                ORDER BY pa.preference ASC LIMIT 1
            """, arguments: [entityId])

            // Create scheduled deletion record
            let now = ISO8601DateFormatter().string(from: Date())
            let stockZeroAt: String? = currentStock == 0 ? now : nil
            let deleteAfter: String? = currentStock == 0
                ? ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date().addingTimeInterval(30 * 86400))
                : nil

            try db.execute(sql: """
                INSERT INTO scheduled_deletions
                (entity_type, entity_id, entity_name, reason, status, stock_at_schedule,
                 stock_reached_zero_at, delete_after, alternative_part_id, alternative_part_name,
                 scheduled_by, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                entityType, entityId, entityName, reason,
                currentStock == 0 ? "pending_approval" : "draining",
                currentStock, stockZeroAt, deleteAfter,
                altRow?["alternative_part_id"] as Int64?, altRow?["name"] as String?,
                scheduledBy, now, now
            ])

            return db.lastInsertedRowID
        }
    }

    /// List scheduled deletions, optionally filtered by status.
    public func listScheduledDeletions(status: String? = nil) throws -> [ScheduledDeletion] {
        try db.writer.read { db in
            var sql = "SELECT * FROM scheduled_deletions WHERE deleted_at IS NULL"
            var args: [DatabaseValueConvertible] = []
            if let status {
                sql += " AND status = ?"
                args.append(status)
            }
            sql += " ORDER BY created_at DESC"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map { row in
                ScheduledDeletion(
                    id: row["id"], entityType: row["entity_type"], entityId: row["entity_id"],
                    entityName: row["entity_name"], reason: row["reason"], status: row["status"],
                    stockAtSchedule: row["stock_at_schedule"], deleteAfter: row["delete_after"],
                    alternativePartId: row["alternative_part_id"], alternativePartName: row["alternative_part_name"],
                    createdAt: row["created_at"]
                )
            }
        }
    }

    /// Approve a scheduled deletion — performs the actual soft delete.
    public func approveScheduledDeletion(id: Int64, approvedBy: Int64?) throws {
        try db.writer.write { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM scheduled_deletions WHERE id = ?", arguments: [id])
            guard let row else { return }
            let entityType: String = row["entity_type"]
            let entityId: Int64 = row["entity_id"]
            let now = ISO8601DateFormatter().string(from: Date())

            // Perform the actual soft delete based on entity type
            let table: String
            switch entityType {
            case "category": table = "part_categories"
            case "style": table = "part_styles"
            case "type": table = "part_types"
            case "brand": table = "brands"
            case "color": table = "part_colors"
            case "part": table = "parts"
            default: return
            }
            try db.execute(sql: "UPDATE \(table) SET deleted_at = ? WHERE id = ?", arguments: [now, entityId])

            // Mark schedule as approved
            try db.execute(sql: """
                UPDATE scheduled_deletions SET status = 'approved', approved_by = ?, approved_at = ?, updated_at = ?
                WHERE id = ?
            """, arguments: [approvedBy, now, now, id])
        }
    }

    /// Cancel a scheduled deletion — restores parts from deprecation.
    public func cancelScheduledDeletion(id: Int64) throws {
        try db.writer.write { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM scheduled_deletions WHERE id = ?", arguments: [id])
            guard let row else { return }
            let entityType: String = row["entity_type"]
            let entityId: Int64 = row["entity_id"]
            let now = ISO8601DateFormatter().string(from: Date())

            // Restore parts — remove deprecation flag
            let whereClause: String
            switch entityType {
            case "category": whereClause = "category_id = ?"
            case "style": whereClause = "style_id = ?"
            case "type": whereClause = "type_id = ?"
            case "brand": whereClause = "brand_id = ?"
            case "color": whereClause = "color_id = ?"
            case "part": whereClause = "id = ?"
            default: whereClause = "1=0"
            }
            try db.execute(sql: """
                UPDATE parts SET is_deprecated = 0, deprecation_reason = NULL, updated_at = ?
                WHERE \(whereClause) AND deleted_at IS NULL
            """, arguments: [now, entityId])

            // Cancel the schedule
            try db.execute(sql: """
                UPDATE scheduled_deletions SET status = 'cancelled', deleted_at = ?, updated_at = ?
                WHERE id = ?
            """, arguments: [now, now, id])
        }
    }

    // =========================================================================
    // MARK: - 12. Supplier Performance Scores
    // =========================================================================

    /// Calculated performance scores for a supplier.
    public struct SupplierScores: Sendable {
        public let qualityScore: Double       // 0-100, based on return rate
        public let onTimeRate: Double          // 0-100, based on delivery timeliness
        public let reliabilityScore: Double    // 0-100, weighted average
        public let totalOrderCount: Int        // total POs to this supplier
        public let totalUnitsReceived: Int     // total units received
        public let totalUnitsReturned: Int     // total units returned to supplier
        public let avgDeliveryDays: Double?    // average days from PO creation to receiving
    }

    /// Calculate performance scores for a supplier based on actual PO/receiving data.
    public func calculateSupplierScores(supplierId: Int64) throws -> SupplierScores {
        try db.writer.read { dbConn in
            // Count total POs and received POs
            let poRow = try Row.fetchOne(dbConn, sql: """
                SELECT
                    COUNT(*) AS total_pos,
                    COUNT(CASE WHEN status IN ('received', 'completed', 'closed') THEN 1 END) AS received_pos
                FROM purchase_orders
                WHERE supplier_id = ? AND deleted_at IS NULL
                """, arguments: [supplierId])
            let totalPOs: Int = poRow?["total_pos"] ?? 0

            // Total units received from this supplier
            let receivedRow = try Row.fetchOne(dbConn, sql: """
                SELECT COALESCE(SUM(qty), 0) AS total_received
                FROM stock_movements
                WHERE supplier_id = ? AND movement_type = 'receipt' AND deleted_at IS NULL
                """, arguments: [supplierId])
            let totalReceived: Int = receivedRow?["total_received"] ?? 0

            // Total units returned TO this supplier
            let returnedRow = try Row.fetchOne(dbConn, sql: """
                SELECT COALESCE(SUM(qty), 0) AS total_returned
                FROM stock_movements
                WHERE supplier_id = ? AND movement_type = 'return' AND deleted_at IS NULL
                AND from_location_type IN ('warehouse', 'staging')
                AND to_location_type = 'supplier'
                """, arguments: [supplierId])
            let totalReturned: Int = returnedRow?["total_returned"] ?? 0

            // Quality score: 100 - (return_rate %)
            let qualityScore: Double
            if totalReceived > 0 {
                let returnRate = (Double(totalReturned) / Double(totalReceived)) * 100
                qualityScore = max(0, min(100, 100 - returnRate))
            } else {
                qualityScore = 0
            }

            // On-time rate: POs with receiving completed within expected delivery window
            let onTimeRow = try Row.fetchOne(dbConn, sql: """
                SELECT
                    COUNT(*) AS total_received_pos,
                    COUNT(CASE
                        WHEN rs.completed_at IS NOT NULL
                        AND julianday(rs.completed_at) - julianday(po.created_at) <= COALESCE(CAST(s.delivery_days AS INTEGER), 14)
                        THEN 1 END) AS on_time_count
                FROM purchase_orders po
                LEFT JOIN receiving_sessions rs ON rs.po_id = po.id AND rs.status = 'complete'
                LEFT JOIN suppliers s ON s.id = po.supplier_id
                WHERE po.supplier_id = ? AND po.deleted_at IS NULL
                AND po.status IN ('received', 'completed', 'closed')
                """, arguments: [supplierId])
            let totalReceivedPOs: Int = onTimeRow?["total_received_pos"] ?? 0
            let onTimeCount: Int = onTimeRow?["on_time_count"] ?? 0

            let onTimeRate: Double
            if totalReceivedPOs > 0 {
                onTimeRate = (Double(onTimeCount) / Double(totalReceivedPOs)) * 100
            } else {
                onTimeRate = 0
            }

            // Average delivery days
            let avgDaysRow = try Row.fetchOne(dbConn, sql: """
                SELECT AVG(julianday(rs.completed_at) - julianday(po.created_at)) AS avg_days
                FROM purchase_orders po
                JOIN receiving_sessions rs ON rs.po_id = po.id AND rs.status = 'complete'
                WHERE po.supplier_id = ? AND po.deleted_at IS NULL
                AND rs.completed_at IS NOT NULL
                """, arguments: [supplierId])
            let avgDays: Double? = avgDaysRow?["avg_days"]

            // Reliability: weighted average (60% on-time, 40% quality)
            let reliabilityScore: Double
            if totalPOs > 0 {
                reliabilityScore = (onTimeRate * 0.6) + (qualityScore * 0.4)
            } else {
                reliabilityScore = 0
            }

            return SupplierScores(
                qualityScore: qualityScore,
                onTimeRate: onTimeRate,
                reliabilityScore: reliabilityScore,
                totalOrderCount: totalPOs,
                totalUnitsReceived: totalReceived,
                totalUnitsReturned: totalReturned,
                avgDeliveryDays: avgDays
            )
        }
    }

    /// Recalculate and persist supplier scores to the suppliers table.
    public func updateSupplierScores(supplierId: Int64) throws {
        let scores = try calculateSupplierScores(supplierId: supplierId)
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE suppliers SET
                    quality_score = ?,
                    on_time_rate = ?,
                    reliability_score = ?,
                    updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [scores.qualityScore, scores.onTimeRate, scores.reliabilityScore, supplierId])
        }
    }

    /// Recalculate scores for ALL suppliers. Use sparingly (e.g., monthly batch).
    public func recalculateAllSupplierScores() throws {
        let suppliers = try db.writer.read { dbConn in
            try Row.fetchAll(dbConn, sql: "SELECT id FROM suppliers WHERE deleted_at IS NULL")
        }
        for row in suppliers {
            let id: Int64 = row["id"]
            try updateSupplierScores(supplierId: id)
        }
    }

    // =========================================================================
    // MARK: - 12b. Supplier Detail Data
    // =========================================================================

    /// Get brands linked to a supplier with carry status.
    public func getSupplierBrands(supplierId: Int64) throws -> [(brandId: Int64, brandName: String, partCount: Int, carryStatus: String)] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT b.id, b.name, COUNT(DISTINCT ps.part_id) AS part_count,
                       COALESCE(bs.carry_status, 'carry_on_shelf') AS carry_status
                FROM brand_supplier_links bs
                JOIN brands b ON b.id = bs.brand_id AND b.deleted_at IS NULL
                LEFT JOIN part_supplier_links ps ON ps.supplier_id = bs.supplier_id AND ps.deleted_at IS NULL
                WHERE bs.supplier_id = ? AND bs.deleted_at IS NULL
                GROUP BY b.id
                ORDER BY b.name ASC
                """, arguments: [supplierId])

            return rows.map { row in
                (brandId: row["id"] as Int64? ?? 0,
                 brandName: row["name"] as String? ?? "",
                 partCount: row["part_count"] as Int? ?? 0,
                 carryStatus: row["carry_status"] as String? ?? "carry_on_shelf")
            }
        }
    }

    /// Get recent POs for a supplier.
    public func getSupplierRecentPOs(supplierId: Int64, limit: Int = 10) throws -> [(poId: Int64, poNumber: String, status: String, total: Double, date: String)] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT id, po_number, status,
                       COALESCE((SELECT SUM(qty * unit_cost) FROM po_line_items WHERE po_id = purchase_orders.id AND deleted_at IS NULL), 0) AS total,
                       created_at
                FROM purchase_orders
                WHERE supplier_id = ? AND deleted_at IS NULL
                ORDER BY created_at DESC
                LIMIT ?
                """, arguments: [supplierId, limit])

            return rows.map { row in
                (poId: row["id"] as Int64? ?? 0,
                 poNumber: row["po_number"] as String? ?? "",
                 status: row["status"] as String? ?? "",
                 total: row["total"] as Double? ?? 0,
                 date: row["created_at"] as String? ?? "")
            }
        }
    }

    /// Count total parts this supplier is linked to.
    public func getSupplierPartCount(supplierId: Int64) throws -> Int {
        try db.writer.read { dbConn in
            let row = try Row.fetchOne(dbConn, sql: """
                SELECT COUNT(*) AS cnt FROM part_supplier_links
                WHERE supplier_id = ? AND deleted_at IS NULL
                """, arguments: [supplierId])
            return row?["cnt"] ?? 0
        }
    }

    // =========================================================================
    // MARK: - 12c. Supplier Contacts
    // =========================================================================

    /// A contact linked to a supplier via entity_contacts.
    public struct SupplierContact: Sendable {
        public let contactId: Int64
        public let firstName: String
        public let lastName: String
        public let role: String?
        public let phone: String?
        public let email: String?
        public let isPrimary: Int
    }

    /// Get all contacts linked to a supplier.
    public func getSupplierContacts(supplierId: Int64) throws -> [SupplierContact] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT id, first_name, last_name, role, phone, email, is_primary
                FROM entity_contacts
                WHERE entity_type = 'supplier' AND entity_id = ? AND deleted_at IS NULL
                ORDER BY is_primary DESC, last_name ASC
                """, arguments: [supplierId])

            return rows.map { row in
                SupplierContact(
                    contactId: row["id"],
                    firstName: row["first_name"] ?? "",
                    lastName: row["last_name"] ?? "",
                    role: row["role"],
                    phone: row["phone"],
                    email: row["email"],
                    isPrimary: row["is_primary"] ?? 0
                )
            }
        }
    }

    /// Quick-add a new contact and link to this supplier.
    public func addSupplierContact(
        supplierId: Int64,
        firstName: String,
        lastName: String,
        role: String?,
        phone: String?,
        email: String?,
        isPrimary: Bool
    ) throws {
        try db.writer.write { dbConn in
            // If setting as primary, clear existing primary
            if isPrimary {
                try dbConn.execute(sql: """
                    UPDATE entity_contacts SET is_primary = 0
                    WHERE entity_type = 'supplier' AND entity_id = ? AND deleted_at IS NULL
                    """, arguments: [supplierId])
            }
            try dbConn.execute(sql: """
                INSERT INTO entity_contacts (entity_type, entity_id, first_name, last_name, role, phone, email, is_primary, created_at)
                VALUES ('supplier', ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                """, arguments: [supplierId, firstName, lastName, role ?? "", phone ?? "", email, isPrimary ? 1 : 0])
        }
    }

    /// Remove a contact link from a supplier (soft delete).
    public func removeSupplierContact(contactId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE entity_contacts SET deleted_at = datetime('now')
                WHERE id = ?
                """, arguments: [contactId])
        }
    }

    // =========================================================================
    // MARK: - 12d. Supplier Costs per Part
    // =========================================================================

    /// Supplier cost data for a single part.
    public struct PartSupplierCost: Sendable {
        public let supplierId: Int64
        public let supplierName: String
        public let supplierCostPrice: Double?
        public let supplierPartNumber: String?
        public let isPreferred: Bool
    }

    /// Get all supplier costs for a specific part.
    public func getPartSupplierCosts(partId: Int64) throws -> [PartSupplierCost] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT ps.supplier_id, s.name AS supplier_name,
                       ps.supplier_cost_price, ps.supplier_part_number, ps.is_preferred
                FROM part_supplier_links ps
                JOIN suppliers s ON s.id = ps.supplier_id AND s.deleted_at IS NULL
                WHERE ps.part_id = ? AND ps.deleted_at IS NULL
                ORDER BY ps.is_preferred DESC, s.name ASC
                """, arguments: [partId])

            return rows.map { row in
                PartSupplierCost(
                    supplierId: row["supplier_id"],
                    supplierName: row["supplier_name"] ?? "",
                    supplierCostPrice: row["supplier_cost_price"],
                    supplierPartNumber: row["supplier_part_number"],
                    isPreferred: (row["is_preferred"] as Int?) == 1
                )
            }
        }
    }

    // =========================================================================
    // MARK: - 12e. Supplier AI Context
    // =========================================================================

    /// Build a context string about suppliers for AI queries.
    public func buildSupplierAIContext() throws -> String {
        try db.writer.read { dbConn in
            var context = "SUPPLIER DATA:\n\n"

            let suppliers = try Row.fetchAll(dbConn, sql: """
                SELECT s.*,
                    (SELECT COUNT(*) FROM part_supplier_links WHERE supplier_id = s.id AND deleted_at IS NULL) AS part_count,
                    (SELECT COUNT(*) FROM brand_supplier_links WHERE supplier_id = s.id AND deleted_at IS NULL) AS brand_count,
                    (SELECT COUNT(*) FROM purchase_orders WHERE supplier_id = s.id AND deleted_at IS NULL) AS po_count
                FROM suppliers s
                WHERE s.deleted_at IS NULL
                ORDER BY s.name ASC
                """)

            context += "Total suppliers: \(suppliers.count)\n"
            let activeCount = suppliers.filter { ($0["is_active"] as Int?) == 1 }.count
            context += "Active: \(activeCount), Inactive: \(suppliers.count - activeCount)\n\n"

            for s in suppliers {
                let name: String = s["name"] ?? ""
                let isActive: Int = s["is_active"] ?? 1
                context += "--- \(name) \(isActive == 1 ? "" : "[INACTIVE]") ---\n"

                if let acct: String = s["account_number"], !acct.isEmpty {
                    context += "  Account #: \(acct)\n"
                }
                if let contact: String = s["contact_name"], !contact.isEmpty {
                    context += "  Contact: \(contact)\n"
                }
                if let phone: String = s["phone"], !phone.isEmpty {
                    context += "  Phone: \(phone)\n"
                }
                if let email: String = s["email"], !email.isEmpty {
                    context += "  Email: \(email)\n"
                }
                if let method: String = s["delivery_method"], !method.isEmpty {
                    context += "  Delivery: \(method)\n"
                }
                if let days: String = s["delivery_days"], !days.isEmpty {
                    context += "  Delivery Days: \(days)\n"
                }

                let quality: Double? = s["quality_score"]
                let onTime: Double? = s["on_time_rate"]
                let reliability: Double? = s["reliability_score"]
                if let q = quality { context += "  Quality Score: \(String(format: "%.0f%%", q))\n" }
                if let o = onTime { context += "  On-Time Rate: \(String(format: "%.0f%%", o))\n" }
                if let r = reliability { context += "  Reliability: \(String(format: "%.0f%%", r))\n" }

                let partCount: Int = s["part_count"] ?? 0
                let brandCount: Int = s["brand_count"] ?? 0
                let poCount: Int = s["po_count"] ?? 0
                context += "  Parts: \(partCount), Brands: \(brandCount), POs: \(poCount)\n"

                if let rep: String = s["rep_name"], !rep.isEmpty {
                    context += "  Sales Rep: \(rep)\n"
                }
                if let notes: String = s["notes"], !notes.isEmpty {
                    context += "  Notes: \(notes)\n"
                }
                context += "\n"
            }

            return context
        }
    }

    // =========================================================================
    // MARK: - 13. Part Traceability
    // =========================================================================

    /// A single step in a part's journey from supplier to job.
    public struct TraceStep: Sendable {
        public let movementId: Int64
        public let date: String
        public let movementType: String     // "receipt", "transfer", "consumption", "return"
        public let fromLocation: String     // e.g. "Supplier: ABC Supply"
        public let toLocation: String       // e.g. "Warehouse: Main"
        public let qty: Int
        public let unitCost: Double?
        public let performedByName: String?
        public let referenceNumber: String? // PO#, etc.
        public let notes: String?
    }

    /// Trace all movements for a specific part, ordered chronologically.
    /// Shows the full journey: Supplier → Warehouse → Staging → Truck → Job
    public func tracePartMovements(partId: Int64) throws -> [TraceStep] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT sm.*, u.display_name AS performer_name
                FROM stock_movements sm
                LEFT JOIN users u ON u.id = sm.performed_by
                WHERE sm.part_id = ? AND sm.deleted_at IS NULL
                ORDER BY sm.created_at ASC
                """, arguments: [partId])

            return rows.map { row in
                let fromType: String? = row["from_location_type"]
                let toType: String? = row["to_location_type"]

                return TraceStep(
                    movementId: row["id"],
                    date: row["created_at"] ?? "",
                    movementType: row["movement_type"] ?? "transfer",
                    fromLocation: describeLocation(type: fromType),
                    toLocation: describeLocation(type: toType),
                    qty: row["qty"],
                    unitCost: row["unit_cost_at_move"],
                    performedByName: row["performer_name"],
                    referenceNumber: row["reference_number"],
                    notes: row["notes"]
                )
            }
        }
    }

    /// Trace movements for a part filtered by supplier — shows everything from a specific supplier.
    public func tracePartFromSupplier(partId: Int64, supplierId: Int64) throws -> [TraceStep] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT sm.*, u.display_name AS performer_name
                FROM stock_movements sm
                LEFT JOIN users u ON u.id = sm.performed_by
                WHERE sm.part_id = ? AND sm.supplier_id = ? AND sm.deleted_at IS NULL
                ORDER BY sm.created_at ASC
                """, arguments: [partId, supplierId])

            return rows.map { row in
                let fromType: String? = row["from_location_type"]
                let toType: String? = row["to_location_type"]

                return TraceStep(
                    movementId: row["id"],
                    date: row["created_at"] ?? "",
                    movementType: row["movement_type"] ?? "transfer",
                    fromLocation: describeLocation(type: fromType),
                    toLocation: describeLocation(type: toType),
                    qty: row["qty"],
                    unitCost: row["unit_cost_at_move"],
                    performedByName: row["performer_name"],
                    referenceNumber: row["reference_number"],
                    notes: row["notes"]
                )
            }
        }
    }

    /// Get the current location of a part's stock — where is it right now?
    public func getPartCurrentLocations(partId: Int64) throws -> [(locationType: String, locationId: Int64, qty: Int)] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT location_type, location_id, qty
                FROM stock
                WHERE part_id = ? AND qty > 0 AND deleted_at IS NULL
                ORDER BY qty DESC
                """, arguments: [partId])

            return rows.map { row in
                (locationType: row["location_type"] ?? "unknown",
                 locationId: row["location_id"] ?? 0,
                 qty: row["qty"] ?? 0)
            }
        }
    }

    /// Describe a location type as a human-readable string
    private func describeLocation(type: String?) -> String {
        guard let type = type else { return "Unknown" }
        switch type.lowercased() {
        case "supplier": return "Supplier"
        case "warehouse": return "Warehouse"
        case "staging": return "Staging Area"
        case "job": return "Job Site"
        case "truck", "vehicle": return "Truck"
        default: return type.capitalized
        }
    }

    // =========================================================================
    // MARK: - 14. Part Audit Trail
    // =========================================================================

    /// A single entry in the part change log.
    public struct PartChangeEntry: Identifiable, Sendable {
        public let id: Int64
        public let partId: Int64
        public let userId: Int64?
        public let userName: String?
        public let action: String
        public let fieldName: String?
        public let oldValue: String?
        public let newValue: String?
        public let context: String?
        public let createdAt: String?
    }

    /// Log a single change to a part for the audit trail.
    public func logPartChange(
        partId: Int64,
        userId: Int64?,
        userName: String?,
        action: String,
        fieldName: String? = nil,
        oldValue: String? = nil,
        newValue: String? = nil,
        context: String? = nil
    ) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO part_change_log
                    (part_id, user_id, user_name, action, field_name, old_value, new_value, context)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [partId, userId, userName, action, fieldName, oldValue, newValue, context]
            )
        }
    }

    /// Log multiple field changes for a single part update.
    public func logPartFieldChanges(
        partId: Int64,
        userId: Int64?,
        userName: String?,
        changes: [(field: String, oldValue: String?, newValue: String?)],
        context: String? = nil
    ) throws {
        guard !changes.isEmpty else { return }
        try db.writer.write { dbConn in
            for change in changes {
                try dbConn.execute(
                    sql: """
                        INSERT INTO part_change_log
                        (part_id, user_id, user_name, action, field_name, old_value, new_value, context)
                        VALUES (?, ?, ?, 'updated', ?, ?, ?, ?)
                        """,
                    arguments: [partId, userId, userName, change.field, change.oldValue, change.newValue, context]
                )
            }
        }
    }

    /// Get the change history for a part, most recent first.
    public func getPartChangeLog(partId: Int64, limit: Int = 50) throws -> [PartChangeEntry] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT * FROM part_change_log
                    WHERE part_id = ?
                    ORDER BY created_at DESC
                    LIMIT ?
                    """, arguments: [partId, limit])
                return rows.map { row in
                    PartChangeEntry(
                        id: row["id"],
                        partId: row["part_id"],
                        userId: row["user_id"],
                        userName: row["user_name"],
                        action: row["action"],
                        fieldName: row["field_name"],
                        oldValue: row["old_value"],
                        newValue: row["new_value"],
                        context: row["context"],
                        createdAt: row["created_at"]
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Admin Dashboard Queries
    // =========================================================================

    /// A user row for the admin voting dashboard, including vote-power status.
    public struct AdminUserRow: Sendable {
        public let id: Int64
        public let displayName: String
        public let hasPower: Bool
    }

    /// A finalized poll row for the admin dashboard history section.
    public struct AdminPollHistoryRow: Sendable {
        public let id: Int64
        public let name: String
        public let result: String
        public let totalVotes: Int
        public let poweredAccept: Int
        public let poweredReject: Int
        public let wasLocked: Bool
        public let finalizedAt: String
    }

    /// Rule stats: manual (hand-created) vs auto-discovered (from polls).
    public struct CompanionRuleStats: Sendable {
        public let manual: Int
        public let autoDiscovered: Int
    }

    /// Get all active users with their companion-vote-power status.
    public func getActiveUsersWithVotePower() throws -> [AdminUserRow] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT u.id, u.display_name,
                           EXISTS(SELECT 1 FROM user_hats uh
                                  JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
                                  WHERE uh.user_id = u.id AND uh.is_active = 1
                                  AND hp.permission_key = 'companion_vote_power') AS has_power
                    FROM users u WHERE u.is_active = 1 AND u.deleted_at IS NULL
                    ORDER BY u.display_name ASC
                    """)
                return rows.map { row in
                    AdminUserRow(
                        id: row["id"],
                        displayName: row["display_name"] ?? "Unknown",
                        hasPower: (row["has_power"] as Int?) == 1
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get finalized poll history for the admin dashboard.
    public func getPollHistory(limit: Int = 20) throws -> [AdminPollHistoryRow] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT cp.id, cp.proposed_rule_name, cp.result,
                           cpr.total_votes, cpr.powered_accept, cpr.powered_reject,
                           cpr.was_admin_locked, cpr.finalized_at
                    FROM companion_polls cp
                    JOIN companion_poll_results cpr ON cpr.poll_id = cp.id
                    ORDER BY cpr.finalized_at DESC
                    LIMIT ?
                    """, arguments: [limit])
                return rows.map { row in
                    AdminPollHistoryRow(
                        id: row["id"] ?? 0,
                        name: row["proposed_rule_name"] ?? "Unknown",
                        result: row["result"] ?? "unknown",
                        totalVotes: row["total_votes"] ?? 0,
                        poweredAccept: row["powered_accept"] ?? 0,
                        poweredReject: row["powered_reject"] ?? 0,
                        wasLocked: (row["was_admin_locked"] as Int?) == 1,
                        finalizedAt: row["finalized_at"] ?? ""
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get manual vs auto-discovered companion rule counts.
    public func getCompanionRuleStats() throws -> CompanionRuleStats {
        do {
            return try db.writer.read { dbConn in
                let manualCount = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM companion_rules
                    WHERE deleted_at IS NULL AND id NOT IN (
                        SELECT COALESCE(created_rule_id, 0) FROM companion_polls WHERE created_rule_id IS NOT NULL
                    )
                    """) ?? 0
                let autoCount = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM companion_polls WHERE created_rule_id IS NOT NULL
                    """) ?? 0
                return CompanionRuleStats(manual: manualCount, autoDiscovered: autoCount)
            }
        } catch {
            if isTableNotFoundError(error) { return CompanionRuleStats(manual: 0, autoDiscovered: 0) }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Sandbox / Co-occurrence Queries
    // =========================================================================

    /// A job row where multiple selected categories co-occurred.
    public struct SandboxJobRow: Sendable {
        public let jobId: Int64
        public let jobName: String
        public let jobNumber: String
    }

    /// A part row used in a job (for sandbox examples).
    public struct SandboxJobPartRow: Sendable {
        public let name: String
        public let categoryName: String
        public let qty: Int
    }

    /// A deeper-level co-occurrence pair for sandbox "next level" preview.
    public struct SandboxNextLevelRow: Sendable {
        public let catAName: String
        public let catBName: String
        public let matchLevel: String
        public let points: Int
        public let confidence: Double
    }

    /// Find jobs where at least 2 of the given categories co-occurred on ordered parts.
    public func getJobsWithCategoryCoOccurrence(categoryIds: [Int64], limit: Int = 3) throws -> [SandboxJobRow] {
        guard !categoryIds.isEmpty else { return [] }
        do {
            return try db.writer.read { dbConn in
                let placeholders = categoryIds.map { _ in "?" }.joined(separator: ", ")
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT DISTINCT j.id, j.job_name, j.job_number
                    FROM jobs j
                    JOIN job_parts jp ON jp.job_id = j.id
                    JOIN parts p ON p.id = jp.part_id
                    WHERE p.category_id IN (\(placeholders))
                      AND jp.deleted_at IS NULL AND p.deleted_at IS NULL
                    GROUP BY j.id
                    HAVING COUNT(DISTINCT p.category_id) >= 2
                    ORDER BY j.created_at DESC
                    LIMIT ?
                    """, arguments: StatementArguments(categoryIds + [limit]))
                return rows.map { row in
                    SandboxJobRow(
                        jobId: row["id"],
                        jobName: row["job_name"] ?? "Unknown",
                        jobNumber: row["job_number"] ?? ""
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get parts consumed on a specific job (for sandbox real examples).
    public func getJobPartsForSandbox(jobId: Int64, limit: Int = 10) throws -> [SandboxJobPartRow] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT p.name, pc.name AS cat_name, jp.qty_consumed
                    FROM job_parts jp
                    JOIN parts p ON p.id = jp.part_id
                    LEFT JOIN part_categories pc ON pc.id = p.category_id
                    WHERE jp.job_id = ? AND jp.deleted_at IS NULL
                    ORDER BY jp.qty_consumed DESC
                    LIMIT ?
                    """, arguments: [jobId, limit])
                return rows.map { row in
                    SandboxJobPartRow(
                        name: (row["name"] as String?) ?? "",
                        categoryName: (row["cat_name"] as String?) ?? "",
                        qty: (row["qty_consumed"] as Int?) ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get deeper-level co-occurrence pairs for categories that matched companion rules.
    public func getNextLevelCoOccurrences(categoryIds: [Int64], limit: Int = 5) throws -> [SandboxNextLevelRow] {
        guard !categoryIds.isEmpty else { return [] }
        do {
            return try db.writer.read { dbConn in
                let placeholders = categoryIds.map { _ in "?" }.joined(separator: ", ")
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT cop.id, cop.category_a_id, cop.category_b_id, cop.points,
                           cop.match_level, cop.confidence,
                           ca.name AS cat_a_name, cb.name AS cat_b_name
                    FROM co_occurrence_pairs cop
                    LEFT JOIN part_categories ca ON ca.id = cop.category_a_id
                    LEFT JOIN part_categories cb ON cb.id = cop.category_b_id
                    WHERE (cop.category_a_id IN (\(placeholders)) OR cop.category_b_id IN (\(placeholders)))
                      AND cop.match_level IN ('style', 'type')
                      AND cop.is_blocked = 0
                    ORDER BY cop.points DESC
                    LIMIT ?
                    """, arguments: StatementArguments(categoryIds + categoryIds + [limit]))
                return rows.map { row in
                    SandboxNextLevelRow(
                        catAName: row["cat_a_name"] ?? "Unknown",
                        catBName: row["cat_b_name"] ?? "Unknown",
                        matchLevel: row["match_level"] ?? "style",
                        points: row["points"] ?? 0,
                        confidence: row["confidence"] ?? 0.0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
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
        return message.contains("no such table") || message.contains("no such column")
    }

    /// Escape a string for CSV output. Wraps in quotes if it contains commas,
    /// double-quotes, or newlines. Doubles any existing double-quotes.
    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    // MARK: - Catalog Search (Full Filters)

    /// Result type for catalog search with full filter support.
    public struct CatalogSearchResult: Sendable {
        public let parts: [PartWithDetails]
        public let totalCount: Int

        public init(parts: [PartWithDetails], totalCount: Int) {
            self.parts = parts
            self.totalCount = totalCount
        }
    }

    /// Sort field for catalog listing.
    public enum CatalogSortField: String, Sendable {
        case name, code, category, brand, stock, cost, sell
    }

    /// Lists catalog parts with full filter, sort, and pagination support.
    public func listCatalogParts(
        search: String? = nil,
        categoryId: Int64? = nil,
        styleId: Int64? = nil,
        typeId: Int64? = nil,
        colorId: Int64? = nil,
        brandId: Int64? = nil,
        lowStockOnly: Bool = false,
        sortField: CatalogSortField = .name,
        sortAscending: Bool = true,
        limit: Int = 25,
        offset: Int = 0
    ) throws -> CatalogSearchResult {
        do { return try db.writer.read { dbConn in
            var whereClauses = ["p.deleted_at IS NULL"]
            var args: [DatabaseValueConvertible?] = []

            if let categoryId {
                whereClauses.append("p.category_id = ?")
                args.append(categoryId)
            }
            if let styleId {
                whereClauses.append("p.style_id = ?")
                args.append(styleId)
            }
            if let typeId {
                whereClauses.append("p.type_id = ?")
                args.append(typeId)
            }
            if let colorId {
                whereClauses.append("p.color_id = ?")
                args.append(colorId)
            }
            if let brandId {
                whereClauses.append("p.brand_id = ?")
                args.append(brandId)
            }

            if let search, !search.isEmpty {
                whereClauses.append("(p.name LIKE ? OR p.code LIKE ? OR COALESCE(b.name, '') LIKE ?)")
                let like = "%\(search)%"
                args.append(like)
                args.append(like)
                args.append(like)
            }

            if lowStockOnly {
                whereClauses.append("""
                    p.min_stock_level IS NOT NULL AND \
                    COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) < p.min_stock_level
                    """)
            }

            let whereSQL = whereClauses.joined(separator: " AND ")

            let orderSQL: String
            switch sortField {
            case .name: orderSQL = "p.name"
            case .code: orderSQL = "p.code"
            case .category: orderSQL = "category_name"
            case .brand: orderSQL = "brand_name"
            case .stock: orderSQL = "total_stock"
            case .cost: orderSQL = "p.company_cost_price"
            case .sell: orderSQL = "(p.company_cost_price * (1 + p.company_markup_percent / 100))"
            }
            let dir = sortAscending ? "ASC" : "DESC"

            // Count query
            let countArgs = StatementArguments(args)
            let countSQL = """
                SELECT COUNT(*) FROM parts p
                LEFT JOIN brands b ON b.id = p.brand_id
                WHERE \(whereSQL)
                """
            let count = try Int.fetchOne(dbConn, sql: countSQL, arguments: countArgs) ?? 0

            // Fetch query
            var fetchArgValues = args
            fetchArgValues.append(limit)
            fetchArgValues.append(offset)
            let fetchArgs = StatementArguments(fetchArgValues)

            let fetchSQL = """
                SELECT p.*,
                       pc.name AS category_name,
                       b.name AS brand_name,
                       ps.name AS style_name,
                       pcol.name AS color_name,
                       COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) AS total_stock
                FROM parts p
                LEFT JOIN part_categories pc ON pc.id = p.category_id
                LEFT JOIN brands b ON b.id = p.brand_id
                LEFT JOIN part_styles ps ON ps.id = p.style_id
                LEFT JOIN part_colors pcol ON pcol.id = p.color_id
                WHERE \(whereSQL)
                ORDER BY \(orderSQL) \(dir)
                LIMIT ? OFFSET ?
                """

            let rows = try Row.fetchAll(dbConn, sql: fetchSQL, arguments: fetchArgs)
            let parts = try rows.map { row in
                let part = try Part(row: row)
                return PartWithDetails(
                    part: part,
                    categoryName: row["category_name"] as String?,
                    styleName: row["style_name"] as String?,
                    typeName: nil,
                    colorName: row["color_name"] as String?,
                    brandName: row["brand_name"] as String?,
                    totalStock: row["total_stock"] as Int
                )
            }
            return CatalogSearchResult(parts: parts, totalCount: count)
        }
        } catch {
            if isTableNotFoundError(error) { return CatalogSearchResult(parts: [], totalCount: 0) }
            throw error
        }
    }

    // MARK: - Stock Entries for Part

    /// Returns all active stock entries for a given part.
    public func listStockEntries(partId: Int64) throws -> [StockEntry] {
        try db.writer.read { dbConn in
            try StockEntry
                .filter(Column("part_id") == partId)
                .filter(Column("deleted_at") == nil)
                .fetchAll(dbConn)
        }
    }
}
