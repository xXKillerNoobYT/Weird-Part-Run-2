import SwiftUI
import WiredPartCore

/// Purchase Orders list page.
///
/// Displays a searchable, sortable table of all purchase orders with PO number,
/// supplier, status, total cost, line count, and order date columns. Supports
/// filtering by status and searching by PO number or supplier name.
struct PurchaseOrdersPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var purchaseOrders: [OrdersService.POListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\OrdersService.POListItem.poNumber)]

    private let statusOptions = ["all", "draft", "submitted", "ordered", "partial", "received", "cancelled"]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { load() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Purchase Orders")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(purchaseOrders.count) PO\(purchaseOrders.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Status", selection: $statusFilter) {
                ForEach(statusOptions, id: \.self) { status in
                    Text(status == "all" ? "All Statuses" : status.capitalized)
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            .onChange(of: statusFilter) { load() }

            TextField("Search POs...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { load() }

            Button {
                load()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading purchase orders...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if purchaseOrders.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "cart")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No purchase orders found")
                    .font(.headline)
                Text("Create a purchase order to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedPOs, sortOrder: $sortOrder) {
                TableColumn("PO #", value: \.poNumber) { po in
                    Text(po.poNumber)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Supplier", value: \.supplierName) { po in
                    Text(po.supplierName)
                        .fontWeight(.medium)
                }
                .width(min: 120, ideal: 180)

                TableColumn("Status", value: \.status) { po in
                    statusBadge(po.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Total Cost") { (po: OrdersService.POListItem) in
                    Text(formatCurrency(po.totalCost))
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 80, ideal: 100)

                TableColumn("Lines", value: \.lineCount) { po in
                    Text("\(po.lineCount)")
                }
                .width(min: 50, ideal: 60)

                TableColumn("Order Date") { (po: OrdersService.POListItem) in
                    Text(po.orderDate ?? "-")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 110)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedPOs: [OrdersService.POListItem] {
        purchaseOrders.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "draft": .secondary
        case "submitted": .blue
        case "ordered": .indigo
        case "partial": .orange
        case "received": .green
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Formatters

    private func formatCurrency(_ amount: Double?) -> String {
        guard let amount else { return "-" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = OrdersService(db: db)
        isLoading = true
        do {
            let allPOs = try service.listPurchaseOrders(
                status: statusFilter == "all" ? nil : statusFilter
            )
            // Client-side search filter
            if searchText.isEmpty {
                purchaseOrders = allPOs
            } else {
                let query = searchText.lowercased()
                purchaseOrders = allPOs.filter {
                    $0.poNumber.lowercased().contains(query) ||
                    $0.supplierName.lowercased().contains(query)
                }
            }
        } catch {
            print("[PurchaseOrdersPage] Load error: \(error)")
        }
        isLoading = false
    }
}
