import SwiftUI
import GRDB
import WiredPartCore

/// Companion rules and alternatives management page.
///
/// Shows companion rules (parts that should be ordered together) and
/// part alternatives (substitute parts). Supports creating new rules
/// and managing existing relationships.
struct PartsCompanionsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var companionRules: [CompanionRuleRow] = []
    @State private var alternatives: [AlternativeRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var activeTab = CompanionTab.rules
    @State private var showAddRule = false
    @State private var showAddAlternative = false

    var body: some View {
        VStack(spacing: 0) {
            // Tabs
            Picker("View", selection: $activeTab) {
                Text("Companion Rules").tag(CompanionTab.rules)
                Text("Alternatives").tag(CompanionTab.alternatives)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch activeTab {
                case .rules:
                    rulesView
                case .alternatives:
                    alternativesView
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search companions...")
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    switch activeTab {
                    case .rules: showAddRule = true
                    case .alternatives: showAddAlternative = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddRule) {
            CompanionRuleFormSheet { await loadData() }
        }
        .sheet(isPresented: $showAddAlternative) {
            AlternativeFormSheet { await loadData() }
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
        .task { await loadData() }
    }

    // MARK: - Rules View

    @ViewBuilder
    private var rulesView: some View {
        if filteredRules.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Companion Rules")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Create rules to automatically suggest companion parts when ordering.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    showAddRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    Text("\(filteredRules.count) rule\(filteredRules.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredRules) { rule in
                    HStack(spacing: 12) {
                        Image(systemName: "link")
                            .foregroundStyle(rule.isActive == 1 ? Color.accentColor : .secondary)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.sourceName)
                                .font(.body)
                                .fontWeight(.medium)

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(rule.targetName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                Text(rule.relationship.capitalized)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                                Text("Qty: \(rule.defaultQty)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if rule.isActive != 1 {
                            Text("Inactive")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(minHeight: 56)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deleteRule(rule) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            Task { await toggleRuleActive(rule) }
                        } label: {
                            Label(rule.isActive == 1 ? "Deactivate" : "Activate",
                                  systemImage: rule.isActive == 1 ? "xmark.circle" : "checkmark.circle")
                        }
                        .tint(rule.isActive == 1 ? .orange : .green)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    // MARK: - Alternatives View

    @ViewBuilder
    private var alternativesView: some View {
        if filteredAlternatives.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Part Alternatives")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Define substitute parts for when primary parts are unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    showAddAlternative = true
                } label: {
                    Label("Add Alternative", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    Text("\(filteredAlternatives.count) alternative\(filteredAlternatives.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredAlternatives) { alt in
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.swap")
                            .foregroundStyle(alt.isActive == 1 ? .purple : .secondary)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(alt.partName)
                                .font(.body)
                                .fontWeight(.medium)

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(alt.alternativeName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                Text(alt.relationship.capitalized)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.1))
                                    .clipShape(Capsule())
                                Text("Priority: \(alt.priority)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .frame(minHeight: 56)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deleteAlternative(alt) }
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
    }

    // MARK: - Filtered

    private var filteredRules: [CompanionRuleRow] {
        if searchText.isEmpty { return companionRules }
        let query = searchText.lowercased()
        return companionRules.filter {
            $0.sourceName.lowercased().contains(query) ||
            $0.targetName.lowercased().contains(query)
        }
    }

    private var filteredAlternatives: [AlternativeRow] {
        if searchText.isEmpty { return alternatives }
        let query = searchText.lowercased()
        return alternatives.filter {
            $0.partName.lowercased().contains(query) ||
            $0.alternativeName.lowercased().contains(query)
        }
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        do {
            let db = appCore.db!
            let result = try await db.writer.read { dbConnection -> ([CompanionRuleRow], [AlternativeRow]) in
                // Companion rules — source/target can be category, style, type, or part
                let ruleRows = try Row.fetchAll(dbConnection, sql: """
                    SELECT cr.*,
                           COALESCE(
                               CASE cr.source_type
                                   WHEN 'part' THEN (SELECT name FROM parts WHERE id = cr.source_id)
                                   WHEN 'category' THEN (SELECT name FROM part_categories WHERE id = cr.source_id)
                                   WHEN 'style' THEN (SELECT name FROM part_styles WHERE id = cr.source_id)
                                   WHEN 'type' THEN (SELECT name FROM part_types WHERE id = cr.source_id)
                               END, 'Unknown'
                           ) AS source_name,
                           COALESCE(
                               CASE cr.target_type
                                   WHEN 'part' THEN (SELECT name FROM parts WHERE id = cr.target_id)
                                   WHEN 'category' THEN (SELECT name FROM part_categories WHERE id = cr.target_id)
                                   WHEN 'style' THEN (SELECT name FROM part_styles WHERE id = cr.target_id)
                                   WHEN 'type' THEN (SELECT name FROM part_types WHERE id = cr.target_id)
                               END, 'Unknown'
                           ) AS target_name
                    FROM companion_rules cr
                    WHERE cr.deleted_at IS NULL
                    ORDER BY cr.created_at DESC
                    """)
                let rules = ruleRows.map { row in
                    CompanionRuleRow(
                        id: row["id"],
                        sourceType: row["source_type"],
                        sourceId: row["source_id"],
                        sourceName: row["source_name"],
                        targetType: row["target_type"],
                        targetId: row["target_id"],
                        targetName: row["target_name"],
                        relationship: row["relationship"],
                        defaultQty: row["default_qty"],
                        isActive: row["is_active"]
                    )
                }

                // Alternatives
                let altRows = try Row.fetchAll(dbConnection, sql: """
                    SELECT pa.*,
                           p1.name AS part_name,
                           p2.name AS alternative_name
                    FROM part_alternatives pa
                    JOIN parts p1 ON p1.id = pa.part_id
                    JOIN parts p2 ON p2.id = pa.alternative_part_id
                    WHERE pa.deleted_at IS NULL
                    ORDER BY pa.priority ASC
                    """)
                let alts = altRows.map { row in
                    AlternativeRow(
                        id: row["id"],
                        partId: row["part_id"],
                        partName: row["part_name"],
                        alternativePartId: row["alternative_part_id"],
                        alternativeName: row["alternative_name"],
                        relationship: row["relationship"],
                        priority: row["priority"],
                        isActive: row["is_active"]
                    )
                }
                return (rules, alts)
            }
            await MainActor.run {
                companionRules = result.0
                alternatives = result.1
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    // MARK: - Actions

    private func deleteRule(_ rule: CompanionRuleRow) async {
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            try await db.writer.write { dbConnection in
                try dbConnection.execute(sql: "UPDATE companion_rules SET deleted_at = ? WHERE id = ?", arguments: [now, rule.id])
            }
            await loadData()
        } catch {}
    }

    private func toggleRuleActive(_ rule: CompanionRuleRow) async {
        do {
            let db = appCore.db!
            let newActive = rule.isActive == 1 ? 0 : 1
            try await db.writer.write { dbConnection in
                try dbConnection.execute(sql: "UPDATE companion_rules SET is_active = ? WHERE id = ?", arguments: [newActive, rule.id])
            }
            await loadData()
        } catch {}
    }

    private func deleteAlternative(_ alt: AlternativeRow) async {
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            try await db.writer.write { dbConnection in
                try dbConnection.execute(sql: "UPDATE part_alternatives SET deleted_at = ? WHERE id = ?", arguments: [now, alt.id])
            }
            await loadData()
        } catch {}
    }
}

// MARK: - Types

private enum CompanionTab {
    case rules, alternatives
}

struct CompanionRuleRow: Identifiable, Sendable {
    let id: Int64
    let sourceType: String
    let sourceId: Int64
    let sourceName: String
    let targetType: String
    let targetId: Int64
    let targetName: String
    let relationship: String
    let defaultQty: Int
    let isActive: Int
}

struct AlternativeRow: Identifiable, Sendable {
    let id: Int64
    let partId: Int64
    let partName: String
    let alternativePartId: Int64
    let alternativeName: String
    let relationship: String
    let priority: Int
    let isActive: Int
}

// MARK: - Companion Rule Form Sheet

private struct CompanionRuleFormSheet: View {
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var parts: [PartPickerItem] = []
    @State private var sourcePartId: Int64 = 0
    @State private var targetPartId: Int64 = 0
    @State private var relationship = "required"
    @State private var defaultQty = 1

    private let relationships = ["required", "recommended", "optional"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Source Part") {
                    Picker("When ordering", selection: $sourcePartId) {
                        Text("Select...").tag(Int64(0))
                        ForEach(parts, id: \.id) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                }

                Section("Target Part") {
                    Picker("Also suggest", selection: $targetPartId) {
                        Text("Select...").tag(Int64(0))
                        ForEach(parts, id: \.id) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                }

                Section("Details") {
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) { r in
                            Text(r.capitalized).tag(r)
                        }
                    }
                    Stepper("Default Qty: \(defaultQty)", value: $defaultQty, in: 1...99)
                }
            }
            .navigationTitle("New Companion Rule")
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
                    .disabled(sourcePartId == 0 || targetPartId == 0 || sourcePartId == targetPartId)
                }
            }
            .task { await loadParts() }
        }
    }

    @Sendable
    private func loadParts() async {
        do {
            let db = appCore.db!
            let rows = try await db.writer.read { dbConnection -> [Row] in
                try Row.fetchAll(dbConnection, sql: "SELECT id, name FROM parts WHERE deleted_at IS NULL ORDER BY name ASC")
            }
            await MainActor.run {
                parts = rows.map { PartPickerItem(id: $0["id"], name: $0["name"]) }
            }
        } catch {}
    }

    private func save() async {
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            try await db.writer.write { dbConnection in
                try dbConnection.execute(
                    sql: """
                        INSERT INTO companion_rules (source_type, source_id, target_type, target_id,
                        relationship, default_qty, is_active, created_at, updated_at)
                        VALUES ('part', ?, 'part', ?, ?, ?, 1, ?, ?)
                        """,
                    arguments: [sourcePartId, targetPartId, relationship, defaultQty, now, now]
                )
            }
        } catch {}
    }
}

// MARK: - Alternative Form Sheet

private struct AlternativeFormSheet: View {
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var parts: [PartPickerItem] = []
    @State private var partId: Int64 = 0
    @State private var alternativePartId: Int64 = 0
    @State private var relationship = "substitute"
    @State private var priority = 1

    private let relationships = ["substitute", "equivalent", "upgrade", "downgrade"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Primary Part") {
                    Picker("Part", selection: $partId) {
                        Text("Select...").tag(Int64(0))
                        ForEach(parts, id: \.id) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                }

                Section("Alternative Part") {
                    Picker("Can be replaced with", selection: $alternativePartId) {
                        Text("Select...").tag(Int64(0))
                        ForEach(parts, id: \.id) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                }

                Section("Details") {
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) { r in
                            Text(r.capitalized).tag(r)
                        }
                    }
                    Stepper("Priority: \(priority)", value: $priority, in: 1...10)
                }
            }
            .navigationTitle("New Alternative")
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
                    .disabled(partId == 0 || alternativePartId == 0 || partId == alternativePartId)
                }
            }
            .task { await loadParts() }
        }
    }

    @Sendable
    private func loadParts() async {
        do {
            let db = appCore.db!
            let rows = try await db.writer.read { dbConnection -> [Row] in
                try Row.fetchAll(dbConnection, sql: "SELECT id, name FROM parts WHERE deleted_at IS NULL ORDER BY name ASC")
            }
            await MainActor.run {
                parts = rows.map { PartPickerItem(id: $0["id"], name: $0["name"]) }
            }
        } catch {}
    }

    private func save() async {
        do {
            let db = appCore.db!
            let now = ISO8601DateFormatter().string(from: Date())
            try await db.writer.write { dbConnection in
                try dbConnection.execute(
                    sql: """
                        INSERT INTO part_alternatives (part_id, alternative_part_id, relationship,
                        priority, is_active, created_at, updated_at)
                        VALUES (?, ?, ?, ?, 1, ?, ?)
                        """,
                    arguments: [partId, alternativePartId, relationship, priority, now, now]
                )
            }
        } catch {}
    }
}

// MARK: - Part Picker Item

struct PartPickerItem: Identifiable, Sendable {
    let id: Int64
    let name: String
}
