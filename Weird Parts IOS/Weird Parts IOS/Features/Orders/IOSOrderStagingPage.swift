import SwiftUI
import WiredPartCore

/// Order staging page for iOS.
///
/// Shows purchase orders in draft status that are being assembled before
/// submission to suppliers. Acts as the unified staging area where items
/// are collected and grouped before final placement. Uses the existing
/// `OrdersService.listPurchaseOrders(status:)` filtered to draft POs.
struct IOSOrderStagingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var stagedOrders: [OrdersService.POListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?

    var body: some View {
        stagedList
            .navigationTitle("Order Staging")
            .searchable(text: $searchText, prompt: "Search staged orders...")
            .onChange(of: searchText) { loadData() }
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Staged List

    @ViewBuilder
    private var stagedList: some View {
        if isLoading {
            ProgressView("Loading staged orders...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredOrders.isEmpty {
            ContentUnavailableView {
                Label("No Staged Orders", systemImage: "tray")
            } description: {
                Text("No draft purchase orders are being staged.")
            }
        } else {
            List {
                Section {
                    Text("\(filteredOrders.count) order\(filteredOrders.count == 1 ? "" : "s") staged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredOrders, id: \.id) { po in
                    stagedRow(po)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredOrders: [OrdersService.POListItem] {
        guard !searchText.isEmpty else { return stagedOrders }
        let query = searchText.lowercased()
        return stagedOrders.filter {
            $0.poNumber.lowercased().contains(query) ||
            $0.supplierName.lowercased().contains(query)
        }
    }

    private func stagedRow(_ po: OrdersService.POListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.up.fill")
                .font(.title3)
                .foregroundStyle(Color.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(po.poNumber)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Text(po.supplierName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge("draft")
                if let total = po.totalCost {
                    Text(String(format: "$%.2f", total))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Label("\(po.lineCount) items", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .foregroundStyle(.orange)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else { return }
        isLoading = stagedOrders.isEmpty
        do {
            // Draft POs are the staging area — not yet submitted
            stagedOrders = try service.listPurchaseOrders(status: "draft")
        } catch {
            print("[IOSOrderStagingPage] Load error: \(error)")
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
