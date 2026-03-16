import SwiftUI
import GRDB
import WiredPartCore

/// Categories management page showing the three-level part hierarchy:
/// Category > Style > Type, with colors linked to types.
///
/// Uses a grouped list layout with expandable sections for each level.
/// Supports creating, editing, and deleting categories, styles, types, and colors.
struct PartsCategoriesPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var categories: [PartCategory] = []
    @State private var styles: [PartStyle] = []
    @State private var types: [PartType] = []
    @State private var colors: [PartColor] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var expandedCategories: Set<Int64> = []
    @State private var expandedStyles: Set<Int64> = []

    // Sheet state
    @State private var showAddCategory = false
    @State private var showAddStyle = false
    @State private var showAddType = false
    @State private var showAddColor = false
    @State private var editingCategory: PartCategory?
    @State private var editingStyle: PartStyle?
    @State private var editingType: PartType?
    @State private var parentCategoryIdForStyle: Int64?
    @State private var parentStyleIdForType: Int64?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading categories...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredCategories.isEmpty {
                emptyState
            } else {
                categoryList
            }
        }
        .searchable(text: $searchText, prompt: "Search categories, styles, types...")
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button { showAddCategory = true } label: {
                        Label("New Category", systemImage: "folder.badge.plus")
                    }
                    Button { showAddColor = true } label: {
                        Label("New Color", systemImage: "paintpalette")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddCategory) {
            CategoryFormSheet(category: nil) { await loadData() }
        }
        .sheet(item: $editingCategory) { cat in
            CategoryFormSheet(category: cat) { await loadData() }
        }
        .sheet(isPresented: $showAddStyle) {
            StyleFormSheet(style: nil, categoryId: parentCategoryIdForStyle ?? 0) { await loadData() }
        }
        .sheet(item: $editingStyle) { style in
            StyleFormSheet(style: style, categoryId: style.categoryId) { await loadData() }
        }
        .sheet(isPresented: $showAddType) {
            TypeFormSheet(type: nil, styleId: parentStyleIdForType ?? 0) { await loadData() }
        }
        .sheet(item: $editingType) { ptype in
            TypeFormSheet(type: ptype, styleId: ptype.styleId) { await loadData() }
        }
        .sheet(isPresented: $showAddColor) {
            ColorFormSheet(color: nil) { await loadData() }
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.systemGroupedBackground))
        #endif
        .task { await loadData() }
    }

    // MARK: - Filtered Data

    private var filteredCategories: [PartCategory] {
        if searchText.isEmpty { return categories }
        let query = searchText.lowercased()
        return categories.filter { cat in
            cat.name.lowercased().contains(query) ||
            stylesForCategory(cat.id!).contains { $0.name.lowercased().contains(query) } ||
            stylesForCategory(cat.id!).flatMap { typesForStyle($0.id!) }.contains { $0.name.lowercased().contains(query) }
        }
    }

    private func stylesForCategory(_ categoryId: Int64) -> [PartStyle] {
        styles.filter { $0.categoryId == categoryId }
    }

    private func typesForStyle(_ styleId: Int64) -> [PartType] {
        types.filter { $0.styleId == styleId }
    }

    // MARK: - Category List

    @ViewBuilder
    private var categoryList: some View {
        List {
            // Colors section
            if !colors.isEmpty {
                Section("Colors (\(colors.count))") {
                    ForEach(colors, id: \.id) { color in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: color.hexCode ?? "#888888") ?? .gray)
                                .frame(width: 24, height: 24)
                            Text(color.name)
                                .font(.body)
                            Spacer()
                            if let hex = color.hexCode {
                                Text(hex)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }

            // Category hierarchy
            ForEach(filteredCategories, id: \.id) { category in
                Section {
                    // Category header row
                    Button {
                        toggleCategory(category.id!)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: expandedCategories.contains(category.id!) ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                    .font(.headline)
                                let styleCount = stylesForCategory(category.id!).count
                                Text("\(styleCount) style\(styleCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deleteCategory(category) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingCategory = category
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            parentCategoryIdForStyle = category.id
                            showAddStyle = true
                        } label: {
                            Label("Add Style", systemImage: "plus")
                        }
                        .tint(Color.accentColor)
                    }

                    // Expanded styles
                    if expandedCategories.contains(category.id!) {
                        ForEach(stylesForCategory(category.id!), id: \.id) { style in
                            styleRow(style)
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Style Row

    @ViewBuilder
    private func styleRow(_ style: PartStyle) -> some View {
        VStack(spacing: 0) {
            Button {
                toggleStyle(style.id!)
            } label: {
                HStack(spacing: 10) {
                    Spacer().frame(width: 16)
                    Image(systemName: expandedStyles.contains(style.id!) ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Image(systemName: "paintbrush.fill")
                        .foregroundStyle(.purple)
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        let typeCount = typesForStyle(style.id!).count
                        Text("\(typeCount) type\(typeCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await deleteStyle(style) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    editingStyle = style
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .leading) {
                Button {
                    parentStyleIdForType = style.id
                    showAddType = true
                } label: {
                    Label("Add Type", systemImage: "plus")
                }
                .tint(Color.accentColor)
            }

            // Expanded types
            if expandedStyles.contains(style.id!) {
                ForEach(typesForStyle(style.id!), id: \.id) { ptype in
                    typeRow(ptype)
                }
            }
        }
    }

    // MARK: - Type Row

    @ViewBuilder
    private func typeRow(_ ptype: PartType) -> some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 46)
            Image(systemName: "tag.fill")
                .foregroundStyle(.teal)
                .font(.caption)
            Text(ptype.name)
                .font(.subheadline)
            Spacer()
        }
        .frame(minHeight: 44)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await deleteType(ptype) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                editingType = ptype
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Categories Yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Create categories to organize your parts hierarchy.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAddCategory = true
            } label: {
                Label("Add Category", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toggle Helpers

    private func toggleCategory(_ id: Int64) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCategories.contains(id) {
                expandedCategories.remove(id)
            } else {
                expandedCategories.insert(id)
            }
        }
    }

    private func toggleStyle(_ id: Int64) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedStyles.contains(id) {
                expandedStyles.remove(id)
            } else {
                expandedStyles.insert(id)
            }
        }
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        do {
            let db = appCore.db!
            let result = try await db.writer.read { dbConnection -> ([PartCategory], [PartStyle], [PartType], [PartColor]) in
                let cats = try PartCategory
                    .filter(Column("deleted_at") == nil)
                    .order(Column("sort_order").asc, Column("name").asc)
                    .fetchAll(dbConnection)
                let stls = try PartStyle
                    .filter(Column("deleted_at") == nil)
                    .order(Column("sort_order").asc, Column("name").asc)
                    .fetchAll(dbConnection)
                let typs = try PartType
                    .filter(Column("deleted_at") == nil)
                    .order(Column("sort_order").asc, Column("name").asc)
                    .fetchAll(dbConnection)
                let cols = try PartColor
                    .filter(Column("deleted_at") == nil)
                    .order(Column("sort_order").asc, Column("name").asc)
                    .fetchAll(dbConnection)
                return (cats, stls, typs, cols)
            }
            await MainActor.run {
                categories = result.0
                styles = result.1
                types = result.2
                colors = result.3
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    // MARK: - Delete Actions

    private func deleteCategory(_ cat: PartCategory) async {
        guard let id = cat.id else { return }
        do {
            let db = appCore.db!
            try await db.writer.write { dbConnection in
                let now = ISO8601DateFormatter().string(from: Date())
                try dbConnection.execute(sql: "UPDATE part_categories SET deleted_at = ? WHERE id = ?", arguments: [now, id])
            }
            await loadData()
        } catch {}
    }

    private func deleteStyle(_ style: PartStyle) async {
        guard let id = style.id else { return }
        do {
            let db = appCore.db!
            try await db.writer.write { dbConnection in
                let now = ISO8601DateFormatter().string(from: Date())
                try dbConnection.execute(sql: "UPDATE part_styles SET deleted_at = ? WHERE id = ?", arguments: [now, id])
            }
            await loadData()
        } catch {}
    }

    private func deleteType(_ ptype: PartType) async {
        guard let id = ptype.id else { return }
        do {
            let db = appCore.db!
            try await db.writer.write { dbConnection in
                let now = ISO8601DateFormatter().string(from: Date())
                try dbConnection.execute(sql: "UPDATE part_types SET deleted_at = ? WHERE id = ?", arguments: [now, id])
            }
            await loadData()
        } catch {}
    }
}

// MARK: - Identifiable Conformances for .sheet(item:)

extension PartCategory: @retroactive Identifiable {}
extension PartStyle: @retroactive Identifiable {}
extension PartType: @retroactive Identifiable {}

// MARK: - Category Form Sheet

private struct CategoryFormSheet: View {
    let category: PartCategory?
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var sortOrder = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Category Details") {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Description (optional)", text: $description)
                        .frame(minHeight: 44)
                    Stepper("Sort Order: \(sortOrder)", value: $sortOrder, in: 0...999)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
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
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let c = category {
                    name = c.name
                    description = c.description ?? ""
                    sortOrder = c.sortOrder
                }
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            if let existing = category, let id = existing.id {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: "UPDATE part_categories SET name = ?, description = ?, sort_order = ?, updated_at = ? WHERE id = ?",
                        arguments: [trimmedName, description.isEmpty ? nil : description, sortOrder, now, id]
                    )
                }
            } else {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: "INSERT INTO part_categories (name, description, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                        arguments: [trimmedName, description.isEmpty ? nil : description, sortOrder, now, now]
                    )
                }
            }
        } catch {}
    }
}

