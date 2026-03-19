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
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var activeTab = CompanionTab.rules
    // Single active-sheet enum to avoid multiple .sheet conflicts
    enum ActiveSheet: Identifiable {
        case addRule
        case addAlternative

        var id: String {
            switch self {
            case .addRule: return "addRule"
            case .addAlternative: return "addAlternative"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

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
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
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
                    case .rules: activeSheet = .addRule
                    case .alternatives: activeSheet = .addAlternative
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addRule:
                CompanionRuleFormSheet { await loadData() }
            case .addAlternative:
                AlternativeFormSheet { await loadData() }
            }
        }
        #if os(iOS)
        .background(DS.Background.page)
        #elseif os(macOS)
        .background(DS.Background.page)
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
                    activeSheet = .addRule
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
                    activeSheet = .addAlternative
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
                            .foregroundStyle(.purple)
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
            guard let db = appCore.db else { return }
            let result = try await db.writer.read { dbConnection -> ([CompanionRuleRow], [AlternativeRow]) in
                // Companion rules — name, description, style_match, qty_mode, qty_ratio
                let ruleRows = try Row.fetchAll(dbConnection, sql: """
                    SELECT cr.id, cr.name, COALESCE(cr.description, cr.style_match) AS description,
                           cr.qty_mode, CAST(COALESCE(cr.qty_ratio, 1) AS INTEGER) AS qty_ratio,
                           cr.is_active
                    FROM companion_rules cr
                    ORDER BY cr.created_at DESC
                    """)
                let rules = ruleRows.map { row in
                    CompanionRuleRow(
                        id: row["id"],
                        sourceName: row["name"] ?? "Unnamed",
                        targetName: row["description"] ?? "",
                        relationship: row["qty_mode"] ?? "sum",
                        defaultQty: row["qty_ratio"] ?? 1,
                        isActive: row["is_active"] ?? 1
                    )
                }

                // Alternatives
                let altRows = try Row.fetchAll(dbConnection, sql: """
                    SELECT pa.id, pa.part_id, pa.alternative_part_id,
                           pa.relationship, pa.preference,
                           p1.name AS part_name,
                           p2.name AS alternative_name
                    FROM part_alternatives pa
                    JOIN parts p1 ON p1.id = pa.part_id
                    JOIN parts p2 ON p2.id = pa.alternative_part_id
                    ORDER BY pa.preference ASC
                    """)
                let alts = altRows.map { row in
                    AlternativeRow(
                        id: row["id"],
                        partId: row["part_id"],
                        partName: row["part_name"],
                        alternativePartId: row["alternative_part_id"],
                        alternativeName: row["alternative_name"],
                        relationship: row["relationship"],
                        priority: row["preference"] ?? 0
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
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Actions

    private func deleteRule(_ rule: CompanionRuleRow) async {
        do {
            guard let db = appCore.db else { return }
            try await db.writer.write { dbConnection in
                try dbConnection.execute(sql: "DELETE FROM companion_rules WHERE id = ?", arguments: [rule.id])
            }
            await loadData()
        } catch {
            print("[PartsCompanionsPage] deleteRule failed: \(error)")
        }
    }

    private func toggleRuleActive(_ rule: CompanionRuleRow) async {
        do {
            guard let db = appCore.db else { return }
            let newActive = rule.isActive == 1 ? 0 : 1
            try await db.writer.write { dbConnection in
                try dbConnection.execute(sql: "UPDATE companion_rules SET is_active = ? WHERE id = ?", arguments: [newActive, rule.id])
            }
            await loadData()
        } catch {
            print("[PartsCompanionsPage] toggleRuleActive failed: \(error)")
        }
    }

    private func deleteAlternative(_ alt: AlternativeRow) async {
        do {
            guard let db = appCore.db else { return }
            try await db.writer.write { dbConnection in
                try dbConnection.execute(sql: "DELETE FROM part_alternatives WHERE id = ?", arguments: [alt.id])
            }
            await loadData()
        } catch {
            print("[PartsCompanionsPage] deleteAlternative failed: \(error)")
        }
    }
}

// MARK: - Types

private enum CompanionTab {
    case rules, alternatives
}

struct CompanionRuleRow: Identifiable, Sendable {
    let id: Int64
    let sourceName: String  // rule name
    let targetName: String  // description or style_match
    let relationship: String  // qty_mode
    let defaultQty: Int  // qty_ratio
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

    private func loadParts() async {
        do {
            guard let db = appCore.db else { return }
            let rows = try db.writer.read { dbConnection -> [Row] in
                try Row.fetchAll(dbConnection, sql: "SELECT id, name FROM parts WHERE deleted_at IS NULL ORDER BY name ASC")
            }
            parts = rows.map { PartPickerItem(id: $0["id"], name: $0["name"]) }
        } catch {
            print("[PartsCompanionsPage] CompanionRuleFormSheet.loadParts failed: \(error)")
        }
    }

    private func save() async {
        let capturedSourcePartId = sourcePartId
        let capturedTargetPartId = targetPartId
        let capturedRelationship = relationship
        let capturedDefaultQty = defaultQty
        do {
            guard let db = appCore.db else { return }
            let now = ISO8601DateFormatter().string(from: Date())
            // Build a name from the source → target parts
            let sourceName = parts.first(where: { $0.id == capturedSourcePartId })?.name ?? "Part"
            let targetName = parts.first(where: { $0.id == capturedTargetPartId })?.name ?? "Part"
            let ruleName = "\(sourceName) → \(targetName)"
            try await db.writer.write { dbConnection in
                try dbConnection.execute(
                    sql: """
                        INSERT INTO companion_rules (name, description, qty_mode, qty_ratio, is_active, created_at, updated_at)
                        VALUES (?, ?, ?, ?, 1, ?, ?)
                        """,
                    arguments: [ruleName, capturedRelationship, "sum", capturedDefaultQty, now, now]
                )
            }
        } catch {
            print("[PartsCompanionsPage] CompanionRuleFormSheet.save failed: \(error)")
        }
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

    private func loadParts() async {
        do {
            guard let db = appCore.db else { return }
            let rows = try db.writer.read { dbConnection -> [Row] in
                try Row.fetchAll(dbConnection, sql: "SELECT id, name FROM parts WHERE deleted_at IS NULL ORDER BY name ASC")
            }
            parts = rows.map { PartPickerItem(id: $0["id"], name: $0["name"]) }
        } catch {
            print("[PartsCompanionsPage] AlternativeFormSheet.loadParts failed: \(error)")
        }
    }

    private func save() async {
        let capturedPartId = partId
        let capturedAlternativePartId = alternativePartId
        let capturedRelationship = relationship
        let capturedPriority = priority
        do {
            guard let db = appCore.db else { return }
            let now = ISO8601DateFormatter().string(from: Date())
            try await db.writer.write { dbConnection in
                try dbConnection.execute(
                    sql: """
                        INSERT INTO part_alternatives (part_id, alternative_part_id, relationship,
                        preference, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [capturedPartId, capturedAlternativePartId, capturedRelationship, capturedPriority, now]
                )
            }
        } catch {
            print("[PartsCompanionsPage] AlternativeFormSheet.save failed: \(error)")
        }
    }
}

// MARK: - Part Picker Item

struct PartPickerItem: Identifiable, Sendable {
    let id: Int64
    let name: String
}
