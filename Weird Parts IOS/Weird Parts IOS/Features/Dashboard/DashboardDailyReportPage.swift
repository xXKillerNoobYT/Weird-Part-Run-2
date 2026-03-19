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
                    // Overdue alert banner
                    if overdueDeliveries > 0 {
                        DSAlertBanner(
                            severity: .error,
                            title: "\(overdueDeliveries) overdue deliver\(overdueDeliveries == 1 ? "y" : "ies")",
                            message: "Immediate attention required"
                        )
                        .padding(.horizontal, DS.Space.lg)
                    }

                    // Pending Actions
                    pendingActionsCard
                        .padding(.horizontal, DS.Space.lg)

                    // Today's Activity
                    todayActivityCard
                        .padding(.horizontal, DS.Space.lg)

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
        .task { await loadData() }
        .onReceive(refreshTimer) { _ in
            Task { await loadData() }
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

                return DailyReportData(
                    pendingJPOs: pJPOs,
                    pendingPOs: pPOs,
                    returnsToSort: rSort,
                    overdueDeliveries: oDeliv,
                    todayCreatedOrders: tOrders,
                    todayReceivedItems: tReceived,
                    todayReturns: tReturns,
                    expectedDeliveries: expDeliv,
                    budgetAlerts: bAlerts
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
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
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
