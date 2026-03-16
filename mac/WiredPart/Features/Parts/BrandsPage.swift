import SwiftUI
import GRDB
import WiredPartCore

/// Brand management page with search, add/edit/delete functionality.
///
/// Displays a list of brands with their name, website, and associated part count.
/// Create and edit operations use a sheet form. Delete is soft-delete with confirmation.
struct BrandsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var brands: [BrandRow] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sheet State

    @State private var showForm = false
    @State private var editingBrand: Brand?

    // MARK: - Form Fields

    @State private var formName = ""
    @State private var formWebsite = ""
    @State private var formNotes = ""

    // MARK: - Delete

    @State private var showDeleteConfirm = false
    @State private var deleteTarget: BrandRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                brandList
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadBrands() }
        .sheet(isPresented: $showForm) { brandFormSheet }
        .alert("Delete Brand", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    softDeleteBrand(target.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(deleteTarget?.name ?? "")\"?")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Brands")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(brands.count) brand\(brands.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            TextField("Search brands...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onChange(of: searchText) { _, _ in loadBrands() }

            Button {
                editingBrand = nil
                formName = ""
                formWebsite = ""
                formNotes = ""
                showForm = true
            } label: {
                Label("Add Brand", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Brand List

    @ViewBuilder
    private var brandList: some View {
        if isLoading {
            ProgressView("Loading brands...")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        } else if brands.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "tag")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text(searchText.isEmpty ? "No brands yet" : "No brands match your search")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(brands, id: \.id) { brand in
                    brandCard(brand)
                }
            }
        }
    }

    private func brandCard(_ brand: BrandRow) -> some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(brand.name)
                        .font(.headline)
                    HStack(spacing: 16) {
                        if !brand.website.isEmpty {
                            Label(brand.website, systemImage: "globe")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Label("\(brand.partCount) part\(brand.partCount == 1 ? "" : "s")", systemImage: "shippingbox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !brand.notes.isEmpty {
                        Text(brand.notes)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button {
                    startEditing(brand)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                Button {
                    deleteTarget = brand
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Form Sheet

    private var brandFormSheet: some View {
        VStack(spacing: 16) {
            Text(editingBrand == nil ? "New Brand" : "Edit Brand")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Brand Name", text: $formName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Website").font(.caption).foregroundStyle(.secondary)
                TextField("https://example.com", text: $formWebsite)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.caption).foregroundStyle(.secondary)
                TextField("Notes (optional)", text: $formNotes)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { showForm = false }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    saveBrand()
                    showForm = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 380)
    }

    // MARK: - Actions

    private func startEditing(_ brand: BrandRow) {
        guard let db = appCore.db else { return }
        do {
            let record = try db.writer.read { conn in
                try Brand.fetchOne(conn, sql: "SELECT * FROM brands WHERE id = ?", arguments: [brand.id])
            }
            if let record {
                editingBrand = record
                formName = record.name
                formWebsite = record.website ?? ""
                formNotes = record.notes ?? ""
                showForm = true
            }
        } catch {
            print("[BrandsPage] Fetch brand error: \(error)")
        }
    }

    private func loadBrands() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { conn in
                var sql = """
                    SELECT
                        b.id, b.name, COALESCE(b.website, '') AS website, COALESCE(b.notes, '') AS notes,
                        (SELECT COUNT(*) FROM parts p WHERE p.brand_id = b.id AND p.deleted_at IS NULL) AS part_count
                    FROM brands b
                    WHERE b.deleted_at IS NULL
                    """
                var args: [DatabaseValueConvertible?] = []

                let trimmed = searchText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    sql += " AND b.name LIKE ?"
                    args.append("%\(trimmed)%")
                }

                sql += " ORDER BY b.name ASC"

                let rows = try Row.fetchAll(conn, sql: sql, arguments: StatementArguments(args))
                brands = rows.map { row in
                    BrandRow(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        website: row["website"] ?? "",
                        notes: row["notes"] ?? "",
                        partCount: row["part_count"] ?? 0
                    )
                }
            }
        } catch {
            print("[BrandsPage] Load error: \(error)")
        }

        isLoading = false
    }

    private func saveBrand() {
        guard let db = appCore.db else { return }
        let name = formName.trimmingCharacters(in: .whitespaces)
        let website = formWebsite.trimmingCharacters(in: .whitespaces)
        let notes = formNotes.trimmingCharacters(in: .whitespaces)

        do {
            if let existing = editingBrand {
                try db.writer.write { conn in
                    try conn.execute(
                        sql: "UPDATE brands SET name = ?, website = ?, notes = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [name, website.isEmpty ? nil : website, notes.isEmpty ? nil : notes, existing.id]
                    )
                }
            } else {
                try db.writer.write { conn in
                    try conn.execute(
                        sql: """
                            INSERT INTO brands (name, website, notes, created_at, updated_at)
                            VALUES (?, ?, ?, datetime('now'), datetime('now'))
                            """,
                        arguments: [name, website.isEmpty ? nil : website, notes.isEmpty ? nil : notes]
                    )
                }
            }
        } catch {
            print("[BrandsPage] Save error: \(error)")
        }

        loadBrands()
    }

    private func softDeleteBrand(_ id: Int64) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE brands SET deleted_at = datetime('now') WHERE id = ?",
                    arguments: [id]
                )
            }
        } catch {
            print("[BrandsPage] Delete error: \(error)")
        }
        loadBrands()
    }
}

// MARK: - Brand Row Model

private struct BrandRow: Identifiable {
    let id: Int64
    let name: String
    let website: String
    let notes: String
    let partCount: Int
}
