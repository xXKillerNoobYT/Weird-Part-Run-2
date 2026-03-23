import SwiftUI
import WiredPartCore

// MARK: - Shared KPI Detail Sheet Pattern

/// Identifies which KPI card was tapped.
enum KPIDetailType: Identifiable {
    case partTypes
    case totalStock
    case activeJobs
    case pendingOrders
    case lowStock

    var id: String {
        switch self {
        case .partTypes: "partTypes"
        case .totalStock: "totalStock"
        case .activeJobs: "activeJobs"
        case .pendingOrders: "pendingOrders"
        case .lowStock: "lowStock"
        }
    }

    var title: String {
        switch self {
        case .partTypes: "Part Types"
        case .totalStock: "Total Stock"
        case .activeJobs: "Active Jobs"
        case .pendingOrders: "Pending Orders"
        case .lowStock: "Low Stock"
        }
    }

    var icon: String {
        switch self {
        case .partTypes: "list.clipboard"
        case .totalStock: "shippingbox.fill"
        case .activeJobs: "hammer"
        case .pendingOrders: "cart"
        case .lowStock: "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .partTypes: .blue
        case .totalStock: .teal
        case .activeJobs: .orange
        case .pendingOrders: .purple
        case .lowStock: .red
        }
    }
}

// MARK: - KPI Detail Router Sheet

