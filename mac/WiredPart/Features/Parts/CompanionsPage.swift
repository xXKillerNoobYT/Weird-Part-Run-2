import SwiftUI
import GRDB
import WiredPartCore

/// Companion rules management page.
///
/// Displays a list of companion rules that link source parts/categories
/// to target parts/categories. Each rule can be toggled active/inactive
/// and edited or deleted via sheets.
struct CompanionsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var rules: [CompanionRowVM] = []
    @State private var isLoading = true

    // MARK: - Sheet State

    @State private var showForm = false
    @State private var editingRule: CompanionRule?

    // MARK: - Form Fields

    @State private var formSourceType = "category"
    @State private var formSourceId: Int64 = 0
    @State private var formTargetType = "category"
    @State private var formTargetId: Int64 = 0
    @State private var formRelationship = "requires"
    @State private var formDefaultQty = "1"
    @State private var formNotes = ""
    @State private var formIsActive = true

    // MARK: - Picker Data

    @State private var categoryOptions: [(id: Int64, name: String)] = []

    // MARK: - Delete

    @State private var showDeleteConfirm = false
    @State private var deleteTarget: CompanionRowVM?

    private let relationshipOptions = ["requires", "recommends", "optional", "replaces"]
    private let entityTypeOptions = ["category", "style", "type", "part"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                ruleList
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadRules() }
        .sheet(isPresented: $showForm) { ruleFormSheet }
        .alert("Delete Rule", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    softDeleteRule(target.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this companion rule?")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Companions")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Define rules linking related parts and categories")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                startNewRule()
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Rule List

    @ViewBuilder
    private var ruleList: some View {
        if isLoading {
            ProgressView("Loading companion rules...")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        } else if rules.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No companion rules yet")
                    .font(.headline)
                Text("Create rules to automatically suggest related parts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(rules, id: \.id) { rule in
                    ruleCard(rule)
                }
            }
        }
    }

    private func ruleCard(_ rule: CompanionRowVM) -> some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    // Source -> Target
                    HStack(spacing: 6) {
                        Label(rule.sourceName, systemImage: "square.fill")
                            .font(.callout)
                            .foregroundStyle(Color.accentColor)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(rule.targetName, systemImage: "square.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }

                    // Metadata
                    HStack(spacing: 12) {
                        Text(rule.relationship.capitalized)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(relationshipColor(rule.relationship).opacity(0.15)))
                            .foregroundStyle(relationshipColor(rule.relationship))

                        Text("Qty: \(rule.defaultQty)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !rule.notes.isEmpty {
                            Text(rule.notes)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Active toggle
                Toggle("", isOn: Binding(
                    get: { rule.isActive },
                    set: { newValue in toggleActive(rule.id, active: newValue) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)

                Button {
                    startEditing(rule)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)

                Button {
                    deleteTarget = rule
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

    private func relationshipColor(_ rel: String) -> Color {
        switch rel {
        case "requires": return .red
        case "recommends": return .orange
        case "optional": return .blue
        case "replaces": return .purple
        default: return .secondary
        }
    }

    // MARK: - Form Sheet

    private var ruleFormSheet: some View {
        VStack(spacing: 16) {
            Text(editingRule == nil ? "New Companion Rule" : "Edit Companion Rule")
                .font(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source Type").font(.caption).foregroundStyle(.secondary)
                    Picker("Source Type", selection: $formSourceType) {
                        ForEach(entityTypeOptions, id: \.self) { Text($0.capitalized) }
                    }
                    .pickerStyle(.menu)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source ID").font(.caption).foregroundStyle(.secondary)
                    TextField("ID", value: $formSourceId, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            Picker("Relationship", selection: $formRelationship) {
                ForEach(relationshipOptions, id: \.self) { Text($0.capitalized) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target Type").font(.caption).foregroundStyle(.secondary)
                    Picker("Target Type", selection: $formTargetType) {
                        ForEach(entityTypeOptions, id: \.self) { Text($0.capitalized) }
                    }
                    .pickerStyle(.menu)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target ID").font(.caption).foregroundStyle(.secondary)
                    TextField("ID", value: $formTargetId, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Default Qty").font(.caption).foregroundStyle(.secondary)
                    TextField("Qty", text: $formDefaultQty)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                Toggle("Active", isOn: $formIsActive)
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
                    saveRule()
                    showForm = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(formSourceId == 0 || formTargetId == 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 440)
    }

    // MARK: - Actions

    private func startNewRule() {
        editingRule = nil
        formSourceType = "category"
        formSourceId = 0
        formTargetType = "category"
        formTargetId = 0
        formRelationship = "requires"
        formDefaultQty = "1"
        formNotes = ""
        formIsActive = true
        showForm = true
    }

    private func startEditing(_ rule: CompanionRowVM) {
        guard let db = appCore.db else { return }
        do {
            let record = try db.writer.read { conn in
                try CompanionRule.fetchOne(conn, sql: "SELECT * FROM companion_rules WHERE id = ?", arguments: [rule.id])
            }
            if let record {
                editingRule = record
                formSourceType = record.sourceType
                formSourceId = record.sourceId
                formTargetType = record.targetType
                formTargetId = record.targetId
                formRelationship = record.relationship
                formDefaultQty = String(record.defaultQty)
                formNotes = record.notes ?? ""
                formIsActive = record.isActive == 1
                showForm = true
            }
        } catch {
            print("[CompanionsPage] Fetch rule error: \(error)")
        }
    }

    private func loadRules() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { conn in
                let dbRules = try CompanionRule.fetchAll(
                    conn,
                    sql: "SELECT * FROM companion_rules WHERE deleted_at IS NULL ORDER BY created_at DESC"
                )

                rules = dbRules.map { rule in
                    CompanionRowVM(
                        id: rule.id ?? 0,
                        sourceType: rule.sourceType,
                        sourceName: "\(rule.sourceType.capitalized) #\(rule.sourceId)",
                        targetType: rule.targetType,
                        targetName: "\(rule.targetType.capitalized) #\(rule.targetId)",
                        relationship: rule.relationship,
                        defaultQty: rule.defaultQty,
                        notes: rule.notes ?? "",
                        isActive: rule.isActive == 1
                    )
                }
            }
        } catch {
            print("[CompanionsPage] Load error: \(error)")
        }

        isLoading = false
    }

    private func saveRule() {
        guard let db = appCore.db else { return }

        do {
            if let existing = editingRule, let id = existing.id {
                try db.writer.write { conn in
                    try conn.execute(
                        sql: """
                            UPDATE companion_rules SET
                                source_type = ?, source_id = ?,
                                target_type = ?, target_id = ?,
                                relationship = ?, default_qty = ?,
                                is_active = ?, notes = ?,
                                updated_at = datetime('now')
                            WHERE id = ?
                            """,
                        arguments: [
                            formSourceType, formSourceId,
                            formTargetType, formTargetId,
                            formRelationship, Int(formDefaultQty) ?? 1,
                            formIsActive ? 1 : 0, formNotes.isEmpty ? nil : formNotes,
                            id
                        ]
                    )
                }
            } else {
                try db.writer.write { conn in
                    try conn.execute(
                        sql: """
                            INSERT INTO companion_rules (source_type, source_id, target_type, target_id, relationship, default_qty, is_active, notes, created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
                            """,
                        arguments: [
                            formSourceType, formSourceId,
                            formTargetType, formTargetId,
                            formRelationship, Int(formDefaultQty) ?? 1,
                            formIsActive ? 1 : 0, formNotes.isEmpty ? nil : formNotes
                        ]
                    )
                }
            }
        } catch {
            print("[CompanionsPage] Save error: \(error)")
        }

        loadRules()
    }

    private func toggleActive(_ id: Int64, active: Bool) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE companion_rules SET is_active = ?, updated_at = datetime('now') WHERE id = ?",
                    arguments: [active ? 1 : 0, id]
                )
            }
        } catch {
            print("[CompanionsPage] Toggle error: \(error)")
        }
        loadRules()
    }

    private func softDeleteRule(_ id: Int64) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE companion_rules SET deleted_at = datetime('now') WHERE id = ?",
                    arguments: [id]
                )
            }
        } catch {
            print("[CompanionsPage] Delete error: \(error)")
        }
        loadRules()
    }
}

// MARK: - View Model

private struct CompanionRowVM: Identifiable {
    let id: Int64
    let sourceType: String
    let sourceName: String
    let targetType: String
    let targetName: String
    let relationship: String
    let defaultQty: Int
    let notes: String
    let isActive: Bool
}
