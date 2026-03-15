import SwiftUI
import GRDB
import WiredPartCore

/// Suppliers management page showing all suppliers with contact info and scores.
///
/// Searchable list with supplier cards showing contact details, delivery info,
/// and quality scores. Supports create, edit, delete via sheets and swipe actions.
struct PartsSuppliersPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var suppliers: [SupplierListRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showAddSupplier = false
    @State private var selectedSupplier: SupplierListRow?
    @State private var filterActive: Bool? = true

    var body: some View {
        VStack(spacing: 0) {
            // Active/All toggle
            Picker("Filter", selection: Binding(
                get: { filterActive ?? false ? 0 : 1 },
                set: { filterActive = $0 == 0 ? true : nil }
            )) {
                Text("Active").tag(0)
                Text("All").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isLoading {
                ProgressView("Loading suppliers...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSuppliers.isEmpty {
                emptyState
            } else {
                suppliersList
            }
        }
        .searchable(text: $searchText, prompt: "Search suppliers...")
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showAddSupplier = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSupplier) {
            SupplierFormSheet(supplier: nil) { await loadData() }
        }
        .sheet(item: $selectedSupplier) { supplier in
            SupplierDetailSheet(supplier: supplier) { await loadData() }
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
        .task { await loadData() }
    }

    // MARK: - Filtered

    private var filteredSuppliers: [SupplierListRow] {
        var result = suppliers
        if let active = filterActive, active {
            result = result.filter { $0.isActive == 1 }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                ($0.contactName?.lowercased().contains(query) ?? false) ||
                ($0.email?.lowercased().contains(query) ?? false) ||
                ($0.phone?.lowercased().contains(query) ?? false)
            }
        }
        return result
    }

    // MARK: - Suppliers List

    @ViewBuilder
    private var suppliersList: some View {
        List {
            Section {
                Text("\(filteredSuppliers.count) supplier\(filteredSuppliers.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(filteredSuppliers) { supplier in
                Button {
                    selectedSupplier = supplier
                } label: {
                    supplierRow(supplier)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await deleteSupplier(supplier) }
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
    private func supplierRow(_ supplier: SupplierListRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .foregroundStyle(supplier.isActive == 1 ? Color.accentColor : .secondary)
                .font(.title3)
                .frame(width: 40, height: 40)
                #if os(iOS)
                .background(Color(.tertiarySystemGroupedBackground))
                #elseif os(macOS)
                .background(Color(.controlBackgroundColor))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(supplier.name)
                        .font(.body)
                        .fontWeight(.medium)
                    if supplier.isActive != 1 {
                        Text("Inactive")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if let contact = supplier.contactName, !contact.isEmpty {
                        Label(contact, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let phone = supplier.phone, !phone.isEmpty {
                        Label(phone, systemImage: "phone.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Quality score indicator
            if let score = supplier.qualityScore, score > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f", score))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(scoreColor(score))
                    Text("quality")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 60)
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Suppliers Yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Add suppliers to track your parts sources and pricing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAddSupplier = true
            } label: {
                Label("Add Supplier", systemImage: "plus.circle.fill")
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
            let rows = try await db.writer.read { dbConnection -> [SupplierListRow] in
                let results = try Row.fetchAll(dbConnection, sql: """
                    SELECT s.*,
                           COUNT(DISTINCT psl.part_id) AS part_count
                    FROM suppliers s
                    LEFT JOIN part_supplier_links psl ON psl.supplier_id = s.id AND psl.deleted_at IS NULL
                    WHERE s.deleted_at IS NULL
                    GROUP BY s.id
                    ORDER BY s.name ASC
                    """)
                return results.map { row in
                    SupplierListRow(
                        id: row["id"],
                        name: row["name"],
                        contactName: row["contact_name"],
                        email: row["email"],
                        phone: row["phone"],
                        address: row["address"],
                        website: row["website"],
                        repName: row["rep_name"],
                        repEmail: row["rep_email"],
                        repPhone: row["rep_phone"],
                        notes: row["notes"],
                        deliveryMethod: row["delivery_method"],
                        deliveryDays: row["delivery_days"],
                        onTimeRate: row["on_time_rate"],
                        qualityScore: row["quality_score"],
                        reliabilityScore: row["reliability_score"],
                        isActive: row["is_active"] ?? 1,
                        partCount: row["part_count"]
                    )
                }
            }
            await MainActor.run {
                suppliers = rows
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    // MARK: - Delete

    private func deleteSupplier(_ supplier: SupplierListRow) async {
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            try await db.writer.write { dbConnection in
                try dbConnection.execute(sql: "UPDATE suppliers SET deleted_at = ? WHERE id = ?", arguments: [now, supplier.id])
            }
            await loadData()
        } catch {}
    }
}

// MARK: - Supplier List Row

struct SupplierListRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let contactName: String?
    let email: String?
    let phone: String?
    let address: String?
    let website: String?
    let repName: String?
    let repEmail: String?
    let repPhone: String?
    let notes: String?
    let deliveryMethod: String?
    let deliveryDays: String?
    let onTimeRate: Double?
    let qualityScore: Double?
    let reliabilityScore: Double?
    let isActive: Int
    let partCount: Int
}

// MARK: - Supplier Form Sheet

private struct SupplierFormSheet: View {
    let supplier: SupplierListRow?
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var contactName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var website = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Supplier Details") {
                    TextField("Supplier Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Contact Name", text: $contactName)
                        .frame(minHeight: 44)
                }

                Section("Contact Info") {
                    TextField("Email", text: $email)
                        .frame(minHeight: 44)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Phone", text: $phone)
                        .frame(minHeight: 44)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                    TextField("Address", text: $address)
                        .frame(minHeight: 44)
                    TextField("Website", text: $website)
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
            .navigationTitle(supplier == nil ? "New Supplier" : "Edit Supplier")
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
                if let s = supplier {
                    name = s.name
                    contactName = s.contactName ?? ""
                    email = s.email ?? ""
                    phone = s.phone ?? ""
                    address = s.address ?? ""
                    website = s.website ?? ""
                    notes = s.notes ?? ""
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
            if let s = supplier {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: """
                            UPDATE suppliers SET name = ?, contact_name = ?, email = ?, phone = ?,
                            address = ?, website = ?, notes = ?, updated_at = ? WHERE id = ?
                            """,
                        arguments: [trimmedName, contactName.isEmpty ? nil : contactName,
                                    email.isEmpty ? nil : email, phone.isEmpty ? nil : phone,
                                    address.isEmpty ? nil : address, website.isEmpty ? nil : website,
                                    notes.isEmpty ? nil : notes, now, s.id]
                    )
                }
            } else {
                try await db.writer.write { dbConnection in
                    try dbConnection.execute(
                        sql: """
                            INSERT INTO suppliers (name, contact_name, email, phone, address, website, notes,
                            is_active, created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
                            """,
                        arguments: [trimmedName, contactName.isEmpty ? nil : contactName,
                                    email.isEmpty ? nil : email, phone.isEmpty ? nil : phone,
                                    address.isEmpty ? nil : address, website.isEmpty ? nil : website,
                                    notes.isEmpty ? nil : notes, now, now]
                    )
                }
            }
        } catch {}
    }
}

// MARK: - Supplier Detail Sheet

private struct SupplierDetailSheet: View {
    let supplier: SupplierListRow
    let onUpdate: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var showEditForm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Contact Information") {
                    if let contact = supplier.contactName, !contact.isEmpty {
                        LabeledContent("Contact", value: contact)
                    }
                    if let email = supplier.email, !email.isEmpty {
                        LabeledContent("Email", value: email)
                    }
                    if let phone = supplier.phone, !phone.isEmpty {
                        LabeledContent("Phone", value: phone)
                    }
                    if let address = supplier.address, !address.isEmpty {
                        LabeledContent("Address", value: address)
                    }
                    if let website = supplier.website, !website.isEmpty {
                        LabeledContent("Website", value: website)
                    }
                }

                if supplier.repName != nil || supplier.repEmail != nil || supplier.repPhone != nil {
                    Section("Sales Rep") {
                        if let rep = supplier.repName, !rep.isEmpty {
                            LabeledContent("Name", value: rep)
                        }
                        if let repEmail = supplier.repEmail, !repEmail.isEmpty {
                            LabeledContent("Email", value: repEmail)
                        }
                        if let repPhone = supplier.repPhone, !repPhone.isEmpty {
                            LabeledContent("Phone", value: repPhone)
                        }
                    }
                }

                Section("Delivery") {
                    if let method = supplier.deliveryMethod, !method.isEmpty {
                        LabeledContent("Method", value: method)
                    }
                    if let days = supplier.deliveryDays, !days.isEmpty {
                        LabeledContent("Delivery Days", value: days)
                    }
                }

                Section("Performance Scores") {
                    if let score = supplier.qualityScore {
                        LabeledContent("Quality") {
                            Text(String(format: "%.0f%%", score))
                                .foregroundStyle(score >= 80 ? .green : score >= 60 ? .orange : .red)
                        }
                    }
                    if let score = supplier.onTimeRate {
                        LabeledContent("On-Time Rate") {
                            Text(String(format: "%.0f%%", score))
                                .foregroundStyle(score >= 80 ? .green : score >= 60 ? .orange : .red)
                        }
                    }
                    if let score = supplier.reliabilityScore {
                        LabeledContent("Reliability") {
                            Text(String(format: "%.0f%%", score))
                                .foregroundStyle(score >= 80 ? .green : score >= 60 ? .orange : .red)
                        }
                    }
                    LabeledContent("Linked Parts", value: "\(supplier.partCount)")
                }

                if let notes = supplier.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(supplier.name)
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
                SupplierFormSheet(supplier: supplier) {
                    await onUpdate()
                    dismiss()
                }
            }
        }
    }
}