/// Dispatches to the correct detail view based on which KPI card was tapped.
struct KPIDetailSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    let type: KPIDetailType

    var body: some View {
        NavigationStack {
            Group {
                switch type {
                case .partTypes:
                    PartTypesDetailView()
                case .totalStock:
                    TotalStockDetailView()
                case .activeJobs:
                    ActiveJobsDetailView()
                case .pendingOrders:
                    PendingOrdersDetailView()
                case .lowStock:
                    LowStockDetailView()
                }
            }
            .navigationTitle(type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Part Types Detail (Layer 1: categories with counts)

private struct PartTypesDetailView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var categories: [CategoryCount] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if categories.isEmpty {
                ContentUnavailableView("No Parts", systemImage: "shippingbox", description: Text("No parts in catalog yet."))
            } else {
                ForEach(categories) { cat in
                    NavigationLink(value: cat) {
                        HStack {
                            Text(cat.name)
                            Spacer()
                            Text("\(cat.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationDestination(for: CategoryCount.self) { cat in
            CategoryPartsListView(categoryId: cat.id, categoryName: cat.name)
        }
        .task { await loadCategories() }
    }

    private func loadCategories() async {
        guard let service = appCore.dashboardService else {
            loadError = "Dashboard service not available"
            isLoading = false
            return
        }
        do {
            let rows = try service.getCategoriesWithCounts()
            await MainActor.run {
                categories = rows.map { row in
                    CategoryCount(id: row.id, name: row.name, count: row.count)
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

/// Layer 2: Parts within a category
private struct CategoryPartsListView: View {
    @EnvironmentObject private var appCore: AppCore
    let categoryId: Int64
    let categoryName: String
    @State private var parts: [PartSummary] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if parts.isEmpty {
                ContentUnavailableView("No Parts", systemImage: "shippingbox", description: Text("No parts in this category."))
            } else {
                ForEach(parts) { part in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(part.name)
                            .dsStyle(.label)
                        if let code = part.code {
                            Text(code)
                                .dsStyle(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Stock: \(part.totalStock)")
                            .dsStyle(.detail)
                            .foregroundStyle(part.totalStock == 0 ? DS.SemanticColor.error : .secondary)
                    }
                }
            }
        }
        .navigationTitle(categoryName)
        .task { await loadParts() }
    }

    private func loadParts() async {
        guard let db = appCore.db else { isLoading = false; return }
        do {
            let rows = try db.writer.read { conn -> [Row] in
                try Row.fetchAll(conn, sql: """
                    SELECT p.id, p.name, p.code,
                           COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) AS total_stock
                    FROM parts p
                    WHERE p.category_id = ? AND p.deleted_at IS NULL
                    ORDER BY p.name
                    """, arguments: [categoryId])
            }
            await MainActor.run {
                parts = rows.map { row in
                    PartSummary(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        code: row["code"] as String?,
                        totalStock: row["total_stock"] ?? 0
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Total Stock Detail (Layer 1: stock by location type)

private struct TotalStockDetailView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var locationGroups: [LocationGroupSummary] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if locationGroups.isEmpty {
                ContentUnavailableView("No Stock", systemImage: "shippingbox", description: Text("No stock recorded yet."))
            } else {
                ForEach(locationGroups) { group in
                    NavigationLink(value: group) {
                        HStack {
                            Image(systemName: group.icon)
                                .foregroundStyle(group.color)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(group.displayName)
                                    .dsStyle(.label)
                                Text("\(group.locationCount) location\(group.locationCount == 1 ? "" : "s")")
                                    .dsStyle(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(group.totalQty)")
                                .dsStyle(.kpiValue)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: LocationGroupSummary.self) { group in
            LocationTypeStockView(locationType: group.locationType, displayName: group.displayName)
        }
        .task { await loadLocationGroups() }
    }

    private func loadLocationGroups() async {
        guard let db = appCore.db else { isLoading = false; return }
        do {
            let rows = try db.writer.read { conn -> [Row] in
                try Row.fetchAll(conn, sql: """
                    SELECT location_type,
                           COUNT(DISTINCT location_id) AS loc_count,
                           SUM(qty) AS total_qty
                    FROM stock
                    WHERE deleted_at IS NULL AND qty > 0
                    GROUP BY location_type
                    ORDER BY total_qty DESC
                    """)
            }
            await MainActor.run {
                locationGroups = rows.map { row in
                    let locType: String = row["location_type"] ?? "unknown"
                    return LocationGroupSummary(
                        locationType: locType,
                        locationCount: row["loc_count"] ?? 0,
                        totalQty: row["total_qty"] ?? 0
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

/// Layer 2: Parts at a specific location type
private struct LocationTypeStockView: View {
    @EnvironmentObject private var appCore: AppCore
    let locationType: String
    let displayName: String
    @State private var items: [LocationStockItem] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if items.isEmpty {
                ContentUnavailableView("No Stock", systemImage: "shippingbox", description: Text("No items at this location type."))
            } else {
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                            Text(item.partName)
                                .dsStyle(.label)
                            if let code = item.partCode {
                                Text(code)
                                    .dsStyle(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Location #\(item.locationId)")
                                .dsStyle(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text("\(item.qty)")
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .navigationTitle(displayName)
        .task { await loadItems() }
    }

    private func loadItems() async {
        guard let db = appCore.db else { isLoading = false; return }
        do {
            let rows = try db.writer.read { conn -> [Row] in
                try Row.fetchAll(conn, sql: """
                    SELECT s.location_id, s.part_id, s.qty,
                           p.name AS part_name, p.code AS part_code
                    FROM stock s
                    LEFT JOIN parts p ON p.id = s.part_id
                    WHERE s.location_type = ? AND s.qty > 0 AND s.deleted_at IS NULL
                    ORDER BY p.name, s.location_id
                    """, arguments: [locationType])
            }
            await MainActor.run {
                items = rows.map { row in
                    LocationStockItem(
                        partId: row["part_id"] ?? 0,
                        partName: row["part_name"] ?? "Unknown",
                        partCode: row["part_code"] as String?,
                        locationId: row["location_id"] ?? 0,
                        qty: row["qty"] ?? 0
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Active Jobs Detail (Layer 1: list of active jobs)

private struct ActiveJobsDetailView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var jobs: [JobsService.JobListItem] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if jobs.isEmpty {
                ContentUnavailableView("No Active Jobs", systemImage: "hammer", description: Text("No jobs are currently active."))
            } else {
                ForEach(jobs) { job in
                    NavigationLink(value: job.id) {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            HStack {
                                Text(job.jobName)
                                    .dsStyle(.label)
                                Spacer()
                                Text(job.status.capitalized)
                                    .dsStyle(.caption)
                                    .padding(.horizontal, DS.Space.xs)
                                    .padding(.vertical, DS.Space.xxxs)
                                    .background(DS.SemanticColor.tint(.green))
                                    .clipShape(Capsule())
                            }
                            HStack(spacing: DS.Space.md) {
                                if !job.jobNumber.isEmpty {
                                    Label(job.jobNumber, systemImage: "number")
                                }
                                Label("\(job.teamCount)", systemImage: "person.2")
                                if let dueDate = job.dueDate {
                                    Label(String(dueDate.prefix(10)), systemImage: "calendar")
                                }
                            }
                            .dsStyle(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: Int64.self) { jobId in
            JobKPIDetailView(jobId: jobId)
        }
        .task { await loadJobs() }
    }

    private func loadJobs() async {
        guard let db = appCore.db else { isLoading = false; return }
        do {
            let service = JobsService(db: db)
            let result = try service.listJobs(status: "active", limit: 50, offset: 0)
            // Also grab in_progress jobs
            let inProgress = try service.listJobs(status: "in_progress", limit: 50, offset: 0)
            await MainActor.run {
                jobs = result + inProgress
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

/// Layer 2: Job detail with budget, labor hours, materials
private struct JobKPIDetailView: View {
    @EnvironmentObject private var appCore: AppCore
    let jobId: Int64
    @State private var detail: JobDetail?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let detail {
                Section("Overview") {
                    LabeledContent("Job Name", value: detail.jobName)
                    LabeledContent("Status", value: detail.status.capitalized)
                    if let customer = detail.customerName {
                        LabeledContent("Customer", value: customer)
                    }
                    if let start = detail.startDate {
                        LabeledContent("Start Date", value: String(start.prefix(10)))
                    }
                    if let due = detail.dueDate {
                        LabeledContent("Due Date", value: String(due.prefix(10)))
                    }
                }
                Section("Labor") {
                    LabeledContent("Team Members", value: "\(detail.teamCount)")
                    LabeledContent("Total Hours", value: String(format: "%.1f", detail.laborHours))
                }
                Section("Budget") {
                    if let budget = detail.budgetLimit, budget > 0 {
                        LabeledContent("Budget", value: String(format: "$%.2f", budget))
                        LabeledContent("Spent", value: String(format: "$%.2f", detail.currentSpend))
                        let pct = (detail.currentSpend / budget) * 100
                        LabeledContent("Used", value: String(format: "%.0f%%", pct))
                    } else {
                        Text("No budget set")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView("Job Not Found", systemImage: "hammer", description: Text("Could not load job details."))
            }
        }
        .navigationTitle("Job Detail")
        .task { await loadDetail() }
    }

    private func loadDetail() async {
        guard let db = appCore.db else { isLoading = false; return }
        do {
            let row = try db.writer.read { conn -> Row? in
                try Row.fetchOne(conn, sql: """
                    SELECT j.job_name, j.status, j.customer_name,
                           j.start_date, j.due_date, j.budget_limit,
                           COALESCE((SELECT COUNT(*) FROM job_team_members jtm
                                     WHERE jtm.job_id = j.id AND jtm.deleted_at IS NULL), 0) AS team_count,
                           COALESCE((SELECT SUM(le.regular_hours + le.overtime_hours) FROM labor_entries le
                                     WHERE le.job_id = j.id AND le.deleted_at IS NULL), 0) AS labor_hours,
                           COALESCE(
                             (SELECT SUM(le.regular_hours * COALESCE(u.pay_rate, 0))
                              FROM labor_entries le LEFT JOIN users u ON u.id = le.user_id
                              WHERE le.job_id = j.id AND le.deleted_at IS NULL), 0
                           ) +
                           COALESCE(
                             (SELECT SUM(po.total_cost) FROM purchase_orders po
                              JOIN po_jpo_links pjl ON pjl.po_id = po.id
                              JOIN job_parts_orders jpo ON jpo.id = pjl.jpo_id
                              WHERE jpo.job_id = j.id AND po.status NOT IN ('cancelled') AND po.deleted_at IS NULL), 0
                           ) AS current_spend
                    FROM jobs j
                    WHERE j.id = ?
                    """, arguments: [jobId])
            }
            await MainActor.run {
                if let row {
                    detail = JobDetail(
                        jobName: row["job_name"] ?? "",
                        status: row["status"] ?? "",
                        customerName: row["customer_name"] as String?,
                        startDate: row["start_date"] as String?,
                        dueDate: row["due_date"] as String?,
                        budgetLimit: row["budget_limit"] as Double?,
                        teamCount: row["team_count"] ?? 0,
                        laborHours: row["labor_hours"] ?? 0,
                        currentSpend: row["current_spend"] ?? 0
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Pending Orders Detail (Layer 1: list of pending POs)

private struct PendingOrdersDetailView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var orders: [OrdersService.POListItem] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if orders.isEmpty {
                ContentUnavailableView("No Pending Orders", systemImage: "cart", description: Text("No purchase orders pending."))
            } else {
                ForEach(orders) { po in
                    NavigationLink(value: po.id) {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            HStack {
                                Text(po.poNumber)
                                    .dsStyle(.label)
                                Spacer()
                                Text(po.status.capitalized)
                                    .dsStyle(.caption)
                                    .padding(.horizontal, DS.Space.xs)
                                    .padding(.vertical, DS.Space.xxxs)
                                    .background(DS.SemanticColor.tint(.orange))
                                    .clipShape(Capsule())
                            }
                            HStack(spacing: DS.Space.md) {
                                Text(po.supplierName)
                                Label("\(po.lineCount) items", systemImage: "list.bullet")
                                if let cost = po.totalCost {
                                    Text(String(format: "$%.2f", cost))
                                }
                            }
                            .dsStyle(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: Int64.self) { poId in
            POKPIDetailView(poId: poId)
        }
        .task { await loadOrders() }
    }

    private func loadOrders() async {
        guard let db = appCore.db else { isLoading = false; return }
        do {
            let service = OrdersService(db: db)
            let pending = try service.listPurchaseOrders(status: "pending", limit: 50)
            let draft = try service.listPurchaseOrders(status: "draft", limit: 50)
            await MainActor.run {
                orders = pending + draft
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

/// Layer 2: PO detail with line items, supplier, status
private struct POKPIDetailView: View {
    @EnvironmentObject private var appCore: AppCore
    let poId: Int64
    @State private var poDetail: PODetail?
    @State private var lineItems: [POLineItemSummary] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let po = poDetail {
                Section("Order Info") {
                    LabeledContent("PO Number", value: po.poNumber)
                    LabeledContent("Supplier", value: po.supplierName)
                    LabeledContent("Status", value: po.status.capitalized)
                    if let date = po.orderDate {
                        LabeledContent("Order Date", value: String(date.prefix(10)))
                    }
                    if let expected = po.expectedDelivery {
                        LabeledContent("Expected Delivery", value: String(expected.prefix(10)))
                    }
                    if let cost = po.totalCost {
                        LabeledContent("Total Cost", value: String(format: "$%.2f", cost))
                    }
                }
                if !lineItems.isEmpty {
                    Section("Line Items") {
                        ForEach(lineItems) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.partName)
                                        .dsStyle(.label)
                                    if let code = item.partCode {
                                        Text(code)
                                            .dsStyle(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("x\(item.qty)")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Order Not Found", systemImage: "cart", description: Text("Could not load order details."))
            }
        }
        .navigationTitle("Order Detail")
        .task { await loadDetail() }
    }

    private func loadDetail() async {
        guard let db = appCore.db else { isLoading = false; return }
        do {
            let result = try await db.writer.read { conn -> (PODetail?, [POLineItemSummary]) in
                let row = try Row.fetchOne(conn, sql: """
                    SELECT po.po_number, po.status, po.total_cost, po.order_date, po.expected_delivery,
                           COALESCE(s.name, 'Unknown') AS supplier_name,
                           s.contact_email AS supplier_email, s.phone AS supplier_phone
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id
                    WHERE po.id = ?
                    """, arguments: [poId])

                let detail = row.map { r in
                    PODetail(
                        poNumber: r["po_number"] ?? "",
                        supplierName: r["supplier_name"] ?? "Unknown",
                        supplierEmail: r["supplier_email"] as String?,
                        supplierPhone: r["supplier_phone"] as String?,
                        status: r["status"] ?? "",
                        totalCost: r["total_cost"] as Double?,
                        orderDate: r["order_date"] as String?,
                        expectedDelivery: r["expected_delivery"] as String?
                    )
                }

                let lineRows = try Row.fetchAll(conn, sql: """
                    SELECT pl.quantity, p.name AS part_name, p.code AS part_code
                    FROM po_line_items pl
                    LEFT JOIN parts p ON p.id = pl.part_id
                    WHERE pl.po_id = ? AND pl.deleted_at IS NULL
                    ORDER BY p.name
                    """, arguments: [poId])

                let lines = lineRows.map { r in
                    POLineItemSummary(
                        partName: r["part_name"] ?? "Unknown",
                        partCode: r["part_code"] as String?,
                        qty: r["quantity"] ?? 0
                    )
                }

                return (detail, lines)
            }
            await MainActor.run {
                poDetail = result.0
                lineItems = result.1
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Low Stock Detail (Layer 1: parts below min level)

private struct LowStockDetailView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var lowStockParts: [LowStockPart] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if lowStockParts.isEmpty {
                ContentUnavailableView("All Stocked", systemImage: "checkmark.circle", description: Text("No parts are below their minimum stock level."))
            } else {
                ForEach(lowStockParts) { part in
                    NavigationLink(value: part) {
                        HStack {
                            VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                                Text(part.name)
                                    .dsStyle(.label)
                                if let code = part.code {
                                    Text(code)
                                        .dsStyle(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: DS.Space.xxxs) {
                                Text("\(part.currentQty) / \(part.minLevel)")
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                                    .foregroundStyle(part.currentQty == 0 ? DS.SemanticColor.error : DS.SemanticColor.warning)
                                Text("current / min")
                                    .dsStyle(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .navigationDestination(for: LowStockPart.self) { part in
            LowStockPartDetailView(partId: part.id, partName: part.name)
        }
        .task { await loadLowStock() }
    }

    private func loadLowStock() async {
        guard let db = appCore.db else { isLoading = false; return }
        do {
            let rows = try db.writer.read { conn -> [Row] in
                try Row.fetchAll(conn, sql: """
                    SELECT p.id, p.name, p.code, p.min_stock_level,
                           COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) AS current_qty
                    FROM parts p
                    WHERE p.deleted_at IS NULL
                      AND p.min_stock_level > 0
                      AND COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) < p.min_stock_level
                    ORDER BY (COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) * 1.0
                              / NULLIF(p.min_stock_level, 0)) ASC
                    """)
            }
            await MainActor.run {
                lowStockParts = rows.map { row in
                    LowStockPart(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        code: row["code"] as String?,
                        currentQty: row["current_qty"] ?? 0,
                        minLevel: row["min_stock_level"] ?? 0
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

/// Layer 2: Low stock part detail — stock by location, last movement, reorder point
private struct LowStockPartDetailView: View {
    @EnvironmentObject private var appCore: AppCore
    let partId: Int64
    let partName: String
    @State private var stockLocations: [LocationStockItem] = []
    @State private var lastMovement: String?
    @State private var reorderPoint: Int?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                Section("Stock by Location") {
                    if stockLocations.isEmpty {
                        Text("No stock at any location")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(stockLocations) { item in
                            HStack {
                                Image(systemName: LocationGroupSummary.iconFor(locationType: item.locationType))
                                    .foregroundStyle(LocationGroupSummary.colorFor(locationType: item.locationType))
                                    .frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(LocationGroupSummary.displayNameFor(locationType: item.locationType))
                                        .dsStyle(.label)
                                    Text("Location #\(item.locationId)")
                                        .dsStyle(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(item.qty)")
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
                Section("Details") {
                    if let rp = reorderPoint {
                        LabeledContent("Reorder Point", value: "\(rp)")
                    }
                    if let movement = lastMovement {
                        LabeledContent("Last Movement", value: String(movement.prefix(10)))
                    } else {
                        LabeledContent("Last Movement", value: "None recorded")
                    }
                }
            }
        }
        .navigationTitle(partName)
        .task { await loadDetail() }
    }

    private func loadDetail() async {
        guard let db = appCore.db else { isLoading = false; return }
        do {
            let result = try await db.writer.read { conn -> ([LocationStockItem], String?, Int?) in
                let stockRows = try Row.fetchAll(conn, sql: """
                    SELECT s.location_type AS locationType, s.location_id, s.qty
                    FROM stock s
                    WHERE s.part_id = ? AND s.qty > 0 AND s.deleted_at IS NULL
                    ORDER BY s.location_type
                    """, arguments: [partId])

                let locations = stockRows.map { row in
                    LocationStockItem(
                        partId: partId,
                        partName: partName,
                        partCode: nil,
                        locationId: row["location_id"] ?? 0,
                        qty: row["qty"] ?? 0,
                        locationType: row["locationType"] ?? "warehouse"
                    )
                }

                let lastMove = try String.fetchOne(conn, sql: """
                    SELECT created_at FROM stock_movements
                    WHERE part_id = ? AND deleted_at IS NULL
                    ORDER BY created_at DESC LIMIT 1
                    """, arguments: [partId])

                let rp = try Int.fetchOne(conn, sql: """
                    SELECT reorder_point FROM parts WHERE id = ?
                    """, arguments: [partId])

                return (locations, lastMove, rp)
            }
            await MainActor.run {
                stockLocations = result.0
                lastMovement = result.1
                reorderPoint = result.2
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Local Model Types

private struct CategoryCount: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let count: Int
}

private struct PartSummary: Identifiable, Sendable {
    let id: Int64
    let name: String
    let code: String?
    let totalStock: Int
}

private struct LocationGroupSummary: Identifiable, Hashable, Sendable {
    let locationType: String
    let locationCount: Int
    let totalQty: Int

    var id: String { locationType }

    var displayName: String {
        Self.displayNameFor(locationType: locationType)
    }

    var icon: String {
        Self.iconFor(locationType: locationType)
    }

    var color: Color {
        Self.colorFor(locationType: locationType)
    }

    static func displayNameFor(locationType: String) -> String {
        switch locationType {
        case "warehouse": "Warehouse"
        case "pulled", "staging": "Staging"
        case "truck": "Truck"
        case "trailer": "Trailer"
        case "job": "Job Site"
        default: locationType.capitalized
        }
    }

    static func iconFor(locationType: String) -> String {
        switch locationType {
        case "warehouse": "building.2"
        case "pulled", "staging": "tray.2"
        case "truck": "truck.box"
        case "trailer": "rectangle.on.rectangle"
        case "job": "mappin.and.ellipse"
        default: "questionmark.circle"
        }
    }

    static func colorFor(locationType: String) -> Color {
        switch locationType {
        case "warehouse": .blue
        case "pulled", "staging": .orange
        case "truck": .green
        case "trailer": .purple
        case "job": .red
        default: .gray
        }
    }
}

private struct LocationStockItem: Identifiable, Sendable {
    let partId: Int64
    let partName: String
    let partCode: String?
    let locationId: Int64
    let qty: Int
    var locationType: String = "warehouse"

    var id: String { "\(partId)-\(locationType)-\(locationId)" }
}

private struct JobDetail: Sendable {
    let jobName: String
    let status: String
    let customerName: String?
    let startDate: String?
    let dueDate: String?
    let budgetLimit: Double?
    let teamCount: Int
    let laborHours: Double
    let currentSpend: Double
}

private struct PODetail: Sendable {
    let poNumber: String
    let supplierName: String
    let supplierEmail: String?
    let supplierPhone: String?
    let status: String
    let totalCost: Double?
    let orderDate: String?
    let expectedDelivery: String?
}

private struct POLineItemSummary: Identifiable, Sendable {
    let partName: String
    let partCode: String?
    let qty: Int

    var id: String { "\(partName)-\(qty)" }
}

private struct LowStockPart: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let code: String?
    let currentQty: Int
    let minLevel: Int
}
