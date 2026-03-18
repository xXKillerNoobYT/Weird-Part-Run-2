import SwiftUI
import GRDB
import WiredPartCore

/// Pricing management page showing parts with their cost, markup, and sell prices.
///
/// Displays a sortable list of parts with pricing details. Supports inline
/// editing of cost and markup percentages, and shows price history.
struct PartsPricingPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var pricingRows: [PricingRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var sortBy: PricingSortOption = .name
    @State private var editingRow: PricingRow?

    var body: some View {
        VStack(spacing: 0) {
            // Sort picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Sort:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(PricingSortOption.allCases, id: \.self) { option in
                        Button {
                            withAnimation { sortBy = option }
                        } label: {
                            Text(option.label)
                                .font(.subheadline)
                                .fontWeight(sortBy == option ? .semibold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(sortBy == option ? Color.accentColor : Color.clear)
                                .foregroundStyle(sortBy == option ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            #if os(iOS)
            .background(Color(.secondarySystemGroupedBackground))
            #elseif os(macOS)
            .background(Color(.secondarySystemGroupedBackground))
            #endif

            if isLoading {
                ProgressView("Loading pricing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sortedParts.isEmpty {
                emptyState
            } else {
                pricingList
            }
        }
        .searchable(text: $searchText, prompt: "Search parts...")
        .refreshable { await loadData() }
        .sheet(item: $editingRow) { row in
            PricingEditSheet(row: row) { await loadData() }
        }
        #if os(iOS)
        .background(DS.Background.page)
        #elseif os(macOS)
        .background(DS.Background.page)
        #endif
        .task { await loadData() }
    }

    // MARK: - Sort & Filter

    private var sortedParts: [PricingRow] {
        var result = pricingRows

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                ($0.code?.lowercased().contains(query) ?? false)
            }
        }

        switch sortBy {
        case .name:
            result.sort { $0.name.lowercased() < $1.name.lowercased() }
        case .costAsc:
            result.sort { $0.costPrice < $1.costPrice }
        case .costDesc:
            result.sort { $0.costPrice > $1.costPrice }
        case .markupDesc:
            result.sort { $0.markupPercent > $1.markupPercent }
        case .sellDesc:
            result.sort { $0.sellPrice > $1.sellPrice }
        }
        return result
    }

    // MARK: - Pricing List

    @ViewBuilder
    private var pricingList: some View {
        List {
            Section {
                Text("\(sortedParts.count) part\(sortedParts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(sortedParts) { row in
                Button {
                    editingRow = row
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            if let code = row.code {
                                Text(code)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Cost:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "$%.2f", row.costPrice))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            HStack(spacing: 4) {
                                Text("Sell:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "$%.2f", row.sellPrice))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                            }
                            Text(String(format: "+%.1f%%", row.markupPercent))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 56)
                }
                .buttonStyle(.plain)
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
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Pricing Data")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Add parts to the catalog to manage pricing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        do {
            guard let db = appCore.db else { return }
            let rows = try await db.writer.read { dbConnection -> [PricingRow] in
                let results = try Row.fetchAll(dbConnection, sql: """
                    SELECT p.id, p.name, p.code, p.company_cost_price, p.company_markup_percent,
                           p.weighted_avg_cost, p.custom_margin_percent, p.cost_last_updated
                    FROM parts p
                    WHERE p.deleted_at IS NULL
                    ORDER BY p.name ASC
                    """)
                return results.map { row in
                    let cost: Double = row["company_cost_price"]
                    let markup: Double = row["company_markup_percent"]
                    return PricingRow(
                        id: row["id"],
                        name: row["name"],
                        code: row["code"],
                        costPrice: cost,
                        markupPercent: markup,
                        sellPrice: cost * (1 + markup / 100),
                        weightedAvgCost: row["weighted_avg_cost"],
                        customMarginPercent: row["custom_margin_percent"],
                        costLastUpdated: row["cost_last_updated"]
                    )
                }
            }
            await MainActor.run {
                pricingRows = rows
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - Sort Options

private enum PricingSortOption: CaseIterable {
    case name, costAsc, costDesc, markupDesc, sellDesc

    var label: String {
        switch self {
        case .name: return "Name"
        case .costAsc: return "Cost ↑"
        case .costDesc: return "Cost ↓"
        case .markupDesc: return "Markup ↓"
        case .sellDesc: return "Sell ↓"
        }
    }
}

// MARK: - Pricing Row

struct PricingRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let code: String?
    let costPrice: Double
    let markupPercent: Double
    let sellPrice: Double
    let weightedAvgCost: Double?
    let customMarginPercent: Double?
    let costLastUpdated: String?
}

// MARK: - Pricing Edit Sheet

private struct PricingEditSheet: View {
    let row: PricingRow
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var costPrice = ""
    @State private var markupPercent = ""

    private var previewSellPrice: Double {
        let cost = Double(costPrice) ?? 0
        let markup = Double(markupPercent) ?? 0
        return cost * (1 + markup / 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Part") {
                    LabeledContent("Name", value: row.name)
                    if let code = row.code {
                        LabeledContent("Code", value: code)
                    }
                }

                Section("Pricing") {
                    HStack {
                        Text("Cost Price")
                        Spacer()
                        Text("$")
                        TextField("0.00", text: $costPrice)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    .frame(minHeight: 44)

                    HStack {
                        Text("Markup")
                        Spacer()
                        TextField("0", text: $markupPercent)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("%")
                    }
                    .frame(minHeight: 44)
                }

                Section("Preview") {
                    LabeledContent("Sell Price") {
                        Text(String(format: "$%.2f", previewSellPrice))
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                    LabeledContent("Profit per Unit") {
                        let cost = Double(costPrice) ?? 0
                        Text(String(format: "$%.2f", previewSellPrice - cost))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                if let wac = row.weightedAvgCost {
                    Section("Cost History") {
                        LabeledContent("Weighted Avg Cost", value: String(format: "$%.2f", wac))
                        if let lastUpdated = row.costLastUpdated {
                            LabeledContent("Last Updated", value: lastUpdated)
                        }
                    }
                }
            }
            .navigationTitle("Edit Pricing")
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
                }
            }
            .onAppear {
                costPrice = String(format: "%.2f", row.costPrice)
                markupPercent = String(format: "%.1f", row.markupPercent)
            }
        }
    }

    private func save() async {
        let cost = Double(costPrice) ?? row.costPrice
        let markup = Double(markupPercent) ?? row.markupPercent
        do {
            guard let db = appCore.db else { return }
            let now = ISO8601DateFormatter().string(from: Date())
            try await db.writer.write { dbConnection in
                try dbConnection.execute(
                    sql: """
                        UPDATE parts SET company_cost_price = ?, company_markup_percent = ?,
                        cost_last_updated = ?, updated_at = ? WHERE id = ?
                        """,
                    arguments: [cost, markup, now, now, row.id]
                )
            }
        } catch {
            print("[PricingEditSheet] Save error: \(error)")
        }
    }
}
