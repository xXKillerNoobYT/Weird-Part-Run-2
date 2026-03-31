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
    let type: KPIDetailType

    var body: some View {
        SheetDismissWrapper(title: type.title) {
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
        .refreshable {
            await loadCategories()
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
                loadError = userFriendlyError(error, context: "load KPI details")
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
        .refreshable {
            await loadParts()
        }
        .task { await loadParts() }
    }

    private func loadParts() async {
        guard let service = appCore.dashboardService else {
            loadError = "Dashboard service not available"
            isLoading = false
            return
        }
        do {
            let rows = try service.getPartsInCategory(categoryId: categoryId)
            await MainActor.run {
                parts = rows.map { row in
                    PartSummary(id: row.id, name: row.name, code: row.code, totalStock: row.totalStock)
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load KPI details")
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
                                .accessibilityHidden(true)
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
        .refreshable {
            await loadLocationGroups()
        }
        .navigationDestination(for: LocationGroupSummary.self) { group in
            LocationTypeStockView(locationType: group.locationType, displayName: group.displayName)
        }
        .task { await loadLocationGroups() }
    }

    private func loadLocationGroups() async {
        guard let service = appCore.dashboardService else {
            loadError = "Dashboard service not available"
            isLoading = false
            return
        }
        do {
            let rows = try service.getStockByLocationType()
            await MainActor.run {
                locationGroups = rows.map { row in
                    LocationGroupSummary(
                        locationType: row.locationType,
                        locationCount: row.locationCount,
                        totalQty: row.totalQty
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load KPI details")
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
        .refreshable {
            await loadItems()
        }
        .task { await loadItems() }
    }

    private func loadItems() async {
        guard let service = appCore.dashboardService else {
            loadError = "Dashboard service not available"
            isLoading = false
            return
        }
        do {
            let rows = try service.getStockAtLocationType(locationType)
            await MainActor.run {
                items = rows.map { row in
                    LocationStockItem(
                        partId: row.partId,
                        partName: row.partName,
                        partCode: row.partCode,
                        locationId: row.locationId,
                        qty: row.qty
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load KPI details")
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
        .refreshable {
            await loadJobs()
        }
        .navigationDestination(for: Int64.self) { jobId in
            JobKPIDetailView(jobId: jobId)
        }
        .task { await loadJobs() }
    }

    private func loadJobs() async {
        guard let service = appCore.jobsService else {
            loadError = "Jobs service not available"
            isLoading = false
            return
        }
        do {
            let result = try service.listJobs(status: "active", limit: 50, offset: 0)
            let inProgress = try service.listJobs(status: "in_progress", limit: 50, offset: 0)
            await MainActor.run {
                jobs = result + inProgress
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load KPI details")
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
        .refreshable {
            await loadDetail()
        }
        .task { await loadDetail() }
    }

    private func loadDetail() async {
        guard let service = appCore.dashboardService else {
            loadError = "Dashboard service not available"
            isLoading = false
            return
        }
        do {
            let kpiDetail = try service.getJobKPIDetail(jobId: jobId)
            await MainActor.run {
                if let kpiDetail {
                    detail = JobDetail(
                        jobName: kpiDetail.jobName,
                        status: kpiDetail.status,
                        customerName: kpiDetail.customerName,
                        startDate: kpiDetail.startDate,
                        dueDate: kpiDetail.dueDate,
                        budgetLimit: kpiDetail.budgetLimit,
                        teamCount: kpiDetail.teamCount,
                        laborHours: kpiDetail.laborHours,
                        currentSpend: kpiDetail.currentSpend
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load KPI details")
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
        .refreshable {
            await loadOrders()
        }
        .navigationDestination(for: Int64.self) { poId in
            POKPIDetailView(poId: poId)
        }
        .task { await loadOrders() }
    }

    private func loadOrders() async {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
        do {
            let pending = try service.listPurchaseOrders(status: "pending", limit: 50)
            let draft = try service.listPurchaseOrders(status: "draft", limit: 50)
            await MainActor.run {
                orders = pending + draft
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load KPI details")
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
        .refreshable {
            await loadDetail()
        }
        .task { await loadDetail() }
    }

    private func loadDetail() async {
        guard let service = appCore.dashboardService else {
            loadError = "Dashboard service not available"
            isLoading = false
            return
        }
        do {
            let result = try service.getPOKPIDetail(poId: poId)
            await MainActor.run {
                if let d = result.detail {
                    poDetail = PODetail(
                        poNumber: d.poNumber,
                        supplierName: d.supplierName,
                        supplierEmail: d.supplierEmail,
                        supplierPhone: d.supplierPhone,
                        status: d.status,
                        totalCost: d.totalCost,
                        orderDate: d.orderDate,
                        expectedDelivery: d.expectedDelivery
                    )
                }
                lineItems = result.lineItems.map { item in
                    POLineItemSummary(
                        partName: item.partName,
                        partCode: item.partCode,
                        qty: item.qty
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load KPI details")
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
        .refreshable {
            await loadLowStock()
        }
        .navigationDestination(for: LowStockPart.self) { part in
            LowStockPartDetailView(partId: part.id, partName: part.name)
        }
        .task { await loadLowStock() }
    }

    private func loadLowStock() async {
        guard let service = appCore.dashboardService else {
            loadError = "Dashboard service not available"
            isLoading = false
            return
        }
        do {
            let rows = try service.getLowStockParts()
            await MainActor.run {
                lowStockParts = rows.map { row in
                    LowStockPart(
                        id: row.id,
                        name: row.name,
                        code: row.code,
                        currentQty: row.currentQty,
                        minLevel: row.minLevel
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load KPI details")
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
                                    .accessibilityHidden(true)
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
        .refreshable {
            await loadDetail()
        }
        .task { await loadDetail() }
    }

    private func loadDetail() async {
        guard let service = appCore.dashboardService else {
            loadError = "Dashboard service not available"
            isLoading = false
            return
        }
        do {
            let locations = try service.getStockLocationsForPart(partId: partId)
            let movementInfo = try service.getPartMovementInfo(partId: partId)
            await MainActor.run {
                stockLocations = locations.map { row in
                    LocationStockItem(
                        partId: partId,
                        partName: partName,
                        partCode: nil,
                        locationId: row.locationId,
                        qty: row.qty,
                        locationType: row.locationType
                    )
                }
                lastMovement = movementInfo.lastMovement
                reorderPoint = movementInfo.reorderPoint
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load KPI details")
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
