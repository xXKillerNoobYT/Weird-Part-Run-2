import SwiftUI
import Combine
import WiredPartCore

/// Standalone Daily Report page, pushed as a sub-page from the Dashboard.
///
/// Shows: pending actions, today's activity, expected deliveries, budget alerts.
/// Self-contained — loads its own data from the database.
struct DashboardDailyReportPage: View {
    @EnvironmentObject private var appCore: AppCore

    // Data state
    @State private var pendingJPOs: Int = 0
    @State private var pendingPOs: Int = 0
    @State private var returnsToSort: Int = 0
    @State private var overdueDeliveries: Int = 0
    @State private var todayCreatedOrders: Int = 0
    @State private var todayReceivedItems: Int = 0
    @State private var todayReturns: Int = 0
    @State private var expectedDeliveries: [ExpectedDelivery] = []
    @State private var budgetAlerts: [JobBudgetAlert] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var timerCancellable: AnyCancellable?

    // My Hours
    @State private var myTodayHours: Double = 0
    @State private var myClockInTime: String?
    @State private var myCurrentJob: String?
    @State private var myBreakMinutes: Int = 0
    @State private var myJobBreakdown: [JobTimeEntry] = []

    // Team (managers only)
    @State private var teamClockedIn: [TeamMemberStatus] = []

    // Fast action sheets
    private enum ActiveSheet: String, Identifiable {
        case reportProblem
        case submitReport
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            OnboardingBanner(pageId: "dashboard-report")

