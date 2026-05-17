import SwiftUI
import WiredPartCore
import UserNotifications

/// Office Dashboard — the manager's morning starting point.
///
/// Sections: AI Briefing, Needs Your Attention (priority-colored),
/// Today's Schedule, Financial Snapshot (hat-gated), Background Tasks.
struct IOSOfficeDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var briefing: DashboardService.OfficeBriefing?
    @State private var smartCards: [DashboardService.OfficeSmartCard] = []
    @State private var attentionItems: [DashboardService.AttentionItem] = []
    @State private var todaySchedule: [DashboardService.ScheduleItem] = []
    @State private var financialSnapshot: DashboardService.FinancialSnapshot?
    @State private var backgroundTaskStatuses: [BackgroundTaskService.OfficeStatusRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var activeSheet: ActiveSheet?
    @State private var selectedAttentionItem: DashboardService.AttentionItem?

    private enum ActiveSheet: Identifiable {
        case help
        case attentionDetail(DashboardService.AttentionItem)
        var id: String {
            switch self {
            case .help: "help"
            case .attentionDetail(let item): "attention-\(item.id)"
            }
        }
    }

    var body: some View {
        List {
            OnboardingBanner(pageId: "office-dashboard")
            SkippedModuleHint(moduleId: "office")

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading dashboard...")
                        Spacer()
                    }
                }
            } else if let error = loadError {
                Section {
                    ErrorStateView(message: error) { loadData() }
                }
            } else {
                smartCardsSection
                aiSummarySection
                attentionSection
                scheduleSection
                quickActionsSection
                if appCore.hasPermission(financialValuesPermission) {
                    financialSection
                }
                backgroundTasksSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Office Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(
                    title: "Office Dashboard Help",
                    sections: [
                        ("What This Page Does", "Your morning command center. Shows an AI-generated daily briefing, items that need your attention (color-coded by priority), today's crew schedule, a financial snapshot, and background task status."),
                        ("How to Use It", "Pull down to refresh all sections. The AI briefing updates hourly and highlights key things you should know. Attention items are sorted by urgency: red means overdue, orange is high priority. The financial snapshot compares this week and month to previous periods so you can spot spending trends."),
                        ("Financial Snapshot", "Only visible if you have the 'view financials' permission. Shows weekly and monthly spend with comparisons to the prior period, plus outstanding PO value."),
                        ("Tips", "Check this page first thing each morning. The briefing and attention items give you a quick read on what matters today without digging through individual pages.")
                    ]
                )
            case .attentionDetail(let item):
                NavigationStack {
                    List {
                        Section("Details") {
                            LabeledContent("Type", value: item.itemType.replacingOccurrences(of: "_", with: " ").capitalized)
                            LabeledContent("Priority") {
                                Text(String(describing: item.priority).capitalized)
                                    .foregroundStyle(colorForPriority(item.priority))
                                    .fontWeight(.semibold)
                            }
                            LabeledContent("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        Section("Description") {
                            Text(item.subtitle)
                                .font(.body)
                        }
                        Section("Suggested Action") {
                            Text(suggestedAction(for: item))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle(item.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { activeSheet = nil }
                        }
                    }
                }
            }
        }
        .refreshable { loadData() }
        .task {
            appCore.onboardingManager?.markCompleted("office-view")
            loadData()
        }
        .onAppear { postPageContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .officeDashboardPageInactive, object: nil)
        }
    }

    // MARK: - AI Summary Section

    @ViewBuilder
    private var smartCardsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(smartCards) { card in
                        if isApprovalCard(card) {
                            NavigationLink {
                                IOSUnifiedApprovalsPage(initialFilter: approvalFilter(for: card))
                                    .environmentObject(appCore)
                            } label: {
                                smartCardView(card)
                            }
                            .buttonStyle(.plain)
                        } else {
                            smartCardView(card)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Command Center")
        }
    }

    private func smartCardView(_ card: DashboardService.OfficeSmartCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: card.systemImage)
                    .font(.headline)
                    .foregroundStyle(colorForPriority(card.severity))
                    .accessibilityHidden(true)
                Spacer()
                Text("\(card.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            Text(card.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(card.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(width: 138, height: 112, alignment: .topLeading)
        .padding(10)
        .background(colorForPriority(card.severity).opacity(card.count > 0 ? 0.14 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.title), \(card.count), \(card.subtitle)")
    }

    private func isApprovalCard(_ card: DashboardService.OfficeSmartCard) -> Bool {
        card.id == "approvals_pending" || card.id == "jpos_pending"
    }

    private func approvalFilter(for card: DashboardService.OfficeSmartCard) -> String? {
        switch card.id {
        case "approvals_pending": return nil
        case "jpos_pending": return "jpo"
        default: return nil
        }
    }

    @ViewBuilder
    private var aiSummarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                        .accessibilityHidden(true)
                    Text("Daily Briefing")
                        .font(.headline)
                    Spacer()
                    if let briefing {
                        Text(briefing.generatedAt, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let briefing {
                    Text(briefing.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !briefing.highlights.isEmpty {
                        Divider()
                        ForEach(briefing.highlights, id: \.self) { highlight in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                    .accessibilityHidden(true)
                                Text(highlight)
                                    .font(.caption)
                            }
                        }
                    }
                } else {
                    Text("Generating briefing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Attention Section

    @ViewBuilder
    private var attentionSection: some View {
        Section {
            if attentionItems.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All caught up!")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(attentionItems) { item in
                    Button {
                        activeSheet = .attentionDetail(item)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: iconForPriority(item.priority))
                                .foregroundStyle(colorForPriority(item.priority))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(item.createdAt, format: .relative(presentation: .numeric))
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text("Needs Your Attention")
                Spacer()
                if !attentionItems.isEmpty {
                    Text("\(attentionItems.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Schedule Section

    @ViewBuilder
    private var scheduleSection: some View {
        Section("Today's Schedule") {
            if todaySchedule.isEmpty {
                Text("Nothing scheduled for today")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todaySchedule) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.employeeName)
                                .font(.subheadline)
                            Text(item.jobName ?? "No job")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let shift = item.shiftStart {
                            Text(shift)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Financial Section

    @ViewBuilder
    private var financialSection: some View {
        Section("Financial Snapshot") {
            if let snapshot = financialSnapshot {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This Week")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(snapshot.spendingThisWeek))
                            .font(.title3)
                            .fontWeight(.semibold)
                        let diff = snapshot.spendingThisWeek - snapshot.spendingLastWeek
                        Text("\(diff >= 0 ? "+" : "")\(formatCurrency(diff)) vs last week")
                            .font(.caption2)
                            .foregroundStyle(diff <= 0 ? .green : .red)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("This Month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(snapshot.spendingThisMonth))
                            .font(.title3)
                            .fontWeight(.semibold)
                        let diff = snapshot.spendingThisMonth - snapshot.spendingLastMonth
                        Text("\(diff >= 0 ? "+" : "")\(formatCurrency(diff)) vs last month")
                            .font(.caption2)
                            .foregroundStyle(diff <= 0 ? .green : .red)
                    }
                }

                if snapshot.outstandingPOValue > 0 {
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("Outstanding POs: \(formatCurrency(snapshot.outstandingPOValue))")
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Quick Actions Section

    @ViewBuilder
    private var quickActionsSection: some View {
        Section("Quick Actions") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink {
                    OrdersRouter(tabId: "orders-jpos")
                        .environmentObject(appCore)
                } label: {
                    quickActionLabel("Review JPOs", icon: "doc.text.magnifyingglass", color: .blue)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    IOSManageJobsPage()
                        .environmentObject(appCore)
                } label: {
                    quickActionLabel("Manage Jobs", icon: "hammer.fill", color: .orange)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    IOSReportsRouter(tabId: "reports-hub")
                        .environmentObject(appCore)
                } label: {
                    quickActionLabel("View Reports", icon: "chart.bar.fill", color: .green)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    IOSDispatchPage()
                        .environmentObject(appCore)
                } label: {
                    quickActionLabel("Dispatch Board", icon: "person.3.fill", color: .purple)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
    }

    private func quickActionLabel(_ title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Background Tasks Section

    @ViewBuilder
    private var backgroundTasksSection: some View {
        Section("Background") {
            ForEach(backgroundTaskStatuses) { status in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: status.systemImage)
                        .foregroundStyle(colorForBackgroundStatus(status.status))
                        .frame(width: 22)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.title)
                            .font(.subheadline)
                        Text(status.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(status.statusLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(colorForBackgroundStatus(status.status))
                }
            }
        }
    }

    // MARK: - Helpers

    private func colorForPriority(_ priority: DashboardService.AttentionPriority) -> Color {
        switch priority {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .overdue: return .red
        }
    }

    private func iconForPriority(_ priority: DashboardService.AttentionPriority) -> String {
        switch priority {
        case .low: return "circle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .overdue: return "flame.fill"
        }
    }

    private func colorForBackgroundStatus(_ status: BackgroundTaskService.OfficeStatus) -> Color {
        switch status {
        case .completed: return .green
        case .running: return .blue
        case .failed: return .red
        case .neverRun, .unavailable: return .secondary
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        Formatters.formatCurrencyWhole(value)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.dashboardService else {
            loadError = "Dashboard service not available"
            isLoading = false
            return
        }

        isLoading = true
        loadError = nil

        do {
            smartCards = try service.getOfficeSmartCards()
            briefing = try service.getOfficeBriefing(userId: appCore.currentUser?.id)
            scheduleDailyBriefingNotificationIfAllowed()

            attentionItems = try service.getAttentionItems()
            todaySchedule = try service.getTodaySchedule()
            backgroundTaskStatuses = try appCore.backgroundTaskService?.officeStatusRows() ?? BackgroundTaskService.OfficeStatusRow.unavailableRows()

            if appCore.hasPermission(financialValuesPermission) {
                financialSnapshot = try service.getFinancialSnapshot()
            } else {
                financialSnapshot = nil
            }
        } catch {
            loadError = userFriendlyError(error, context: "load office dashboard")
        }

        isLoading = false
        postPageContext()
    }

    private func postPageContext() {
        NotificationCenter.default.post(
            name: .officeDashboardPageActive,
            object: nil,
            userInfo: [
                "context": "Office Dashboard: \(smartCards.count) smart cards, \(attentionItems.count) attention items, \(todaySchedule.count) schedule items, financial snapshot visible: \(financialSnapshot != nil), background rows: \(backgroundTaskStatuses.count)."
            ]
        )
    }

    private func scheduleDailyBriefingNotificationIfAllowed() {
        guard let userId = appCore.currentUser?.id else { return }
        let hasOfficeAccess = appCore.hasPermission(officeAccessPermission)
        Task {
            _ = await OfficeDailyBriefingNotificationScheduler().scheduleIfAllowed(
                userId: userId,
                hasOfficeAccess: hasOfficeAccess
            )
        }
    }

    private func scheduleDailyBriefingNotificationIfAllowed() {
        guard let userId = appCore.currentUser?.id else { return }
        let hasOfficeAccess = appCore.hasPermission(officeAccessPermission)
        Task {
            _ = await OfficeDailyBriefingNotificationScheduler().scheduleIfAllowed(
                userId: userId,
                hasOfficeAccess: hasOfficeAccess
            )
        }
    }

    private func suggestedAction(for item: DashboardService.AttentionItem) -> String {
        switch item.itemType {
        case "overdue_po": return "Go to Orders → Purchase Orders to follow up with the supplier."
        case "low_stock": return "Go to Parts → Catalog to check stock levels and create a reorder."
        case "jpo_approval", "pending_approval": return "Go to Office → Approvals to review and approve."
        case "overdue_job": return "Go to Jobs to check status and update the timeline."
        case "maintenance_due": return "Go to Fleet → Maintenance to schedule service."
        case "expiring_cert": return "Go to People → Employee Detail to renew the certification."
        case "open_qa": return "Go to Chat → Q&A to answer or route the field question."
        case "warranty_expiring": return "Go to Jobs to review warranty follow-up before it expires."
        case "time_off": return "Go to Office → Approvals to approve or reject the time-off request."
        default: return "Review this item and take appropriate action."
        }
    }
}

enum OfficeDailyBriefingNotificationPermission: Sendable {
    case authorized
    case denied
    case notDetermined
}

enum OfficeDailyBriefingNotificationScheduleResult: Equatable, Sendable {
    case scheduled
    case alreadyScheduled
    case noOfficeAccess
    case permissionDenied
    case permissionNotDetermined
    case failed
}

protocol OfficeDailyBriefingNotificationCenter: Sendable {
    func authorizationStatus() async -> OfficeDailyBriefingNotificationPermission
    func pendingRequestIdentifiers() async -> Set<String>
    func addCalendarNotification(
        identifier: String,
        title: String,
        body: String,
        dateComponents: DateComponents,
        repeats: Bool
    ) async throws
}

struct OfficeDailyBriefingNotificationScheduler: Sendable {
    private let center: any OfficeDailyBriefingNotificationCenter
    private let calendar: Calendar

    init(
        center: any OfficeDailyBriefingNotificationCenter = UserNotificationCenterOfficeBriefingAdapter(),
        calendar: Calendar = .current
    ) {
        self.center = center
        self.calendar = calendar
    }

    func scheduleIfAllowed(
        userId: Int64,
        hasOfficeAccess: Bool,
        now: Date = Date()
    ) async -> OfficeDailyBriefingNotificationScheduleResult {
        guard hasOfficeAccess else { return .noOfficeAccess }

        switch await center.authorizationStatus() {
        case .authorized:
            break
        case .denied:
            return .permissionDenied
        case .notDetermined:
            return .permissionNotDetermined
        }

        let identifier = "office.daily-briefing.7am.user.\(userId)"
        if await center.pendingRequestIdentifiers().contains(identifier) {
            return .alreadyScheduled
        }

        var components = calendar.dateComponents([.timeZone], from: now)
        components.hour = 7
        components.minute = 0

        do {
            try await center.addCalendarNotification(
                identifier: identifier,
                title: "Your daily briefing is ready",
                body: "Your daily briefing is ready",
                dateComponents: components,
                repeats: true
            )
            return .scheduled
        } catch {
            return .failed
        }
    }
}

struct UserNotificationCenterOfficeBriefingAdapter: OfficeDailyBriefingNotificationCenter {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> OfficeDailyBriefingNotificationPermission {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    continuation.resume(returning: .authorized)
                case .denied:
                    continuation.resume(returning: .denied)
                case .notDetermined:
                    continuation.resume(returning: .notDetermined)
                @unknown default:
                    continuation.resume(returning: .denied)
                }
            }
        }
    }

    func pendingRequestIdentifiers() async -> Set<String> {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: Set(requests.map(\.identifier)))
            }
        }
    }

    func addCalendarNotification(
        identifier: String,
        title: String,
        body: String,
        dateComponents: DateComponents,
        repeats: Bool
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }
}