// MARK: - Style Form Sheet

private struct StyleFormSheet: View {
    let style: PartStyle?
    let categoryId: Int64
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var sortOrder = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Style Details") {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Description (optional)", text: $description)
                        .frame(minHeight: 44)
                    Stepper("Sort Order: \(sortOrder)", value: $sortOrder, in: 0...999)
                }
            }
            .navigationTitle(style == nil ? "New Style" : "Edit Style")
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
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let s = style {
                    name = s.name
                    description = s.description ?? ""
                    sortOrder = s.sortOrder
                }
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            if let existing = style, let id = existing.id {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: "UPDATE part_styles SET name = ?, description = ?, sort_order = ?, updated_at = ? WHERE id = ?",
                        arguments: [trimmedName, description.isEmpty ? nil : description, sortOrder, now, id]
                    )
                }
            } else {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: "INSERT INTO part_styles (category_id, name, description, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                        arguments: [categoryId, trimmedName, description.isEmpty ? nil : description, sortOrder, now, now]
                    )
                }
            }
        } catch {}
    }
}

// MARK: - Type Form Sheet

private struct TypeFormSheet: View {
    let type: PartType?
    let styleId: Int64
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var sortOrder = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Type Details") {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Description (optional)", text: $description)
                        .frame(minHeight: 44)
                    Stepper("Sort Order: \(sortOrder)", value: $sortOrder, in: 0...999)
                }
            }
            .navigationTitle(type == nil ? "New Type" : "Edit Type")
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
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let t = type {
                    name = t.name
                    description = t.description ?? ""
                    sortOrder = t.sortOrder
                }
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            if let existing = type, let id = existing.id {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: "UPDATE part_types SET name = ?, description = ?, sort_order = ?, updated_at = ? WHERE id = ?",
                        arguments: [trimmedName, description.isEmpty ? nil : description, sortOrder, now, id]
                    )
                }
            } else {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: "INSERT INTO part_types (style_id, name, description, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                        arguments: [styleId, trimmedName, description.isEmpty ? nil : description, sortOrder, now, now]
                    )
                }
            }
        } catch {}
    }
}