            if isLoading {
                DSLoadingState()
                    .padding(.top, DS.Space.jumbo)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
                    .padding(.top, DS.Space.xl)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    // Fast Actions Bar
                    fastActionsBar
                        .padding(.horizontal, DS.Space.lg)

                    // Overdue alert banner
                    if overdueDeliveries > 0 {
                        DSAlertBanner(
                            severity: .error,
                            title: "\(overdueDeliveries) overdue deliver\(overdueDeliveries == 1 ? "y" : "ies")",
                            message: "Immediate attention required"
                        )
                        .padding(.horizontal, DS.Space.lg)
                    }

                    // My Hours Today
                    myHoursTodayCard
                        .padding(.horizontal, DS.Space.lg)

                    // Pending Actions
                    pendingActionsCard
                        .padding(.horizontal, DS.Space.lg)

                    // Today's Activity
                    todayActivityCard
                        .padding(.horizontal, DS.Space.lg)

                    // Who's Clocked In (managers only)
                    if appCore.hasPermission("view_labor") && !teamClockedIn.isEmpty {
                        teamClockedInCard
                            .padding(.horizontal, DS.Space.lg)
                    }

                    // Expected Deliveries
                    expectedDeliveriesCard
                        .padding(.horizontal, DS.Space.lg)

                    // Budget Alerts
                    if !budgetAlerts.isEmpty {
                        budgetAlertsCard
                            .padding(.horizontal, DS.Space.lg)
                    }

                    // Live indicator
                    HStack(spacing: DS.Space.xs) {
                        Circle()
                            .fill(DS.SemanticColor.success)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text("Live — updates every 60 seconds")
                            .dsStyle(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Space.sm)
                }
                .padding(.vertical)
            }
        }
        // Fix #149: dismiss keyboard when scrolling report page
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await loadData() }
        .background(DS.Background.page)
        .navigationTitle("Daily Report")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .task {
            await loadData()
            appCore.onboardingManager?.markCompleted("daily-report-view")
        }
        .onAppear {
            timerCancellable = refreshTimer.sink { _ in
                Task { await loadData() }
            }
        }
        .onDisappear {
            timerCancellable?.cancel()
            timerCancellable = nil
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .reportProblem:
                ReportProblemSheet()
                    .environmentObject(appCore)
            case .submitReport:
                SubmitDailyReportSheet()
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Daily Report Help",
                    sections: [
                        ("Overview", "A real-time snapshot of today's operations. Shows your hours, pending actions, activity stats, expected deliveries, and budget alerts."),
                        ("Fast Actions", "Use the action bar at the top for quick lunch breaks, reporting problems, or submitting your daily report."),
                        ("Team View", "Managers can see who is clocked in and their current job assignments. Pull down to refresh data.")
                    ]
                )
            }
        }
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        guard let service = appCore.dashboardService else {
            await MainActor.run {
                loadError = "Dashboard service not available"
                isLoading = false
            }
            return
        }

        let currentUserId = appCore.currentUser?.id

        do {
            // Fetch daily report counters via DashboardService
            let report = try service.getDailyReport()
            let expDeliv = try service.getExpectedDeliveries()
            let bAlerts = try service.getBudgetAlerts()

            // My hours today
            var myHoursResult: DashboardService.MyHoursToday?
            if let userId = currentUserId {
                myHoursResult = try service.getMyHoursToday(userId: userId)
            }

            // Team clocked in
            let teamResult = try service.getTeamClockedIn()

            await MainActor.run {
                pendingJPOs = report.pendingJPOs
                pendingPOs = report.pendingPOs
                returnsToSort = report.returnsToSort
                overdueDeliveries = report.overdueDeliveries
                todayCreatedOrders = report.todayCreatedOrders
                todayReceivedItems = report.todayReceivedItems
                todayReturns = report.todayReturns

                expectedDeliveries = expDeliv.map { row in
                    ExpectedDelivery(
                        id: row.id,
                        poNumber: row.poNumber,
                        supplierName: row.supplierName,
                        expectedDate: row.expectedDate,
                        lineCount: row.lineCount,
                        isOverdue: row.isOverdue
                    )
                }

                budgetAlerts = bAlerts.map { row in
                    JobBudgetAlert(
                        id: row.id,
                        jobName: row.jobName,
                        currentSpend: row.currentSpend,
                        budgetLimit: row.budgetLimit,
                        pctUsed: row.pctUsed
                    )
                }

                if let myHours = myHoursResult {
                    myTodayHours = myHours.totalHours
                    myClockInTime = myHours.clockInTime
                    myCurrentJob = myHours.currentJobName
                    myBreakMinutes = myHours.breakMinutes
                    myJobBreakdown = myHours.jobBreakdown.map { entry in
                        JobTimeEntry(
                            id: entry.jobName,
                            jobName: entry.jobName,
                            hours: entry.hours
                        )
                    }
                }

                teamClockedIn = teamResult.map { member in
                    // Calculate duration text from raw clock-in timestamp
                    let durationText: String = {
                        guard member.clockInRaw.count >= 19 else { return "—" }
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        let formatterBasic = ISO8601DateFormatter()
                        formatterBasic.formatOptions = [.withInternetDateTime]
                        if let date = formatter.date(from: member.clockInRaw) ?? formatterBasic.date(from: member.clockInRaw) {
                            let mins = Int(Date().timeIntervalSince(date) / 60)
                            if mins < 60 { return "\(mins)m" }
                            return "\(mins / 60)h \(mins % 60)m"
                        }
                        return "—"
                    }()
                    return TeamMemberStatus(
                        id: member.id,
                        displayName: member.displayName,
                        jobName: member.jobName,
                        clockInTime: member.clockInTime,
                        durationText: durationText
                    )
                }

                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load daily report")
                isLoading = false
            }
        }
    }

    // MARK: - My Hours Today

    @ViewBuilder
    private var myHoursTodayCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("My Hours Today")
                    .dsStyle(.sectionTitle)
                Spacer()
                Text(String(format: "%.1fh", myTodayHours))
                    .dsStyle(.kpiValue)
                    .foregroundStyle(.blue)
            }

            // Current clock status
            HStack(spacing: DS.Space.md) {
                if let clockIn = myClockInTime, let job = myCurrentJob {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clocked in since \(clockIn)")
                            .dsStyle(.detail)
                        Text(job)
                            .dsStyle(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "clock")
                        .foregroundStyle(.gray)
                        .accessibilityHidden(true)
                    Text("Not currently clocked in")
                        .dsStyle(.detail)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Job breakdown
            if !myJobBreakdown.isEmpty {
                Divider()
                VStack(spacing: DS.Space.xs) {
                    ForEach(myJobBreakdown) { entry in
                        HStack {
                            Text(entry.jobName)
                                .dsStyle(.detail)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1fh", entry.hours))
                                .dsStyle(.detail)
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                    }
                }
            }

            if myBreakMinutes > 0 {
                HStack {
                    Text("Break time")
                        .dsStyle(.detail)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(myBreakMinutes)m")
                        .dsStyle(.detail)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(DS.Space.lg)
        .dsCard()
    }

    // MARK: - Fast Actions Bar

    @ViewBuilder
    private var fastActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.md) {
                DSQuickActionButton(title: "Lunch", icon: "fork.knife", color: .green) {
                    startLunchOrBreak()
                }
                DSQuickActionButton(title: "Break", icon: "cup.and.saucer.fill", color: .purple) {
                    startLunchOrBreak()
                }
                DSQuickActionButton(title: "Problem", icon: "exclamationmark.triangle.fill", color: .red) {
                    activeSheet = .reportProblem
                }
                DSQuickActionButton(title: "Day Report", icon: "doc.text.fill", color: .indigo) {
                    activeSheet = .submitReport
                }
                DSQuickActionButton(title: "Supply Run", icon: "truck.box.fill", color: .blue) {
                    // Geofencing (12D) handles supply run transitions automatically.
                    // This button clocks out as a quick action.
                    startLunchOrBreak()
                }
            }
        }
    }

    /// Clocks out the current user (for lunch, break, or supply run).
    private func startLunchOrBreak() {
        guard let service = appCore.jobsService,
              let userId = appCore.currentUser?.id else {
            loadError = "Jobs service not available"
            return
        }
        do {
            if let active = try service.getActiveClockEntry(userId: userId) {
                try service.clockOut(laborEntryId: active.id)
            }
            Task { await loadData() }
        } catch {
            loadError = userFriendlyError(error, context: "load daily report")
        }
    }

    // MARK: - Pending Actions Card

    private var pendingActionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pending Actions")
                    .dsStyle(.sectionTitle)
                Spacer()
                let total = pendingJPOs + pendingPOs + returnsToSort + overdueDeliveries
                Text(total > 0 ? "\(total)" : "All clear")
                    .dsStyle(.label)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xxxs + 1)
                    .background(Capsule().fill(DS.SemanticColor.tint(total > 0 ? DS.SemanticColor.warning : DS.SemanticColor.success)))
                    .foregroundStyle(total > 0 ? DS.SemanticColor.warning : DS.SemanticColor.success)
            }
            .padding(DS.Space.lg)

            VStack(spacing: 0) {
                pendingActionRow("JPOs awaiting approval", count: pendingJPOs, icon: "cart", urgent: false)
                Divider().padding(.leading, DS.Space.jumbo)
                pendingActionRow("POs to submit", count: pendingPOs, icon: "shippingbox", urgent: false)
                Divider().padding(.leading, DS.Space.jumbo)
                pendingActionRow("Returns to sort", count: returnsToSort, icon: "arrow.uturn.backward.circle", urgent: false)
                Divider().padding(.leading, DS.Space.jumbo)
                pendingActionRow("Overdue deliveries", count: overdueDeliveries, icon: "exclamationmark.triangle", urgent: true)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.md)
        }
        .dsCard()
    }

    private func pendingActionRow(_ label: String, count: Int, icon: String, urgent: Bool) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(urgent && count > 0 ? DS.SemanticColor.error : .secondary)
                .accessibilityHidden(true)
            Text(label)
                .dsStyle(.detail)
            Spacer()
            Text("\(count)")
                .dsStyle(.detail)
                .fontWeight(.bold)
                .foregroundStyle(
                    count > 0
                        ? (urgent ? DS.SemanticColor.error : DS.SemanticColor.warning)
                        : .secondary
                )
        }
        .padding(.vertical, DS.Space.xs)
        .opacity(count > 0 ? 1 : 0.5)
    }

    // MARK: - Today's Activity

    private var todayActivityCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Today's Activity")
                .dsStyle(.sectionTitle)

            HStack(spacing: DS.Space.md) {
                activityStat("Orders Created", value: todayCreatedOrders, color: .blue)
                activityStat("Items Received", value: todayReceivedItems, color: .green)
                activityStat("Returns", value: todayReturns, color: .purple)
            }
        }
        .padding(DS.Space.lg)
        .dsCard()
    }

    private func activityStat(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: DS.Space.xxs) {
            Text("\(value)")
                .dsStyle(.kpiValue)
                .foregroundStyle(color)
            Text(label)
                .dsStyle(.label)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.SemanticColor.muted(color)))
    }

    // MARK: - Expected Deliveries

    private var expectedDeliveriesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Expected Deliveries This Week")
                    .dsStyle(.sectionTitle)
                Spacer()
                if !expectedDeliveries.isEmpty {
                    Text("\(expectedDeliveries.count)")
                        .dsStyle(.label)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.xxxs + 1)
                        .background(Capsule().fill(Color(.systemGray4)))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DS.Space.lg)

            if expectedDeliveries.isEmpty {
                Text("No deliveries expected this week.")
                    .dsStyle(.detail)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, DS.Space.lg)
            } else {
                VStack(spacing: DS.Space.sm) {
                    ForEach(expectedDeliveries) { delivery in
                        HStack(spacing: DS.Space.md) {
                            Image(systemName: "truck.box")
                                .foregroundStyle(delivery.isOverdue ? DS.SemanticColor.error : .secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                                Text("\(delivery.poNumber) — \(delivery.supplierName)")
                                    .dsStyle(.detail)
                                    .lineLimit(1)
                                Text("\(delivery.lineCount) item\(delivery.lineCount == 1 ? "" : "s")")
                                    .dsStyle(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: DS.Space.xxxs) {
                                Text(delivery.expectedDate)
                                    .dsStyle(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(delivery.isOverdue ? DS.SemanticColor.error : .secondary)
                                if delivery.isOverdue {
                                    Text("Overdue")
                                        .dsStyle(.label)
                                        .padding(.horizontal, DS.Space.xs)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(DS.SemanticColor.tint(DS.SemanticColor.error)))
                                        .foregroundStyle(DS.SemanticColor.error)
                                }
                            }
                        }
                        .padding(DS.Space.md - 2)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .stroke(delivery.isOverdue ? DS.SemanticColor.error.opacity(0.3) : Color(.separator), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.md)
            }
        }
        .dsCard()
    }

    // MARK: - Who's Clocked In (Team)

    @ViewBuilder
    private var teamClockedInCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Who's Clocked In")
                    .dsStyle(.sectionTitle)
                Spacer()
                Text("\(teamClockedIn.count)")
                    .dsStyle(.label)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xxxs + 1)
                    .background(Capsule().fill(DS.SemanticColor.tint(.green)))
                    .foregroundStyle(.green)
            }
            .padding(DS.Space.lg)

            VStack(spacing: DS.Space.sm) {
                ForEach(teamClockedIn) { member in
                    HStack(spacing: DS.Space.md) {
                        // Avatar circle with initials
                        Text(String(member.displayName.prefix(1)))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.blue))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                                .dsStyle(.detail)
                                .fontWeight(.medium)
                            Text(member.jobName)
                                .dsStyle(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(member.durationText)
                            .dsStyle(.detail)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.md)
        }
        .dsCard()
    }

    // MARK: - Budget Alerts

    private var budgetAlertsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Budget Alerts")
                .dsStyle(.sectionTitle)
                .padding(DS.Space.lg)

            VStack(spacing: DS.Space.sm) {
                ForEach(budgetAlerts) { alert in
                    let alertColor = alert.pctUsed >= 100 ? DS.SemanticColor.error : DS.SemanticColor.warning
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: "dollarsign.circle")
                            .foregroundStyle(alertColor)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                            Text(alert.jobName)
                                .dsStyle(.detail)
                                .lineLimit(1)
                            Text("\(String(format: "$%.2f", alert.currentSpend)) of \(String(format: "$%.2f", alert.budgetLimit))")
                                .dsStyle(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(alert.pctUsed))%")
                            .dsStyle(.label)
                            .padding(.horizontal, DS.Space.sm)
                            .padding(.vertical, DS.Space.xxxs + 1)
                            .background(Capsule().fill(DS.SemanticColor.tint(alertColor)))
                            .foregroundStyle(alertColor)
                    }
                    .padding(DS.Space.md - 2)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .stroke(alertColor.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.md)
        }
        .dsCard()
    }
}

