import SwiftUI
import GRDB
import WiredPartCore

/// Brands management page showing all part brands with their linked suppliers.
///
/// Uses a searchable list with swipe actions for edit/delete.
/// Tap a brand to view/edit details. Create new brands via the + button.
struct PartsBrandsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var brands: [BrandListRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showAddBrand = false
    @State private var editingBrand: BrandListRow?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading brands...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredBrands.isEmpty {
                emptyState
            } else {
                brandsList
            }
        }
        .searchable(text: $searchText, prompt: "Search brands...")
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showAddBrand = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddBrand) {
            BrandFormSheet(brand: nil) { await loadData() }
        }
        .sheet(item: $editingBrand) { brandRow in
            BrandFormSheet(brand: brandRow) { await loadData() }
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
        .task { await loadData() }
    }

    // MARK: - Filtered

    private var filteredBrands: [BrandListRow] {
        if searchText.isEmpty { return brands }
        let query = searchText.lowercased()
        return brands.filter {
            $0.name.lowercased().contains(query) ||
            ($0.website?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Brands List

    @ViewBuilder
    private var brandsList: some View {
        List {
            Section {
                Text("\(filteredBrands.count) brand\(filteredBrands.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(filteredBrands) { brand in
                Button {
                    editingBrand = brand
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            #if os(iOS)
                            .background(Color(.tertiarySystemGroupedBackground))
                            #elseif os(macOS)
                            .background(Color(.controlBackgroundColor))
                            #endif
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(brand.name)
                                .font(.body)
                                .fontWeight(.medium)

                            HStack(spacing: 8) {
                                if let website = brand.website, !website.isEmpty {
                                    Text(website)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(brand.partCount)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("parts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 56)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await deleteBrand(brand) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        editingBrand = brand
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tag")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Brands Yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Add brands to organize your parts by manufacturer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAddBrand = true
            } label: {
                Label("Add Brand", systemImage: "plus.circle.fill")
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
            let rows = try await db.writer.read { dbConnection -> [BrandListRow] in
                let results = try Row.fetchAll(dbConnection, sql: """
                    SELECT b.*,
                           COUNT(DISTINCT p.id) AS part_count
                    FROM brands b
                    LEFT JOIN parts p ON p.brand_id = b.id AND p.deleted_at IS NULL
                    WHERE b.deleted_at IS NULL
                    GROUP BY b.id
                    ORDER BY b.name ASC
                    """)
                return results.map { row in
                    BrandListRow(
                        id: row["id"],
                        name: row["name"],
                        website: row["website"],
                        notes: row["notes"],
                        partCount: row["part_count"]
                    )
                }
            }
            await MainActor.run {
                brands = rows
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    // MARK: - Delete

    private func deleteBrand(_ brand: BrandListRow) async {
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            try await db.writer.write { dbConnection in
                try dbConnection.execute(sql: "UPDATE brands SET deleted_at = ? WHERE id = ?", arguments: [now, brand.id])
            }
            await loadData()
        } catch {}
    }
}

// MARK: - Brand List Row

struct BrandListRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let website: String?
    let notes: String?
    let partCount: Int
}

// MARK: - Brand Form Sheet

private struct BrandFormSheet: View {
    let brand: BrandListRow?
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var website = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Brand Details") {
                    TextField("Brand Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Website (optional)", text: $website)
                        .frame(minHeight: 44)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(brand == nil ? "New Brand" : "Edit Brand")
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
                if let b = brand {
                    name = b.name
                    website = b.website ?? ""
                    notes = b.notes ?? ""
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
            let websiteValue = website.isEmpty ? nil : website
            let notesValue = notes.isEmpty ? nil : notes
            if let b = brand {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: "UPDATE brands SET name = ?, website = ?, notes = ?, updated_at = ? WHERE id = ?",
                        arguments: [trimmedName, websiteValue, notesValue, now, b.id]
                    )
                }
            } else {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: "INSERT INTO brands (name, website, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                        arguments: [trimmedName, websiteValue, notesValue, now, now]
                    )
                }
            }
        } catch {}
    }
}
