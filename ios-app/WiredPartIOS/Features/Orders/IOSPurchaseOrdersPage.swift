import SwiftUI
import WiredPartCore

/// Purchase orders list page for iOS.
///
/// Displays a searchable list of POs with PO number, supplier name,
/// status badge, total cost, and line count. Supports pull-to-refresh
/// and status-based filtering.
struct IOSPurchaseOrdersPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var purchaseOrders: [OrdersService.POListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"

    private let statusOptions = ["all", "draft", "submitted", "ordered", "partial", "received", "cancelled"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusPicker
                poList
            }
            .navigationTitle("Purchase Orders")
            .searchable(text: $searchText, prompt: "Search POs...")
            .onChange(of: searchText) { loadData() }
            .refreshable { loadData() }
            .task { loadData() }
        }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    Button {
                        statusFilter = status
                        loadData()
                    } label: {
                        Text(status == "all" ? "All" : status.capitalized)
                            .font(.caption)
                            .fontWeight(statusFilter == status ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(statusFilter == status ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(statusFilter == status ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - PO List

    @ViewBuilder
    private var poList: some View {
        if isLoading {
            ProgressView("Loading purchase orders...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredPOs.isEmpty {
            ContentUnavailableView {
                Label("No Purchase Orders", systemImage: "doc.text.fill")
            } description: {
                Text("No purchase orders match your criteria.")
            }
        } else {
            List(filteredPOs, id: \.id) { po in
                poRow(po)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredPOs: [OrdersService.POListItem] {
        guard !searchText.isEmpty else { return purchaseOrders }
        let query = searchText.lowercased()
        return purchaseOrders.filter {
            $0.poNumber.lowercased().contains(query) ||
            $0.supplierName.lowercased().contains(query)
        }
    }

    private func poRow(_ po: OrdersService.POListItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(po.poNumber)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Text(po.supplierName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let date = po.orderDate {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(po.status)
                if let total = po.totalCost {
                    Text(String(format: "$%.2f", total))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Label("\(po.lineCount) lines", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "draft": .secondary
        case "submitted": .orange
        case "ordered": .blue
        case "partial": .purple
        case "received": .green
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else { return }
        isLoading = purchaseOrders.isEmpty
        do {
            purchaseOrders = try service.listPurchaseOrders(
                status: statusFilter == "all" ? nil : statusFilter
            )
        } catch {
            print("[IOSPurchaseOrdersPage] Load error: \(error)")
        }
        isLoading = false
    }
}