// MARK: - Local Model Types

private struct ExpectedDelivery: Identifiable, Sendable {
    let id: Int64
    let poNumber: String
    let supplierName: String
    let expectedDate: String
    let lineCount: Int
    let isOverdue: Bool
}

private struct JobBudgetAlert: Identifiable, Sendable {
    let id: Int64
    let jobName: String
    let currentSpend: Double
    let budgetLimit: Double
    let pctUsed: Double
}

private struct JobTimeEntry: Identifiable, Sendable {
    let id: String
    let jobName: String
    let hours: Double
}

private struct TeamMemberStatus: Identifiable, Sendable {
    let id: Int64
    let displayName: String
    let jobName: String
    let clockInTime: String
    let durationText: String
}

// MARK: - Report Problem Sheet

private struct ReportProblemSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedJobId: Int64?
    @State private var description = ""
    @State private var jobs: [(id: Int64, name: String)] = []
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var wasAutoFilled = false

    var body: some View {
        let dismissSheet = { dismiss() }
        NavigationStack {
            Form {
                Section {
                    Picker("Job", selection: $selectedJobId) {
                        Text("Select a job").tag(nil as Int64?)
                        ForEach(jobs, id: \.id) { job in
                            Text(job.name).tag(job.id as Int64?)
                        }
                    }
                    .onChange(of: selectedJobId) { _, _ in
                        wasAutoFilled = false
                    }
                } header: {
                    Text("Job")
                } footer: {
                    if wasAutoFilled {
                        Text("Auto-filled from your active clock entry")
                    }
                }
                Section("Problem Description") {
                    TextField("Describe the problem...", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Report Problem")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismissSheet() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submitProblem()
                    }
                    .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .task {
                loadJobs()
                autoFillFromClockEntry()
            }
        }
    }

    private func submitProblem() {
        guard let service = appCore.dashboardService,
              let userId = appCore.currentUser?.id else {
            saveError = "Service not available"
            return
        }
        isSaving = true
        saveError = nil
        do {
            try service.reportProblem(
                userId: userId,
                jobId: selectedJobId,
                description: description.trimmingCharacters(in: .whitespaces)
            )
            isSaving = false
            dismiss()
        } catch {
            saveError = userFriendlyError(error, context: "save daily report")
            isSaving = false
        }
    }

    private func loadJobs() {
        guard let service = appCore.dashboardService else {
            saveError = "Dashboard service not available"
            return
        }
        do {
            let activeJobs = try service.getActiveJobsForPicker()
            jobs = activeJobs.map { (id: $0.id, name: $0.jobName) }
        } catch {
            // Non-critical — picker will just be empty
        }
    }

    private func autoFillFromClockEntry() {
        guard selectedJobId == nil,
              let service = appCore.jobsService,
              let userId = appCore.currentUser?.id else { return }
        do {
            if let activeEntry = try service.getActiveClockEntry(userId: userId) {
                selectedJobId = activeEntry.jobId
                wasAutoFilled = true
            }
        } catch {
            // Non-fatal — user can still select manually
        }
    }
}

// MARK: - Submit Daily Report Sheet

private struct SubmitDailyReportSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var reportData: DailyReportGenerator.DailyReportData?
    @State private var todaysJobs: [(jobId: Int64, jobName: String, hours: Double)] = []
    @State private var selectedJobId: Int64?
    @State private var accomplishments = ""
    @State private var issues = ""
    @State private var tomorrowNotes = ""
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var isLoadingReport = true

    var body: some View {
        NavigationStack {
            Form {
                // Job picker (if multiple jobs today)
                if todaysJobs.count > 1 {
                    Section("Job") {
                        Picker("Select Job", selection: $selectedJobId) {
                            ForEach(todaysJobs, id: \.jobId) { job in
                                Text("\(job.jobName) (\(String(format: "%.1fh", job.hours)))")
                                    .tag(job.jobId as Int64?)
                            }
                        }
                        .onChange(of: selectedJobId) { _, newValue in
                            if let jid = newValue {
                                loadReportForJob(jid)
                            }
                        }
                    }
                }

                // System-generated section
                if let report = reportData {
                    Section {
                        HStack {
                            Label("Hours", systemImage: "clock")
                            Spacer()
                            Text(String(format: "%.1fh", report.totalHours))
                                .font(.headline)
                        }

                        if !report.breaksTaken.isEmpty {
                            ForEach(report.breaksTaken, id: \.startTime) { brk in
                                HStack {
                                    Image(systemName: "cup.and.saucer")
                                        .foregroundStyle(.orange)
                                        .accessibilityHidden(true)
                                    Text(brk.type.capitalized)
                                    Spacer()
                                    Text("\(brk.durationMinutes)m")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !report.todosCompleted.isEmpty {
                            ForEach(report.todosCompleted, id: \.name) { todo in
                                HStack {
                                    Image(systemName: todo.stage == "complete" ? "checkmark.circle.fill" : "circle.dotted")
                                        .foregroundStyle(todo.stage == "complete" ? .green : .blue)
                                        .accessibilityLabel(todo.stage == "complete" ? "Completed" : "In progress")
                                    Text(todo.name).lineLimit(1)
                                    Spacer()
                                    Text(todo.stage.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !report.jposCreated.isEmpty {
                            ForEach(report.jposCreated, id: \.jpoNumber) { jpo in
                                HStack {
                                    Image(systemName: "doc.plaintext")
                                        .foregroundStyle(.purple)
                                        .accessibilityHidden(true)
                                    Text(jpo.jpoNumber)
                                    Spacer()
                                    Text("\(jpo.lineCount) items")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !report.qaQuestions.isEmpty {
                            ForEach(report.qaQuestions, id: \.question) { qa in
                                HStack {
                                    Image(systemName: "questionmark.circle")
                                        .foregroundStyle(.blue)
                                        .accessibilityHidden(true)
                                    Text(qa.question).lineLimit(1)
                                    Spacer()
                                    Text(qa.status.capitalized)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }

                        if report.messagesCount > 0 {
                            HStack {
                                Image(systemName: "bubble.left")
                                    .foregroundStyle(.indigo)
                                    .accessibilityHidden(true)
                                Text("Messages sent")
                                Spacer()
                                Text("\(report.messagesCount)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("System-Generated")
                    } footer: {
                        Text("Automatically compiled from today's activity")
                    }
                } else if isLoadingReport {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading report data...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Manual fields
                Section("What was accomplished today?") {
                    TextField("Work completed...", text: $accomplishments, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Issues encountered") {
                    TextField("Any problems or blockers...", text: $issues, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Notes for tomorrow") {
                    TextField("What needs to happen next...", text: $tomorrowNotes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Daily Report")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submitReport()
                    }
                    .disabled(accomplishments.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .task { loadInitialData() }
        }
    }

    private func loadInitialData() {
        guard let generator = appCore.dailyReportGenerator,
              let userId = appCore.currentUser?.id else {
            isLoadingReport = false
            return
        }
        do {
            todaysJobs = try generator.getTodaysJobs(userId: userId)
            if let primaryJob = todaysJobs.first {
                selectedJobId = primaryJob.jobId
                reportData = try generator.generateReport(userId: userId, jobId: primaryJob.jobId)
            }
        } catch {
            // Non-fatal — manual report still works
        }
        isLoadingReport = false
    }

    private func loadReportForJob(_ jobId: Int64) {
        guard let generator = appCore.dailyReportGenerator,
              let userId = appCore.currentUser?.id else { return }
        do {
            reportData = try generator.generateReport(userId: userId, jobId: jobId)
        } catch {
            // Non-fatal
        }
    }

    private func submitReport() {
        guard let service = appCore.dashboardService,
              let userId = appCore.currentUser?.id else {
            saveError = "Service not available"
            return
        }
        isSaving = true
        saveError = nil
        do {
            try service.submitDailyReport(
                userId: userId,
                accomplishments: accomplishments.trimmingCharacters(in: .whitespaces),
                issues: issues.trimmingCharacters(in: .whitespaces),
                tomorrowNotes: tomorrowNotes.trimmingCharacters(in: .whitespaces)
            )
            isSaving = false
            dismiss()
        } catch {
            saveError = userFriendlyError(error, context: "save daily report")
            isSaving = false
        }
    }
}