// MARK: - Color Form Sheet

private struct ColorFormSheet: View {
    let color: PartColor?
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hexCode = "#888888"
    @State private var sortOrder = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Color Details") {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Hex Code (e.g. #FF0000)", text: $hexCode)
                        .frame(minHeight: 44)
                        .monospaced()
                    HStack {
                        Text("Preview")
                        Spacer()
                        Circle()
                            .fill(Color(hex: hexCode) ?? .gray)
                            .frame(width: 32, height: 32)
                    }
                    Stepper("Sort Order: \(sortOrder)", value: $sortOrder, in: 0...999)
                }
            }
            .navigationTitle(color == nil ? "New Color" : "Edit Color")
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
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let c = color {
                    name = c.name
                    hexCode = c.hexCode ?? "#888888"
                    sortOrder = c.sortOrder
                }
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            if let existing = color, let id = existing.id {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: "UPDATE part_colors SET name = ?, hex_code = ?, sort_order = ?, updated_at = ? WHERE id = ?",
                        arguments: [trimmedName, hexCode, sortOrder, now, id]
                    )
                }
            } else {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: "INSERT INTO part_colors (name, hex_code, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                        arguments: [trimmedName, hexCode, sortOrder, now, now]
                    )
                }
            }
        } catch {}
    }
}
