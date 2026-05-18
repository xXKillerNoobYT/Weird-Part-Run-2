import SwiftUI
import Charts
import Combine
import WiredPartCore

/// Main dashboard view with KPI cards, charts, alerts, and quick actions.
///
/// Sub-pages (QR Scanner, Clock In/Out, Daily Report) are pushed via NavigationStack.
/// Uses AppCore to query the database directly for summary statistics.
/// All data is fetched on appear, supports pull-to-refresh, and auto-refreshes every 60s.
struct DashboardView: View {
    @EnvironmentObject private var appCore: AppCore

    // KPI + alerts state
    @State private var stats = DashboardStats()
    @State private var certAlerts: [CertAlert] = []
    @State private var vehicleAlerts: [VehicleAlert] = []

    // Charts data
    @State private var laborChartData: [LaborDayData] = []
    @State private var stockChartData: [StockLevelData] = []
    @State private var spendingChartData: [SpendingCategory] = []

    // Background tasks
    @State private var taskSummary: BackgroundTaskService.TaskSummary?
    @State private var recentTasks: [BackgroundTaskService.TaskLogEntry] = []

    // Sheet management — single enum to avoid SwiftUI multiple-.sheet() bug
    private enum ActiveSheet: Identifiable {
        case help
        case kpiDetail(KPIDetailType)
        case createJob
        case companySetup
        var id: String {
            switch self {
            case .help: return "help"
            case .kpiDetail(let type): return "kpi_\(type.id)"
            case .createJob: return "createJob"
            case .companySetup: return "companySetup"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    // Clock status
    @State private var isCurrentlyClockedIn = false
    @State private var clockedInJobName: String?
    @State private var clockedInJobNumber: String?
    @State private var clockInTime: Date?
    @State private var clockDurationText: String = "0m"

    // Dashboard sub-page navigation
    enum DashboardDestination: Hashable {
        case scanner
        case clock
        case dailyReport
    }

    // Onboarding checklist persistence
    @AppStorage("onboarding_checklist_dismissed") private var checklistDismissed = false
    @AppStorage("hasCompletedCompanySetup") private var hasCompletedCompanySetup = false
    @State private var warehouseHasFloorPlan = false
    @State private var showChecklistDismissToast = false
    @State private var checklistDismissToastTask: Task<Void, Never>?
    private let checklistDismissToastDurationSeconds: TimeInterval = 5
    // showCreateJobSheet and showCompanySetupWizard consolidated into ActiveSheet enum

    @State private var isLoading = true
    @State private var loadError: String?

    // Lifecycle-aware timers — only fire when dashboard is visible (fixes #214)
    @State private var refreshCancellable: AnyCancellable?
    @State private var clockCancellable: AnyCancellable?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    // Greeting
                    greeting
                        .padding(.horizontal, DS.Space.lg)

                    OnboardingBanner(pageId: "dashboard-home")
                        .padding(.horizontal, DS.Space.lg)

                    SkippedModuleHint(moduleId: "dashboard")
                        .padding(.horizontal, DS.Space.lg)

                    clockStatusBanner
                        .padding(.horizontal, DS.Space.lg)

                    gettingStartedChecklist

                    onboardingProgressSection

                    if isLoading {
                        DSLoadingState()
                            .padding(.top, DS.Space.jumbo)
                    } else if let error = loadError {
                        ErrorStateView(message: error) { Task { await loadData() } }
                            .padding(.top, DS.Space.xl)
                    } else {
                        quickActionsSection
                        kpiSection
                        chartsSection
                        alertsContent
                        backgroundTasksCard
                    }
                }
                .padding(.vertical)
            }
            .refreshable { await loadData() }
            .background(DS.Background.page)
            .task { await loadData() }
            .onAppear {
                NotificationCenter.default.post(
                    name: .dashboardPageActive,
                    object: nil,
                    userInfo: [
                        "context": "Dashboard: \(stats.activeJobs) active jobs, \(stats.totalStock) total stock, \(stats.partTypes) part types, \(stats.pendingOrders) pending orders, \(stats.lowStockCount) low stock, \(stats.employeeCount) employees. Clocked in: \(isCurrentlyClockedIn ? (clockedInJobName ?? "yes") : "no")."
                    ]
                )
                // Start timers only when visible (fixes #214)
                refreshCancellable = Timer.publish(every: 60, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in Task { await loadData() } }
                clockCancellable = Timer.publish(every: 30, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in updateClockDuration() }
            }
            .onDisappear {
                NotificationCenter.default.post(name: .dashboardPageInactive, object: nil)
                refreshCancellable?.cancel()
                clockCancellable?.cancel()
                checklistDismissToastTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .task { appCore.onboardingManager?.markCompleted("dashboard-view-kpis") }
            .navigationDestination(for: DashboardDestination.self) { dest in
                switch dest {
                case .scanner:
                    IOSDashboardQRScannerPage()
                case .clock:
                    IOSClockPage()
                case .dailyReport:
                    DashboardDailyReportPage()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showChecklistDismissToast {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Checklist dismissed")
                        .font(.subheadline)
                    Spacer(minLength: DS.Space.sm)
                    Button("Undo") {
                        checklistDismissToastTask?.cancel()
                        withAnimation {
                            checklistDismissed = false
                            showChecklistDismissToast = false
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8, y: 3)
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.lg)
                .accessibilityElement(children: .contain)
            }
        }
        // Sheet placed OUTSIDE NavigationStack so @Environment(\.dismiss) in sheet content
        // binds to the sheet's dismiss, not the outer NavigationStack's dismiss.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(
                    title: "Dashboard Help",
                    sections: [
                        ("Overview", "Your daily command center. See clock status, quick actions, KPI stats, charts, and alerts all in one place."),
                        ("Quick Actions", "Use the quick action buttons near the top to scan QR codes, clock in/out, view the daily report, move stock, or create new orders."),
                        ("KPI Cards", "Tap any KPI card to see detailed breakdowns. Cards show part types, total stock, active jobs, pending orders, and low stock warnings.")
                    ]
                )
            case .kpiDetail(let detail):
                KPIDetailSheet(type: detail)
                    .environmentObject(appCore)
                    .task { appCore.onboardingManager?.markCompleted("dashboard-tap-kpi") }
            case .createJob:
                IOSCreateJobSheet()
                    .environmentObject(appCore)
            case .companySetup:
                CompanySetupWizard()
                    .environmentObject(appCore)
            }
        }
    }

    // MARK: - First-Launch Detection

    /// True if the app has no meaningful data — indicates first-launch or empty state.
    private var isFirstLaunchState: Bool {
        stats.activeJobs == 0 &&
        stats.partTypes == 0 &&
        stats.totalStock == 0
    }

    // MARK: - Getting Started Checklist

    @ViewBuilder
    private var gettingStartedChecklist: some View {
        if isFirstLaunchState && !checklistDismissed {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.blue)
                        .font(.title2)
                        .accessibilityHidden(true)
                    Text("Getting Started")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button {
                        checklistDismissToastTask?.cancel()
                        withAnimation {
                            checklistDismissed = true
                            showChecklistDismissToast = true
                        }
                        checklistDismissToastTask = Task {
                            try? await Task.sleep(for: .seconds(checklistDismissToastDurationSeconds))
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                withAnimation {
                                    showChecklistDismissToast = false
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss checklist")
                }

                Text("Welcome to WiredPart! Complete these steps to set up your business.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    checklistItem(
                        step: 1,
                        title: "Add Your Team",
                        subtitle: "Add employees so they can clock in and get assigned to jobs.",
                        icon: "person.badge.plus",
                        color: .blue,
                        isComplete: stats.employeeCount > 0
                    ) {
                        IOSEmployeesPage().environmentObject(appCore)
                    }

                    checklistItem(
                        step: 2,
                        title: "Set Up Parts Catalog",
                        subtitle: "Import or create your parts inventory so you can track stock and order materials.",
                        icon: "wrench.and.screwdriver.fill",
                        color: .green,
                        isComplete: stats.partTypes > 0
                    ) {
                        PartsRouter(tabId: "parts-import-export").environmentObject(appCore)
                    }

                    // Step 3 uses a sheet instead of NavigationLink
                    Button {
                        activeSheet = .createJob
                    } label: {
                        checklistItemLabel(
                            step: 3,
                            title: "Create Your First Job",
                            subtitle: "Jobs are the core of WiredPart — create one to start tracking work.",
                            icon: "briefcase.fill",
                            color: .orange,
                            isComplete: stats.activeJobs > 0
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(stats.activeJobs > 0)

                    checklistItem(
                        step: 4,
                        title: "Configure Your Warehouse",
                        subtitle: "Set up warehouse locations and bins so parts can be tracked on shelves.",
                        icon: "building.2.fill",
                        color: .purple,
                        isComplete: warehouseHasFloorPlan
                    ) {
                        WarehouseOnboardingWizard().environmentObject(appCore)
                    }
                }

                // Progress indicator
                let completed = [
                    stats.employeeCount > 0,
                    stats.partTypes > 0,
                    stats.activeJobs > 0,
                    warehouseHasFloorPlan,
                ].filter { $0 }.count

                HStack {
                    Text("\(completed) of 4 complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView(value: Double(completed), total: 4.0)
                        .frame(width: 100)
                }

                // Resume company setup (admin only)
                if !hasCompletedCompanySetup && appCore.hasPermission("manage_jobs") {
                    Button {
                        activeSheet = .companySetup
                    } label: {
                        Label("Resume Company Setup", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                // Tour button
                if appCore.onboardingManager?.isOnboardingActive != true {
                    Button {
                        withAnimation { appCore.onboardingManager?.isOnboardingActive = true }
                    } label: {
                        Label("Take the Full App Tour", systemImage: "graduationcap.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
            )
            .padding(.horizontal, DS.Space.lg)
        }
    }

    private func checklistItem<Destination: View>(
        step: Int,
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isComplete: Bool,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            checklistItemLabel(step: step, title: title, subtitle: subtitle, icon: icon, color: color, isComplete: isComplete)
        }
        .buttonStyle(.plain)
        .disabled(isComplete)
    }

    private func checklistItemLabel(
        step: Int,
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isComplete: Bool
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : color.opacity(0.15))
                    .frame(width: 36, height: 36)
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                } else {
                    Text("\(step)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(color)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(isComplete)
                    .foregroundStyle(isComplete ? .secondary : .primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !isComplete {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Onboarding Progress

    @ViewBuilder
    private var onboardingProgressSection: some View {
        if let manager = appCore.onboardingManager, manager.isOnboardingActive {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "graduationcap.fill")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    Text("App Tour Progress")
                        .font(.headline)
                    Spacer()
                    let overall = manager.overallProgress(permissions: appCore.permissions)
                    Text("\(overall.completed)/\(overall.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(appModules, id: \.id) { module in
                    let progress = manager.moduleProgress(module.id, permissions: appCore.permissions)
                    if progress.total > 0 {
                        HStack {
                            Image(systemName: module.icon)
                                .font(.caption)
                                .frame(width: 24)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(module.label)
                                .font(.subheadline)
                            Spacer()
                            Text("\(progress.completed)/\(progress.total)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: Double(progress.completed), total: max(Double(progress.total), 1))
                                .frame(width: 60)
                        }
                    }
                }

                Button {
                    withAnimation { manager.isOnboardingActive = false }
                } label: {
                    Text("End Tour")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
            )
            .padding(.horizontal, DS.Space.lg)
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(greetingText)
                .dsStyle(.pageTitle)
            Text(formattedDate)
                .dsStyle(.detail)
                .foregroundStyle(.secondary)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = appCore.currentUser?.displayName ?? "there"
        let timeOfDay: String
        switch hour {
        case 0..<12:  timeOfDay = "Good morning"
        case 12..<17: timeOfDay = "Good afternoon"
        default:      timeOfDay = "Good evening"
        }
        return "\(timeOfDay), \(name)"
    }

    private var formattedDate: String {
        Formatters.fullDateFormatter.string(from: Date())
    }

    // MARK: - Clock Status Banner

    @ViewBuilder
    private var clockStatusBanner: some View {
        NavigationLink(value: DashboardDestination.clock) {
            HStack(spacing: DS.Space.md) {
                // Status dot
                Circle()
                    .fill(isCurrentlyClockedIn ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(isCurrentlyClockedIn ? "Status: clocked in" : "Status: not clocked in")

                if isCurrentlyClockedIn {
                    VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                        Text("Clocked In")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)

                        if let jobName = clockedInJobName {
                            Text(jobName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Live duration
                    Text(clockDurationText)
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(.green)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                } else {
                    Text("Not clocked in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Clock In")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(DS.Space.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isCurrentlyClockedIn
                        ? Color.green.opacity(0.08)
                        : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(isCurrentlyClockedIn ? Color.green.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clockStatusBanner")
    }

    // MARK: - Duration Update

    private func updateClockDuration() {
        guard let startTime = clockInTime else {
            clockDurationText = "0m"
            return
        }
        let elapsed = Date().timeIntervalSince(startTime)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        if hours > 0 {
            clockDurationText = "\(hours)h \(minutes)m"
        } else {
            clockDurationText = "\(minutes)m"
        }
    }

    // MARK: - KPI Cards

    @ViewBuilder
    private var kpiSection: some View {
        let twoColumns = [
            GridItem(.flexible(), spacing: DS.Space.md),
            GridItem(.flexible(), spacing: DS.Space.md),
        ]
        VStack(spacing: DS.Space.md) {
            // Row 1: Part Types + Total Stock
            LazyVGrid(columns: twoColumns, spacing: DS.Space.md) {
                DSKPICard(title: "Part Types", value: "\(stats.partTypes)", icon: "list.clipboard", color: .blue) {
                    activeSheet = .kpiDetail(.partTypes)
                }
                .accessibilityIdentifier("kpi_partTypes")
                DSKPICard(title: "Total Stock", value: "\(stats.totalStock)", icon: "shippingbox.fill", color: .teal) {
                    activeSheet = .kpiDetail(.totalStock)
                }
                .accessibilityIdentifier("kpi_totalStock")
            }
            // Row 2: Active Jobs + Pending Orders
            LazyVGrid(columns: twoColumns, spacing: DS.Space.md) {
                DSKPICard(title: "Active Jobs", value: "\(stats.activeJobs)", icon: "hammer", color: .orange) {
                    activeSheet = .kpiDetail(.activeJobs)
                }
                .accessibilityIdentifier("kpi_activeJobs")
                DSKPICard(title: "Pending Orders", value: "\(stats.pendingOrders)", icon: "cart", color: .purple) {
                    activeSheet = .kpiDetail(.pendingOrders)
                }
                .accessibilityIdentifier("kpi_pendingOrders")
            }
            // Row 3: Low Stock (full width)
            DSKPICard(title: "Low Stock", value: "\(stats.lowStockCount)", icon: "exclamationmark.triangle", color: stats.lowStockCount > 0 ? .red : .green) {
                activeSheet = .kpiDetail(.lowStock)
            }
            .accessibilityIdentifier("kpi_lowStock")
        }
        .padding(.horizontal, DS.Space.lg)
    }

    // MARK: - Charts Section

    @ViewBuilder
    private var chartsSection: some View {
        VStack(spacing: DS.Space.md) {
            if !laborChartData.isEmpty {
                LaborHoursChart(data: laborChartData)
                    .padding(.horizontal, DS.Space.lg)
            }
            if !stockChartData.isEmpty {
                StockLevelChart(data: stockChartData)
                    .padding(.horizontal, DS.Space.lg)
            }
            if !spendingChartData.isEmpty {
                SpendingChart(data: spendingChartData)
                    .padding(.horizontal, DS.Space.lg)
            }
        }
    }

    // MARK: - Alerts Content

    @ViewBuilder
    private var alertsContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if !certAlerts.isEmpty {
                alertsSection(
                    title: "Certification Alerts",
                    icon: "exclamationmark.shield.fill",
                    color: .orange,
                    items: certAlerts.map { "\($0.userName): \($0.certName) expires \($0.expiryDate)" }
                )
            }

            if !vehicleAlerts.isEmpty {
                alertsSection(
                    title: "Vehicle Alerts",
                    icon: "car.badge.gearshape.fill",
                    color: .red,
                    items: vehicleAlerts.map { "\($0.vehicleNumber): \($0.alertMessage)" }
                )
            }

            if certAlerts.isEmpty && vehicleAlerts.isEmpty {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.SemanticColor.success)
                        .accessibilityHidden(true)
                    Text("No upcoming expiry alerts")
                        .foregroundStyle(.secondary)
                }
                .padding(DS.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard()
                .padding(.horizontal, DS.Space.lg)
            }
        }
    }

    @ViewBuilder
    private func alertsSection(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .dsStyle(.sectionTitle)
            }

            ForEach(items, id: \.self) { item in
                HStack(spacing: DS.Space.sm) {
                    Circle()
                        .fill(DS.SemanticColor.tint(color))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(item)
                        .dsStyle(.detail)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .padding(.horizontal, DS.Space.lg)
    }

    // MARK: - Background Tasks Card

    @ViewBuilder
    private var backgroundTasksCard: some View {
        if let summary = taskSummary, summary.totalRuns > 0 {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                // Header
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "gearshape.2.fill")
                        .foregroundStyle(.indigo)
                        .accessibilityHidden(true)
                    Text("Background Tasks")
                        .dsStyle(.sectionTitle)
                    Spacer()
                    Text("24h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Space.xs)
                        .padding(.vertical, DS.Space.xxxs)
                        .background(
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                        )
                }

                // Summary row
                HStack(spacing: DS.Space.lg) {
                    taskSummaryStat(
                        count: summary.totalRuns,
                        label: "Runs",
                        color: .primary
                    )
                    taskSummaryStat(
                        count: summary.successCount,
                        label: "OK",
                        color: DS.SemanticColor.success
                    )
                    if summary.failureCount > 0 {
                        taskSummaryStat(
                            count: summary.failureCount,
                            label: "Failed",
                            color: DS.SemanticColor.error
                        )
                    }
                    if summary.runningCount > 0 {
                        taskSummaryStat(
                            count: summary.runningCount,
                            label: "Running",
                            color: .blue
                        )
                    }
                    Spacer()
                }

                // Recent tasks (up to 3)
                if !recentTasks.isEmpty {
                    Divider()

                    ForEach(recentTasks.prefix(3)) { task in
                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: task.statusIcon)
                                .font(.caption)
                                .foregroundStyle(colorForStatus(task.status))
                                .frame(width: 16)
                                .accessibilityLabel("Status: \(task.status)")

                            VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                                Text(task.taskName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)

                                if let summary = task.resultSummary {
                                    Text(summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else if let error = task.errorMessage {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(DS.SemanticColor.error)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            if let duration = task.durationString {
                                Text(duration)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } else if task.status == "running" {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                    }
                }
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .padding(.horizontal, DS.Space.lg)
        }
    }

    private func taskSummaryStat(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: DS.Space.xxxs) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "completed": return DS.SemanticColor.success
        case "failed": return DS.SemanticColor.error
        case "running": return .blue
        default: return .secondary
        }
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSSectionHeader(title: "Quick Actions")
                .padding(.horizontal, DS.Space.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.md) {
                    NavigationLink(value: DashboardDestination.scanner) {
                        DSQuickActionButton(title: "Scan QR", icon: "qrcode.viewfinder", color: .purple)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quickAction_scanQR")

                    NavigationLink(value: DashboardDestination.clock) {
                        DSQuickActionButton(title: "Clock In", icon: "clock.badge.checkmark.fill", color: .green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quickAction_clockIn")

                    NavigationLink(value: DashboardDestination.dailyReport) {
                        DSQuickActionButton(title: "Daily Report", icon: "doc.text.magnifyingglass", color: .indigo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quickAction_dailyReport")

                    DSQuickActionButton(title: "Move Stock", icon: "arrow.left.arrow.right", color: .orange) {
                        navigateToModule("warehouse")
                    }
                    .accessibilityIdentifier("quickAction_moveStock")
                    DSQuickActionButton(title: "New Order", icon: "plus.circle.fill", color: .blue) {
                        navigateToModule("orders")
                    }
                    .accessibilityIdentifier("quickAction_newOrder")
                }
                .padding(.horizontal, DS.Space.lg)
            }
        }
    }

    // Daily Report is now a separate sub-page: DashboardDailyReportPage

    // Daily report cards (pendingActions, todayActivity, expectedDeliveries, budgetAlerts)
    // are now in DashboardDailyReportPage.swift

    // MARK: - Navigation

    private func navigateToModule(_ moduleId: String) {
        NotificationCenter.default.post(
            name: .navigateToModule,
            object: nil,
            userInfo: ["moduleId": moduleId]
        )
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        loadError = nil
        do {
            guard let service = appCore.dashboardService else {
                await MainActor.run {
                    loadError = "Dashboard service not available"
                    isLoading = false
                }
                return
            }

            let currentUserId = appCore.currentUser?.id
            let bgService = appCore.backgroundTaskService

            // KPI summary via DashboardService
            let kpi = try service.getKPISummary()
            let empCount = (try? service.getEmployeeCount()) ?? 0
            let newStats = DashboardStats(
                partTypes: kpi.partTypes,
                totalStock: kpi.totalStock,
                activeJobs: kpi.activeJobs,
                pendingOrders: kpi.pendingOrders,
                lowStockCount: kpi.lowStockAlerts,
                employeeCount: empCount
            )

            // Alerts via DashboardService
            let certResults = try service.getCertificationExpiryAlerts()
            let certs = certResults.map { a in
                CertAlert(userName: a.displayName, certName: a.certName, expiryDate: a.expiryDate)
            }

            let vehicleResults = try service.getVehicleExpiryAlerts()
            let vAlerts = vehicleResults.map { a in
                VehicleAlert(vehicleNumber: a.vehicleNumber,
                             alertMessage: "\(a.expiryType.capitalized) expires \(a.expiryDate)")
            }

            // Clock status
            var clockStatus = DashboardService.ClockStatus(isClockedIn: false, jobName: nil, jobNumber: nil, clockInTimestamp: nil)
            if let userId = currentUserId {
                clockStatus = try service.getClockStatus(userId: userId)
            }

            // Background task summary
            let bgSummary = try? bgService?.last24HoursSummary()
            let bgRecent = (try? bgService?.recentTasks(limit: 3)) ?? []

            // Warehouse floor plan check for onboarding checklist
            let hasFloorPlan = (try? appCore.warehouseService?.listFloorPlans().count ?? 0) ?? 0 > 0

            await MainActor.run {
                warehouseHasFloorPlan = hasFloorPlan
                stats = newStats
                certAlerts = certs
                vehicleAlerts = vAlerts
                taskSummary = bgSummary
                recentTasks = bgRecent
                isCurrentlyClockedIn = clockStatus.isClockedIn
                clockedInJobName = clockStatus.jobName
                clockedInJobNumber = clockStatus.jobNumber
                if let timeStr = clockStatus.clockInTimestamp {
                    clockInTime = Formatters.iso8601Fractional.date(from: timeStr)
                        ?? Formatters.iso8601Basic.date(from: timeStr)
                    updateClockDuration()
                } else {
                    clockInTime = nil
                }
                isLoading = false
            }

            // Load chart data in background (non-blocking)
            await loadChartData()
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load dashboard")
                isLoading = false
            }
        }
    }

    /// Loads chart data for the dashboard visualizations.
    @Sendable
    private func loadChartData() async {
        guard let service = appCore.dashboardService else {
            loadError = "Dashboard service not available"
            isLoading = false
            return
        }
        do {
            // Labor hours for past 7 days
            let laborRows = try service.getLaborChartData()
            let laborDays = laborRows.map { row in
                let date = Formatters.localDateFormatter.date(from: row.dateString) ?? Date()
                return LaborDayData(
                    dayLabel: Formatters.dayOfWeekFormatter.string(from: date),
                    date: row.dateString,
                    regularHours: row.regularHours,
                    overtimeHours: row.overtimeHours
                )
            }

            // Stock levels
            let stockRows = try service.getStockChartData()
            let stockLevels = stockRows.map { row in
                StockLevelData(
                    partName: row.partName,
                    quantity: row.quantity,
                    minLevel: row.minLevel
                )
            }

            // Spending breakdown
            let spendingRows = try service.getSpendingChartData()
            let colorMap: [String: Color] = ["Labor": .blue, "Parts": .orange, "Fuel": .green]
            let spending = spendingRows.map { row in
                SpendingCategory(
                    name: row.name,
                    amount: row.amount,
                    color: colorMap[row.name] ?? .gray
                )
            }

            await MainActor.run {
                laborChartData = laborDays
                stockChartData = stockLevels
                spendingChartData = spending
            }
        } catch { loadError = userFriendlyError(error, context: "load dashboard") }
    }
}

// MARK: - Data Types

private struct DashboardStats: Sendable {
    var partTypes = 0
    var totalStock = 0
    var activeJobs = 0
    var pendingOrders = 0
    var lowStockCount = 0
    var employeeCount = 0
}

private struct CertAlert: Sendable {
    let userName: String
    let certName: String
    let expiryDate: String
}

private struct VehicleAlert: Sendable {
    let vehicleNumber: String
    let alertMessage: String
}


