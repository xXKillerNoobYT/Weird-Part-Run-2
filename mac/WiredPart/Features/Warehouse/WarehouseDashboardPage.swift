import SwiftUI
import GRDB
import WiredPartCore

/// Warehouse dashboard showing KPI cards, recent activity feed, and quick actions.
///
/// Displays total stock units, stock health percentage, shortfall count,
/// and pending tasks. Shows the most recent 20 movements with performer
/// name, movement type, and quantity. Provides quick action buttons for
/// common warehouse operations.
struct WarehouseDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var totalStock: Int = 0
    @State private var healthPercent: Int = 100
    @State private var shortfallCount: Int = 0
    @State private var todayMovements: Int = 0
    @State private var pendingStagingCount: Int = 0
    @State private var pendingReceivingCount: Int = 0
    @State private var recentMovements: [MovementDisplayRow] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                kpiCards
                quickActions
                recentActivitySection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Warehouse Dashboard")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Stock overview and recent activity")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - KPI Cards

    private var kpiCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ], spacing: 16) {
            kpiCard(
                title: "Total Stock Units",
                value: "\(totalStock)",
                icon: "shippingbox.fill",
                color: .blue
            )
            kpiCard(
                title: "Stock Health",
                value: "\(healthPercent)%",
                icon: "heart.fill",
                color: healthPercent >= 80 ? .green : healthPercent >= 50 ? .orange : .red
            )
            kpiCard(
                title: "Shortfalls",
                value: "\(shortfallCount)",
                icon: "exclamationmark.triangle.fill",
                color: shortfallCount > 0 ? .red : .green
            )
            kpiCard(
                title: "Today's Movements",
                value: "\(todayMovements)",
                icon: "arrow.left.arrow.right",
                color: .purple
            )
        }
    }

    private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 12) {
                quickActionButton(
                    label: "New Movement",
                    icon: "arrow.left.arrow.right",
                    color: .blue
                )
                quickActionButton(
                    label: "Start Receiving",
                    icon: "shippingbox.and.arrow.backward",
                    color: .green
                )
                quickActionButton(
                    label: "View Staging",
                    icon: "tray.2",
                    color: .orange
                )
                Spacer()
            }
        }
    }

    private func quickActionButton(label: String, icon: String, color: Color) -> some View {
        Button {
            // Navigation is handled by the tab bar — these are informational placeholders
        } label: {
            Label(label, systemImage: icon)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    // MARK: - Pending Tasks

    private var pendingTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pending Tasks")
                .font(.headline)

            if pendingStagingCount == 0 && pendingReceivingCount == 0 {
                Text("No pending tasks")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                if pendingStagingCount > 0 {
                    HStack {
                        Image(systemName: "tray.2.fill")
                            .foregroundStyle(.orange)
                        Text("\(pendingStagingCount) staging tag\(pendingStagingCount == 1 ? "" : "s") awaiting action")
                            .font(.callout)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                if pendingReceivingCount > 0 {
                    HStack {
                        Image(systemName: "shippingbox.and.arrow.backward.fill")
                            .foregroundStyle(.blue)
                        Text("\(pendingReceivingCount) receiving session\(pendingReceivingCount == 1 ? "" : "s") in progress")
                            .font(.callout)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Recent Activity

    @ViewBuilder
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                Text("\(recentMovements.count) movement\(recentMovements.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            pendingTasksSection

            if isLoading {
                ProgressView("Loading activity...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if recentMovements.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No recent movements")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(recentMovements, id: \.id) { movement in
                        movementRow(movement)
                    }
                }
            }
        }
    }

    private func movementRow(_ movement: MovementDisplayRow) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: movementTypeIcon(movement.movementType))
                    .font(.title3)
                    .foregroundStyle(movementTypeColor(movement.movementType))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(movement.partName)
                        .font(.callout)
                        .fontWeight(.medium)
                    HStack(spacing: 8) {
                        Text(movement.movementType.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(movementTypeColor(movement.movementType).opacity(0.15))
                            .foregroundStyle(movementTypeColor(movement.movementType))
                            .clipShape(Capsule())
                        if let performer = movement.performerName {
                            Text(performer)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(movement.qty > 0 ? "+\(movement.qty)" : "\(movement.qty)")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(movement.qty > 0 ? .green : .red)

                    if let locationDesc = movement.locationDescription {
                        Text(locationDesc)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(formatDate(movement.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Helpers

    nonisolated private func movementTypeIcon(_ type: String) -> String {
        switch type {
        case "transfer": return "arrow.left.arrow.right"
        case "consume": return "flame"
        case "return": return "arrow.uturn.backward"
        case "receive": return "shippingbox.and.arrow.backward"
        case "adjust": return "plusminus"
        default: return "arrow.left.arrow.right"
        }
    }

    nonisolated private func movementTypeColor(_ type: String) -> Color {
        switch type {
        case "transfer": return .blue
        case "consume": return .orange
        case "return": return .purple
        case "receive": return .green
        case "adjust": return .gray
        default: return .blue
        }
    }

    nonisolated private func formatDate(_ dateStr: String?) -> String {
        guard let dateStr else { return "-" }
        // Show just date and time portion
        if dateStr.count >= 16 {
            return String(dateStr.prefix(16))
        }
        return dateStr
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            // Load KPIs
            if let service = appCore.warehouseService {
                let kpi = try service.getWarehouseKPIs()
                totalStock = kpi.totalStock
                healthPercent = kpi.stockHealthPercent
                shortfallCount = kpi.shortfallCount
                todayMovements = kpi.todayMovements
            }

            // Load pending counts
            try db.writer.read { conn in
                pendingStagingCount = try Int.fetchOne(
                    conn,
                    sql: "SELECT COUNT(*) FROM pulled_staging_tags WHERE deleted_at IS NULL"
                ) ?? 0
            }

            try db.writer.read { conn in
                pendingReceivingCount = try Int.fetchOne(
                    conn,
                    sql: "SELECT COUNT(*) FROM receiving_sessions WHERE status = 'in_progress' AND deleted_at IS NULL"
                ) ?? 0
            }

            // Load recent movements
            try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT sm.id, sm.part_id, sm.qty, sm.movement_type,
                           sm.from_location_type, sm.to_location_type,
                           sm.created_at, sm.notes,
                           COALESCE(p.name, 'Unknown Part') AS part_name,
                           u.display_name AS performer_name
                    FROM stock_movements sm
                    LEFT JOIN parts p ON p.id = sm.part_id
                    LEFT JOIN users u ON u.id = sm.performed_by
                    WHERE sm.deleted_at IS NULL
                    ORDER BY sm.created_at DESC
                    LIMIT 20
                    """)

                recentMovements = rows.map { row in
                    let fromLoc: String? = row["from_location_type"]
                    let toLoc: String? = row["to_location_type"]
                    var locDesc: String?
                    if let from = fromLoc, let to = toLoc {
                        locDesc = "\(from) -> \(to)"
                    } else if let to = toLoc {
                        locDesc = "-> \(to)"
                    } else if let from = fromLoc {
                        locDesc = "\(from) ->"
                    }

                    return MovementDisplayRow(
                        id: row["id"] ?? 0,
                        partName: row["part_name"] ?? "Unknown",
                        qty: row["qty"] ?? 0,
                        movementType: row["movement_type"] ?? "transfer",
                        performerName: row["performer_name"],
                        locationDescription: locDesc,
                        createdAt: row["created_at"]
                    )
                }
            }
        } catch {
            print("[WarehouseDashboard] Load error: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Display Models

private struct MovementDisplayRow: Identifiable {
    let id: Int64
    let partName: String
    let qty: Int
    let movementType: String
    let performerName: String?
    let locationDescription: String?
    let createdAt: String?
}
