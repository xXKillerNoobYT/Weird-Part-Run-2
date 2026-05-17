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

    @State private var setupTier: WarehouseService.WarehouseSetupTier = .complete
    @AppStorage("warehouseSetupBannerDismissed") private var bannerDismissed = false

    @StateObject private var cartManager = CartManager()

    private enum ActiveSheet: Identifiable {
        case newMovement
        case qrScanner
        case onboardingWizard
        case partsFlowWizard
        case cartSheet
        case help

        var id: String { String(describing: self) }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "warehouse-dashboard")
            SkippedModuleHint(moduleId: "warehouse")

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    CartBadgeButton(cartManager: cartManager)
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .onChange(of: cartManager.isCartSheetPresented) { _, presented in
            if presented {
                activeSheet = .cartSheet
                cartManager.isCartSheetPresented = false
            }
        }
        .onChange(of: selectedFilter) { postAIContext() }
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("wh-dashboard-view")
            // Detect warehouse setup tier for dismissable banner
            if let service = appCore.warehouseService {
                setupTier = (try? service.getSetupProgress()) ?? .none
            }
        }
        .onDisappear {
            NotificationCenter.default.post(name: .warehouseDashboardPageInactive, object: nil)
        }
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
        case .onboardingWizard:
            WarehouseOnboardingWizard()
                .environmentObject(appCore)
        case .partsFlowWizard:
            PartsFlowWizard()
                .environmentObject(appCore)
        case .cartSheet:
            CartSheetView(cartManager: cartManager)
                .environmentObject(appCore)
        case .help:
            PageHelpSheet(
                title: "Warehouse Dashboard Help",
                sections: [
                    ("Overview", "Monitor warehouse operations at a glance. Smart cards show today's movements, active receiving sessions, audits due, and staging status."),
                    ("Filters", "Tap a smart card to filter the activity feed to that category. Tap again to clear the filter."),
                    ("Quick Actions", "Use the quick action buttons to start a new movement or scan QR codes for bin lookups.")
                ]
            )
        }
    }

    // MARK: - Dashboard Content

    // MARK: - Setup Banner

    @ViewBuilder
    private var setupBanner: some View {
        if !bannerDismissed && setupTier != .complete {
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: setupTier == .floorPlanInProgress ? "arrow.triangle.2.circlepath" : "building.2")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(setupBannerTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(setupBannerSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        withAnimation { bannerDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }

                HStack(spacing: 10) {
                    if setupTier == .none {
                        Button { activeSheet = .onboardingWizard } label: {
                            Text("Full Setup")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        Button { activeSheet = .partsFlowWizard } label: {
                            Text("Just Count Parts")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.teal)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    } else if setupTier == .partsOnly {
                        Button { activeSheet = .onboardingWizard } label: {
                            Text("Set Up Floor Plan")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    } else if setupTier == .floorPlanInProgress {
                        Button { activeSheet = .onboardingWizard } label: {
                            Text("Resume Setup")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var setupBannerTitle: String {
        switch setupTier {
        case .none: "Warehouse not configured"
        case .partsOnly: "Floor plan not configured"
        case .floorPlanInProgress: "Warehouse setup in progress"
        case .complete: ""
        }
    }

    private var setupBannerSubtitle: String {
        switch setupTier {
        case .none: "Your parts won't have accurate locations. Set up now or just count your parts to get started."
        case .partsOnly: "You have parts with locations. Add a floor plan to unlock full warehouse features."
        case .floorPlanInProgress: "Pick up where you left off to complete your warehouse configuration."
        case .complete: ""
        }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Setup banner (dismissable)
                setupBanner

                // Smart Card Filters
                smartCardFilters

                // Alerts / Warnings
                alertsBanner

                // KPI Summary
                kpiRow

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

    // MARK: - Alerts

    @ViewBuilder
    private var alertsBanner: some View {
        let auditDueCount = max(0, auditSummary.map { $0.totalParts - $0.countedParts } ?? 0)
        let lowConfidenceCount = auditSummary?.discrepancies ?? 0
        let shortfalls = dashKPIs?.kpis.shortfallCount ?? 0

        if auditDueCount > 0 || lowConfidenceCount > 0 || shortfalls > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Label("Warehouse Alerts", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                if auditDueCount > 0 {
                    alertLine("\(auditDueCount) part\(auditDueCount == 1 ? "" : "s") still need audit coverage", icon: "clipboard")
                }
                if lowConfidenceCount > 0 {
                    alertLine("\(lowConfidenceCount) low-confidence/variance area\(lowConfidenceCount == 1 ? "" : "s") need review", icon: "chart.bar.doc.horizontal")
                }
                if shortfalls > 0 {
                    alertLine("\(shortfalls) stocked part\(shortfalls == 1 ? "" : "s") below minimum", icon: "shippingbox")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25), lineWidth: 1))
        }
    }

    private func alertLine(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.primary)
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
                .accessibilityHidden(true)
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
                Button { navigate(to: "warehouse-movements") } label: {
                    quickActionButton(
                        title: "Movements",
                        icon: "arrow.left.arrow.right.circle.fill",
                        color: .blue
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("whAction_movements")

                Button { navigate(to: "warehouse-receiving") } label: {
                    quickActionButton(
                        title: "Receiving",
                        icon: "arrow.down.circle",
                        color: .green
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("whAction_receiving")

                Button { navigate(to: "warehouse-audit") } label: {
                    quickActionButton(
                        title: "Audit",
                        icon: "clipboard.fill",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("whAction_audit")
            }
        }
    }

    private func quickActionButton(title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .accessibilityHidden(true)
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
                subPageLink(title: "Movements", icon: "arrow.left.arrow.right", color: .blue, moduleId: "warehouse-movements")
                subPageLink(title: "Receiving", icon: "arrow.down.circle", color: .green, moduleId: "warehouse-receiving")
                subPageLink(title: "Staging", icon: "shippingbox.and.arrow.backward", color: .blue, moduleId: "warehouse-staging")
                subPageLink(title: "Returns", icon: "arrow.uturn.left", color: .purple, moduleId: "warehouse-returns")
                subPageLink(title: "Audit", icon: "clipboard", color: .orange, moduleId: "warehouse-audit")
                subPageLink(title: "Inventory", icon: "square.grid.3x3", color: .purple, moduleId: "warehouse-inventory")
                subPageLink(title: "Locations", icon: "mappin.and.ellipse", color: .teal, moduleId: "warehouse-locations")
                subPageLink(title: "Floor Plan", icon: "map", color: .indigo, moduleId: "warehouse-locations")
                subPageLink(title: "Tools", icon: "wrench.and.screwdriver", color: .brown, moduleId: "warehouse-tools")
                subPageLink(title: "Network", icon: "point.3.connected.trianglepath.dotted", color: .cyan, moduleId: "warehouse-network")
                subPageLink(title: "Leaderboard", icon: "trophy", color: .yellow, moduleId: "warehouse-leaderboard")
                subPageLink(title: "Settings", icon: "gearshape", color: .gray, moduleId: "warehouse-settings")
            }
        }
    }

    private func subPageLink(title: String, icon: String, color: Color, moduleId: String) -> some View {
        Button {
            navigate(to: moduleId)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func navigate(to moduleId: String) {
        NotificationCenter.default.post(
            name: .navigateToModule,
            object: nil,
            userInfo: ["moduleId": moduleId]
        )
    }

    // MARK: - Recent Activity

    @ViewBuilder
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedFilter.map { "Filtered: \($0.rawValue)" } ?? "Recent Activity")
                .font(.headline)
                .padding(.horizontal, 4)

            let filtered = filteredMovements

            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
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
                .accessibilityHidden(true)

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
            recentMovements = try service.listMovements(limit: 10, sortOrder: .newestFirst)
            postAIContext()
        } catch {
            loadError = userFriendlyError(error, context: "load warehouse dashboard")
        }
        isLoading = false
    }

    private func postAIContext() {
        let kpis = dashKPIs?.kpis
        let movementCounts = Dictionary(grouping: recentMovements, by: \.movementType)
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let context = """
        Warehouse Dashboard page. Read-only context.
        Stock total: \(kpis?.totalStock ?? 0), health: \(kpis?.stockHealthPercent ?? 0)%, shortfalls: \(kpis?.shortfallCount ?? 0), movements today: \(kpis?.todayMovements ?? 0).
        Active receiving sessions: \(dashKPIs?.activeReceivingSessions ?? 0), pending staging: \(dashKPIs?.pendingStagingCount ?? 0), pending returns: \(dashKPIs?.pendingReturns ?? 0).
        Audit counted/total: \(auditSummary?.countedParts ?? 0)/\(auditSummary?.totalParts ?? 0), discrepancies: \(auditSummary?.discrepancies ?? 0), selected filter: \(selectedFilter?.rawValue ?? "none").
        Recent movement rows loaded: \(recentMovements.count), visible after filter: \(filteredMovements.count), movement types: \(movementCounts.isEmpty ? "none" : movementCounts).
        Available read-only guidance: explain KPI cards, selected activity filter, quick action locations, and warehouse sub-page links. Do not create movements or launch scanners directly.
        """
        NotificationCenter.default.post(
            name: .warehouseDashboardPageActive,
            object: nil,
            userInfo: ["context": context]
        )
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
