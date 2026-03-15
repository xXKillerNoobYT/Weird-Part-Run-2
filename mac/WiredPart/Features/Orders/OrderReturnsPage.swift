import SwiftUI
import WiredPartCore

/// Order Returns list page.
///
/// Displays a searchable, sortable table of all returns with type, status,
/// supplier, reason, line count, and credit amount columns. Supports filtering
/// by status and searching by supplier name or reason.
struct OrderReturnsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var returns: [OrdersService.ReturnListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\OrdersService.ReturnListItem.id)]

    private let statusOptions = ["all", "pending", "requested", "approved", "shipped", "received", "credited", "cancelled"]

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
                Text("Returns")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(returns.count) return\(returns.count == 1 ? "" : "s")")
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

            TextField("Search returns...", text: $searchText)
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
            ProgressView("Loading returns...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if returns.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No returns found")
                    .font(.headline)
                Text("Returns will appear here when created.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedReturns, sortOrder: $sortOrder) {
                TableColumn("ID", value: \.id) { item in
                    Text("#\(item.id)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
                .width(min: 60, ideal: 70)

                TableColumn("Type", value: \.returnType) { item in
                    Text(item.returnType.capitalized)
                        .fontWeight(.medium)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Status", value: \.status) { item in
                    statusBadge(item.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Supplier") { (item: OrdersService.ReturnListItem) in
                    Text(item.supplierName ?? "-")
                }
                .width(min: 100, ideal: 150)

                TableColumn("Reason") { (item: OrdersService.ReturnListItem) in
                    Text(item.reason ?? "-")
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 160)

                TableColumn("Lines", value: \.lineCount) { item in
                    Text("\(item.lineCount)")
                }
                .width(min: 50, ideal: 60)

                TableColumn("Credit") { (item: OrdersService.ReturnListItem) in
                    Text(formatCurrency(item.creditAmount))
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 80, ideal: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedReturns: [OrdersService.ReturnListItem] {
        returns.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "pending": .orange
        case "requested": .blue
        case "approved": .indigo
        case "shipped": .purple
        case "received": .teal
        case "credited": .green
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
            let allReturns = try service.listReturns(
                status: statusFilter == "all" ? nil : statusFilter
            )
            // Client-side search filter
            if searchText.isEmpty {
                returns = allReturns
            } else {
                let query = searchText.lowercased()
                returns = allReturns.filter {
                    ($0.supplierName?.lowercased().contains(query) ?? false) ||
                    ($0.reason?.lowercased().contains(query) ?? false)
                }
            }
        } catch {
            print("[OrderReturnsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
