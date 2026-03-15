import SwiftUI
import GRDB
import WiredPartCore

/// Hierarchical tree editor for Part Categories > Styles > Types.
///
/// Displays a collapsible tree using DisclosureGroup. Each level supports
/// create, edit, and soft-delete operations. Data loads via direct GRDB queries
/// against the local database (no PartsService dependency required).
struct CategoriesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var categories: [PartCategory] = []
    @State private var stylesByCategory: [Int64: [PartStyle]] = [:]
    @State private var typesByStyle: [Int64: [PartType]] = [:]
    @State private var isLoading = true

    // MARK: - Sheet State

    @State private var showCategorySheet = false
    @State private var showStyleSheet = false
    @State private var showTypeSheet = false

    @State private var editingCategory: PartCategory?
    @State private var editingStyle: PartStyle?
    @State private var editingType: PartType?

    @State private var parentCategoryId: Int64?
    @State private var parentStyleId: Int64?

    // MARK: - Form Fields

    @State private var formName = ""
    @State private var formDescription = ""

    // MARK: - Delete Confirmation

    @State private var showDeleteConfirm = false
    @State private var deleteAction: (() -> Void)?
    @State private var deleteMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                treeContent
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadHierarchy() }
        .sheet(isPresented: $showCategorySheet) { categoryFormSheet }
        .sheet(isPresented: $showStyleSheet) { styleFormSheet }
        .sheet(isPresented: $showTypeSheet) { typeFormSheet }
        .alert("Confirm Delete", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteAction?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Categories")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Manage part hierarchy: Category > Style > Type")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                editingCategory = nil
                formName = ""
                formDescription = ""
                showCategorySheet = true
            } label: {
                Label("Add Category", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Tree Content

    @ViewBuilder
    private var treeContent: some View {
        if isLoading {
            ProgressView("Loading hierarchy...")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        } else if categories.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(categories, id: \.id) { category in
                    categoryRow(category)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No categories yet")
                .font(.headline)
            Text("Create your first category to organize parts.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Category Row

    private func categoryRow(_ category: PartCategory) -> some View {
        let catId = category.id ?? 0
        let styles = stylesByCategory[catId] ?? []

        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(styles, id: \.id) { style in
                    styleRow(style, categoryId: catId)
                }

                // Add Style button
                Button {
                    parentCategoryId = catId
                    editingStyle = nil
                    formName = ""
                    formDescription = ""
                    showStyleSheet = true
                } label: {
                    Label("Add Style", systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 4)
            }
        } label: {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(category.name)
                    .fontWeight(.semibold)
                Text("\(styles.count) style\(styles.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                editDeleteButtons(
                    editAction: {
                        editingCategory = category
                        formName = category.name
                        formDescription = category.description ?? ""
                        showCategorySheet = true
                    },
                    deleteAction: {
                        deleteMessage = "Delete category \"\(category.name)\" and all its styles and types?"
                        self.deleteAction = { softDeleteCategory(catId) }
                        showDeleteConfirm = true
                    }
                )
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.controlBackgroundColor)))
    }

    // MARK: - Style Row

    private func styleRow(_ style: PartStyle, categoryId: Int64) -> some View {
        let styleId = style.id ?? 0
        let types = typesByStyle[styleId] ?? []

        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(types, id: \.id) { type in
                    typeRow(type, styleId: styleId)
                }

                // Add Type button
                Button {
                    parentStyleId = styleId
                    editingType = nil
                    formName = ""
                    formDescription = ""
                    showTypeSheet = true
                } label: {
                    Label("Add Type", systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 4)
            }
        } label: {
            HStack {
                Image(systemName: "paintbrush.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(style.name)
                    .fontWeight(.medium)
                Text("\(types.count) type\(types.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                editDeleteButtons(
                    editAction: {
                        parentCategoryId = categoryId
                        editingStyle = style
                        formName = style.name
                        formDescription = style.description ?? ""
                        showStyleSheet = true
                    },
                    deleteAction: {
                        deleteMessage = "Delete style \"\(style.name)\" and all its types?"
                        self.deleteAction = { softDeleteStyle(styleId) }
                        showDeleteConfirm = true
                    }
                )
            }
        }
        .padding(.leading, 16)
        .padding(.vertical, 2)
    }

    // MARK: - Type Row

    private func typeRow(_ type: PartType, styleId: Int64) -> some View {
        HStack {
            Image(systemName: "tag.fill")
                .foregroundStyle(.green)
                .font(.caption2)
            Text(type.name)
                .font(.callout)
            if let desc = type.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            editDeleteButtons(
                editAction: {
                    parentStyleId = styleId
                    editingType = type
                    formName = type.name
                    formDescription = type.description ?? ""
                    showTypeSheet = true
                },
                deleteAction: {
                    deleteMessage = "Delete type \"\(type.name)\"?"
                    self.deleteAction = { softDeleteType(type.id ?? 0) }
                    showDeleteConfirm = true
                }
            )
        }
        .padding(.leading, 32)
        .padding(.vertical, 2)
    }

    // MARK: - Shared Edit/Delete Buttons

    private func editDeleteButtons(editAction: @escaping () -> Void, deleteAction: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Button(action: editAction) {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            Button(action: deleteAction) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Category Form Sheet

    private var categoryFormSheet: some View {
        VStack(spacing: 16) {
            Text(editingCategory == nil ? "New Category" : "Edit Category")
                .font(.headline)

            TextField("Category Name", text: $formName)
                .textFieldStyle(.roundedBorder)
            TextField("Description (optional)", text: $formDescription)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { showCategorySheet = false }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    saveCategory()
                    showCategorySheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    // MARK: - Style Form Sheet

    private var styleFormSheet: some View {
        VStack(spacing: 16) {
            Text(editingStyle == nil ? "New Style" : "Edit Style")
                .font(.headline)

            TextField("Style Name", text: $formName)
                .textFieldStyle(.roundedBorder)
            TextField("Description (optional)", text: $formDescription)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { showStyleSheet = false }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    saveStyle()
                    showStyleSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    // MARK: - Type Form Sheet

    private var typeFormSheet: some View {
        VStack(spacing: 16) {
            Text(editingType == nil ? "New Type" : "Edit Type")
                .font(.headline)

            TextField("Type Name", text: $formName)
                .textFieldStyle(.roundedBorder)
            TextField("Description (optional)", text: $formDescription)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { showTypeSheet = false }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    saveType()
                    showTypeSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    // MARK: - Data Loading

    private func loadHierarchy() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { conn in
                categories = try PartCategory.fetchAll(
                    conn,
                    sql: "SELECT * FROM part_categories WHERE deleted_at IS NULL ORDER BY sort_order ASC, name ASC"
                )

                var stylesMap: [Int64: [PartStyle]] = [:]
                var typesMap: [Int64: [PartType]] = [:]

                let allStyles = try PartStyle.fetchAll(
                    conn,
                    sql: "SELECT * FROM part_styles WHERE deleted_at IS NULL ORDER BY sort_order ASC, name ASC"
                )
                for style in allStyles {
                    stylesMap[style.categoryId, default: []].append(style)
                }

                let allTypes = try PartType.fetchAll(
                    conn,
                    sql: "SELECT * FROM part_types WHERE deleted_at IS NULL ORDER BY sort_order ASC, name ASC"
                )
                for type in allTypes {
                    typesMap[type.styleId, default: []].append(type)
                }

                stylesByCategory = stylesMap
                typesByStyle = typesMap
            }
        } catch {
            print("[CategoriesPage] Load error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Save Operations

    private func saveCategory() {
        guard let db = appCore.db else { return }
        let name = formName.trimmingCharacters(in: .whitespaces)
        let desc = formDescription.trimmingCharacters(in: .whitespaces)

        do {
            if var existing = editingCategory {
                existing.name = name
                existing.description = desc.isEmpty ? nil : desc
                try db.writer.write { conn in
                    try conn.execute(
                        sql: "UPDATE part_categories SET name = ?, description = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [name, desc.isEmpty ? nil : desc, existing.id]
                    )
                }
            } else {
                let maxSort = try db.writer.read { conn in
                    try Int.fetchOne(conn, sql: "SELECT COALESCE(MAX(sort_order), 0) FROM part_categories WHERE deleted_at IS NULL")
                } ?? 0
                try db.writer.write { conn in
                    try conn.execute(
                        sql: """
                            INSERT INTO part_categories (name, description, sort_order, created_at, updated_at)
                            VALUES (?, ?, ?, datetime('now'), datetime('now'))
                            """,
                        arguments: [name, desc.isEmpty ? nil : desc, maxSort + 1]
                    )
                }
            }
        } catch {
            print("[CategoriesPage] Save category error: \(error)")
        }

        loadHierarchy()
    }

    private func saveStyle() {
        guard let db = appCore.db, let categoryId = parentCategoryId else { return }
        let name = formName.trimmingCharacters(in: .whitespaces)
        let desc = formDescription.trimmingCharacters(in: .whitespaces)

        do {
            if var existing = editingStyle {
                existing.name = name
                existing.description = desc.isEmpty ? nil : desc
                try db.writer.write { conn in
                    try conn.execute(
                        sql: "UPDATE part_styles SET name = ?, description = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [name, desc.isEmpty ? nil : desc, existing.id]
                    )
                }
            } else {
                let maxSort = try db.writer.read { conn in
                    try Int.fetchOne(conn, sql: "SELECT COALESCE(MAX(sort_order), 0) FROM part_styles WHERE category_id = ? AND deleted_at IS NULL", arguments: [categoryId])
                } ?? 0
                try db.writer.write { conn in
                    try conn.execute(
                        sql: """
                            INSERT INTO part_styles (category_id, name, description, sort_order, created_at, updated_at)
                            VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
                            """,
                        arguments: [categoryId, name, desc.isEmpty ? nil : desc, maxSort + 1]
                    )
                }
            }
        } catch {
            print("[CategoriesPage] Save style error: \(error)")
        }

        loadHierarchy()
    }

    private func saveType() {
        guard let db = appCore.db, let styleId = parentStyleId else { return }
        let name = formName.trimmingCharacters(in: .whitespaces)
        let desc = formDescription.trimmingCharacters(in: .whitespaces)

        do {
            if var existing = editingType {
                existing.name = name
                existing.description = desc.isEmpty ? nil : desc
                try db.writer.write { conn in
                    try conn.execute(
                        sql: "UPDATE part_types SET name = ?, description = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [name, desc.isEmpty ? nil : desc, existing.id]
                    )
                }
            } else {
                let maxSort = try db.writer.read { conn in
                    try Int.fetchOne(conn, sql: "SELECT COALESCE(MAX(sort_order), 0) FROM part_types WHERE style_id = ? AND deleted_at IS NULL", arguments: [styleId])
                } ?? 0
                try db.writer.write { conn in
                    try conn.execute(
                        sql: """
                            INSERT INTO part_types (style_id, name, description, sort_order, created_at, updated_at)
                            VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
                            """,
                        arguments: [styleId, name, desc.isEmpty ? nil : desc, maxSort + 1]
                    )
                }
            }
        } catch {
            print("[CategoriesPage] Save type error: \(error)")
        }

        loadHierarchy()
    }

    // MARK: - Soft Delete Operations

    private func softDeleteCategory(_ id: Int64) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE part_categories SET deleted_at = datetime('now') WHERE id = ?",
                    arguments: [id]
                )
                // Cascade soft-delete styles and types under this category
                let styleIds = try Int64.fetchAll(
                    conn,
                    sql: "SELECT id FROM part_styles WHERE category_id = ? AND deleted_at IS NULL",
                    arguments: [id]
                )
                for styleId in styleIds {
                    try conn.execute(
                        sql: "UPDATE part_types SET deleted_at = datetime('now') WHERE style_id = ?",
                        arguments: [styleId]
                    )
                }
                try conn.execute(
                    sql: "UPDATE part_styles SET deleted_at = datetime('now') WHERE category_id = ?",
                    arguments: [id]
                )
            }
        } catch {
            print("[CategoriesPage] Delete category error: \(error)")
        }
        loadHierarchy()
    }

    private func softDeleteStyle(_ id: Int64) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE part_styles SET deleted_at = datetime('now') WHERE id = ?",
                    arguments: [id]
                )
                try conn.execute(
                    sql: "UPDATE part_types SET deleted_at = datetime('now') WHERE style_id = ?",
                    arguments: [id]
                )
            }
        } catch {
            print("[CategoriesPage] Delete style error: \(error)")
        }
        loadHierarchy()
    }

    private func softDeleteType(_ id: Int64) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE part_types SET deleted_at = datetime('now') WHERE id = ?",
                    arguments: [id]
                )
            }
        } catch {
            print("[CategoriesPage] Delete type error: \(error)")
        }
        loadHierarchy()
    }
}
