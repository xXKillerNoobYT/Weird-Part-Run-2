import SwiftUI
import UIKit
import WiredPartCore

/// Warehouse dashboard showing KPI smart cards, recent activity, and quick actions.
///
/// Smart cards act as toggle filters for service-backed dashboard categories:
/// Moves Today, Receiving Active, Audit Due, and Staged Ready.
/// Quick actions open movement wizard and QR scanner as sheets.
struct WarehouseDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - State

    @State private var dashKPIs: WarehouseService.DashboardKPIs?
    @State private var auditSummary: WarehouseService.AuditSummary?
    @State private var auditCards: WarehouseService.DashboardSmartCardSummary?
    @State private var warehouseScore: Double?
    @State private var recentMovements: [WarehouseService.MovementRow] = []
    @State private var activeReceivingSessions: [WarehouseService.ReceivingSessionInfo] = []
    @State private var auditQueue: [WarehouseService.AuditQueueItem] = []
    @State private var stagedItems: [WarehouseService.StagedItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedFilter: DashboardFilter?
    @State private var activeSheet: ActiveSheet?

    private enum DashboardFilter: String, CaseIterable {
        case movesToday = "Moves Today"
        case receivingActive = "Receiving Active"
        case auditDue = "Audit Due"
        case stagedReady = "Staged Ready"
    }

    @State private var setupTier: WarehouseService.WarehouseSetupTier = .complete
    @AppStorage("warehouseSetupBannerDismissed") private var bannerDismissed = false

    @StateObject private var cartManager = CartManager()

    private enum ActiveSheet: Identifiable {
        case newMovement
        case qrScanner
        case onboardingWizard
        case partsFlowWizard
        case warehouseSettings
        case cartSheet
        case help

        var id: String { String(describing: self) }
    }

    private struct WarehouseQuickAction: Identifiable {
        let title: String
        let icon: String
        let color: Color
        let identifier: String
        let moduleId: String?
        let tabId: String?
        let sheet: ActiveSheet?
        let requiredPermission: String?

        var id: String { identifier }
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
                    Button { activeSheet = .newMovement } label: {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                    }
                    .accessibilityLabel("New Movement")
                    .accessibilityHint("Opens the guided movement wizard")
                    .accessibilityIdentifier("whAction_newMovement")

                    CartBadgeButton(cartManager: cartManager)
                    Button { activeSheet = .newMovement } label: {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                    }
                    .accessibilityLabel("New Movement")
                    .accessibilityIdentifier("whAction_newMovement")
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
            appCore.onboardingManager?.markCompleted("wh-dashboard-audit-score")
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
            IOSMovementWizard()
                .environmentObject(appCore)
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
        case .warehouseSettings:
            NavigationStack {
                IOSWarehouseSettingsPage()
                    .environmentObject(appCore)
            }
        case .cartSheet:
            CartSheetView(cartManager: cartManager)
                .environmentObject(appCore)
        case .help:
            PageHelpSheet(
                title: "Warehouse Dashboard Help",
                sections: [
                    ("Overview", "Monitor warehouse operations at a glance. Smart cards show today's movements, audits due, confidence risk, active audit sessions, and organization issues."),
                    ("Warehouse Score", "The overall score combines part confidence, organization ratings, user ratings, shelf utilization, misplacements, label accuracy, audit response time, and stock health."),
                    ("Filters", "Tap a smart card to switch the work queue between today's movements, active receiving, audit queue, and staged parts. Tap again to clear the filter."),
                    ("Quick Actions", "Use quick actions to start a movement, scan QR codes, continue receiving, or open the audit queue.")
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

                    Button { activeSheet = .warehouseSettings } label: {
                        Text("Warehouse Settings")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("whAction_warehouseSettings")

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

    // MARK: - Alerts

    @ViewBuilder
    private var alertsWarningsBanner: some View {
        let canPerformAudit = appCore.hasPermission("perform_audit")
        let auditDue = canPerformAudit ? (auditCards?.auditDue ?? auditQueue.count) : 0
        let lowConfidenceAreas = canPerformAudit ? (auditCards?.lowConfidenceAreas ?? 0) : 0
        let lowStockWarnings = auditCards?.lowStockWarnings ?? dashKPIs?.kpis.shortfallCount ?? 0
        let activeReceiving = auditCards?.activeReceiving ?? activeReceivingSessions.count

        if auditDue > 0 || lowConfidenceAreas > 0 || lowStockWarnings > 0 || activeReceiving > 0 {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Alerts & Warnings")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                }

                VStack(spacing: 8) {
                    if auditDue > 0 {
                        alertRow(
                            title: "\(auditDue) parts need audit",
                            subtitle: "Low confidence items are queued for verification.",
                            icon: "checkmark.shield.fill",
                            color: .orange,
                            tabId: "warehouse-audit"
                        )
                    }
                    if lowConfidenceAreas > 0 {
                        alertRow(
                            title: "\(lowConfidenceAreas) low-confidence areas",
                            subtitle: "Review the audit queue before relying on these locations.",
                            icon: "exclamationmark.shield.fill",
                            color: .red,
                            tabId: "warehouse-audit"
                        )
                    }
                    if lowStockWarnings > 0 {
                        alertRow(
                            title: "\(lowStockWarnings) stock shortfalls",
                            subtitle: "Open inventory to review parts below minimum level.",
                            icon: "shippingbox.fill",
                            color: .red,
                            tabId: "warehouse-inventory"
                        )
                    }
                    if activeReceiving > 0 {
                        alertRow(
                            title: "\(activeReceiving) receiving sessions active",
                            subtitle: "Continue sorting and close sessions when complete.",
                            icon: "arrow.down.circle.fill",
                            color: .blue,
                            tabId: "warehouse-receiving"
                        )
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func alertRow(title: String, subtitle: String, icon: String, color: Color, tabId: String) -> some View {
        Button {
            navigateToWarehouseTab(tabId)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Setup banner (dismissable)
                setupBanner

                // Service-backed alerts and warnings
                alertsWarningsBanner

                // Smart Card Filters
                smartCardFilters

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
        let movementsCount = auditCards?.movesToday ?? kpis?.todayMovements ?? 0
        let activeReceivingCount = auditCards?.activeReceiving ?? activeReceivingSessions.count
        let auditDueCount = auditCards?.auditDue ?? auditQueue.count
        let stagedReadyCount = auditCards?.stagedReady ?? stagedItems.count

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                smartCard(
                    filter: .movesToday,
                    count: movementsCount,
                    icon: "arrow.left.arrow.right",
                    color: .purple
                )
                smartCard(
                    filter: .receivingActive,
                    count: activeReceivingCount,
                    icon: "arrow.down.circle.fill",
                    color: activeReceivingCount > 0 ? .blue : .green
                )
                smartCard(
                    filter: .auditDue,
                    count: max(0, auditDueCount),
                    icon: "clipboard.fill",
                    color: auditDueCount > 0 ? .orange : .green
                )
                smartCard(
                    filter: .stagedReady,
                    count: stagedReadyCount,
                    icon: "tray.2.fill",
                    color: stagedReadyCount > 0 ? .teal : .green
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - KPI Row

    private var kpiRow: some View {
        let kpis = dashKPIs?.kpis
        let totalStock = kpis?.totalStock ?? 0
        let healthPct = kpis?.stockHealthPercent ?? 100
        let shortfalls = kpis?.shortfallCount ?? 0

        return LazyVGrid(columns: [
            GridItem(.adaptive(minimum: kpiMinimumCardWidth), spacing: 12),
        ], spacing: 12) {
            miniKPI(
                title: "Audit Score",
                value: "\(Int(warehouseScorePercent.rounded()))%",
                icon: "gauge.with.dots.needle.bottom.50percent",
                color: scoreColor(warehouseScorePercent),
                accessibilityIdentifier: "warehouseKPIAuditScore"
            )
            miniKPI(
                title: "Total Stock",
                value: "\(totalStock)",
                icon: "shippingbox.fill",
                color: .blue,
                accessibilityIdentifier: "warehouseKPITotalStock"
            )
            miniKPI(
                title: "Health",
                value: "\(healthPct)%",
                icon: "heart.fill",
                color: healthPct >= 80 ? .green : healthPct >= 50 ? .orange : .red,
                accessibilityIdentifier: "warehouseKPIHealth"
            )
            miniKPI(
                title: "Shortfalls",
                value: "\(shortfalls)",
                icon: "exclamationmark.triangle.fill",
                color: shortfalls > 0 ? .red : .green,
                accessibilityIdentifier: "warehouseKPIShortfalls"
            )
        }
    }

    private var kpiMinimumCardWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 240 : 150
    }

    private func miniKPI(
        title: String,
        value: String,
        icon: String,
        color: Color,
        accessibilityIdentifier: String
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 74)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.headline)
                .padding(.horizontal, 4)

            if usesCompactQuickActionGrid {
                VStack(spacing: 12) {
                    ForEach(Array(quickActionRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 12) {
                            ForEach(row) { action in
                                quickActionTile(action)
                            }
                            if row.count == 1 {
                                Color.clear
                            }
                        }
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            } else {
                HStack(spacing: 12) {
                    ForEach(quickActions) { action in
                        quickActionTile(action)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
        }
    }

    private var usesCompactQuickActionGrid: Bool {
        horizontalSizeClass == .compact &&
            (dynamicTypeSize >= .accessibility1 || UIScreen.main.bounds.width < 360)
    }

    private var quickActions: [WarehouseQuickAction] {
        [
            WarehouseQuickAction(
                title: "New Movement",
                icon: "arrow.left.arrow.right.circle.fill",
                color: .blue,
                identifier: "whAction_newMovement",
                moduleId: nil,
                tabId: nil,
                sheet: .newMovement,
                requiredPermission: nil
            ),
            WarehouseQuickAction(
                title: "Scan QR",
                icon: "qrcode.viewfinder",
                color: .orange,
                identifier: "whAction_scanQR",
                moduleId: nil,
                tabId: nil,
                sheet: .qrScanner,
                requiredPermission: nil
            ),
            WarehouseQuickAction(
                title: "Receiving",
                icon: "arrow.down.circle",
                color: .green,
                identifier: "whAction_receiving",
                moduleId: "warehouse",
                tabId: "warehouse-receiving",
                sheet: nil,
                requiredPermission: nil
            ),
            WarehouseQuickAction(
                title: "Audit Queue",
                icon: "clipboard.fill",
                color: .orange,
                identifier: "whAction_auditQueue",
                moduleId: "warehouse",
                tabId: "warehouse-audit",
                sheet: nil,
                requiredPermission: "perform_audit"
            ),
        ]
    }

    private var quickActionRows: [[WarehouseQuickAction]] {
        stride(from: 0, to: quickActions.count, by: 2).map { start in
            Array(quickActions[start..<min(start + 2, quickActions.count)])
        }
    }

    @ViewBuilder
    private func quickActionTile(_ action: WarehouseQuickAction) -> some View {
        let tile = Button { performQuickAction(action) } label: {
            quickActionButton(title: action.title, icon: action.icon, color: action.color)
        }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(action.title)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(action.identifier)

        if let requiredPermission = action.requiredPermission {
            tile.hideWithoutPermission(requiredPermission)
        } else {
            tile
        }
    }

    private func performQuickAction(_ action: WarehouseQuickAction) {
        if let sheet = action.sheet {
            activeSheet = sheet
        } else if let moduleId = action.moduleId {
            var userInfo: [String: Any] = ["moduleId": moduleId]
            if let tabId = action.tabId {
                userInfo["tabId"] = tabId
            }
            NotificationCenter.default.post(
                name: .navigateToModule,
                object: nil,
                userInfo: userInfo
            )
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
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
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
                subPageLink(title: "Receiving", icon: "shippingbox.fill", color: .green, tabId: "warehouse-receiving")
                subPageLink(title: "Staging", icon: "tray.2.fill", color: .teal, tabId: "warehouse-staging")
                subPageLink(title: "Movements", icon: "arrow.left.arrow.right", color: .blue, tabId: "warehouse-movements")
                subPageLink(title: "Inventory", icon: "square.grid.3x3.fill", color: .purple, tabId: "warehouse-inventory")
                subPageLink(title: "Locations", icon: "map.fill", color: .mint, tabId: "warehouse-locations")
                subPageLink(title: "Audit", icon: "checkmark.shield.fill", color: .orange, tabId: "warehouse-audit")
                    .hideWithoutPermission("perform_audit")
                subPageLink(title: "Returns", icon: "arrow.uturn.left", color: .indigo, tabId: "warehouse-returns")
                subPageLink(title: "Tools", icon: "wrench.and.screwdriver.fill", color: .brown, tabId: "warehouse-tools")
                subPageLink(title: "Leaderboard", icon: "trophy.fill", color: .yellow, tabId: "warehouse-leaderboard")
                subPageLink(title: "Network", icon: "antenna.radiowaves.left.and.right", color: .cyan, tabId: "warehouse-network")
                subPageLink(title: "Settings", icon: "gearshape.fill", color: .gray, tabId: "warehouse-settings")
            }
        }
    }

    private func subPageLink(title: String, icon: String, color: Color, tabId: String) -> some View {
        Button {
            navigateToWarehouseTab(tabId)
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
        .accessibilityIdentifier("whSubPage_\(tabId)")
        .accessibilityLabel(title)
    }

    // MARK: - Recent Activity

    @ViewBuilder
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedFilter.map { "Filtered: \($0.rawValue)" } ?? "Recent Activity")
                .font(.headline)
                .padding(.horizontal, 4)

            switch selectedFilter {
            case .movesToday, .none:
                movementQueue
            case .receivingActive:
                receivingQueue
            case .auditDue:
                auditDueQueue
            case .stagedReady:
                stagedReadyQueue
            }
        }
    }

    @ViewBuilder
    private var movementQueue: some View {
        let rows = selectedFilter == nil ? recentMovements : todaysMovements

        if rows.isEmpty {
            emptyQueue(
                icon: "arrow.left.arrow.right",
                title: selectedFilter == nil ? "No recent movements" : "No movements today",
                subtitle: selectedFilter == nil ? "Warehouse activity will appear here as parts move." : "Today's completed movements will appear here."
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, movement in
                    movementActivityRow(movement)

                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var receivingQueue: some View {
        if activeReceivingSessions.isEmpty {
            emptyQueue(
                icon: "arrow.down.circle",
                title: "No active receiving",
                subtitle: "Open purchase-order receiving sessions will appear here."
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(activeReceivingSessions.enumerated()), id: \.element.id) { index, session in
                    receivingRow(session)
                    if index < activeReceivingSessions.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var auditDueQueue: some View {
        if auditQueue.isEmpty {
            emptyQueue(
                icon: "checkmark.shield",
                title: "No audits due",
                subtitle: "Low-confidence parts will appear here when they need verification."
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(auditQueue.enumerated()), id: \.element.partId) { index, item in
                    auditQueueRow(item)
                    if index < auditQueue.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var stagedReadyQueue: some View {
        if stagedItems.isEmpty {
            emptyQueue(
                icon: "tray.2",
                title: "No staged parts ready",
                subtitle: "Pulled parts tagged for jobs, trucks, or other destinations will appear here."
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(stagedItems.enumerated()), id: \.element.id) { index, item in
                    stagedItemRow(item)
                    if index < stagedItems.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var todaysMovements: [WarehouseService.MovementRow] {
        recentMovements.filter { isToday($0.createdAt) }
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

                    if let auditSummary = auditSummaryText(for: movement) {
                        Text(auditSummary)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else if let from = movement.fromLocationType, let to = movement.toLocationType {
                        Text("\(from.capitalized) → \(to.capitalized)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(quantityLabel(for: movement))
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

    private func receivingRow(_ session: WarehouseService.ReceivingSessionInfo) -> some View {
        Button {
            navigateToWarehouseTab("warehouse-receiving")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.body)
                    .foregroundStyle(.green)
                    .frame(width: 32, height: 32)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("PO #\(session.poId)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(session.itemCount) items • \(session.mode.replacingOccurrences(of: "_", with: " ").capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(session.startedByName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatDate(session.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func auditQueueRow(_ item: WarehouseService.AuditQueueItem) -> some View {
        Button {
            navigateToWarehouseTab("warehouse-audit")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.body)
                    .foregroundStyle(scoreColor(item.confidencePercent))
                    .frame(width: 32, height: 32)
                    .background(scoreColor(item.confidencePercent).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.partName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(item.locationCode ?? item.partCode ?? "Unassigned location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Int(item.confidencePercent.rounded()))%")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("confidence")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func stagedItemRow(_ item: WarehouseService.StagedItem) -> some View {
        Button {
            navigateToWarehouseTab("warehouse-staging")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tray.2.fill")
                    .font(.body)
                    .foregroundStyle(.teal)
                    .frame(width: 32, height: 32)
                    .background(Color.teal.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.partName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(item.destinationLabel ?? item.destinationType?.capitalized ?? "Ready for destination")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(item.qty)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(formatDate(item.taggedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyQueue(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            auditCards = try service.getDashboardSmartCardSummary()
            warehouseScore = try service.getWarehouseOverallScore()
            recentMovements = try service.listMovements(limit: 10)
            activeReceivingSessions = try service.getActiveSessions()
            auditQueue = try service.getAuditQueue(limit: 10)
            stagedItems = try service.getStagedItems()
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
        Warehouse audit score: \(Int(warehouseScorePercent.rounded()))%, confidence risk areas: \(auditCards?.lowConfidenceAreas ?? 0), audit due: \(auditCards?.auditDue ?? 0), low-stock warnings: \(auditCards?.lowStockWarnings ?? 0).
        Dashboard queues loaded: \(todaysMovements.count) moves today, \(activeReceivingSessions.count) receiving active, \(auditQueue.count) audit due, \(stagedItems.count) staged ready. Movement types: \(movementCounts.isEmpty ? "none" : movementCounts).
        Available read-only guidance: explain KPI cards, audit score components, selected activity filter, quick action locations, and warehouse sub-page links. Do not create movements or launch scanners directly.
        """
        NotificationCenter.default.post(
            name: .warehouseDashboardPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }

    // MARK: - Helpers

    private func movementIcon(_ type: String) -> String {
        StockMovement.MovementType.systemImageName(forRawValue: type)
    }

    private func movementColor(_ type: String) -> Color {
        switch StockMovement.MovementType(rawValue: type) {
        case .transfer, .restockFromShop:
            return .blue
        case .receive, .receiving, .receivingStaged, .receipt:
            return .green
        case .consume, .pull, .usage, .jobPull:
            return .orange
        case .stockReturn, .returnToSupplier:
            return .purple
        case .adjustment, .addStock, .writeOff:
            return .gray
        case nil:
            return .blue
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 85 { return .green }
        if score >= 70 { return .orange }
        return .red
    }

    private var warehouseScorePercent: Double {
        max(0, min(100, (warehouseScore ?? 10.0) * 10.0))
    }

    private func movementLabel(_ type: String) -> String {
        StockMovement.MovementType.displayName(forRawValue: type)
    }

    private func auditSummaryText(for movement: WarehouseService.MovementRow) -> String? {
        guard movement.movementType == "adjustment",
              let notes = movement.notes,
              notes.hasPrefix("Audit count adjustment:") else { return nil }
        return notes.replacingOccurrences(of: "Audit count adjustment:", with: "Audit:")
    }

    private func quantityLabel(for movement: WarehouseService.MovementRow) -> String {
        guard movement.movementType == "adjustment",
              auditSummaryText(for: movement) != nil else { return "\(movement.qty)" }
        return movement.qty >= 0 ? "+\(movement.qty)" : "\(movement.qty)"
    }

    private func formatDate(_ dateStr: String?) -> String {
        guard let dateStr else { return "" }
        if dateStr.count >= 10 {
            return String(dateStr.prefix(10))
        }
        return dateStr
    }

    private func isToday(_ dateStr: String?) -> Bool {
        guard let dateStr, dateStr.count >= 10 else { return false }
        let today = DateFormatter.dashboardDayFormatter.string(from: Date())
        return String(dateStr.prefix(10)) == today
    }

    private func navigateToWarehouseTab(_ tabId: String) {
        NotificationCenter.default.post(
            name: .navigateToModule,
            object: nil,
            userInfo: ["moduleId": "warehouse", "tabId": tabId]
        )
    }
}

private extension DateFormatter {
    static let dashboardDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
