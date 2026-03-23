import SwiftUI
import Combine
import GRDB
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
        .refreshable { await loadData() }
        .background(DS.Background.page)
        .navigationTitle("Daily Report")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .task { await loadData() }
        .onReceive(refreshTimer) { _ in
            Task { await loadData() }
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
        guard let db = appCore.db else {
            await MainActor.run {
                loadError = "Database not available"
                isLoading = false
            }
            return
        }

        let currentUserId = appCore.currentUser?.id

        do {
            let result = try await db.writer.read { conn -> DailyReportData in
                let pJPOs = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM job_parts_orders WHERE status = 'submitted' AND deleted_at IS NULL") ?? 0
                let pPOs = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM purchase_orders WHERE status = 'submitted' AND deleted_at IS NULL") ?? 0
                let rSort = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM returns WHERE status = 'submitted' AND deleted_at IS NULL") ?? 0
                let oDeliv = try Int.fetchOne(conn, sql: """
                    SELECT COUNT(*) FROM purchase_orders
                    WHERE expected_delivery IS NOT NULL
                      AND date(expected_delivery) < date('now')
                      AND status NOT IN ('received', 'cancelled')
                      AND deleted_at IS NULL
                    """) ?? 0

                let tOrders = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM purchase_orders WHERE date(created_at) = date('now') AND deleted_at IS NULL") ?? 0
                let tReceived = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM receiving_sessions WHERE date(created_at) = date('now') AND deleted_at IS NULL") ?? 0
                let tReturns = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM returns WHERE date(created_at) = date('now') AND deleted_at IS NULL") ?? 0

                let deliveryRows = try Row.fetchAll(conn, sql: """
                    SELECT po.id, po.po_number, po.expected_delivery,
                           COALESCE(s.name, 'Unknown') AS supplier_name,
                           (SELECT COUNT(*) FROM po_line_items pl WHERE pl.po_id = po.id AND pl.deleted_at IS NULL) AS line_count,
                           CASE WHEN date(po.expected_delivery) < date('now') THEN 1 ELSE 0 END AS is_overdue
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id
                    WHERE po.expected_delivery IS NOT NULL
                      AND po.status NOT IN ('received', 'cancelled')
                      AND po.deleted_at IS NULL
                      AND date(po.expected_delivery) BETWEEN date('now', '-7 days') AND date('now', '+7 days')
                    ORDER BY po.expected_delivery ASC
                    LIMIT 20
                    """)
                let expDeliv = deliveryRows.map { row in
                    ExpectedDelivery(
                        id: row["id"] ?? 0,
                        poNumber: row["po_number"] ?? "",
                        supplierName: row["supplier_name"] ?? "Unknown",
                        expectedDate: String((row["expected_delivery"] as String? ?? "").prefix(10)),
                        lineCount: row["line_count"] ?? 0,
                        isOverdue: (row["is_overdue"] as Int? ?? 0) == 1
                    )
                }

                let budgetRows = try Row.fetchAll(conn, sql: """
                    SELECT * FROM (
                        SELECT j.id, j.job_name, j.budget_limit AS budget,
                               COALESCE(
                                 (SELECT SUM(le.regular_hours * COALESCE(u.pay_rate, 0))
                                  FROM labor_entries le
                                  LEFT JOIN users u ON u.id = le.user_id
                                  WHERE le.job_id = j.id AND le.deleted_at IS NULL), 0
                               ) +
                               COALESCE(
                                 (SELECT SUM(po.total_cost)
                                  FROM purchase_orders po
                                  JOIN po_jpo_links pjl ON pjl.po_id = po.id
                                  JOIN job_parts_orders jpo ON jpo.id = pjl.jpo_id
                                  WHERE jpo.job_id = j.id
                                    AND po.status NOT IN ('cancelled')
                                    AND po.deleted_at IS NULL), 0
                               ) AS current_spend
                        FROM jobs j
                        WHERE j.budget_limit IS NOT NULL AND j.budget_limit > 0
                          AND j.status = 'active'
                          AND j.deleted_at IS NULL
                    ) sub
                    WHERE current_spend >= budget * 0.8
                    ORDER BY (current_spend * 1.0 / budget) DESC
                    LIMIT 10
                    """)
                let bAlerts = budgetRows.map { row in
                    let budget: Double = row["budget"] ?? 0
                    let spend: Double = row["current_spend"] ?? 0
                    return JobBudgetAlert(
                        id: row["id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        currentSpend: spend,
                        budgetLimit: budget,
                        pctUsed: budget > 0 ? (spend / budget) * 100 : 0
                    )
                }

                // --- My Hours Today ---
                var myHoursVal: Double = 0
                var myClockInVal: String?
                var myJobVal: String?
                var myBreaksVal: Int = 0
                var myBreakdownVal: [JobTimeEntry] = []

                if let userId = currentUserId {
                    // Total completed hours today
                    myHoursVal = try Double.fetchOne(conn, sql: """
                        SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
                        FROM labor_entries
                        WHERE user_id = ? AND date(clock_in) = date('now') AND deleted_at IS NULL
                        """, arguments: [userId]) ?? 0

                    // Current active clock-in
                    if let activeRow = try Row.fetchOne(conn, sql: """
                        SELECT le.clock_in, COALESCE(j.job_name, 'Shop / Warehouse') AS job_name
                        FROM labor_entries le
                        LEFT JOIN jobs j ON j.id = le.job_id
                        WHERE le.user_id = ? AND le.clock_out IS NULL AND le.deleted_at IS NULL
                        ORDER BY le.clock_in DESC LIMIT 1
                        """, arguments: [userId]) {
                        let rawClockIn: String = activeRow["clock_in"] ?? ""
                        // Extract HH:mm from ISO timestamp
                        if rawClockIn.count >= 16 {
                            myClockInVal = String(rawClockIn.suffix(from: rawClockIn.index(rawClockIn.startIndex, offsetBy: 11)).prefix(5))
                        } else {
                            myClockInVal = rawClockIn
                        }
                        myJobVal = activeRow["job_name"]

                        // Add active session elapsed time
                        let activeHours = try Double.fetchOne(conn, sql: """
                            SELECT (julianday('now') - julianday(clock_in)) * 24
                            FROM labor_entries
                            WHERE user_id = ? AND clock_out IS NULL AND deleted_at IS NULL
                            ORDER BY clock_in DESC LIMIT 1
                            """, arguments: [userId]) ?? 0
                        myHoursVal += max(0, activeHours)
                    }

                    // Job breakdown
                    let breakdownRows = try Row.fetchAll(conn, sql: """
                        SELECT COALESCE(j.job_name, 'Shop / Warehouse') AS job_name,
                               SUM(
                                 CASE WHEN le.clock_out IS NOT NULL THEN le.regular_hours + le.overtime_hours
                                      ELSE (julianday('now') - julianday(le.clock_in)) * 24
                                 END
                               ) AS total_hours
                        FROM labor_entries le
                        LEFT JOIN jobs j ON j.id = le.job_id
                        WHERE le.user_id = ? AND date(le.clock_in) = date('now') AND le.deleted_at IS NULL
                        GROUP BY le.job_id
                        ORDER BY total_hours DESC
                        """, arguments: [userId])
                    myBreakdownVal = breakdownRows.map { row in
                        JobTimeEntry(
                            id: row["job_name"] ?? "unknown",
                            jobName: row["job_name"] ?? "Shop / Warehouse",
                            hours: max(0, row["total_hours"] ?? 0)
                        )
                    }

                    // Break minutes: gaps between consecutive entries today
                    let gapMinutes = try Int.fetchOne(conn, sql: """
                        SELECT COALESCE(SUM(gap_minutes), 0) FROM (
                            SELECT CAST((julianday(le2.clock_in) - julianday(le1.clock_out)) * 1440 AS INTEGER) AS gap_minutes
                            FROM labor_entries le1
                            JOIN labor_entries le2
                                ON le2.user_id = le1.user_id
                                AND le2.clock_in > le1.clock_out
                                AND le2.deleted_at IS NULL
                                AND date(le2.clock_in) = date('now')
                            WHERE le1.user_id = ? AND le1.clock_out IS NOT NULL AND le1.deleted_at IS NULL
                                AND date(le1.clock_in) = date('now')
                                AND NOT EXISTS (
                                    SELECT 1 FROM labor_entries le3
                                    WHERE le3.user_id = le1.user_id
                                        AND le3.clock_in > le1.clock_out
                                        AND le3.clock_in < le2.clock_in
                                        AND le3.deleted_at IS NULL
                                        AND date(le3.clock_in) = date('now')
                                )
                        )
                        """, arguments: [userId]) ?? 0
                    myBreaksVal = max(0, gapMinutes)
                }

                // --- Who's Clocked In (team) ---
                let teamRows = try Row.fetchAll(conn, sql: """
                    SELECT u.id, u.display_name,
                           COALESCE(j.job_name, 'Shop / Warehouse') AS job_name,
                           le.clock_in
                    FROM labor_entries le
                    JOIN users u ON u.id = le.user_id
                    LEFT JOIN jobs j ON j.id = le.job_id
                    WHERE le.clock_out IS NULL AND le.deleted_at IS NULL AND u.deleted_at IS NULL
                    ORDER BY le.clock_in ASC
                    """)
                let teamVal = teamRows.map { row in
                    let rawClockIn: String = row["clock_in"] ?? ""
                    // Calculate duration text
                    let durationText: String = {
                        guard rawClockIn.count >= 19 else { return "—" }
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        let formatterBasic = ISO8601DateFormatter()
                        formatterBasic.formatOptions = [.withInternetDateTime]
                        if let date = formatter.date(from: rawClockIn) ?? formatterBasic.date(from: rawClockIn) {
                            let mins = Int(Date().timeIntervalSince(date) / 60)
                            if mins < 60 { return "\(mins)m" }
                            return "\(mins / 60)h \(mins % 60)m"
                        }
                        return "—"
                    }()
                    let timeText: String = rawClockIn.count >= 16
                        ? String(rawClockIn.suffix(from: rawClockIn.index(rawClockIn.startIndex, offsetBy: 11)).prefix(5))
                        : rawClockIn
                    return TeamMemberStatus(
                        id: row["id"] ?? 0,
                        displayName: row["display_name"] ?? "",
                        jobName: row["job_name"] ?? "",
                        clockInTime: timeText,
                        durationText: durationText
                    )
                }

                return DailyReportData(
                    pendingJPOs: pJPOs,
                    pendingPOs: pPOs,
                    returnsToSort: rSort,
                    overdueDeliveries: oDeliv,
                    todayCreatedOrders: tOrders,
                    todayReceivedItems: tReceived,
                    todayReturns: tReturns,
                    expectedDeliveries: expDeliv,
                    budgetAlerts: bAlerts,
                    myHours: myHoursVal,
                    myClockIn: myClockInVal,
                    myJob: myJobVal,
                    myBreaks: myBreaksVal,
                    jobBreakdown: myBreakdownVal,
                    team: teamVal
                )
            }

            await MainActor.run {
                pendingJPOs = result.pendingJPOs
                pendingPOs = result.pendingPOs
                returnsToSort = result.returnsToSort
                overdueDeliveries = result.overdueDeliveries
                todayCreatedOrders = result.todayCreatedOrders
                todayReceivedItems = result.todayReceivedItems
                todayReturns = result.todayReturns
                expectedDeliveries = result.expectedDeliveries
                budgetAlerts = result.budgetAlerts
                myTodayHours = result.myHours
                myClockInTime = result.myClockIn
                myCurrentJob = result.myJob
                myBreakMinutes = result.myBreaks
                myJobBreakdown = result.jobBreakdown
                teamClockedIn = result.team
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
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
              let userId = appCore.currentUser?.id else { return }
        do {
            if let active = try service.getActiveClockEntry(userId: userId) {
                try service.clockOut(laborEntryId: active.id)
            }
            Task { await loadData() }
        } catch {
            loadError = error.localizedDescription
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
                        VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                            Text(alert.jobName)
                                .dsStyle(.detail)
                                .lineLimit(1)
                            Text("$\(Int(alert.currentSpend)) of $\(Int(alert.budgetLimit))")
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

private struct DailyReportData: Sendable {
    let pendingJPOs: Int
    let pendingPOs: Int
    let returnsToSort: Int
    let overdueDeliveries: Int
    let todayCreatedOrders: Int
    let todayReceivedItems: Int
    let todayReturns: Int
    let expectedDeliveries: [ExpectedDelivery]
    let budgetAlerts: [JobBudgetAlert]

    // My Hours
    let myHours: Double
    let myClockIn: String?
    let myJob: String?
    let myBreaks: Int
    let jobBreakdown: [JobTimeEntry]

    // Team
    let team: [TeamMemberStatus]
}

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    Picker("Job", selection: $selectedJobId) {
                        Text("Select a job").tag(nil as Int64?)
                        ForEach(jobs, id: \.id) { job in
                            Text(job.name).tag(job.id as Int64?)
                        }
                    }
                }
                Section("Problem Description") {
                    TextField("Describe the problem...", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Report Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        // TODO: Create notebook entry tagged as 'problem'
                        dismiss()
                    }
                    .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { loadJobs() }
        }
    }

    private func loadJobs() {
        guard let db = appCore.db else { return }
        do {
            let rows = try db.writer.read { conn in
                try Row.fetchAll(conn, sql: """
                    SELECT id, job_name FROM jobs
                    WHERE status = 'active' AND deleted_at IS NULL
                    ORDER BY job_name ASC
                    """)
            }
            jobs = rows.map { (id: $0["id"] ?? 0, name: $0["job_name"] ?? "") }
        } catch {
            // Non-critical — picker will just be empty
        }
    }
}

// MARK: - Submit Daily Report Sheet

private struct SubmitDailyReportSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var accomplishments = ""
    @State private var issues = ""
    @State private var tomorrowNotes = ""

    var body: some View {
        NavigationStack {
            Form {
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
            }
            .navigationTitle("Daily Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        // TODO: Save daily report via JobsService
                        dismiss()
                    }
                    .disabled(accomplishments.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
