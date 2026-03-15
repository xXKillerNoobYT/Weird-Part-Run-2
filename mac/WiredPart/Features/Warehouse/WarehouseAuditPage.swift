import SwiftUI
import GRDB
import WiredPartCore

/// Warehouse audit page for physical inventory counts.
///
/// Supports starting new audits, tracking counting progress, viewing
/// discrepancies between physical counts and system quantities,
/// and showing summary statistics.
struct WarehouseAuditPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var auditItems: [AuditItemRow] = []
    @State private var isLoading = true
    @State private var isAuditActive = false

    // MARK: - Audit State

    @State private var totalParts = 0
    @State private var countedParts = 0
    @State private var discrepancyCount = 0

    // MARK: - Filters

    @State private var searchText = ""
    @State private var showOnlyDiscrepancies = false

    // MARK: - Confirm

    @State private var showStartConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                summaryCards
                auditContent
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
        .alert("Start New Audit", isPresented: $showStartConfirm) {
            Button("Start Audit") { startNewAudit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Start a new physical inventory audit? This will create count entries for all active parts with stock.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Inventory Audit")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                if isAuditActive {
                    Text("Audit in progress - \(countedParts) of \(totalParts) counted")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Physical inventory verification")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            Toggle("Discrepancies Only", isOn: $showOnlyDiscrepancies)
                .toggleStyle(.switch)
                .onChange(of: showOnlyDiscrepancies) { _, _ in filterItems() }

            TextField("Search parts...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onChange(of: searchText) { _, _ in filterItems() }

            Button {
                showStartConfirm = true
            } label: {
                Label("Start New Audit", systemImage: "checkmark.shield")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ], spacing: 16) {
            summaryCard(
                title: "Total Parts",
                value: "\(totalParts)",
                icon: "shippingbox",
                color: .blue
            )
            summaryCard(
                title: "Counted",
                value: "\(countedParts)",
                icon: "checkmark.circle",
                color: .green
            )
            summaryCard(
                title: "Completion",
                value: totalParts > 0 ? "\(Int(Double(countedParts) / Double(totalParts) * 100))%" : "0%",
                icon: "chart.pie",
                color: .purple
            )
            summaryCard(
                title: "Discrepancies",
                value: "\(discrepancyCount)",
                icon: "exclamationmark.triangle",
                color: discrepancyCount > 0 ? .red : .green
            )
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: totalParts > 0 ? Double(countedParts) / Double(totalParts) : 0)
                .progressViewStyle(.linear)
                .tint(countedParts == totalParts && totalParts > 0 ? .green : Color.accentColor)

            HStack {
                Text("\(countedParts) of \(totalParts) parts counted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if discrepancyCount > 0 {
                    Text("\(discrepancyCount) discrepanc\(discrepancyCount == 1 ? "y" : "ies") found")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Audit Content

    @ViewBuilder
    private var auditContent: some View {
        progressBar

        if isLoading {
            ProgressView("Loading audit data...")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        } else if auditItems.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No audit data")
                    .font(.headline)
                Text("Start a new audit to begin counting inventory.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            // Header
            HStack {
                Text("Part")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("System Qty")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 90)
                Text("Counted")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 90)
                Text("Difference")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 90)
                Text("Status")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 90)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            LazyVStack(spacing: 6) {
                ForEach(filteredItems, id: \.id) { item in
                    auditItemCard(item)
                }
            }
        }
    }

    private var filteredItems: [AuditItemRow] {
        var items = auditItems
        let trimmed = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !trimmed.isEmpty {
            items = items.filter {
                $0.partName.lowercased().contains(trimmed) || $0.partCode.lowercased().contains(trimmed)
            }
        }
        if showOnlyDiscrepancies {
            items = items.filter { $0.difference != 0 }
        }
        return items
    }

    private func auditItemCard(_ item: AuditItemRow) -> some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.partName)
                        .font(.callout)
                        .fontWeight(.medium)
                    if !item.partCode.isEmpty {
                        Text(item.partCode)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(item.systemQty)")
                    .font(.callout)
                    .frame(width: 90)

                // Editable counted field
                TextField("", value: Binding(
                    get: { item.countedQty },
                    set: { newValue in updateCount(itemId: item.id, count: newValue) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .multilineTextAlignment(.center)

                // Difference
                Text(item.difference > 0 ? "+\(item.difference)" : "\(item.difference)")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(item.difference == 0 ? Color.green : Color.red)
                    .frame(width: 90)

                // Status badge
                auditStatusBadge(item)
                    .frame(width: 90)
            }
            .padding(.vertical, 2)
        }
    }

    private func auditStatusBadge(_ item: AuditItemRow) -> some View {
        let (label, color): (String, Color) = {
            if !item.isCounted { return ("Pending", .gray) }
            if item.difference == 0 { return ("Match", .green) }
            return ("Mismatch", .red)
        }()

        return Text(label)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Actions

    private func startNewAudit() {
        guard let db = appCore.db else { return }

        do {
            try db.writer.write { conn in
                // Clear any existing audit data (simple in-memory approach)
                // In a real implementation this would use a dedicated audit_sessions table
                try conn.execute(sql: "DELETE FROM _audit_counts WHERE 1=1")
            }
        } catch {
            // Table may not exist, which is fine — we'll create it
        }

        do {
            try db.writer.write { conn in
                // Create audit counts table if it doesn't exist
                try conn.execute(sql: """
                    CREATE TABLE IF NOT EXISTS _audit_counts (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        part_id INTEGER NOT NULL,
                        system_qty INTEGER NOT NULL DEFAULT 0,
                        counted_qty INTEGER,
                        counted_at TEXT,
                        created_at TEXT DEFAULT (datetime('now')),
                        UNIQUE(part_id)
                    )
                    """)

                // Clear previous audit data
                try conn.execute(sql: "DELETE FROM _audit_counts")

                // Populate with all active parts that have stock
                try conn.execute(sql: """
                    INSERT INTO _audit_counts (part_id, system_qty)
                    SELECT p.id,
                           COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0)
                    FROM parts p
                    WHERE p.deleted_at IS NULL
                    ORDER BY p.name ASC
                    """)
            }
            isAuditActive = true
        } catch {
            print("[AuditPage] Start audit error: \(error)")
        }

        loadData()
    }

    private func updateCount(itemId: Int64, count: Int) {
        guard let db = appCore.db else { return }
        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "UPDATE _audit_counts SET counted_qty = ?, counted_at = datetime('now') WHERE id = ?",
                    arguments: [count, itemId]
                )
            }
            loadData()
        } catch {
            print("[AuditPage] Update count error: \(error)")
        }
    }

    private func filterItems() {
        // filteredItems is a computed property, so this just triggers a view update
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { conn in
                // Check if audit table exists
                let tableExists = try Int.fetchOne(conn, sql: """
                    SELECT COUNT(*) FROM sqlite_master
                    WHERE type='table' AND name='_audit_counts'
                    """) ?? 0

                guard tableExists > 0 else {
                    auditItems = []
                    totalParts = 0
                    countedParts = 0
                    discrepancyCount = 0
                    isAuditActive = false
                    isLoading = false
                    return
                }

                let rows = try Row.fetchAll(conn, sql: """
                    SELECT ac.id, ac.part_id, ac.system_qty, ac.counted_qty, ac.counted_at,
                           COALESCE(p.name, 'Unknown Part') AS part_name,
                           COALESCE(p.code, '') AS part_code
                    FROM _audit_counts ac
                    LEFT JOIN parts p ON p.id = ac.part_id
                    ORDER BY p.name ASC
                    """)

                auditItems = rows.map { row in
                    let systemQty: Int = row["system_qty"] ?? 0
                    let countedQty: Int? = row["counted_qty"]
                    let isCounted = countedQty != nil
                    let diff = (countedQty ?? systemQty) - systemQty

                    return AuditItemRow(
                        id: row["id"] ?? 0,
                        partId: row["part_id"] ?? 0,
                        partName: row["part_name"] ?? "Unknown",
                        partCode: row["part_code"] ?? "",
                        systemQty: systemQty,
                        countedQty: countedQty ?? systemQty,
                        difference: diff,
                        isCounted: isCounted,
                        countedAt: row["counted_at"]
                    )
                }

                totalParts = auditItems.count
                countedParts = auditItems.filter { $0.isCounted }.count
                discrepancyCount = auditItems.filter { $0.isCounted && $0.difference != 0 }.count
                isAuditActive = totalParts > 0
            }
        } catch {
            print("[AuditPage] Load error: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Display Models

private struct AuditItemRow: Identifiable {
    let id: Int64
    let partId: Int64
    let partName: String
    let partCode: String
    let systemQty: Int
    let countedQty: Int
    let difference: Int
    let isCounted: Bool
    let countedAt: String?
}
