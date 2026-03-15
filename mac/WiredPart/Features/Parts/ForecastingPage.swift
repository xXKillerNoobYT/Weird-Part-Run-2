import SwiftUI
import GRDB
import WiredPartCore

/// Demand forecasting data page.
///
/// Displays a table of parts with their forecasting metrics: ADU-30, ADU-90,
/// reorder point, target quantity, suggested order, and days until low stock.
/// Sorted by days-until-low ascending (most urgent first) by default.
/// Includes a "Recalculate" button that triggers a forecast refresh.
struct ForecastingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var rows: [ForecastRow] = []
    @State private var isLoading = true
    @State private var isRecalculating = false
    @State private var lastRunDate = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\ForecastRow.daysUntilLow)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadForecasts() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Forecasting")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                if !lastRunDate.isEmpty {
                    Text("Last run: \(lastRunDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(rows.count) parts with forecast data")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                recalculateForecasts()
            } label: {
                if isRecalculating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Recalculate", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRecalculating)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table Content

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading forecast data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No forecast data")
                    .font(.headline)
                Text("Run forecasting to generate demand predictions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedRows, sortOrder: $sortOrder) {
                TableColumn("Part", value: \.name) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .fontWeight(.medium)
                        if !row.code.isEmpty {
                            Text(row.code)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .width(min: 150, ideal: 220)

                TableColumn("ADU-30", value: \.adu30) { row in
                    Text(row.adu30 > 0 ? String(format: "%.2f", row.adu30) : "-")
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 70, ideal: 80)

                TableColumn("ADU-90", value: \.adu90) { row in
                    Text(row.adu90 > 0 ? String(format: "%.2f", row.adu90) : "-")
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 70, ideal: 80)

                TableColumn("Reorder Pt", value: \.reorderPoint) { row in
                    Text(row.reorderPoint > 0 ? "\(row.reorderPoint)" : "-")
                }
                .width(min: 80, ideal: 90)

                TableColumn("Target Qty", value: \.targetQty) { row in
                    Text(row.targetQty > 0 ? "\(row.targetQty)" : "-")
                }
                .width(min: 80, ideal: 90)

                TableColumn("Suggested", value: \.suggestedOrder) { row in
                    if row.suggestedOrder > 0 {
                        Text("\(row.suggestedOrder)")
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 80, ideal: 90)

                TableColumn("Days Until Low", value: \.daysUntilLow) { row in
                    urgencyBadge(days: row.daysUntilLow)
                }
                .width(min: 100, ideal: 120)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedRows: [ForecastRow] {
        rows.sorted(using: sortOrder)
    }

    private func urgencyBadge(days: Int) -> some View {
        let color: Color
        let text: String

        if days <= 0 {
            color = .red
            text = "NOW"
        } else if days <= 7 {
            color = .red
            text = "\(days)d"
        } else if days <= 14 {
            color = .orange
            text = "\(days)d"
        } else if days <= 30 {
            color = .yellow
            text = "\(days)d"
        } else if days == 999 {
            // Sentinel value for "no data"
            return AnyView(Text("-").foregroundStyle(.secondary))
        } else {
            color = .green
            text = "\(days)d"
        }

        return AnyView(
            Text(text)
                .font(.system(.caption, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.15)))
                .foregroundStyle(color)
        )
    }

    // MARK: - Data Loading

    private func loadForecasts() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { conn in
                let dbRows = try Row.fetchAll(
                    conn,
                    sql: """
                        SELECT
                            p.id, COALESCE(p.code, '') AS code, p.name,
                            COALESCE(p.forecast_adu_30, 0) AS adu30,
                            COALESCE(p.forecast_adu_90, 0) AS adu90,
                            COALESCE(p.forecast_reorder_point, 0) AS reorder_point,
                            COALESCE(p.forecast_target_qty, 0) AS target_qty,
                            COALESCE(p.forecast_suggested_order, 0) AS suggested_order,
                            COALESCE(p.forecast_days_until_low, 999) AS days_until_low,
                            p.forecast_last_run
                        FROM parts p
                        WHERE p.deleted_at IS NULL
                          AND (p.forecast_adu_30 IS NOT NULL OR p.forecast_adu_90 IS NOT NULL OR p.forecast_days_until_low IS NOT NULL)
                        ORDER BY COALESCE(p.forecast_days_until_low, 999) ASC
                        LIMIT 500
                        """
                )

                rows = dbRows.map { row in
                    ForecastRow(
                        id: row["id"] ?? 0,
                        code: row["code"] ?? "",
                        name: row["name"] ?? "",
                        adu30: row["adu30"] ?? 0,
                        adu90: row["adu90"] ?? 0,
                        reorderPoint: row["reorder_point"] ?? 0,
                        targetQty: row["target_qty"] ?? 0,
                        suggestedOrder: row["suggested_order"] ?? 0,
                        daysUntilLow: row["days_until_low"] ?? 999
                    )
                }

                // Get most recent forecast run date
                if let dateStr = try String?.fetchOne(
                    conn,
                    sql: "SELECT MAX(forecast_last_run) FROM parts WHERE forecast_last_run IS NOT NULL"
                ) {
                    lastRunDate = dateStr ?? ""
                }
            }
        } catch {
            print("[ForecastingPage] Load error: \(error)")
        }

        isLoading = false
    }

    /// Recalculate forecasts for all parts.
    ///
    /// Computes ADU (Average Daily Usage) over 30 and 90 day windows
    /// based on stock movement history. Updates reorder points, target
    /// quantities, suggested order amounts, and days-until-low estimates.
    private func recalculateForecasts() {
        guard let db = appCore.db else { return }
        isRecalculating = true

        // Run on a background thread to avoid blocking UI
        let writer = db.writer
        Task.detached {
            do {
                try await writer.write { conn in
                    // Compute ADU-30: average daily consumption over last 30 days
                    // from stock movements (outbound movements / 30)
                    try conn.execute(sql: """
                        UPDATE parts SET
                            forecast_adu_30 = COALESCE(
                                (SELECT CAST(SUM(ABS(sm.quantity)) AS REAL) / 30.0
                                 FROM stock_movements sm
                                 WHERE sm.part_id = parts.id
                                   AND sm.movement_type IN ('pull', 'consumption', 'transfer_out')
                                   AND sm.deleted_at IS NULL
                                   AND date(sm.created_at) >= date('now', '-30 days')),
                                0
                            ),
                            forecast_adu_90 = COALESCE(
                                (SELECT CAST(SUM(ABS(sm.quantity)) AS REAL) / 90.0
                                 FROM stock_movements sm
                                 WHERE sm.part_id = parts.id
                                   AND sm.movement_type IN ('pull', 'consumption', 'transfer_out')
                                   AND sm.deleted_at IS NULL
                                   AND date(sm.created_at) >= date('now', '-90 days')),
                                0
                            ),
                            forecast_last_run = datetime('now'),
                            updated_at = datetime('now')
                        WHERE deleted_at IS NULL
                        """)

                    // Compute reorder point: ADU-90 * lead_time_safety_factor (default 7 days)
                    try conn.execute(sql: """
                        UPDATE parts SET
                            forecast_reorder_point = CAST(COALESCE(forecast_adu_90, 0) * 7 AS INTEGER),
                            forecast_target_qty = CAST(COALESCE(forecast_adu_90, 0) * 14 AS INTEGER)
                        WHERE deleted_at IS NULL
                        """)

                    // Compute suggested order: target_qty - current_stock (if positive)
                    try conn.execute(sql: """
                        UPDATE parts SET
                            forecast_suggested_order = MAX(0,
                                COALESCE(forecast_target_qty, 0)
                                - COALESCE(
                                    (SELECT SUM(se.quantity) FROM stock_entries se WHERE se.part_id = parts.id AND se.deleted_at IS NULL),
                                    0
                                )
                            )
                        WHERE deleted_at IS NULL
                        """)

                    // Compute days until low: current_stock / ADU-90 (if ADU > 0)
                    try conn.execute(sql: """
                        UPDATE parts SET
                            forecast_days_until_low = CASE
                                WHEN COALESCE(forecast_adu_90, 0) > 0 THEN
                                    CAST(
                                        COALESCE(
                                            (SELECT SUM(se.quantity) FROM stock_entries se WHERE se.part_id = parts.id AND se.deleted_at IS NULL),
                                            0
                                        ) / forecast_adu_90
                                    AS INTEGER)
                                ELSE 999
                            END
                        WHERE deleted_at IS NULL
                        """)
                }
            } catch {
                print("[ForecastingPage] Recalculate error: \(error)")
            }

            await MainActor.run {
                isRecalculating = false
                loadForecasts()
            }
        }
    }
}

// MARK: - Forecast Row Model

struct ForecastRow: Identifiable {
    let id: Int64
    let code: String
    let name: String
    let adu30: Double
    let adu90: Double
    let reorderPoint: Int
    let targetQty: Int
    let suggestedOrder: Int
    let daysUntilLow: Int
}
