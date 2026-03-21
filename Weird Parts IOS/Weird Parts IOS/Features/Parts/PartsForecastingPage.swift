import SwiftUI
import WiredPartCore

/// Demand forecasting page showing parts with their forecast data.
///
/// Displays average daily usage (ADU), reorder points, suggested orders,
/// and days until low stock. Color-coded urgency indicators help prioritize
/// reordering decisions. Trend arrows compare ADU-30 vs ADU-90.
struct PartsForecastingPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var forecastRows: [PartsService.ForecastDataRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var filterUrgency: UrgencyFilter = .all
    @State private var selectedRow: PartsService.ForecastDataRow?
    @State private var isRecalculating = false

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
            .background(Color(.secondarySystemGroupedBackground))

            if isLoading {
                ProgressView("Loading forecast data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await recalculateForecasts() }
                } label: {
                    if isRecalculating {
                        ProgressView()
                    } else {
                        Label("Recalculate", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isRecalculating)
            }
        }
        .background(DS.Background.page)
        .task { await loadData() }
    }

    // MARK: - Filtered

    private var filteredRows: [PartsService.ForecastDataRow] {
        var result = forecastRows

        switch filterUrgency {
        case .all:
            break
        case .critical:
            result = result.filter { ($0.part.forecastDaysUntilLow ?? 999) <= 7 }
        case .warning:
            result = result.filter {
                let days = $0.part.forecastDaysUntilLow ?? 999
                return days > 7 && days <= 30
            }
        case .healthy:
            result = result.filter { ($0.part.forecastDaysUntilLow ?? 999) > 30 }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.part.name.lowercased().contains(query) ||
                ($0.part.code?.lowercased().contains(query) ?? false)
            }
        }

        // Sort by urgency (most urgent first)
        result.sort { ($0.part.forecastDaysUntilLow ?? 999) < ($1.part.forecastDaysUntilLow ?? 999) }
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
                        count: forecastRows.filter { ($0.part.forecastDaysUntilLow ?? 999) <= 7 }.count,
                        color: .red
                    )
                    statCard(
                        label: "Warning",
                        count: forecastRows.filter { let d = $0.part.forecastDaysUntilLow ?? 999; return d > 7 && d <= 30 }.count,
                        color: .orange
                    )
                    statCard(
                        label: "Healthy",
                        count: forecastRows.filter { ($0.part.forecastDaysUntilLow ?? 999) > 30 }.count,
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

            // Last recalculated timestamp
            if let lastRun = forecastRows.first(where: { $0.part.forecastLastRun != nil })?.part.forecastLastRun {
                Section {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("Last recalculated: \(formatTimestamp(lastRun))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
    private func forecastRowView(_ row: PartsService.ForecastDataRow) -> some View {
        HStack(spacing: 12) {
            // Urgency indicator
            Circle()
                .fill(urgencyColor(row.part.forecastDaysUntilLow))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.part.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let code = row.part.code {
                        Text(code)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        if let adu = row.part.forecastAdu30, adu > 0 {
                            Text(String(format: "ADU: %.1f/day", adu))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        trendIndicator(adu30: row.part.forecastAdu30, adu90: row.part.forecastAdu90)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let days = row.part.forecastDaysUntilLow {
                    Text("\(days)d")
                        .font(.headline)
                        .foregroundStyle(urgencyColor(row.part.forecastDaysUntilLow))
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

                if let suggested = row.part.forecastSuggestedOrder, suggested > 0 {
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

    // MARK: - Trend Indicator

    @ViewBuilder
    private func trendIndicator(adu30: Double?, adu90: Double?) -> some View {
        if let short = adu30, let long = adu90, long > 0 {
            let ratio = short / long
            if ratio > 1.15 {
                // Usage trending up (30-day > 90-day by 15%+)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if ratio < 0.85 {
                // Usage trending down
                Image(systemName: "arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                // Stable
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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
        loadError = nil
        do {
            guard let service = appCore.partsService else {
                loadError = "Parts service not available"
                isLoading = false
                return
            }
            let rows = try service.listForecastDataWithStock()
            await MainActor.run {
                forecastRows = rows
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    @Sendable
    private func recalculateForecasts() async {
        isRecalculating = true
        do {
            guard let service = appCore.partsService else { return }
            try service.recalculateForecasts()
            await loadData()
        } catch {
            await MainActor.run {
                loadError = "Recalculation failed: \(error.localizedDescription)"
            }
        }
        await MainActor.run {
            isRecalculating = false
        }
    }

    // MARK: - Helpers

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return iso
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

// MARK: - Identifiable conformance for ForecastDataRow

extension PartsService.ForecastDataRow: Identifiable {
    public var id: Int64 { part.id ?? 0 }
}

// MARK: - Forecast Detail Sheet

private struct ForecastDetailSheet: View {
    let row: PartsService.ForecastDataRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Part") {
                    LabeledContent("Name", value: row.part.name)
                    if let code = row.part.code {
                        LabeledContent("Code", value: code)
                    }
                    LabeledContent("Current Stock", value: "\(row.currentStock)")
                }

                Section("Forecast Metrics") {
                    if let adu30 = row.part.forecastAdu30 {
                        LabeledContent("Avg Daily Usage (30d)", value: String(format: "%.2f", adu30))
                    }
                    if let adu90 = row.part.forecastAdu90 {
                        LabeledContent("Avg Daily Usage (90d)", value: String(format: "%.2f", adu90))
                    }
                    // Trend row
                    if let adu30 = row.part.forecastAdu30, let adu90 = row.part.forecastAdu90, adu90 > 0 {
                        let ratio = adu30 / adu90
                        LabeledContent("Usage Trend") {
                            HStack(spacing: 4) {
                                if ratio > 1.15 {
                                    Image(systemName: "arrow.up.right")
                                        .foregroundStyle(.red)
                                    Text("Increasing")
                                        .foregroundStyle(.red)
                                } else if ratio < 0.85 {
                                    Image(systemName: "arrow.down.right")
                                        .foregroundStyle(.green)
                                    Text("Decreasing")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                    Text("Stable")
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                    if let rp = row.part.forecastReorderPoint {
                        LabeledContent("Reorder Point", value: "\(rp)")
                    }
                    if let target = row.part.forecastTargetQty {
                        LabeledContent("Target Qty", value: "\(target)")
                    }
                    if let suggested = row.part.forecastSuggestedOrder {
                        LabeledContent("Suggested Order") {
                            Text("\(suggested)")
                                .fontWeight(.bold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if let days = row.part.forecastDaysUntilLow {
                        LabeledContent("Days Until Low") {
                            Text("\(days)")
                                .fontWeight(.bold)
                                .foregroundStyle(days <= 7 ? .red : days <= 30 ? .orange : .green)
                        }
                    }
                }

                Section("Stock Levels") {
                    if let min = row.part.minStockLevel {
                        LabeledContent("Min Stock", value: "\(min)")
                    }
                    if let max = row.part.maxStockLevel {
                        LabeledContent("Max Stock", value: "\(max)")
                    }
                    if let target = row.part.targetStockLevel {
                        LabeledContent("Target Stock", value: "\(target)")
                    }
                    if let rp = row.part.reorderPoint {
                        LabeledContent("Manual Reorder Point", value: "\(rp)")
                    }
                }

                if let lastRun = row.part.forecastLastRun {
                    Section("Last Updated") {
                        Text(lastRun)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Forecast Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
