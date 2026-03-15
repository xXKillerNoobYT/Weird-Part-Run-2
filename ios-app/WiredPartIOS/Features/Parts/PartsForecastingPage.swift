import SwiftUI
import GRDB
import WiredPartCore

/// Demand forecasting page showing parts with their forecast data.
///
/// Displays average daily usage (ADU), reorder points, suggested orders,
/// and days until low stock. Color-coded urgency indicators help prioritize
/// reordering decisions.
struct PartsForecastingPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var forecastRows: [ForecastRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var filterUrgency: UrgencyFilter = .all
    @State private var selectedRow: ForecastRow?

    var body: some View {
        VStack(spacing: 0) {
            // Urgency filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(UrgencyFilter.allCases, id: \.self) { filter in
                        Button {
                            withAnimation { filterUrgency = filter }
                        } label: {
                            HStack(spacing: 4) {
                                if filter != .all {
                                    Circle()
                                        .fill(filter.color)
                                        .frame(width: 8, height: 8)
                                }
                                Text(filter.label)
                                    .font(.subheadline)
                                    .fontWeight(filterUrgency == filter ? .semibold : .regular)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(filterUrgency == filter ? Color.accentColor : Color.clear)
                            .foregroundStyle(filterUrgency == filter ? .white : .primary)
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
            .background(Color(.controlBackgroundColor))
            #endif

            if isLoading {
                ProgressView("Loading forecast data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredRows.isEmpty {
                emptyState
            } else {
                forecastList
            }
        }
        .searchable(text: $searchText, prompt: "Search parts...")
        .refreshable { await loadData() }
        .sheet(item: $selectedRow) { row in
            ForecastDetailSheet(row: row)
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
        .task { await loadData() }
    }

    // MARK: - Filtered

    private var filteredRows: [ForecastRow] {
        var result = forecastRows

        switch filterUrgency {
        case .all:
            break
        case .critical:
            result = result.filter { ($0.daysUntilLow ?? 999) <= 7 }
        case .warning:
            result = result.filter {
                let days = $0.daysUntilLow ?? 999
                return days > 7 && days <= 30
            }
        case .healthy:
            result = result.filter { ($0.daysUntilLow ?? 999) > 30 }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                ($0.code?.lowercased().contains(query) ?? false)
            }
        }

        // Sort by urgency (most urgent first)
        result.sort { ($0.daysUntilLow ?? 999) < ($1.daysUntilLow ?? 999) }
        return result
    }

    // MARK: - Forecast List

    @ViewBuilder
    private var forecastList: some View {
        List {
            // Summary stats
            Section {
                HStack(spacing: 16) {
                    statCard(
                        label: "Critical",
                        count: forecastRows.filter { ($0.daysUntilLow ?? 999) <= 7 }.count,
                        color: .red
                    )
                    statCard(
                        label: "Warning",
                        count: forecastRows.filter { let d = $0.daysUntilLow ?? 999; return d > 7 && d <= 30 }.count,
                        color: .orange
                    )
                    statCard(
                        label: "Healthy",
                        count: forecastRows.filter { ($0.daysUntilLow ?? 999) > 30 }.count,
                        color: .green
                    )
                }
            }

            Section("\(filteredRows.count) parts") {
                ForEach(filteredRows) { row in
                    Button {
                        selectedRow = row
                    } label: {
                        forecastRowView(row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder
    private func statCard(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func forecastRowView(_ row: ForecastRow) -> some View {
        HStack(spacing: 12) {
            // Urgency indicator
            Circle()
                .fill(urgencyColor(row.daysUntilLow))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let code = row.code {
                        Text(code)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    if let adu = row.adu30, adu > 0 {
                        Text(String(format: "ADU: %.1f/day", adu))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let days = row.daysUntilLow {
                    Text("\(days)d")
                        .font(.headline)
                        .foregroundStyle(urgencyColor(row.daysUntilLow))
                    Text("until low")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("no data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let suggested = row.suggestedOrder, suggested > 0 {
                    Text("Order \(suggested)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 60)
    }

    private func urgencyColor(_ daysUntilLow: Int?) -> Color {
        guard let days = daysUntilLow else { return .secondary }
        if days <= 7 { return .red }
        if days <= 30 { return .orange }
        return .green
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Forecast Data")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Forecast data is generated from order history and stock movements. Add parts and process orders to see forecasts.")
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
            let db = appCore.db!
            let rows = try await db.writer.read { dbConnection -> [ForecastRow] in
                let results = try Row.fetchAll(dbConnection, sql: """
                    SELECT p.id, p.name, p.code,
                           p.forecast_adu_30, p.forecast_adu_90,
                           p.forecast_reorder_point, p.forecast_target_qty,
                           p.forecast_suggested_order, p.forecast_days_until_low,
                           p.forecast_last_run,
                           p.min_stock_level, p.max_stock_level, p.target_stock_level,
                           p.reorder_point,
                           COALESCE(SUM(se.quantity), 0) AS current_stock
                    FROM parts p
                    LEFT JOIN stock_entries se ON se.part_id = p.id AND se.deleted_at IS NULL
                    WHERE p.deleted_at IS NULL
                    GROUP BY p.id
                    ORDER BY COALESCE(p.forecast_days_until_low, 9999) ASC
                    """)
                return results.map { row in
                    ForecastRow(
                        id: row["id"],
                        name: row["name"],
                        code: row["code"],
                        adu30: row["forecast_adu_30"],
                        adu90: row["forecast_adu_90"],
                        reorderPoint: row["forecast_reorder_point"],
                        targetQty: row["forecast_target_qty"],
                        suggestedOrder: row["forecast_suggested_order"],
                        daysUntilLow: row["forecast_days_until_low"],
                        lastRun: row["forecast_last_run"],
                        minStock: row["min_stock_level"],
                        maxStock: row["max_stock_level"],
                        targetStock: row["target_stock_level"],
                        manualReorderPoint: row["reorder_point"],
                        currentStock: row["current_stock"]
                    )
                }
            }
            await MainActor.run {
                forecastRows = rows
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - Types

private enum UrgencyFilter: CaseIterable {
    case all, critical, warning, healthy

    var label: String {
        switch self {
        case .all: return "All"
        case .critical: return "Critical"
        case .warning: return "Warning"
        case .healthy: return "Healthy"
        }
    }

    var color: Color {
        switch self {
        case .all: return .primary
        case .critical: return .red
        case .warning: return .orange
        case .healthy: return .green
        }
    }
}

struct ForecastRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let code: String?
    let adu30: Double?
    let adu90: Double?
    let reorderPoint: Int?
    let targetQty: Int?
    let suggestedOrder: Int?
    let daysUntilLow: Int?
    let lastRun: String?
    let minStock: Int?
    let maxStock: Int?
    let targetStock: Int?
    let manualReorderPoint: Int?
    let currentStock: Int
}

// MARK: - Forecast Detail Sheet

private struct ForecastDetailSheet: View {
    let row: ForecastRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Part") {
                    LabeledContent("Name", value: row.name)
                    if let code = row.code {
                        LabeledContent("Code", value: code)
                    }
                    LabeledContent("Current Stock", value: "\(row.currentStock)")
                }

                Section("Forecast Metrics") {
                    if let adu30 = row.adu30 {
                        LabeledContent("Avg Daily Usage (30d)", value: String(format: "%.2f", adu30))
                    }
                    if let adu90 = row.adu90 {
                        LabeledContent("Avg Daily Usage (90d)", value: String(format: "%.2f", adu90))
                    }
                    if let rp = row.reorderPoint {
                        LabeledContent("Reorder Point", value: "\(rp)")
                    }
                    if let target = row.targetQty {
                        LabeledContent("Target Qty", value: "\(target)")
                    }
                    if let suggested = row.suggestedOrder {
                        LabeledContent("Suggested Order") {
                            Text("\(suggested)")
                                .fontWeight(.bold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if let days = row.daysUntilLow {
                        LabeledContent("Days Until Low") {
                            Text("\(days)")
                                .fontWeight(.bold)
                                .foregroundStyle(days <= 7 ? .red : days <= 30 ? .orange : .green)
                        }
                    }
                }

                Section("Stock Levels") {
                    if let min = row.minStock {
                        LabeledContent("Min Stock", value: "\(min)")
                    }
                    if let max = row.maxStock {
                        LabeledContent("Max Stock", value: "\(max)")
                    }
                    if let target = row.targetStock {
                        LabeledContent("Target Stock", value: "\(target)")
                    }
                    if let rp = row.manualReorderPoint {
                        LabeledContent("Manual Reorder Point", value: "\(rp)")
                    }
                }

                if let lastRun = row.lastRun {
                    Section("Last Updated") {
                        Text(lastRun)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Forecast Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
