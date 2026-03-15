import SwiftUI
import GRDB
import WiredPartCore

/// Pricing management page with inline cost and markup editing.
///
/// Permission-gated — requires "show_dollar_values". Shows a searchable table
/// of parts with cost price, markup %, and calculated sell price. Users can
/// edit cost and markup inline and save changes per-row.
struct PricingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var rows: [PricingRow] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Inline Editing

    @State private var editingId: Int64?
    @State private var editCost = ""
    @State private var editMarkup = ""
    @State private var showSaved = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if !appCore.hasPermission("show_dollar_values") {
                permissionDenied
            } else {
                tableContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadPricing() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Pricing")
                .font(.largeTitle)
                .fontWeight(.bold)

            if showSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .transition(.opacity)
            }

            Spacer()

            TextField("Search parts...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)
                .onChange(of: searchText) { _, _ in loadPricing() }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Permission Denied

    private var permissionDenied: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Access Restricted")
                .font(.headline)
            Text("You need the \"Show Dollar Values\" permission to view pricing.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Table Content

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading pricing data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No parts found")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    // Table header
                    HStack(spacing: 0) {
                        headerCell("Code", width: 100)
                        headerCell("Name", width: nil)
                        headerCell("Cost Price", width: 120)
                        headerCell("Markup %", width: 100)
                        headerCell("Sell Price", width: 120)
                        headerCell("", width: 60) // Actions
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))

                    Divider()

                    // Data rows
                    LazyVStack(spacing: 0) {
                        ForEach(rows, id: \.id) { row in
                            pricingRowView(row)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func headerCell(_ title: String, width: CGFloat?) -> some View {
        Group {
            if let width {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: width, alignment: .leading)
            } else {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func pricingRowView(_ row: PricingRow) -> some View {
        let isEditing = editingId == row.id

        return HStack(spacing: 0) {
            Text(row.code)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(row.name)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isEditing {
                TextField("Cost", text: $editCost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                TextField("Markup", text: $editMarkup)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            } else {
                Text(String(format: "$%.2f", row.costPrice))
                    .frame(width: 120, alignment: .leading)
                    .foregroundStyle(.secondary)

                Text(String(format: "%.0f%%", row.markupPercent))
                    .frame(width: 100, alignment: .leading)
                    .foregroundStyle(.secondary)
            }

            Text(String(format: "$%.2f", isEditing ? calculatedSell : row.sellPrice))
                .frame(width: 120, alignment: .leading)
                .fontWeight(.medium)

            // Actions
            Group {
                if isEditing {
                    HStack(spacing: 4) {
                        Button {
                            savePricing(row)
                        } label: {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)

                        Button {
                            editingId = nil
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        editingId = row.id
                        editCost = String(format: "%.2f", row.costPrice)
                        editMarkup = String(format: "%.0f", row.markupPercent)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 60)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(isEditing ? Color.accentColor.opacity(0.05) : Color.clear)
    }

    private var calculatedSell: Double {
        let cost = Double(editCost) ?? 0
        let markup = Double(editMarkup) ?? 0
        return cost * (1 + markup / 100)
    }

    // MARK: - Data Loading

    private func loadPricing() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { conn in
                var sql = """
                    SELECT id, COALESCE(code, '-') AS code, name, company_cost_price, company_markup_percent
                    FROM parts
                    WHERE deleted_at IS NULL
                    """
                var args: [DatabaseValueConvertible?] = []

                let trimmed = searchText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    sql += " AND (name LIKE ? OR code LIKE ?)"
                    let like = "%\(trimmed)%"
                    args.append(like)
                    args.append(like)
                }

                sql += " ORDER BY name ASC LIMIT 500"

                let dbRows = try Row.fetchAll(conn, sql: sql, arguments: StatementArguments(args) ?? StatementArguments())
                rows = dbRows.map { row in
                    let cost: Double = row["company_cost_price"] ?? 0
                    let markup: Double = row["company_markup_percent"] ?? 0
                    return PricingRow(
                        id: row["id"] ?? 0,
                        code: row["code"] ?? "-",
                        name: row["name"] ?? "",
                        costPrice: cost,
                        markupPercent: markup,
                        sellPrice: cost * (1 + markup / 100)
                    )
                }
            }
        } catch {
            print("[PricingPage] Load error: \(error)")
        }

        isLoading = false
    }

    private func savePricing(_ row: PricingRow) {
        guard let db = appCore.db else { return }
        guard let cost = Double(editCost), let markup = Double(editMarkup) else { return }

        do {
            try db.writer.write { conn in
                try conn.execute(
                    sql: """
                        UPDATE parts SET
                            company_cost_price = ?,
                            company_markup_percent = ?,
                            cost_last_updated = datetime('now'),
                            updated_at = datetime('now')
                        WHERE id = ?
                        """,
                    arguments: [cost, markup, row.id]
                )
            }
        } catch {
            print("[PricingPage] Save error: \(error)")
        }

        editingId = nil
        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSaved = false }
        }
        loadPricing()
    }
}

// MARK: - Pricing Row Model

private struct PricingRow: Identifiable {
    let id: Int64
    let code: String
    let name: String
    let costPrice: Double
    let markupPercent: Double
    let sellPrice: Double
}
