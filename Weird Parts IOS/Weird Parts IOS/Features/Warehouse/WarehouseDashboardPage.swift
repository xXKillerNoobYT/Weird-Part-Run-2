import SwiftUI
import WiredPartCore

/// Warehouse dashboard showing KPI smart cards, recent activity, and quick actions.
///
/// Smart cards act as toggle filters for the activity feed:
/// Movements Today, Receiving Active, Audit Due, Staging Ready.
/// Quick actions open movement wizard and QR scanner as sheets.
struct WarehouseDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var dashKPIs: WarehouseService.DashboardKPIs?
    @State private var auditSummary: WarehouseService.AuditSummary?
    @State private var recentMovements: [WarehouseService.MovementRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedFilter: DashboardFilter?
    @State private var activeSheet: ActiveSheet?

    private enum DashboardFilter: String, CaseIterable {
        case movements = "Movements Today"
        case receiving = "Receiving Active"
        case auditDue = "Audit Due"
        case staging = "Staging Ready"
    }

    private enum ActiveSheet: Identifiable {
        case newMovement
        case qrScanner

        var id: String { String(describing: self) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading warehouse...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                dashboardContent
            }
        }
        .refreshable { loadData() }
        .background(DS.Background.page)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .task { loadData() }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .newMovement:
            NavigationStack {
                IOSMovementWizard()
                    .environmentObject(appCore)
            }
        case .qrScanner:
            QRScanSheet(expectedType: .bin) { result in
                activeSheet = nil
            }
            .environmentObject(appCore)
        }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Smart Card Filters
                smartCardFilters

                // Quick Actions
                quickActionsSection

                // Sub-page Links
                subPageLinks

                // Recent Activity
                recentActivitySection
            }
            .padding()
        }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        let kpis = dashKPIs?.kpis
        let movementsCount = kpis?.todayMovements ?? 0
        let receivingCount = dashKPIs?.activeReceivingSessions ?? 0
        let auditDueCount = auditSummary.map { $0.totalParts - $0.countedParts } ?? 0
        let stagingCount = dashKPIs?.pendingStagingCount ?? 0

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                smartCard(
                    filter: .movements,
                    count: movementsCount,
                    icon: "arrow.left.arrow.right",
                    color: .purple
                )
                smartCard(
                    filter: .receiving,
                    count: receivingCount,
                    icon: "arrow.down.circle",
                    color: .green
                )
                smartCard(
                    filter: .auditDue,
                    count: max(0, auditDueCount),
                    icon: "clipboard.fill",
                    color: auditDueCount > 0 ? .orange : .green
                )
                smartCard(
                    filter: .staging,
                    count: stagingCount,
                    icon: "shippingbox.and.arrow.backward",
                    color: .blue
                )
            }
        }
    }

    private func smartCard(filter: DashboardFilter, count: Int, icon: String, color: Color) -> some View {
        let isSelected = selectedFilter == filter

        return Button {
            selectedFilter = isSelected ? nil : filter
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(filter.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 100)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.rawValue): \(count)")
    }

    // MARK: - KPI Row

    private var kpiRow: some View {
        let kpis = dashKPIs?.kpis
        let totalStock = kpis?.totalStock ?? 0
        let healthPct = kpis?.stockHealthPercent ?? 100
        let shortfalls = kpis?.shortfallCount ?? 0

        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            miniKPI(title: "Total Stock", value: "\(totalStock)", icon: "shippingbox.fill", color: .blue)
            miniKPI(
                title: "Health",
                value: "\(healthPct)%",
                icon: "heart.fill",
                color: healthPct >= 80 ? .green : healthPct >= 50 ? .orange : .red
            )
            miniKPI(
                title: "Shortfalls",
                value: "\(shortfalls)",
                icon: "exclamationmark.triangle.fill",
                color: shortfalls > 0 ? .red : .green
            )
        }
    }

    private func miniKPI(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.headline)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                Button { activeSheet = .newMovement } label: {
                    quickActionButton(
                        title: "New Movement",
                        icon: "arrow.left.arrow.right.circle.fill",
                        color: .blue
                    )
                }
                .buttonStyle(.plain)

                Button { activeSheet = .qrScanner } label: {
                    quickActionButton(
                        title: "Scan QR",
                        icon: "qrcode.viewfinder",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Sub-page Links

    private var subPageLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Warehouse")
                .font(.headline)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                subPageLink(title: "Audit", icon: "clipboard", color: .orange, moduleId: "warehouse-audit")
                subPageLink(title: "Staging", icon: "shippingbox.and.arrow.backward", color: .blue, moduleId: "warehouse-staging")
                subPageLink(title: "Receiving", icon: "arrow.down.circle", color: .green, moduleId: "warehouse-receiving")
                subPageLink(title: "Inventory", icon: "square.grid.3x3", color: .purple, moduleId: "warehouse-inventory")
            }
        }
    }

    private func subPageLink(title: String, icon: String, color: Color, moduleId: String) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .navigateToModule,
                object: nil,
                userInfo: ["moduleId": moduleId]
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Activity

    @ViewBuilder
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedFilter == nil ? "Recent Activity" : "Filtered: \(selectedFilter!.rawValue)")
                .font(.headline)
                .padding(.horizontal, 4)

            let filtered = filteredMovements

            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(selectedFilter == nil ? "No recent movements" : "No matching activity")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, movement in
                        movementActivityRow(movement)

                        if index < filtered.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var filteredMovements: [WarehouseService.MovementRow] {
        guard let filter = selectedFilter else { return recentMovements }
        switch filter {
        case .movements:
            return recentMovements // Already today's movements from KPIs
        case .receiving:
            return recentMovements.filter { $0.movementType == "receive" }
        case .auditDue:
            return recentMovements.filter { $0.movementType == "adjustment" }
        case .staging:
            return recentMovements.filter { $0.movementType == "transfer" }
        }
    }

    @ViewBuilder
    private func movementActivityRow(_ movement: WarehouseService.MovementRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: movementIcon(movement.movementType))
                .font(.body)
                .foregroundStyle(movementColor(movement.movementType))
                .frame(width: 32, height: 32)
                .background(movementColor(movement.movementType).opacity(0.12))
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
                        Text("\(from.capitalized) → \(to.capitalized)")
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

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            isLoading = false
            return
        }

        isLoading = dashKPIs == nil
        loadError = nil

        do {
            dashKPIs = try service.getDashboardKPIs()
            auditSummary = try service.getAuditSummary()
            recentMovements = try service.listMovements(limit: 10)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func movementIcon(_ type: String) -> String {
        switch type {
        case "transfer": "arrow.left.arrow.right"
        case "receive": "arrow.down.circle"
        case "consume": "flame"
        case "return_to_supplier": "arrow.uturn.left"
        case "adjustment": "plus.forwardslash.minus"
        default: "arrow.left.arrow.right"
        }
    }

    private func movementColor(_ type: String) -> Color {
        switch type {
        case "transfer": .blue
        case "receive": .green
        case "consume": .orange
        case "return_to_supplier": .purple
        case "adjustment": .gray
        default: .blue
        }
    }

    private func movementLabel(_ type: String) -> String {
        switch type {
        case "transfer": "Transfer"
        case "receive": "Received"
        case "consume": "Consumed"
        case "return_to_supplier": "Returned"
        case "adjustment": "Adjustment"
        default: type.capitalized
        }
    }

    private func formatDate(_ dateStr: String?) -> String {
        guard let dateStr else { return "" }
        if dateStr.count >= 10 {
            return String(dateStr.prefix(10))
        }
        return dateStr
    }
}
