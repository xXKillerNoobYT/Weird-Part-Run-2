import SwiftUI
import GRDB
import WiredPartCore

/// Warehouse dashboard showing KPI cards, recent activity, and quick actions.
///
/// Displays total stock, stock health percentage, shortfall count,
/// and today's movement count as headline cards. Below the cards is a
/// recent activity feed pulled from the last 10 stock movements, plus
/// quick action buttons for common warehouse tasks.
struct WarehouseDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var kpis: WarehouseService.WarehouseKPI?
    @State private var recentMovements: [WarehouseService.MovementRow] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading warehouse...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                dashboardContent
            }
        }
        .refreshable { await loadData() }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
        .task { await loadData() }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // KPI Cards
                kpiSection

                // Quick Actions
                quickActionsSection

                // Recent Activity
                recentActivitySection
            }
            .padding()
        }
    }

    // MARK: - KPI Cards

    @ViewBuilder
    private var kpiSection: some View {
        let currentKPIs = kpis ?? WarehouseService.WarehouseKPI(
            totalStock: 0, stockHealthPercent: 100, shortfallCount: 0, todayMovements: 0
        )

        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            kpiCard(
                title: "Total Stock",
                value: "\(currentKPIs.totalStock)",
                icon: "shippingbox.fill",
                color: .blue
            )
            kpiCard(
                title: "Stock Health",
                value: "\(currentKPIs.stockHealthPercent)%",
                icon: "heart.fill",
                color: currentKPIs.stockHealthPercent >= 80 ? .green :
                       currentKPIs.stockHealthPercent >= 50 ? .orange : .red
            )
            kpiCard(
                title: "Shortfalls",
                value: "\(currentKPIs.shortfallCount)",
                icon: "exclamationmark.triangle.fill",
                color: currentKPIs.shortfallCount > 0 ? .red : .green
            )
            kpiCard(
                title: "Today's Moves",
                value: "\(currentKPIs.todayMovements)",
                icon: "arrow.left.arrow.right",
                color: .purple
            )
        }
    }

    @ViewBuilder
    private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.headline)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                quickActionButton(
                    title: "New Movement",
                    icon: "arrow.left.arrow.right.circle.fill",
                    color: .blue
                )
                quickActionButton(
                    title: "Scan QR",
                    icon: "qrcode.viewfinder",
                    color: .orange
                )
            }
        }
    }

    @ViewBuilder
    private func quickActionButton(title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recent Activity

    @ViewBuilder
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity")
                .font(.headline)
                .padding(.horizontal, 4)

            if recentMovements.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No recent movements")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                #if os(iOS)
                .background(Color(.secondarySystemGroupedBackground))
                #elseif os(macOS)
                .background(Color(.controlBackgroundColor))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentMovements.enumerated()), id: \.element.id) { index, movement in
                        movementActivityRow(movement)

                        if index < recentMovements.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                #if os(iOS)
                .background(Color(.secondarySystemGroupedBackground))
                #elseif os(macOS)
                .background(Color(.controlBackgroundColor))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func movementActivityRow(_ movement: WarehouseService.MovementRow) -> some View {
        HStack(spacing: 12) {
            // Movement type icon
            Image(systemName: movementIcon(movement.movementType))
                .font(.body)
                .foregroundStyle(movementColor(movement.movementType))
                .frame(width: 32, height: 32)
                #if os(iOS)
                .background(movementColor(movement.movementType).opacity(0.12))
                #elseif os(macOS)
                .background(movementColor(movement.movementType).opacity(0.12))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(movement.partName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(movementLabel(movement.movementType))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let from = movement.fromLocationType, let to = movement.toLocationType {
                        Text("\(from.capitalized) -> \(to.capitalized)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(movement.qty)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(formatDate(movement.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        do {
            guard let service = appCore.warehouseService else {
                await MainActor.run { isLoading = false }
                return
            }
            let fetchedKPIs = try service.getWarehouseKPIs()
            let fetchedMovements = try service.listMovements(limit: 10)
            await MainActor.run {
                kpis = fetchedKPIs
                recentMovements = fetchedMovements
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    // MARK: - Helpers

    private func movementIcon(_ type: String) -> String {
        switch type {
        case "transfer": return "arrow.left.arrow.right"
        case "receive": return "arrow.down.circle"
        case "consume": return "flame"
        case "return_to_supplier": return "arrow.uturn.left"
        case "adjustment": return "plus.forwardslash.minus"
        default: return "arrow.left.arrow.right"
        }
    }

    private func movementColor(_ type: String) -> Color {
        switch type {
        case "transfer": return .blue
        case "receive": return .green
        case "consume": return .orange
        case "return_to_supplier": return .purple
        case "adjustment": return .gray
        default: return .blue
        }
    }

    private func movementLabel(_ type: String) -> String {
        switch type {
        case "transfer": return "Transfer"
        case "receive": return "Received"
        case "consume": return "Consumed"
        case "return_to_supplier": return "Returned"
        case "adjustment": return "Adjustment"
        default: return type.capitalized
        }
    }

    private func formatDate(_ dateStr: String?) -> String {
        guard let dateStr else { return "" }
        // Show just the date portion for compactness
        if dateStr.count >= 10 {
            return String(dateStr.prefix(10))
        }
        return dateStr
    }
}
