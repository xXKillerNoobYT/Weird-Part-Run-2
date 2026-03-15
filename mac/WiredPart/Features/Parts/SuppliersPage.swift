import SwiftUI
import GRDB
import WiredPartCore

/// Supplier management page with performance metrics.
///
/// Displays suppliers in card-style layout showing contact info, delivery method,
/// and performance scores (on-time rate, quality, reliability, communication).
/// Supports full CRUD via sheet form with soft-delete.
struct SuppliersPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var suppliers: [Supplier] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sheet State

    @State private var showForm = false
    @State private var editingSupplier: Supplier?

    // MARK: - Form Fields

    @State private var formName = ""
    @State private var formContactName = ""
    @State private var formPhone = ""
    @State private var formEmail = ""
    @State private var formWebsite = ""
    @State private var formAddress = ""
    @State private var formDeliveryMethod = ""
    @State private var formNotes = ""

    // MARK: - Delete

    @State private var showDeleteConfirm = false
    @State private var deleteTarget: Supplier?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                supplierList
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadSuppliers() }
        .sheet(isPresented: $showForm) { supplierFormSheet }
        .alert("Delete Supplier", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget, let id = target.id {
                    softDeleteSupplier(id)
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
                Text("Suppliers")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(suppliers.count) supplier\(suppliers.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            TextField("Search suppliers...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onChange(of: searchText) { _, _ in loadSuppliers() }

            Button {
                startNewSupplier()
            } label: {
                Label("Add Supplier", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Supplier List

    @ViewBuilder
    private var supplierList: some View {
        if isLoading {
            ProgressView("Loading suppliers...")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        } else if suppliers.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "building.2")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text(searchText.isEmpty ? "No suppliers yet" : "No suppliers match your search")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(suppliers, id: \.id) { supplier in
                    supplierCard(supplier)
                }
            }
        }
    }

    private func supplierCard(_ supplier: Supplier) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Top row: name + actions
                HStack {
                    Text(supplier.name)
                        .font(.headline)
                    if let method = supplier.deliveryMethod, !method.isEmpty {
                        Text(method)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Button { startEditing(supplier) } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    Button {
                        deleteTarget = supplier
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }

                // Contact info row
                HStack(spacing: 16) {
                    if let contact = supplier.contactName, !contact.isEmpty {
                        Label(contact, systemImage: "person")
                            .font(.caption)
                    }
                    if let phone = supplier.phone, !phone.isEmpty {
                        Label(phone, systemImage: "phone")
                            .font(.caption)
                    }
                    if let email = supplier.email, !email.isEmpty {
                        Label(email, systemImage: "envelope")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)

                // Performance metrics
                HStack(spacing: 20) {
                    if let rate = supplier.onTimeRate {
                        metricBadge(label: "On-Time", value: String(format: "%.0f%%", rate * 100), color: rate >= 0.9 ? .green : (rate >= 0.7 ? .orange : .red))
                    }
                    if let quality = supplier.qualityScore {
                        metricBadge(label: "Quality", value: String(format: "%.1f", quality), color: quality >= 4.0 ? .green : (quality >= 3.0 ? .orange : .red))
                    }
                    if let reliability = supplier.reliabilityScore {
                        metricBadge(label: "Reliability", value: String(format: "%.1f", reliability), color: reliability >= 4.0 ? .green : (reliability >= 3.0 ? .orange : .red))
                    }
                    if let comm = supplier.communicationScore {
                        metricBadge(label: "Communication", value: String(format: "%.1f", comm), color: comm >= 4.0 ? .green : (comm >= 3.0 ? .orange : .red))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func metricBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Form Sheet

    private var supplierFormSheet: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(editingSupplier == nil ? "New Supplier" : "Edit Supplier")
                    .font(.headline)

                Group {
                    formField("Supplier Name", text: $formName)
                    formField("Contact Name", text: $formContactName)

                    Divider()
                    Text("Contact").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        formField("Phone", text: $formPhone)
                        formField("Email", text: $formEmail)
                    }
                    formField("Website", text: $formWebsite)
                    formField("Address", text: $formAddress)

                    Divider()
                    formField("Delivery Method", text: $formDeliveryMethod)
                    formField("Notes", text: $formNotes)
                }

                HStack {
                    Button("Cancel") { showForm = false }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        saveSupplier()
                        showForm = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 440, minHeight: 400)
    }

    private func formField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Actions

    private func startNewSupplier() {
        editingSupplier = nil
        formName = ""
        formContactName = ""
        formPhone = ""
        formEmail = ""
        formWebsite = ""
        formAddress = ""
        formDeliveryMethod = ""
        formNotes = ""
        showForm = true
    }

    private func startEditing(_ supplier: Supplier) {
        editingSupplier = supplier
        formName = supplier.name
        formContactName = supplier.contactName ?? ""
        formPhone = supplier.phone ?? ""
        formEmail = supplier.email ?? ""
        formWebsite = supplier.website ?? ""
        formAddress = supplier.address ?? ""
        formDeliveryMethod = supplier.deliveryMethod ?? ""
        formNotes = supplier.notes ?? ""
        showForm = true
    }

    private func loadSuppliers() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { conn in
                var sql = "SELECT * FROM suppliers WHERE deleted_at IS NULL"
                var args: [DatabaseValueConvertible?] = []

                let trimmed = searchText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    sql += " AND (name LIKE ? OR COALESCE(contact_name, '') LIKE ?)"
                    let like = "%\(trimmed)%"
                    args.append(like)
                    args.append(like)
                }

                sql += " ORDER BY name ASC"

                suppliers = try Supplier.fetchAll(conn, sql: sql, arguments: StatementArguments(args) ?? StatementArguments())
            }
        } catch {
            print("[SuppliersPage] Load error: \(error)")
        }

        isLoading = false
    }

    private func saveSupplier() {
        guard let db = appCore.db else { return }
        let name = formName.trimmingCharacters(in: .whitespaces)

        do {
            if let existing = editingSupplier, let id = existing.id {
                try db.writer.write { conn in
                    try conn.execute(
                        sql: """
                            UPDATE suppliers SET
                                name = ?, contact_name = ?, phone = ?, email = ?,
                                website = ?, address = ?, delivery_method = ?, notes = ?,
                                updated_at = datetime('now')
                            WHERE id = ?
                            """,
                        arguments: [
                            name,
                            formContactName.isEmpty ? nil : formContactName,
                            formPhone.isEmpty ? nil : formPhone,
                            formEmail.isEmpty ? nil : formEmail,
                            formWebsite.isEmpty ? nil : formWebsite,
                            formAddress.isEmpty ? nil : formAddress,
                            formDeliveryMethod.isEmpty ? nil : formDeliveryMethod,
                            formNotes.isEmpty ? nil : formNotes,
                            id
                        ]
                    )
                }
            } else {
                try db.writer.write { conn in
                    try conn.execute(
                        sql: """
                            INSERT INTO suppliers (name, contact_name, phone, email, website, address, delivery_method, notes, is_active, created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
                            """,
                        arguments: [
                            name,
                            formContactName.isEmpty ? nil : formContactName,
                            formPhone.isEmpty ? nil : formPhone,
                            formEmail.isEmpty ? nil : formEmail,
                            formWebsite.isEmpty ? nil : formWebsite,
                            formAddress.isEmpty ? nil : formAddress,
                            formDeliveryMethod.isEmpty ? nil : formDeliveryMethod,
                            formNotes.isEmpty ? nil : formNotes
                        ]
                    )
                }
            }
        } catch {
            print("[SuppliersPage] Save error: \(error)")
        }

        loadSuppliers()
    }

    private func softDeleteSupplier(_ id: Int64) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?",
                    arguments: [id]
                )
            }
        } catch {
            print("[SuppliersPage] Delete error: \(error)")
        }
        loadSuppliers()
    }
}
